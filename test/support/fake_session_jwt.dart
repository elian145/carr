import 'dart:convert';

/// Builds a JWT shaped like the ones the backend issues (`sub` = the
/// account's public id, `exp`, `type`). The signature is a placeholder: the
/// client never verifies it.
String fakeSessionJwt(
  String sub, {
  Duration expiresIn = const Duration(minutes: 30),
  String type = 'access',
  Map<String, dynamic>? extraClaims,
  bool includeSub = true,
}) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(json.encode(m))).replaceAll('=', '');
  final exp =
      DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  return [
    b64({'alg': 'HS256', 'typ': 'JWT'}),
    b64({
      if (includeSub) 'sub': sub,
      'exp': exp,
      'type': type,
      'fresh': false,
      ...?extraClaims,
    }),
    'signature',
  ].join('.');
}
