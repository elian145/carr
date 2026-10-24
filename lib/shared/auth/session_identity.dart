import 'dart:convert';

/// Reads WHO a persisted session belongs to straight from its own tokens.
///
/// Every access and refresh token the backend issues carries the account's
/// stable public id as its `sub` claim (`create_access_token(identity=
/// user.public_id)`), and `/auth/me` returns that same value as `id`. The
/// tokens are already persisted in secure storage (see `TokenStore`) and are
/// loaded before the first frame, so the signed-in account's id is known on a
/// cold start *without* waiting for a `/auth/me` round trip.
///
/// Why this instead of persisting a separate "last user id":
///  * it can never drift from the session: the identity IS the token in use,
///    so logout, a rejected session, or logging in as someone else changes it
///    automatically;
///  * nothing extra to store, protect, migrate or invalidate -- existing
///    installs already hold tokens carrying it.
///
/// SECURITY: the claim is decoded WITHOUT verifying the signature (the client
/// has no key, by design). The result is therefore only a *presentation
/// hint* -- "which account does this device think it is signed in as" -- and
/// is never an authorization decision. Every owner action is still
/// authorized by the backend from the token it receives; a forged or stale
/// hint can at worst show a button that the server then rejects.
class SessionIdentity {
  SessionIdentity._();

  /// Public ids are UUIDs (or legacy hex strings). Anything else -- notably
  /// the legacy numeric / `user:<n>` identities the backend still tolerates
  /// -- is not a public id and must not be mistaken for one.
  static final RegExp _publicIdShape = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{5,63}$');

  /// Seconds of slack when comparing `exp` to the local clock.
  static const int _clockSkewSeconds = 60;

  /// The public id the session made of [accessToken] / [refreshToken]
  /// belongs to, or `null` when it cannot be established safely.
  ///
  /// The access token is preferred, but an EXPIRED access token (typical on a
  /// cold start after >30 minutes) falls back to the refresh token, which
  /// names the same account and lives for days. `null` when:
  ///  * neither token is a well-formed JWT with a public-id `sub`;
  ///  * every usable token is expired (the session is dead; the server will
  ///    reject it and the app clears it);
  ///  * the two tokens disagree about the account (inconsistent -> distrust).
  ///
  /// With [ignoreExpiry] the account the tokens were ISSUED for is returned
  /// even if they have expired -- used only to tell "this cached profile
  /// belongs to the session's account" from "it belongs to someone else",
  /// never to grant anything on its own.
  static String? fromTokens({
    String? accessToken,
    String? refreshToken,
    DateTime? now,
    bool ignoreExpiry = false,
  }) {
    final at = now ?? DateTime.now();
    final access = _read(accessToken);
    final refresh = _read(refreshToken);

    if (tokensConflict(accessToken: accessToken, refreshToken: refreshToken)) {
      return null;
    }
    final accessId =
        (access != null && (ignoreExpiry || !access.expired(at)))
        ? access.sub
        : null;
    final refreshId =
        (refresh != null && (ignoreExpiry || !refresh.expired(at)))
        ? refresh.sub
        : null;
    return accessId ?? refreshId;
  }

  /// True when the two tokens name DIFFERENT accounts (even if expired): the
  /// stored session is inconsistent and must not be trusted for identity.
  static bool tokensConflict({String? accessToken, String? refreshToken}) {
    final a = _read(accessToken)?.sub;
    final r = _read(refreshToken)?.sub;
    return a != null && r != null && a != r;
  }

  /// The public id in [jwt]'s `sub` claim, or null if it is malformed, not a
  /// public id, or expired. Exposed for tests.
  static String? subjectOf(String? jwt, {DateTime? now}) {
    final claims = _read(jwt);
    if (claims == null || claims.expired(now ?? DateTime.now())) return null;
    return claims.sub;
  }

  static _Claims? _read(String? jwt) {
    final token = (jwt ?? '').trim();
    if (token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = json.decode(payload);
      if (decoded is! Map) return null;
      final rawSub = decoded['sub'];
      final sub = rawSub is String ? rawSub.trim() : '';
      final validSub = sub.isNotEmpty &&
          _publicIdShape.hasMatch(sub) &&
          // Reject legacy numeric identities.
          !RegExp(r'^\d+$').hasMatch(sub);
      final rawExp = decoded['exp'];
      final exp = rawExp is num ? rawExp.toInt() : null;
      return _Claims(validSub ? sub : null, exp);
    } catch (_) {
      return null;
    }
  }
}

class _Claims {
  const _Claims(this.sub, this.exp);

  final String? sub;
  final int? exp;

  bool expired(DateTime now) {
    final e = exp;
    if (e == null) return false;
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    return e + SessionIdentity._clockSkewSeconds <= nowSeconds;
  }
}
