import 'dart:convert';

/// Builds an UNSIGNED, JWT-shaped token whose `sub` is [subject].
///
/// The app only reads the `sub` claim locally (account-ownership scoping, see
/// `accountIdFromJwt`); the signature is verified by the backend, never by the
/// client. [nonce] makes otherwise-identical tokens distinct (every real login
/// issues a new token).
String testJwt(
  String subject, {
  Object? nonce,
  String type = 'access',
  Duration expiresIn = const Duration(hours: 1),
}) {
  String enc(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(json.encode(m))).replaceAll('=', '');
  final header = enc({'alg': 'none', 'typ': 'JWT'});
  final payload = enc({
    'sub': subject,
    'type': type,
    if (nonce != null) 'n': nonce.toString(),
    'exp': DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000,
  });
  return '$header.$payload.test-signature';
}

/// Subject of a token built by [testJwt] (test backends only).
String? testJwtSubject(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = json.decode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return payload is Map ? payload['sub']?.toString() : null;
  } catch (_) {
    return null;
  }
}
