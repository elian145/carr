import 'dart:convert';

/// Extracts the `sub` (account id) claim from a JWT **for local ownership
/// bookkeeping only**.
///
/// This does NOT verify the signature and must never be used for an
/// authorization decision. It is only used to key private on-device data
/// (saved searches, pending chat sends, caches) by account, so that data
/// written under one account is never shown to, or sent as, another.
///
/// Fails closed: returns `null` for anything that is not a well-formed JWT
/// carrying a non-empty string `sub`, and for the LEGACY subject forms the
/// backend still tolerates on old sessions (purely numeric ids, `user:<n>`):
/// those are not public ids, never equal what `/auth/me` reports, and must
/// neither become an owner key nor end an otherwise valid session. Such a
/// session simply has no private-data owner until its first token refresh
/// (the refreshed token carries the public id).
///
/// The backend sets `sub` to `User.public_id` (the same value `/auth/me`
/// returns as `id`); the app cross-checks the two after the profile loads
/// (see `AuthService`).
String? accountIdFromJwt(String? token) {
  final t = (token ?? '').trim();
  if (t.isEmpty) return null;
  final parts = t.split('.');
  if (parts.length != 3) return null;
  try {
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    final decoded = json.decode(utf8.decode(base64.decode(payload)));
    if (decoded is! Map) return null;
    final sub = decoded['sub'];
    if (sub is! String) return null;
    final id = sub.trim();
    if (id.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(id) || id.contains(':')) return null;
    return id;
  } catch (_) {
    return null;
  }
}

/// Identity of the authentication session a request / operation started in.
///
/// [epoch] changes on every authentication transition (login, logout, token
/// clear, account change), including "logout and log in again as the same
/// account", so an operation started in an earlier session can be recognised
/// and abandoned even when the account id is unchanged.
class AuthSessionSnapshot {
  const AuthSessionSnapshot({
    required this.epoch,
    required this.accountId,
    required this.authenticated,
  });

  final int epoch;

  /// Validated owner id (JWT `sub`), or `null` when unknown / inconsistent.
  final String? accountId;

  /// Whether the operation carried credentials. This only scopes caches and
  /// distinguishes public GETs; it does NOT exempt the operation from session
  /// checks: an account-sensitive operation that started without credentials
  /// is still invalidated by any later authentication transition.
  final bool authenticated;
}
