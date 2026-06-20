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
