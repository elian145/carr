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
    final cacheKey = url.toString();
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

    try {
      final response = await sendOnce(effectiveTimeout);
      _cacheGetResponse(cacheKey, response);
      return response;
    } on TimeoutException {
      final stale = _cachedGetIfFresh(cacheKey);
      if (stale != null) {
        appLog('ApiService.GET stale-while-revalidate $cacheKey');
        return stale;
      }
      // One cold-start retry when we had used the warm budget.
      if (effectiveTimeout < ApiService._coldTimeout) {
        final response = await sendOnce(ApiService._coldTimeout);
        _cacheGetResponse(cacheKey, response);
        return response;
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

    // Initialize tokens from storage without discarding an in-memory session
    // when secure storage is empty or temporarily unreadable (tests, keychain).
    static Future<void> initializeTokens() async {
      await TokenStore.load();
      final storedAccess = TokenStore.token;
      final storedRefresh = TokenStore.refreshToken;
      if (storedAccess != null && storedAccess.isNotEmpty) {
        ApiService._accessToken = storedAccess;
      }
      if (storedRefresh != null && storedRefresh.isNotEmpty) {
        ApiService._refreshToken = storedRefresh;
      }
    }

    // Save tokens to storage
    static Future<void> _saveAccessToken(String accessToken) async {
      await TokenStore.save(accessToken);
      ApiService._accessToken = TokenStore.token;
    }

    static Future<void> _saveRefreshToken(String? refreshToken) async {
      await TokenStore.saveRefresh(refreshToken);
      ApiService._refreshToken = TokenStore.refreshToken;
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
      await _saveAccessToken(t);
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
      await setAccessToken(accessToken);
      await setRefreshToken(refreshToken);
    }

    // Clear tokens
    static Future<void> clearTokens() async {
      await TokenStore.clear();
      ApiService._accessToken = null;
      ApiService._refreshToken = null;
      ApiService.onTokensCleared?.call();
    }

    static Future<void> _ensureTokenLoaded() async {
      if (ApiService._accessToken != null && ApiService._accessToken!.isNotEmpty) return;
      await TokenStore.load();
      final t = TokenStore.token;
      if (t != null && t.isNotEmpty) {
        ApiService._accessToken = t;
      }
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
      await _ensureTokenLoaded();

      Future<http.Response> sendOnce() async {
        final request = await buildRequest();
        request.headers['X-Carnet-Review-Aware'] = '1'; // see _getHeaders
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
        if (await _refreshAccessToken()) {
          response = await _withStaleClientRetry(sendOnce);
        } else {
          refreshFailedTransiently = _lastRefreshTransient;
        }
      }
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

    static Future<bool> _refreshAccessToken() {
      final inFlight = _refreshInFlight;
      if (inFlight != null) return inFlight;
      final future = _refreshAccessTokenOnce();
      _refreshInFlight = future;
      return future.whenComplete(() {
        if (identical(_refreshInFlight, future)) {
          _refreshInFlight = null;
        }
      });
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
    static Future<void> _handleUnrefreshable401() async {
      if (_lastRefreshTransient) {
        throw ApiException(
          statusCode: 503,
          message: 'Session refresh temporarily unavailable',
        );
      }
      await clearTokens();
    }

    static Future<bool> _refreshAccessTokenOnce() async {
      final rt = (ApiService._refreshToken ?? '').trim();
      if (rt.isEmpty) {
        _lastRefreshTransient = false;
        return false;
      }
      // Pessimistic default: anything that does not reach a definitive
      // server verdict below (an exception, a timeout) is transient.
      _lastRefreshTransient = true;
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
          if (access != null && access.isNotEmpty) {
            await _saveAccessToken(access);
            if (refresh != null && refresh.isNotEmpty) {
              await _saveRefreshToken(refresh);
            }
            _lastRefreshTransient = false;
            return true;
          }
          // 2xx without a usable token: definitive (malformed) answer.
          _lastRefreshTransient = false;
        } else {
          final code = response.statusCode;
          // Only a clear client-side rejection (401/403/422/...) is a
          // definitive "this refresh token is no good". Timeouts, rate
          // limits and server errors say nothing about the session.
          _lastRefreshTransient =
              code == 408 || code == 429 || code >= 500;
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
      await _ensureTokenLoaded();
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
        if (await _refreshAccessToken()) {
          // Retry request with new token
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
          await _handleUnrefreshable401();
          throw Exception('Authentication failed');
        }
      }

      return _handleResponse(response);
    }

    /// GET that returns a JSON array (e.g. legacy `/my_listings` compat).
    static Future<List<Map<String, dynamic>>> makeAuthenticatedListRequest(
      String endpoint,
    ) async {
      await _ensureTokenLoaded();
      final url = Uri.parse('${ApiService.baseUrl}$endpoint');
      var requestHeaders = _getHeaders();

      var response = await _getWithAdaptiveTimeout(
        url,
        headers: requestHeaders,
      );

      var refreshFailedTransiently = false;
      if (response.statusCode == 401) {
        if (await _refreshAccessToken()) {
          requestHeaders = _getHeaders();
          response = await _getWithAdaptiveTimeout(
            url,
            headers: requestHeaders,
          );
        } else {
          refreshFailedTransiently = _lastRefreshTransient;
        }
      }

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
