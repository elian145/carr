/// HTTP/API failure surfaced by [ApiService] and related clients.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? body;

  ApiException({required this.statusCode, required this.message, this.body});

  /// Machine-readable error code from JSON body, e.g. `phone_verification_required`.
  String? get errorCode {
    final raw = body?['code'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return null;
  }

  @override
  String toString() => message;
}

/// Thrown when a GET request is intentionally cancelled via [ApiCancelToken]
/// (e.g. the screen that started it was disposed before it completed) —
/// see F-06.
///
/// Deliberately distinct from every real failure mode so callers can tell
/// "the caller stopped caring" apart from an actual network/server problem
/// and silently discard the result instead of surfacing an error:
/// - [ApiException] — a real HTTP status failure (404/401/429/5xx/...).
/// - [TimeoutException] (`dart:async`) — the adaptive/fixed request timeout
///   expired while a response was still pending.
/// - [FormatException] — an empty/malformed/unexpectedly-shaped 200 body.
/// - Transport failures (e.g. `SocketException`) — a genuine connectivity
///   problem, unrelated to cancellation.
///
/// Existing callers that never pass an [ApiCancelToken] can never observe
/// this exception — it is only ever thrown when a token they explicitly
/// opted into was cancelled.
class ApiCancelledException implements Exception {
  const ApiCancelledException();

  @override
  String toString() => 'ApiCancelledException: request was cancelled';
}
