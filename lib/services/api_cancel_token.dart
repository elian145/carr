import 'dart:async';

/// Cooperative cancellation signal for a single read-only GET request (F-06).
///
/// Deliberately minimal: no chaining, no linked/child tokens, no reasons —
/// just "not cancelled yet" / "cancelled". Wraps a single [Completer] whose
/// [whenCancelled] future is threaded straight into `package:http`'s
/// `Abortable.abortTrigger` (see `_sendAbortableGet` in
/// `lib/services/api/api_http.dart`), so calling [cancel] triggers genuine
/// abortion of the underlying `dart:io`/browser HTTP request via
/// `IOClient`/`BrowserClient` — not merely an early return from a `await`.
///
/// Scoped to GET requests only. Do not use this for POST/PUT/PATCH/DELETE or
/// multipart uploads: aborting a write mid-flight risks orphaning a request
/// the server may already be processing or has already durably applied
/// (see BE-18/API-01's idempotency handling for why writes are excluded).
class ApiCancelToken {
  final Completer<void> _completer = Completer<void>();

  /// Whether [cancel] has already been called.
  bool get isCancelled => _completer.isCompleted;

  /// Future passed as `Abortable.abortTrigger`. Completes exactly once, when
  /// [cancel] is called, and never completes with an error — required by
  /// `Abortable.abortTrigger`'s own contract ("This future must not
  /// complete with an error.").
  Future<void> get whenCancelled => _completer.future;

  /// Requests cancellation of the request(s) this token was passed to.
  ///
  /// Idempotent — safe to call more than once (e.g. once from a widget's
  /// `dispose()` and, defensively, again elsewhere).
  void cancel() {
    if (_completer.isCompleted) return;
    _completer.complete();
  }
}
