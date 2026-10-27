part of '../api_service.dart';

/// Token storage and authenticated HTTP core (split from [ApiService]).
abstract final class _ApiServiceHttp {
  _ApiServiceHttp._();

  static void _cacheGetResponse(String cacheKey, http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) return;
    ApiService._getResponseCache[cacheKey] = _ApiGetCacheEntry(
      response,
      DateTime.now(),
    );
    ApiService._markRequestSuccess();
  }

  static http.Response? _cachedGetIfFresh(String cacheKey) {
    final entry = ApiService._getResponseCache[cacheKey];
    if (entry == null || !entry.isUsable) return null;
    return entry.response;
  }

  static Future<T> _withStaleClientRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      if (!isStaleHttpClientError(e)) rethrow;
      ApiService.recycleProductionHttpClient();
      return await action();
    }
  }

  /// Sends a single GET using `package:http`'s [http.Abortable] support
  /// (F-06), and translates its [http.RequestAbortedException] into this
  /// repo's own [ApiCancelledException] so callers never need to import or
  /// match on a `package:http`-internal type.
  ///
  /// This is the ONLY change to how GET requests are constructed for F-06:
  /// headers, auth, the caller's own timeout wrapping, caching, and retry
  /// logic all live in the callers below, unchanged. Omitting [cancelToken]
  /// (the default) preserves the exact prior behavior — an
  /// [http.AbortableRequest] with a `null` `abortTrigger` sends and behaves
  /// identically to a plain, non-abortable GET; only the call shape
  /// (`Client.send` + `Response.fromStream` instead of the `Client.get`
  /// convenience method) differs, which is required to attach an
  /// `abortTrigger` at all.
  ///
  /// If [cancelToken] is already cancelled, this throws
  /// [ApiCancelledException] immediately, without making any network call.
  static Future<http.Response> _sendAbortableGet(
    Uri url, {
    Map<String, String>? headers,
    ApiCancelToken? cancelToken,
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      throw const ApiCancelledException();
    }
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: cancelToken?.whenCancelled,
    );
    if (headers != null) request.headers.addAll(headers);
    try {
      final streamed = await ApiService._httpClient.send(request);
      return await http.Response.fromStream(streamed);
    } on http.RequestAbortedException {
      throw const ApiCancelledException();
    }
  }

  /// GET with adaptive timeout; on cold-start timeout, return fresh-enough cache.
  ///
  /// [cancelToken] is optional (F-06); when provided and cancelled, the
  /// underlying request is genuinely aborted (see [_sendAbortableGet]) and
  /// the resulting [ApiCancelledException] propagates straight out of this
  /// function — it is never a [TimeoutException], so it is never caught by
  /// the `on TimeoutException` branch below, and therefore an aborted GET
  /// is never cached and never falls back to the stale-while-revalidate
  /// cache or the cold-start retry.
  static Future<http.Response> _getWithAdaptiveTimeout(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    ApiCancelToken? cancelToken,
  }) async {
    // F-39: the cache is scoped by session epoch + account, and a response is
    // neither stored nor returned once the session it was requested under has
    // ended (an A response must never be displayed or cached under B).
    final carriesAuth = headers?.keys.any(
          (k) => k.toLowerCase() == 'authorization',
        ) ??
        false;
    final session = ApiService.captureSession(authenticated: carriesAuth);
    final scope = '${session.epoch}|'
        '${session.authenticated ? (session.accountId ?? 'unverified') : 'guest'}';
    final cacheKey = '$scope|${url.toString()}';
    final effectiveTimeout = timeout ?? ApiService.requestTimeout();
    Future<http.Response> sendOnce(Duration t) {
      return _withStaleClientRetry(
        () => _sendAbortableGet(
          url,
          headers: headers,
          cancelToken: cancelToken,
        ).timeout(t),
      );
    }

    // A genuinely public request (no Authorization header) carries nothing
    // account-specific, so a login that happens meanwhile does not invalidate
    // it. Account-sensitive callers (`_makeAuthenticatedRequest`, ...) keep
    // their OWN strict session and check it after this returns.
    void assertIfAccountBound() {
      if (session.authenticated) ApiService.assertSessionCurrent(session);
    }

    http.Response deliver(http.Response response) {
      assertIfAccountBound();
      if (session.epoch == ApiService._sessionEpoch) {
        _cacheGetResponse(cacheKey, response);
      }
      return response;
    }

    try {
      return deliver(await sendOnce(effectiveTimeout));
    } on TimeoutException {
      assertIfAccountBound();
      final stale = _cachedGetIfFresh(cacheKey);
      if (stale != null) {
        appLog('ApiService.GET stale-while-revalidate ${url.toString()}');
        return stale;
      }
      // One cold-start retry when we had used the warm budget.
      if (effectiveTimeout < ApiService._coldTimeout) {
        return deliver(await sendOnce(ApiService._coldTimeout));
      }
      rethrow;
    }
  }

  static Future<http.Response> _sendWithAdaptiveTimeout(
    Future<http.Response> Function() send, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? ApiService.requestTimeout();
    try {
      final response = await _withStaleClientRetry(
        () => send().timeout(effectiveTimeout),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        ApiService._markRequestSuccess();
      }
      return response;
    } on TimeoutException {
      if (effectiveTimeout < ApiService._coldTimeout) {
        final response = await _withStaleClientRetry(
          () => send().timeout(ApiService._coldTimeout),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          ApiService._markRequestSuccess();
        }
        return response;
      }
      rethrow;
    }
  }

    // -----------------------------------------------------------------
    // Serialized credential persistence (F-35 / F-39 hardening).
    //
    // Every read or write of the persisted credentials goes through ONE
    // FIFO queue, and every queued operation re-checks the session epoch
    // it belongs to at the moment it actually runs:
    //  * a persist whose session was superseded before it started is
    //    skipped -- the newer transition persists its own state;
    //  * a persist that is already running finishes before the next
    //    transition's persist starts, so the LAST transition always wins in
    //    storage (a slow write for account A can never land after, and
    //    overwrite, account B's);
    //  * in-memory credentials change synchronously and are never
    //    re-assigned from storage after an await.
    // A waiter queue (not a chained Future) is used so nothing is tied to
    // the zone that created it.
    // -----------------------------------------------------------------
    static bool _ioBusy = false;
    static final List<Completer<void>> _ioWaiters = <Completer<void>>[];

    static Future<T> _persistSerialized<T>(Future<T> Function() op) async {
      if (_ioBusy) {
        final turn = Completer<void>();
        _ioWaiters.add(turn);
        await turn.future; // ownership of [_ioBusy] is handed to us
      } else {
        _ioBusy = true;
      }
      try {
        return await op();
      } finally {
        if (_ioWaiters.isNotEmpty) {
          _ioWaiters.removeAt(0).complete();
        } else {
          _ioBusy = false;
        }
      }
    }

    // -----------------------------------------------------------------
    // Authentication attempts.
    //
    // A login / OTP verification is a network round trip that ends in
    // installing credentials. Each one takes a number from
    // [_authGeneration] when it STARTS and may only install if the number is
    // still the latest when its response arrives. Any later attempt, any
    // sign-out, any other credential installation and an explicit cancel
    // advance the number, so a stale response can never replace (or
    // resurrect over) the session that exists by then.
    // -----------------------------------------------------------------
    static int _authGeneration = 0;

    static int beginAuthAttempt() => ++_authGeneration;

    /// Throws [ApiSessionChangedException] if [attempt] has been superseded.
    static void assertAuthAttemptCurrent(int attempt) {
      if (attempt != _authGeneration) throw ApiSessionChangedException();
    }

    static void cancelPendingAuthAttempts() {
      _authGeneration++;
    }

    // -----------------------------------------------------------------
    // Access / refresh pairing.
    //
    // A refresh token can mint access tokens for ITS account, so one that
    // belongs to another account must never sit next to the current access
    // token. Identity is read from the tokens' `sub` claims; a token that
    // names no account (opaque / legacy numeric subject) is "unknown".
    // -----------------------------------------------------------------

    /// Both tokens name an account and they are DIFFERENT accounts.
    static bool _pairConflicts(String? access, String? refresh) {
      final a = accountIdFromJwt(access);
      final r = accountIdFromJwt(refresh);
      return a != null && r != null && a != r;
    }

    /// Both tokens provably name the SAME account.
    static bool _pairProvablyMatches(String? access, String? refresh) {
      final a = accountIdFromJwt(access);
      final r = accountIdFromJwt(refresh);
      return a != null && r != null && a == r;
    }

    /// Test hook: forget any operation left half-way by a previous test.
    @visibleForTesting
    static void debugResetTokenIo() {
      _ioBusy = false;
      _ioWaiters.clear();
      _restoreInFlight = null;
      _clearsInProgress = 0;
      _refreshInFlight = null;
      _refreshInFlightEpoch = null;
    }

    // Initialize tokens from storage without discarding an in-memory session
    // when secure storage is empty or temporarily unreadable (tests, keychain).
    static Future<void> initializeTokens() async {
      final epochAtStart = ApiService._sessionEpoch;
      String? storedAccess;
      String? storedRefresh;
      await _persistSerialized(() async {
        await TokenStore.load();
        storedAccess = TokenStore.token;
        storedRefresh = TokenStore.refreshToken;
      });
      // Another transition (login, logout, restore) happened while storage
      // was being read: what was read may belong to the session that just
      // ended, and the newer transition already persisted and scoped its own
      // state. Never adopt it.
      if (ApiService._sessionEpoch != epochAtStart || _clearsInProgress > 0) {
        return;
      }
      final beforeAccess = ApiService._accessToken;
      final beforeRefresh = ApiService._refreshToken;
      final access = storedAccess;
      final refresh = storedRefresh;
      if (access != null && access.isNotEmpty) {
        ApiService._accessToken = access;
      }
      if (refresh != null && refresh.isNotEmpty) {
        ApiService._refreshToken = refresh;
      }
      if (ApiService._accessToken != beforeAccess ||
          ApiService._refreshToken != beforeRefresh) {
        _bumpSession();
      }
      // Always (re)scope on-device data to whoever holds the session now
      // (no-op when already scoped). Covers a previous run that was killed
      // between clearing tokens and re-scoping local data.
      await AccountScope.activate(
        ApiService.currentAccountId,
        generation: AccountScope.generation,
      );
    }

    /// F-39: an authentication transition happened. Synchronously invalidates
    /// everything bound to the previous session: the epoch (so in-flight
    /// requests abandon themselves), the identity verdict, the GET response
    /// cache and any in-memory account caches registered with
    /// [AccountScope].
    static void _bumpSession() {
      ApiService._sessionEpoch++;
      ApiService._identityRejected = false;
      ApiService._getResponseCache.clear();
      AccountScope.notifySessionChanged();
    }

    /// Applies a refreshed token pair that belongs to the session identified
    /// by [epoch] (refresh-token rotation inside the SAME session; logins go
    /// through [installSession]). Returns `false`, touching nothing, when
    /// that session has already ended.
    ///
    /// Memory changes synchronously (so no await can interleave with a
    /// half-applied pair); persistence is serialized and skipped if a newer
    /// transition superseded the session before it ran. A rotation that
    /// changes the decodable account id is treated as a session change (fail
    /// closed).
    static Future<bool> _applyRefreshedTokens(
      int epoch,
      String accessToken,
      String? refreshToken,
    ) async {
      if (ApiService._sessionEpoch != epoch) return false;
      final access = accessToken.trim();
      final refresh = (refreshToken ?? '').trim();
      final before = ApiService.currentAccountId;
      ApiService._accessToken = access;
      final keepNewRefresh =
          refresh.isNotEmpty && !_pairConflicts(access, refresh);
      if (keepNewRefresh) ApiService._refreshToken = refresh;
      final after = ApiService.currentAccountId;
      var rescope = false;
      if (after != before) {
        if (before != null) {
          // The credentials now name a DIFFERENT account (or none): that is
          // not a rotation, it is another session.
          _bumpSession();
        }
        // before == null: the same session just became identifiable (legacy
        // numeric-subject session refreshed into a public-id token). Nothing
        // in flight is abandoned; only on-device data is re-scoped to the
        // owner that is now known.
        rescope = true;
      }
      final myEpoch = ApiService._sessionEpoch;
      final generation = AccountScope.generation;
      await _persistSerialized(() async {
        if (ApiService._sessionEpoch != myEpoch) return;
        await TokenStore.save(access);
        if (keepNewRefresh) await TokenStore.saveRefresh(refresh);
      });
      if (rescope) {
        await AccountScope.activate(after, generation: generation);
      }
      return true;
    }

    static Future<void> _saveRefreshToken(String? refreshToken) async {
      final epoch = ApiService._sessionEpoch;
      final r = (refreshToken ?? '').trim();
      if (r.isNotEmpty && _pairConflicts(ApiService._accessToken, r)) {
        // Another account's refresh token must never sit next to the current
        // access token.
        logNonFatal(
          StateError('refresh token belongs to another account'),
          StackTrace.current,
          'ApiService._saveRefreshToken',
        );
        return;
      }
      ApiService._refreshToken = r.isEmpty ? null : r;
      await _persistSerialized(() async {
        if (ApiService._sessionEpoch != epoch) return;
        await TokenStore.saveRefresh(r.isEmpty ? null : r);
      });
    }

    /// Persists the CURRENT credentials again (no transition), unless the
    /// session [epoch] they belong to has been superseded.
    static Future<void> _persistAccessIfCurrent(int epoch, String access) =>
        _persistSerialized(() async {
          if (ApiService._sessionEpoch != epoch) return;
          await TokenStore.save(access);
        });

    /// Installs credentials for a NEW authentication session (login, signup,
    /// external auth, account switch) -- even when it is the same account that
    /// signed out a moment ago. In-memory credentials and the epoch change
    /// synchronously, before any await, so no request can run half-way
    /// between two sessions; then they are persisted and on-device data is
    /// re-scoped to the new owner before this returns.
    ///
    /// A session superseded while it was being persisted leaves memory,
    /// storage and on-device scope to the newer transition (see
    /// [_persistSerialized]).
    ///
    /// [refresh] null/empty drops any previous refresh token: the old
    /// account's refresh token must never survive into a new session.
    static Future<void> installSession(String access, String? refresh) async {
      final a = access.trim();
      // A pair naming two different accounts is never installed: keep the
      // access token (it is the credential that was issued), drop the foreign
      // refresh token.
      final r = _pairConflicts(a, refresh) ? '' : (refresh ?? '').trim();
      _authGeneration++;
      ApiService._accessToken = a;
      ApiService._refreshToken = r.isEmpty ? null : r;
      _bumpSession();
      final epoch = ApiService._sessionEpoch;
      final generation = AccountScope.generation;
      await _persistSerialized(() async {
        if (ApiService._sessionEpoch != epoch) return;
        await TokenStore.save(a);
        await TokenStore.saveRefresh(r.isEmpty ? null : r);
      });
      if (ApiService._sessionEpoch != epoch) return;
      await AccountScope.activate(
        ApiService.currentAccountId,
        generation: generation,
      );
    }

    /// Set the current access token (best-effort persisted).
    /// Use this when the app obtains a token outside of [ApiService.login],
    /// e.g. after signup or external auth.
    static Future<void> setAccessToken(String? token) async {
      final t = (token ?? '').trim();
      if (t.isEmpty) {
        await clearTokens();
        return;
      }
      if (t == ApiService._accessToken) {
        await _persistAccessIfCurrent(ApiService._sessionEpoch, t);
        return;
      }
      // A different access token starts a new session. The previous refresh
      // token only survives when it provably belongs to the SAME account as
      // the new access token; otherwise it is dropped (it could mint tokens
      // for the account that was signed in before).
      final keepRefresh = _pairProvablyMatches(t, ApiService._refreshToken);
      _authGeneration++;
      ApiService._accessToken = t;
      if (!keepRefresh) ApiService._refreshToken = null;
      _bumpSession();
      final epoch = ApiService._sessionEpoch;
      final generation = AccountScope.generation;
      await _persistSerialized(() async {
        if (ApiService._sessionEpoch != epoch) return;
        await TokenStore.save(t);
        if (!keepRefresh) await TokenStore.saveRefresh(null);
      });
      if (ApiService._sessionEpoch != epoch) return;
      await AccountScope.activate(
        ApiService.currentAccountId,
        generation: generation,
      );
    }

    /// Set the current refresh token (best-effort persisted).
    static Future<void> setRefreshToken(String? token) async {
      final t = (token ?? '').trim();
      if (t.isEmpty) {
        await _saveRefreshToken(null);
        return;
      }
      await _saveRefreshToken(t);
    }

    /// Set both access and refresh tokens (best-effort persisted).
    static Future<void> setTokens({
      String? accessToken,
      String? refreshToken,
    }) async {
      final a = (accessToken ?? '').trim();
      if (a.isEmpty) {
        await clearTokens();
        await setRefreshToken(refreshToken);
        return;
      }
      final r = (refreshToken ?? '').trim();
      if (a == ApiService._accessToken &&
          r == (ApiService._refreshToken ?? '')) {
        final epoch = ApiService._sessionEpoch;
        await _persistSerialized(() async {
          if (ApiService._sessionEpoch != epoch) return;
          await TokenStore.save(a);
          await TokenStore.saveRefresh(r.isEmpty ? null : r);
        });
        return;
      }
      await installSession(a, refreshToken);
    }

    // Clear tokens
    static Future<void> clearTokens() async {
      // In-memory first + epoch bump (synchronous) so requests still in
      // flight for the ended session can never be retried, nor deliver
      // results, nor clear a LATER session's tokens.
      _authGeneration++; // a login still in flight is now stale
      ApiService._accessToken = null;
      ApiService._refreshToken = null;
      _bumpSession();
      final epoch = ApiService._sessionEpoch;
      final generation = AccountScope.generation;
      _clearsInProgress++;
      try {
        // Always runs (FIFO): a sign-out queued before a later login wipes
        // storage first and the login's persist lands after it.
        await _persistSerialized(() => TokenStore.clear());
        if (ApiService._sessionEpoch == epoch) {
          await AccountScope.activate(null, generation: generation);
        }
      } finally {
        _clearsInProgress--;
      }
      // A newer transition (another sign-out, a login) owns scoping and
      // notifications now: this stale sign-out must not run ITS cleanup.
      if (ApiService._sessionEpoch != epoch) return;
      ApiService.onTokensCleared?.call();
    }

    /// > 0 while [clearTokens] is still wiping persistent storage. A request
    /// that finds no in-memory session in that window must NOT reload the
    /// not-yet-deleted persisted tokens (that would resurrect the session
    /// that is being signed out).
    static int _clearsInProgress = 0;

    /// Starts an authenticated call: captures the session the call was made in
    /// BEFORE the first await (an async gap during which another account could
    /// sign in), restores the persisted session if none is in memory yet, and
    /// refuses to continue with a later session's credentials.
    ///
    /// A call that began WITHOUT credentials may only run in the session this
    /// very cold start restored from storage. If any other transition
    /// (login, logout, account switch) happened while it waited, it is
    /// abandoned: it must never silently pick up an unrelated account.
    static Future<AuthSessionSnapshot> _beginAuthenticatedRequest() async {
      final entry = ApiService.captureSession();
      final restored = await _restorePersistedSession();
      if (entry.authenticated) {
        ApiService.assertSessionCurrent(entry);
        return entry;
      }
      if (restored != null && restored.epoch > entry.epoch) {
        // This call's cold start restored the persisted session.
        if (ApiService._sessionEpoch != restored.epoch) {
          throw ApiSessionChangedException();
        }
        return restored;
      }
      if (ApiService._sessionEpoch != entry.epoch) {
        throw ApiSessionChangedException();
      }
      return entry; // still a guest: nothing was restored
    }

    static Future<void> _ensureTokenLoaded() async {
      await _restorePersistedSession();
    }

    static Future<AuthSessionSnapshot?>? _restoreInFlight;
    static int _restoreStartEpoch = -1;

    /// Restores the persisted session into memory when none is loaded yet.
    /// Concurrent cold-start callers share ONE restore. Returns the restored
    /// session, or `null` when nothing was restored (a session already
    /// exists, nothing is persisted, or another transition got there first).
    static Future<AuthSessionSnapshot?> _restorePersistedSession() {
      final access = ApiService._accessToken;
      if (access != null && access.isNotEmpty) {
        return Future<AuthSessionSnapshot?>.value(null);
      }
      if (_clearsInProgress > 0) {
        return Future<AuthSessionSnapshot?>.value(null);
      }
      final inFlight = _restoreInFlight;
      if (inFlight != null && _restoreStartEpoch == ApiService._sessionEpoch) {
        return inFlight;
      }
      final epochAtStart = ApiService._sessionEpoch;
      _restoreStartEpoch = epochAtStart;
      final future = _doRestorePersistedSession(epochAtStart);
      _restoreInFlight = future;
      unawaited(future.whenComplete(() {
        if (identical(_restoreInFlight, future)) _restoreInFlight = null;
      }).then<void>((_) {}, onError: (Object _) {}));
      return future;
    }

    static Future<AuthSessionSnapshot?> _doRestorePersistedSession(
      int epochAtStart,
    ) async {
      String? storedAccess;
      String? storedRefresh;
      await _persistSerialized(() async {
        await TokenStore.load();
        storedAccess = TokenStore.token;
        storedRefresh = TokenStore.refreshToken;
      });
      // The session changed (or is being cleared) while storage was read:
      // what was read may belong to the session that just ended.
      if (_clearsInProgress > 0 || ApiService._sessionEpoch != epochAtStart) {
        return null;
      }
      final t = storedAccess;
      if (t == null || t.isEmpty || (ApiService._accessToken ?? '').isNotEmpty) {
        return null;
      }
      ApiService._accessToken = t;
      final rt = storedRefresh;
      if ((ApiService._refreshToken ?? '').isEmpty &&
          rt != null &&
          rt.isNotEmpty) {
        ApiService._refreshToken = rt;
      }
      _bumpSession();
      final restored = ApiService.captureSession();
      await AccountScope.activate(
        ApiService.currentAccountId,
        generation: AccountScope.generation,
      );
      return restored;
    }

    // Get headers with authorization
    //
    // MI-03/U-01: every normal request also carries `Accept-Language` (one
    // of `en`/`ar`/`ku`, mirroring the app's current effective locale --
    // see `LocaleController.resolveCode()`) so the backend can localize its
    // response even before/without an authenticated `User.locale`. This is
    // the single chokepoint for outgoing headers -- do not add the header
    // separately to individual call sites.
    //
    // `X-Carnet-Review-Aware: 1` tells the backend this build understands
    // listing-edit moderation (an edit of an Active listing is a saved draft
    // the seller submits explicitly). The backend therefore never submits
    // such a draft on the seller's behalf; only builds WITHOUT this header
    // (which never send a final submit call) get the legacy auto-finalize.
    // Keep it on every request, including multipart uploads below.
    static Map<String, String> _getHeaders({bool includeAuth = true}) {
      Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Accept-Language': LocaleController.resolveCode(),
        'X-Carnet-Review-Aware': '1',
      };

      if (includeAuth && ApiService._accessToken != null && ApiService._accessToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${ApiService._accessToken}';
      }

      return headers;
    }

    // Handle API response
    static Map<String, dynamic> _handleResponse(http.Response response) {
      final int code = response.statusCode;
      final String body = response.body;
      if (code >= 200 && code < 300) {
        return body.isNotEmpty ? json.decode(body) : <String, dynamic>{};
      }
      if (code == 429) {
        String message = 'Too many requests. Please try again later.';
        int? retryAfterSeconds;
        Map<String, dynamic> err = <String, dynamic>{};

        try {
          err = body.isNotEmpty
              ? Map<String, dynamic>.from(json.decode(body) as Map)
              : <String, dynamic>{};
          final msg = (err['message'] ?? err['error'] ?? '').toString().trim();
          if (msg.isNotEmpty) {
            message = msg;
          }
          final retryAfter = err['retry_after'];
          if (retryAfter is int) {
            retryAfterSeconds = retryAfter;
          } else if (retryAfter is num) {
            retryAfterSeconds = retryAfter.toInt();
          }
        } catch (_) {
          // Malformed rate-limit body — keep generic message.
        }

        final retryHeader = response.headers['retry-after'];
        if (retryAfterSeconds == null && retryHeader != null) {
          retryAfterSeconds = int.tryParse(retryHeader.trim());
        }

        if (retryAfterSeconds != null && retryAfterSeconds > 0) {
          final lower = message.toLowerCase();
          if (!lower.contains('try again')) {
            final waitLabel = retryAfterSeconds < 60
                ? '$retryAfterSeconds second${retryAfterSeconds == 1 ? '' : 's'}'
                : '${(retryAfterSeconds / 60).ceil()} minute${(retryAfterSeconds / 60).ceil() == 1 ? '' : 's'}';
            message = '$message Please try again in $waitLabel.';
          }
        }

        throw ApiException(statusCode: code, message: message, body: err);
      }
      try {
        final Map<String, dynamic> err = body.isNotEmpty
            ? json.decode(body) as Map<String, dynamic>
            : <String, dynamic>{};
        final messagePart =
            (err['message'] ?? '').toString().trim();
        final errorPart = (err['error'] ?? '').toString().trim();
        final detailPart = (err['detail'] ?? '').toString().trim();
        String msg = messagePart;
        if (errorPart.isNotEmpty &&
            errorPart != messagePart &&
            !messagePart.contains(errorPart)) {
          msg = msg.isEmpty ? errorPart : '$msg ($errorPart)';
        }
        if (msg.isEmpty) {
          msg = errorPart;
        }
        if (detailPart.isNotEmpty &&
            detailPart != msg &&
            !msg.contains(detailPart)) {
          msg = msg.isEmpty ? detailPart : '$msg ($detailPart)';
        }
        throw ApiException(
          statusCode: code,
          message: msg.isNotEmpty ? msg : 'API request failed ($code)',
          body: err,
        );
      } on ApiException {
        rethrow;
      } catch (_) {
        throw ApiException(
          statusCode: code,
          message: 'API request failed ($code)',
        );
      }
    }

    static Map<String, dynamic> _decodeMapBody(
      String body, {
      required int statusCode,
      String fallbackMessage = 'API request failed',
    }) {
      if (body.trim().isEmpty) {
        return <String, dynamic>{};
      }
      try {
        final decoded = json.decode(body);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
        }
        throw ApiException(
          statusCode: statusCode,
          message: '$fallbackMessage ($statusCode)',
        );
      } on ApiException {
        rethrow;
      } catch (_) {
        throw ApiException(
          statusCode: statusCode,
          message: body.trim().isNotEmpty
              ? body.trim()
              : '$fallbackMessage ($statusCode)',
        );
      }
    }

    static ApiException _uploadException(int statusCode, String responseBody) {
      String message = 'Upload failed';
      Map<String, dynamic>? body;
      try {
        final decoded = responseBody.trim().isNotEmpty
            ? json.decode(responseBody)
            : <String, dynamic>{};
        if (decoded is Map) {
          body = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
          final msg = (body['message'] ?? body['error'] ?? '').toString().trim();
          if (msg.isNotEmpty) message = msg;
        } else if (responseBody.trim().isNotEmpty) {
          message = responseBody.trim();
        }
      } catch (_) {
        if (responseBody.trim().isNotEmpty) message = responseBody.trim();
      }
      return ApiException(statusCode: statusCode, message: message, body: body);
    }

    static Future<Map<String, dynamic>> _sendAuthenticatedMultipart(
      Future<http.MultipartRequest> Function() buildRequest,
    ) async {
      final session = await _beginAuthenticatedRequest();

      Future<http.Response> sendOnce() async {
        // Never dispatch (or re-dispatch) under credentials of a later session.
        ApiService.assertSessionCurrent(session);
        final request = await buildRequest();
        request.headers['X-Carnet-Review-Aware'] = '1'; // see _getHeaders
        ApiService.assertSessionCurrent(session);
        if (ApiService._accessToken != null && ApiService._accessToken!.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer ${ApiService._accessToken}';
        }
        // P-01 testability follow-up: send through the shared
        // ApiService._httpClient (same as every other request in this
        // file) instead of the request's own default `send()`, which opens
        // a brand-new throwaway `http.Client()` under the hood. Behavior is
        // unchanged in production (the shared client is a plain
        // `http.Client()` too), but this is what lets
        // `ApiService.testHttpClient` (used by widget/unit tests, e.g. the
        // P-01 async-upload regression test) actually observe multipart
        // uploads instead of always hitting Flutter's test-binding
        // `HttpClient` stub, which unconditionally returns 400.
        final streamed = await ApiService._httpClient
            .send(request)
            .timeout(ApiService._uploadTimeout);
        return http.Response.fromStream(streamed);
      }

      // Recycle a dead socket, but do not retry timeouts here: the server may
      // have already stored the files and a second POST would duplicate them.
      var response = await _withStaleClientRetry(sendOnce);
      var refreshFailedTransiently = false;
      if (response.statusCode == 401) {
        if (await _refreshAccessToken(session)) {
          response = await _withStaleClientRetry(sendOnce);
        } else {
          refreshFailedTransiently = _lastRefreshTransient;
        }
      }
      ApiService.assertSessionCurrent(session);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _decodeMapBody(
          response.body,
          statusCode: response.statusCode,
          fallbackMessage: 'Upload failed',
        );
      }
      if (response.statusCode == 401) {
        if (refreshFailedTransiently) {
          // Transient refresh failure: keep the session; the caller's
          // retry classification treats 503 as recoverable.
          throw ApiException(
            statusCode: 503,
            message: 'Session refresh temporarily unavailable',
          );
        }
        await clearTokens();
      }
      throw _uploadException(response.statusCode, response.body);
    }

    // Refresh access token (single-flight so rotating refresh tokens are not raced).
    static Future<bool>? _refreshInFlight;
    static int? _refreshInFlightEpoch;

    /// [session], when given, is the session the CALLER's request started in:
    /// the refresh is refused (and the caller abandoned with
    /// [ApiSessionChangedException]) if that session already ended, and a
    /// refresh that completes after the session ended is never reported as a
    /// usable result for the caller. A refresh is only ever shared between
    /// callers of the same session epoch.
    static Future<bool> _refreshAccessToken([AuthSessionSnapshot? session]) async {
      if (session != null) ApiService.assertSessionCurrent(session);
      final epoch = ApiService._sessionEpoch;
      Future<bool> future;
      final inFlight = _refreshInFlight;
      if (inFlight != null && _refreshInFlightEpoch == epoch) {
        future = inFlight;
      } else {
        future = _refreshAccessTokenOnce(epoch);
        _refreshInFlight = future;
        _refreshInFlightEpoch = epoch;
        unawaited(future.whenComplete(() {
          if (identical(_refreshInFlight, future)) {
            _refreshInFlight = null;
            _refreshInFlightEpoch = null;
          }
        }).catchError((Object _) => false));
      }
      final ok = await future;
      if (session != null) ApiService.assertSessionCurrent(session);
      return ok;
    }

    /// True when the most recent [_refreshAccessToken] attempt failed for a
    /// TRANSIENT reason (network error, timeout, 408/429/5xx) rather than
    /// because the server definitively rejected the refresh token.
    ///
    /// Real-device bug (Galaxy A17, app backgrounded mid-submit): the first
    /// request after returning to the foreground got a 401, the refresh call
    /// then failed only because the radio/socket was not back yet, and every
    /// caller treated "refresh returned false" as "session is dead": it wiped
    /// the stored tokens and threw a non-retryable error. For a pending Sell
    /// submission that classified a perfectly healthy upload as permanently
    /// failed (red "couldn't finish uploading" banner), and it logged the
    /// seller out of an otherwise valid session. A transient refresh failure
    /// must never clear tokens and must surface as a retryable error.
    static bool _lastRefreshTransient = false;

    @visibleForTesting
    static bool get lastRefreshWasTransient => _lastRefreshTransient;

    /// Called by every call site that has just seen "401 and refresh failed".
    /// Throws a retryable [ApiException] (503) -- WITHOUT touching the stored
    /// tokens -- when the refresh failure was transient; otherwise clears the
    /// session (definitive rejection) and returns so the caller can throw its
    /// usual "authentication failed" error.
    static Future<void> _handleUnrefreshable401([
      AuthSessionSnapshot? session,
    ]) async {
      // A request that belongs to an ended session must never wipe the tokens
      // of the session that replaced it (F-35: a stale A request signing B out).
      if (session != null) ApiService.assertSessionCurrent(session);
      if (_lastRefreshTransient) {
        throw ApiException(
          statusCode: 503,
          message: 'Session refresh temporarily unavailable',
        );
      }
      await clearTokens();
    }

    static Future<bool> _refreshAccessTokenOnce(int epoch) async {
      // A refresh belonging to an ended session must not report anything
      // about the session that replaced it: only the session the refresh was
      // started for may set the shared verdict flag.
      void verdict(bool transient) {
        if (ApiService._sessionEpoch == epoch) _lastRefreshTransient = transient;
      }

      final rt = (ApiService._refreshToken ?? '').trim();
      if (rt.isEmpty) {
        verdict(false);
        return false;
      }
      // Pessimistic default: anything that does not reach a definitive
      // server verdict below (an exception, a timeout) is transient.
      verdict(true);
      try {
        final response = await ApiService._httpClient
            .post(
              Uri.parse('${ApiService.baseUrl}/auth/refresh'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $rt',
              },
            )
            .timeout(ApiService.requestTimeout());
        if (response.statusCode >= 200 && response.statusCode < 300) {
          ApiService._markRequestSuccess();
          final data = response.body.isNotEmpty
              ? json.decode(response.body)
              : <String, dynamic>{};
          final String? access = (data['access_token'] as String?)?.trim();
          final String? refresh = (data['refresh_token'] as String?)?.trim();
          if (ApiService._sessionEpoch != epoch) {
            // The session this refresh was started for has ended: its new
            // tokens must never be installed over (or next to) the current
            // session's credentials.
            return false;
          }
          if (access != null && access.isNotEmpty) {
            // Memory changes synchronously and persistence is serialized and
            // re-checked against [epoch] when it runs, so a sign-out / login
            // that overlaps the write can neither be resurrected nor
            // overwritten (see [_applyRefreshedTokens]).
            final applied = await _applyRefreshedTokens(epoch, access, refresh);
            if (!applied) return false;
            verdict(false);
            return true;
          }
          // 2xx without a usable token: definitive (malformed) answer.
          verdict(false);
        } else {
          final code = response.statusCode;
          // Only a clear client-side rejection (401/403/422/...) is a
          // definitive "this refresh token is no good". Timeouts, rate
          // limits and server errors say nothing about the session.
          verdict(code == 408 || code == 429 || code >= 500);
        }
      } catch (e, st) {
        logNonFatal(e, st, 'ApiService._tryRefreshToken');
      }
      return false;
    }
    // Make authenticated request with automatic token refresh
    static Future<Map<String, dynamic>> _makeAuthenticatedRequest(
      String method,
      String endpoint, {
      Map<String, dynamic>? body,
      Map<String, String>? headers,
    }) async {
      // F-35/F-39: bound to the session this call was MADE in (captured before
      // any await), so the credentials below can only be that session's.
      final session = await _beginAuthenticatedRequest();
      final url = Uri.parse('${ApiService.baseUrl}$endpoint');
      final requestHeaders = {..._getHeaders(), ...?headers};

      http.Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await _getWithAdaptiveTimeout(
            url,
            headers: requestHeaders,
          );
          break;
        case 'POST':
          response = await _sendWithAdaptiveTimeout(
            () => ApiService._httpClient.post(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            ),
          );
          break;
        case 'PUT':
          response = await _sendWithAdaptiveTimeout(
            () => ApiService._httpClient.put(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            ),
          );
          break;
        case 'PATCH':
          response = await _sendWithAdaptiveTimeout(
            () => ApiService._httpClient.patch(
              url,
              headers: requestHeaders,
              body: body != null ? json.encode(body) : null,
            ),
          );
          break;
        case 'DELETE':
          response = await _sendWithAdaptiveTimeout(
            () => ApiService._httpClient.delete(url, headers: requestHeaders),
          );
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      // If unauthorized, try to refresh token
      if (response.statusCode == 401) {
        // Throws [ApiSessionChangedException] (instead of refreshing with, or
        // retrying under, a later session's credentials) when this request's
        // session has ended.
        if (await _refreshAccessToken(session)) {
          // Retry request with new token (same session, rotated token)
          requestHeaders['Authorization'] = 'Bearer ${ApiService._accessToken}';

          switch (method.toUpperCase()) {
            case 'GET':
              response = await _getWithAdaptiveTimeout(
                url,
                headers: requestHeaders,
              );
              break;
            case 'POST':
              response = await _sendWithAdaptiveTimeout(
                () => ApiService._httpClient.post(
                  url,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null,
                ),
              );
              break;
            case 'PUT':
              response = await _sendWithAdaptiveTimeout(
                () => ApiService._httpClient.put(
                  url,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null,
                ),
              );
              break;
            case 'PATCH':
              response = await _sendWithAdaptiveTimeout(
                () => ApiService._httpClient.patch(
                  url,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null,
                ),
              );
              break;
            case 'DELETE':
              response = await _sendWithAdaptiveTimeout(
                () => ApiService._httpClient.delete(
                  url,
                  headers: requestHeaders,
                ),
              );
              break;
          }
        } else {
          // Throws a retryable 503 (tokens untouched) when the refresh
          // failure was only transient; otherwise clears the session.
          await _handleUnrefreshable401(session);
          throw Exception('Authentication failed');
        }
      }

      // The result of a request that started under a session that has since
      // ended is never handed to the caller (which may now be a different
      // account).
      ApiService.assertSessionCurrent(session);
      return _handleResponse(response);
    }

    /// GET that returns a JSON array (e.g. legacy `/my_listings` compat).
    static Future<List<Map<String, dynamic>>> makeAuthenticatedListRequest(
      String endpoint,
    ) async {
      final session = await _beginAuthenticatedRequest();
      final url = Uri.parse('${ApiService.baseUrl}$endpoint');
      var requestHeaders = _getHeaders();

      var response = await _getWithAdaptiveTimeout(
        url,
        headers: requestHeaders,
      );

      var refreshFailedTransiently = false;
      if (response.statusCode == 401) {
        if (await _refreshAccessToken(session)) {
          requestHeaders = _getHeaders();
          response = await _getWithAdaptiveTimeout(
            url,
            headers: requestHeaders,
          );
        } else {
          refreshFailedTransiently = _lastRefreshTransient;
        }
      }
      ApiService.assertSessionCurrent(session);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = response.body.isNotEmpty ? json.decode(response.body) : <dynamic>[];
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map(
                (e) => Map<String, dynamic>.from(
                  e.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList();
        }
        throw ApiException(
          statusCode: response.statusCode,
          message: 'Expected a JSON array',
        );
      }

      if (response.statusCode == 401) {
        if (refreshFailedTransiently) {
          throw ApiException(
            statusCode: 503,
            message: 'Session refresh temporarily unavailable',
          );
        }
        await clearTokens();
      }
      _handleResponse(response);
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Request failed',
      );
    }
}
