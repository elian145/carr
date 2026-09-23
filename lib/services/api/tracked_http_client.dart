import 'package:http/http.dart' as http;

/// Wraps an [http.Client] so it can be retired (see [closeWhenIdle]) without
/// aborting requests that are actively in flight on it.
///
/// ## Why this exists
///
/// `package:http`'s `IOClient.close()` calls `dart:io`'s
/// `HttpClient.close(force: true)`, which — per its own docs — "terminates
/// all active connections" and "The behavior of `close` is not defined if
/// there are requests executing when `close` is called." In practice this
/// force-aborts the TCP socket for *every* request currently using that
/// client, including ones that have nothing to do with why the client is
/// being replaced.
///
/// `ApiService` shares a single production `http.Client` across every
/// endpoint (GETs, JSON POST/PUT/PATCH/DELETE, and multipart uploads) and
/// replaces it in two situations:
///   1. [ApiService.recycleProductionHttpClient] is called from
///      `_withStaleClientRetry` when *one* request hits a stale-connection
///      error (broken pipe / connection reset / bad file descriptor — see
///      `isStaleHttpClientError`), and from `AppWithDeepLinks`'s
///      `didChangeAppLifecycleState` on every app resume (iOS silently
///      reclaims idle keep-alive sockets while backgrounded).
///   2. A caller's own resilience loop (e.g.
///      `SellListingMediaUpload._uploadImagesResilient`) recycles between
///      retry attempts.
///
/// Without this wrapper, closing the shared client in either case would
/// force-abort *any other* request concurrently in flight on it — e.g. a
/// multipart video upload that is happily streaming its body — producing
/// exactly the production symptom this class fixes: `ClientException:
/// Content size below specified contentLength` (the socket died mid-write,
/// so fewer bytes reached the server than the `Content-Length` header
/// promised), for a request that was never itself retried or reused.
///
/// [TrackedHttpClient] tracks how many [send] calls are currently in
/// flight. [closeWhenIdle] only closes the underlying client once that
/// count reaches zero; if requests are active, the close is deferred until
/// the last one finishes. New requests are never routed through a
/// "closing" instance in the first place — callers are expected to swap in
/// a brand new [TrackedHttpClient] for new requests (see
/// [ApiService.recycleProductionHttpClient]) and only call [closeWhenIdle]
/// on the outgoing one.
class TrackedHttpClient extends http.BaseClient {
  TrackedHttpClient(this._inner);

  final http.Client _inner;
  int _active = 0;
  bool _closeRequested = false;
  bool _closed = false;

  /// Number of [send] calls currently awaiting [http.Client.send] on the
  /// wrapped client. Exposed `@visibleForTesting`-style for regression
  /// tests; safe to read in production too.
  int get activeRequestCount => _active;

  /// Whether [closeWhenIdle] has been called on this instance.
  bool get closeRequested => _closeRequested;

  /// Whether the underlying client has actually been closed yet.
  bool get isClosed => _closed;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      // Mirrors IOClient's own "client is already closed" message so
      // existing `isStaleHttpClientError`/error-mapping logic elsewhere
      // still recognizes this as a class of transport failure, not a new
      // unclassified crash. This should be unreachable in practice: a
      // caller only ever holds a reference to the *current* client via
      // `ApiService._httpClient`, and a retired instance is never handed
      // out for new work (see class docs).
      throw http.ClientException(
        'HTTP request failed. Client is already closed.',
        request.url,
      );
    }
    _active++;
    try {
      return await _inner.send(request);
    } finally {
      _active--;
      _maybeCloseNow();
    }
  }

  void _maybeCloseNow() {
    if (_closeRequested && !_closed && _active <= 0) {
      _closed = true;
      try {
        _inner.close();
      } catch (_) {
        // Best-effort, matching the prior `try { previous.close(); } catch
        // (_) {}` behavior in ApiService.recycleProductionHttpClient.
      }
    }
  }

  /// Retires this client: closes the underlying [http.Client] immediately
  /// if nothing is using it right now, or defers the close until every
  /// in-flight [send] call finishes.
  ///
  /// This is the safe replacement for calling `close()` directly on a
  /// client that might still have active requests (e.g. a multipart
  /// upload's body still streaming) — see class docs.
  void closeWhenIdle() {
    _closeRequested = true;
    _maybeCloseNow();
  }

  /// Alias for [closeWhenIdle] so this remains a drop-in [http.Client].
  /// Prefer calling [closeWhenIdle] explicitly at call sites for clarity.
  @override
  void close() => closeWhenIdle();
}
