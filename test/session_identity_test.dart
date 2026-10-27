// The signed-in account's public id is restored from the persisted session's
// own tokens, so ownership can be decided on the first frame of a cold start
// instead of waiting for `/auth/me`. These tests pin the parser and the
// `AuthService.userId` / invalidation / recovery behaviour built on it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/connectivity_service.dart';
import 'package:car_listing_app/shared/auth/session_identity.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_session_jwt.dart';

const _a = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const _b = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';

String _rawJwt(Object payload) {
  String b64(String s) =>
      base64Url.encode(utf8.encode(s)).replaceAll('=', '');
  return '${b64('{"alg":"HS256"}')}.${b64(json.encode(payload))}.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionIdentity.subjectOf', () {
    test('reads the public id from a valid token', () {
      expect(SessionIdentity.subjectOf(fakeSessionJwt(_a)), _a);
    });

    test('rejects malformed / empty / non-JWT input', () {
      for (final bad in <String?>[
        null,
        '',
        '   ',
        'access',
        'a.b',
        'a.b.c.d',
        'x.!!!notbase64!!!.y',
        'x.${base64Url.encode(utf8.encode('not json'))}.y',
        'x.${base64Url.encode(utf8.encode('[1,2]'))}.y',
      ]) {
        expect(SessionIdentity.subjectOf(bad), isNull, reason: '$bad');
      }
    });

    test('rejects a token without a usable subject', () {
      expect(
        SessionIdentity.subjectOf(fakeSessionJwt(_a, includeSub: false)),
        isNull,
      );
      expect(SessionIdentity.subjectOf(_rawJwt({'sub': 42})), isNull);
      expect(SessionIdentity.subjectOf(_rawJwt({'sub': ''})), isNull);
    });

    test('legacy numeric / "user:<n>" identities are not public ids', () {
      for (final legacy in ['7', '12345', 'user:7', 'user:12345']) {
        expect(
          SessionIdentity.subjectOf(_rawJwt({'sub': legacy})),
          isNull,
          reason: legacy,
        );
      }
    });

    test('an expired token yields nothing; a token with no exp is accepted', () {
      expect(
        SessionIdentity.subjectOf(
          fakeSessionJwt(_a, expiresIn: const Duration(minutes: -10)),
        ),
        isNull,
      );
      expect(SessionIdentity.subjectOf(_rawJwt({'sub': _a})), _a);
    });
  });

  group('SessionIdentity.fromTokens', () {
    test('prefers the access token', () {
      expect(
        SessionIdentity.fromTokens(
          accessToken: fakeSessionJwt(_a),
          refreshToken: fakeSessionJwt(_a, type: 'refresh'),
        ),
        _a,
      );
    });

    test('expired access token (cold start after >30 min) falls back to the '
        'still-valid refresh token', () {
      expect(
        SessionIdentity.fromTokens(
          accessToken: fakeSessionJwt(
            _a,
            expiresIn: const Duration(hours: -2),
          ),
          refreshToken: fakeSessionJwt(
            _a,
            type: 'refresh',
            expiresIn: const Duration(days: 20),
          ),
        ),
        _a,
      );
    });

    test('both expired -> null (the session is dead)', () {
      expect(
        SessionIdentity.fromTokens(
          accessToken: fakeSessionJwt(_a, expiresIn: const Duration(hours: -2)),
          refreshToken: fakeSessionJwt(
            _a,
            type: 'refresh',
            expiresIn: const Duration(days: -1),
          ),
        ),
        isNull,
      );
    });

    test('tokens that name DIFFERENT accounts are distrusted', () {
      expect(
        SessionIdentity.fromTokens(
          accessToken: fakeSessionJwt(_a),
          refreshToken: fakeSessionJwt(_b, type: 'refresh'),
        ),
        isNull,
      );
    });

    test('no tokens / opaque tokens -> null', () {
      expect(SessionIdentity.fromTokens(), isNull);
      expect(
        SessionIdentity.fromTokens(accessToken: 'abc', refreshToken: 'def'),
        isNull,
      );
    });
  });

  group('AuthService.userId (session-restored identity)', () {
    var meCalls = 0;
    Completer<void>? meGate;
    Completer<void>? logoutGate;
    var meDown = false;
    String meId = _a;

    http.Client client() => MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/me')) {
        meCalls++;
        final gate = meGate;
        if (gate != null) await gate.future;
        if (meDown) throw const SocketException('Network is unreachable');
        return http.Response(
          json.encode({
            'user': {'id': meId, 'username': 'u', 'account_type': 'individual'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/auth/logout')) {
        final gate = logoutGate;
        if (gate != null) await gate.future;
      }
      return http.Response('{}', 200);
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({'push_enabled': false});
      TokenStore.testMode = true;
      meCalls = 0;
      meGate = null;
      logoutGate = null;
      meDown = false;
      meId = _a;
      AuthService().resetTestSession();
      ApiService.testHttpClient = client();
      await ApiService.setTokens(
        accessToken: fakeSessionJwt(_a),
        refreshToken: fakeSessionJwt(_a, type: 'refresh'),
      );
    });

    tearDown(() async {
      ApiService.testHttpClient = null;
      AuthService().resetTestSession();
      await ApiService.clearTokens();
      ConnectivityService.instance.isOnline.value = true;
      TokenStore.testMode = false;
      TokenStore.resetForTests();
    });

    test('is known immediately from the restored session, with NO /auth/me',
        () {
      expect(AuthService().currentUser, isNull);
      expect(AuthService().userId, _a);
      expect(meCalls, 0);
    });

    test('stays the same when the profile arrives (no identity change)',
        () async {
      var seen = <String?>[];
      void listener() => seen.add(AuthService().userId);
      AuthService().addListener(listener);
      addTearDown(() => AuthService().removeListener(listener));

      await AuthService().refreshProfile();
      expect(AuthService().userId, _a);
      expect(seen, isNotEmpty);
      expect(seen.toSet(), {_a}, reason: 'never null / never another id');
    });

    test('slow /auth/me: identity is already available while it is pending',
        () async {
      meGate = Completer<void>();
      final load = AuthService().refreshProfile();
      await Future<void>.delayed(Duration.zero);
      expect(AuthService().userId, _a);
      meGate!.complete();
      await load;
      expect(AuthService().userId, _a);
    });

    test('token loss with NO profile ever loaded still notifies and clears '
        'the identity', () async {
      var notified = 0;
      void listener() => notified++;
      AuthService().addListener(listener);
      addTearDown(() => AuthService().removeListener(listener));
      expect(AuthService().userId, _a); // the UI has seen it

      await ApiService.clearTokens();

      expect(notified, greaterThan(0));
      expect(AuthService().userId, isNull);
    });

    test('a profile left over from the PREVIOUS account does not win over '
        'the tokens now in use (account switch)', () async {
      await AuthService().refreshProfile();
      expect(AuthService().userId, _a);

      await ApiService.setTokens(
        accessToken: fakeSessionJwt(_b),
        refreshToken: fakeSessionJwt(_b, type: 'refresh'),
      );
      expect(AuthService().userId, _b, reason: 'tokens are the session');
    });

    test('logout drops the identity immediately, before the server call '
        'returns', () async {
      await AuthService().refreshProfile();
      logoutGate = Completer<void>();
      var notified = 0;
      void listener() => notified++;
      AuthService().addListener(listener);
      addTearDown(() => AuthService().removeListener(listener));

      final done = AuthService().logout();
      await Future<void>.delayed(Duration.zero);
      expect(AuthService().userId, isNull);
      expect(notified, greaterThan(0));

      logoutGate!.complete();
      await done;
      expect(AuthService().userId, isNull);
      expect(ApiService.isAuthenticated, isFalse);
    });

    test('a definitive 401 from /auth/me ends the session and the identity',
        () async {
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/me') ||
            request.url.path.endsWith('/auth/refresh')) {
          return http.Response('{"message":"expired"}', 401);
        }
        return http.Response('{}', 200);
      });
      expect(AuthService().userId, _a);
      await AuthService().refreshProfile();
      expect(ApiService.isAuthenticated, isFalse);
      expect(AuthService().userId, isNull);
    });

    test('opaque (legacy) tokens: no restored identity, falls back to the '
        'profile', () async {
      await ApiService.setTokens(accessToken: 'opaque', refreshToken: 'opaque2');
      expect(AuthService().userId, isNull);
      await AuthService().refreshProfile();
      expect(AuthService().userId, _a);
    });

    test('temporary /auth/me failure: identity stays, bounded retry heals it '
        'with no user action', () async {
      meDown = true;
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(milliseconds: 20),
        Duration(milliseconds: 20),
      ];
      await AuthService().refreshProfile();
      expect(AuthService().userId, _a, reason: 'identity survives the failure');
      expect(AuthService().currentUser, isNull);

      meDown = false;
      for (var i = 0; i < 50 && AuthService().currentUser == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(AuthService().currentUser, isNotNull);
      expect(AuthService().userId, _a);
    });

    test('connectivity coming back recovers a stranded profile by itself',
        () async {
      meDown = true;
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(minutes: 30),
      ];
      AuthService().hookConnectivityRecovery();
      AuthService().hookConnectivityRecovery(); // idempotent

      ConnectivityService.instance.isOnline.value = false;
      await AuthService().refreshProfile();
      expect(AuthService().isProfileStranded, isTrue);
      final before = meCalls;

      meDown = false;
      ConnectivityService.instance.isOnline.value = true; // back online
      for (var i = 0; i < 50 && AuthService().currentUser == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(AuthService().currentUser, isNotNull);
      expect(
        meCalls,
        before + 1,
        reason: 'exactly one recovery request (single-flight)',
      );
    });

    test('a LATE /auth/me response that started under an ended session '
        '(logout / rejection) is discarded and cannot restore the identity',
        () async {
      meGate = Completer<void>();
      final load = AuthService().refreshProfile();
      await Future<void>.delayed(Duration.zero);
      expect(AuthService().userId, _a);

      await ApiService.clearTokens(); // logout / session lost
      expect(AuthService().userId, isNull);

      meGate!.complete(); // the old response finally arrives
      await load;
      expect(AuthService().currentUser, isNull);
      expect(AuthService().isAuthenticated, isFalse);
      expect(AuthService().userId, isNull);
      expect(ApiService.isAuthenticated, isFalse);
    });

    test('a LATE /auth/me response for account A cannot overwrite the '
        'session after switching to account B', () async {
      meGate = Completer<void>();
      meId = _a;
      final load = AuthService().refreshProfile();
      await Future<void>.delayed(Duration.zero);

      await ApiService.setTokens(
        accessToken: fakeSessionJwt(_b),
        refreshToken: fakeSessionJwt(_b, type: 'refresh'),
      );
      meGate!.complete();
      await load;

      expect(AuthService().currentUser, isNull, reason: "A's profile dropped");
      expect(AuthService().userId, _b);
      expect(AuthService().isAuthenticated, isFalse);
    });

    test('a LATE /auth/me response arriving after logout then a fresh login '
        'as ANOTHER account is discarded too', () async {
      meGate = Completer<void>();
      final load = AuthService().refreshProfile();
      await Future<void>.delayed(Duration.zero);
      await ApiService.clearTokens();
      await ApiService.setTokens(
        accessToken: fakeSessionJwt(_b),
        refreshToken: fakeSessionJwt(_b, type: 'refresh'),
      );
      meGate!.complete();
      await load;
      expect(AuthService().currentUser, isNull);
      expect(AuthService().userId, _b);
    });

    group('a stale cached profile never grants identity against the '
        'active session', () {
      late void Function()? savedHook;

      setUp(() async {
        await AuthService().refreshProfile();
        expect(AuthService().userId, _a);
        // Simulate the stale state directly: the hook that normally wipes the
        // cached profile on token loss is suspended, so only the identity
        // rules themselves are under test.
        savedHook = ApiService.onTokensCleared;
        ApiService.onTokensCleared = null;
      });

      tearDown(() => ApiService.onTokensCleared = savedHook);

      test('no session at all -> null', () async {
        await ApiService.clearTokens();
        expect(AuthService().currentUser, isNotNull, reason: 'stale cache');
        expect(AuthService().userId, isNull);
      });

      test('tokens of a DIFFERENT account -> that account, never the cache',
          () async {
        await ApiService.setTokens(
          accessToken: fakeSessionJwt(_b),
          refreshToken: fakeSessionJwt(_b, type: 'refresh'),
        );
        expect(AuthService().userId, _b);
      });

      test('EXPIRED tokens of a different account -> null', () async {
        await ApiService.setTokens(
          accessToken: fakeSessionJwt(_b, expiresIn: const Duration(hours: -3)),
          refreshToken: fakeSessionJwt(
            _b,
            type: 'refresh',
            expiresIn: const Duration(days: -2),
          ),
        );
        expect(AuthService().userId, isNull);
      });

      test('expired tokens of the SAME account (e.g. wrong device clock) '
          'keep the matching profile', () async {
        await ApiService.setTokens(
          accessToken: fakeSessionJwt(_a, expiresIn: const Duration(hours: -3)),
          refreshToken: fakeSessionJwt(
            _a,
            type: 'refresh',
            expiresIn: const Duration(days: -2),
          ),
        );
        expect(AuthService().userId, _a);
      });

      test('inconsistent tokens (access=A, refresh=B) -> null', () async {
        // `setTokens` itself refuses to install such a pair (see
        // auth_attempt_race_test); a pair like this can only come back from
        // corrupted persisted storage, which must still fail closed.
        await TokenStore.save(
          fakeSessionJwt(_a, expiresIn: const Duration(hours: -3)),
        );
        await TokenStore.saveRefresh(
          fakeSessionJwt(
            _b,
            type: 'refresh',
            expiresIn: const Duration(days: -2),
          ),
        );
        await ApiService.initializeTokens();
        expect(AuthService().userId, isNull);
      });
    });

    test('token ROTATION for the same account (refresh while /auth/me is '
        'in flight) keeps the profile and never changes or blanks the id',
        () async {
      meGate = Completer<void>();
      final load = AuthService().refreshProfile();
      await Future<void>.delayed(Duration.zero);

      final seen = <String?>[];
      void listener() => seen.add(AuthService().userId);
      AuthService().addListener(listener);
      addTearDown(() => AuthService().removeListener(listener));

      await ApiService.setTokens(
        accessToken: fakeSessionJwt(_a), // new token, same account
        refreshToken: fakeSessionJwt(_a, type: 'refresh'),
      );
      expect(AuthService().userId, _a);
      meGate!.complete();
      await load;

      expect(AuthService().currentUser, isNotNull, reason: 'not discarded');
      expect(AuthService().userId, _a);
      expect(seen.toSet().difference({_a}), isEmpty, reason: 'no flicker');
    });

    test('real refresh flow: expired access token -> 401 -> refresh -> '
        'profile loads, identity stable throughout', () async {
      final expired = fakeSessionJwt(_a, expiresIn: const Duration(hours: -1));
      final fresh = fakeSessionJwt(_a);
      final freshRefresh = fakeSessionJwt(
        _a,
        type: 'refresh',
        expiresIn: const Duration(days: 30),
      );
      await ApiService.setTokens(
        accessToken: expired,
        refreshToken: fakeSessionJwt(
          _a,
          type: 'refresh',
          expiresIn: const Duration(days: 20),
        ),
      );
      var refreshCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/refresh')) {
          refreshCalls++;
          return http.Response(
            json.encode({'access_token': fresh, 'refresh_token': freshRefresh}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('/auth/me')) {
          meCalls++;
          if (request.headers['Authorization'] == 'Bearer $expired') {
            return http.Response('{"message":"expired"}', 401);
          }
          return http.Response(
            json.encode({
              'user': {'id': _a, 'username': 'u', 'account_type': 'individual'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      });

      final seen = <String?>[];
      void listener() => seen.add(AuthService().userId);
      AuthService().addListener(listener);
      addTearDown(() => AuthService().removeListener(listener));
      expect(AuthService().userId, _a, reason: 'known before any request');

      await AuthService().refreshProfile();

      expect(refreshCalls, 1);
      expect(ApiService.accessToken, fresh, reason: 'token rotated');
      expect(AuthService().currentUser, isNotNull);
      expect(AuthService().userId, _a);
      expect(seen.toSet().difference({_a}), isEmpty, reason: 'no flicker');
    });

    test('connectivity recovery does nothing when the profile is loaded',
        () async {
      await AuthService().refreshProfile();
      AuthService().hookConnectivityRecovery();
      final before = meCalls;
      ConnectivityService.instance.isOnline.value = false;
      ConnectivityService.instance.isOnline.value = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(meCalls, before);
    });
  });
}
