// Authentication-attempt races and access/refresh pairing.
//
// 1. A login / OTP-verification response that arrives after a NEWER login, a
//    logout, an account switch or a cancelled attempt must never install
//    credentials: it is stale and must not replace the current session.
// 2. An access token may never be installed alongside a refresh token that
//    belongs to another account (or to an unprovable session).
//
// Every race is forced with controlled barriers (a mock server parks one
// response until the test opens its gate) -- never with sleeps.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/prefs/account_local_data.dart';

import 'support/test_jwt.dart';

class _Gate {
  final Completer<void> _reached = Completer<void>();
  final Completer<void> _release = Completer<void>();
  bool _armed = true;
  Future<void> get reached => _reached.future;
  Future<void> hit() async {
    if (!_armed) return;
    _armed = false;
    _reached.complete();
    await _release.future;
  }

  void open() {
    if (!_release.isCompleted) _release.complete();
  }
}

class _Srv {
  final Set<String> valid = <String>{};
  final Map<String, _Gate> gates = <String, _Gate>{};
  int _n = 0;

  /// When set, /auth/login hands out a refresh token for THIS subject
  /// (a server/proxy bug or hostile response pairing two accounts).
  String? refreshSubjectOverride;

  http.Response _j(int code, Object body) => http.Response(
        json.encode(body),
        code,
        headers: {'content-type': 'application/json'},
      );

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    final h = r.headers['Authorization'] ?? r.headers['authorization'];
    final bearer =
        (h != null && h.startsWith('Bearer ')) ? h.substring(7) : null;
    final Map<String, dynamic> body =
        r.body.isEmpty ? <String, dynamic>{} : json.decode(r.body);

    String issue(String acct) {
      final access = testJwt(acct, nonce: 'i${++_n}');
      valid.add(access);
      return access;
    }

    if (path.endsWith('/auth/login')) {
      final acct = (body['username'] ?? '').toString();
      final g = gates['login:$acct'];
      if (g != null) await g.hit();
      return _j(200, {
        'access_token': issue(acct),
        'refresh_token': testJwt(
          refreshSubjectOverride ?? acct,
          nonce: 'r$_n',
          type: 'refresh',
        ),
      });
    }
    if (path.endsWith('/auth/phone/verify')) {
      final phone = (body['phone_number'] ?? '').toString();
      final acct = 'ph${phone.substring(phone.length - 4)}';
      final g = gates['verify:$acct'];
      if (g != null) await g.hit();
      return _j(200, {
        'access_token': issue(acct),
        'refresh_token': testJwt(acct, nonce: 'r$_n', type: 'refresh'),
      });
    }
    if (path.endsWith('/auth/logout')) return _j(200, {});
    if (path.endsWith('/auth/refresh')) return _j(401, {'message': 'no'});
    if (bearer == null || !valid.contains(bearer)) {
      return _j(401, {'message': 'unauthorized'});
    }
    final actor = testJwtSubject(bearer);
    if (path.endsWith('/auth/me')) {
      final g = gates['me:$actor'];
      if (g != null) await g.hit();
      return _j(200, {'id': actor, 'username': actor});
    }
    return _j(404, {'message': 'nf'});
  }
}

late _Srv _srv;
int _n = 0;

Future<Object?> outcome(Future<Object?> f) =>
    f.then<Object?>((v) => v, onError: (Object e) => e);

Future<String?> marker() async =>
    (await SharedPreferences.getInstance()).getString(
      AccountLocalData.markerKey,
    );

Future<void> signedInAs(String acct) {
  final access = testJwt(acct, nonce: 's${++_n}');
  _srv.valid.add(access);
  return ApiService.setTokens(
    accessToken: access,
    refreshToken: testJwt(acct, nonce: 'sr$_n', type: 'refresh'),
  );
}

Future<Map<String, dynamic>> viaPassword(String acct) =>
    ApiService.login(acct, 'pw');

Future<Map<String, dynamic>> viaOtp(String last4) =>
    ApiService.phoneVerify(phoneNumber: '+9647501$last4', code: '123456');

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() async {
    TokenStore.testMode = true;
    TokenStore.resetForTests();
    TokenStore.debugIoGate = null;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    _srv = _Srv();
    ApiService.testHttpClient = MockClient(_srv.handle);
    ApiService.debugResetSessionForTests();
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDown(() async {
    TokenStore.debugIoGate = null;
    await ApiService.clearTokens();
    ApiService.testHttpClient = null;
    AuthService().resetTestSession();
    // ignore: invalid_use_of_visible_for_testing_member
    AccountLocalData.debugReset();
    TokenStore.resetForTests();
  });

  // =========================================================================
  group('1. stale login / OTP responses', () {
    test('control: an uncontested login installs its session', () async {
      await viaPassword('A');
      expect(ApiService.currentAccountId, 'A');
      expect(testJwtSubject(TokenStore.token), 'A');
      expect(await marker(), 'A');
    });

    test('control: logging in again after a logout works', () async {
      await viaPassword('A');
      await ApiService.clearTokens();
      await viaPassword('A');
      expect(ApiService.currentAccountId, 'A');
    });

    test('control: logging in while another account is signed in switches '
        'to the new account', () async {
      await signedInAs('B');
      await viaPassword('A');
      expect(ApiService.currentAccountId, 'A');
      expect(ApiService.refreshToken, isNotNull);
      expect(testJwtSubject(ApiService.refreshToken), 'A');
    });

    test('A/B overlapping logins: A\'s slow response arrives AFTER B\'s '
        'login finished and must not replace B', () async {
      final gateA = _srv.gates['login:A'] = _Gate();
      final a = outcome(viaPassword('A'));
      await gateA.reached;
      await viaPassword('B'); // newer login starts and completes
      final bAccess = ApiService.accessToken;
      final bRefresh = ApiService.refreshToken;
      gateA.open();

      expect(await a, isA<ApiSessionChangedException>());
      expect(ApiService.accessToken, bAccess);
      expect(ApiService.refreshToken, bRefresh);
      expect(ApiService.currentAccountId, 'B');
      expect(testJwtSubject(TokenStore.token), 'B');
      expect(testJwtSubject(TokenStore.refreshToken), 'B');
      expect(await marker(), 'B');
    });

    test('A/B overlapping logins: A responds FIRST while B (the newer '
        'attempt) is still in flight - A is already superseded', () async {
      final gateA = _srv.gates['login:A'] = _Gate();
      final gateB = _srv.gates['login:B'] = _Gate();
      final a = outcome(viaPassword('A'));
      await gateA.reached;
      final b = outcome(viaPassword('B'));
      await gateB.reached;

      gateA.open();
      expect(await a, isA<ApiSessionChangedException>());
      expect(ApiService.isAuthenticated, isFalse,
          reason: 'a superseded attempt must not install even briefly');

      gateB.open();
      expect(await b, isA<Map<String, dynamic>>());
      expect(ApiService.currentAccountId, 'B');
      expect(await marker(), 'B');
    });

    test('login vs logout: a login that was still in flight when the user '
        'signed out never installs', () async {
      await signedInAs('B');
      final gateA = _srv.gates['login:A'] = _Gate();
      final a = outcome(viaPassword('A'));
      await gateA.reached;
      await ApiService.clearTokens(); // user signs out meanwhile
      gateA.open();

      expect(await a, isA<ApiSessionChangedException>());
      expect(ApiService.isAuthenticated, isFalse);
      expect(ApiService.currentAccountId, isNull);
      expect(TokenStore.token, isNull);
      expect(TokenStore.refreshToken, isNull);
      expect(await marker(), AccountLocalData.guestOwner);
    });

    test('login vs ApiService.logout (server revocation round trip)',
        () async {
      final gateA = _srv.gates['login:A'] = _Gate();
      final a = outcome(viaPassword('A'));
      await gateA.reached;
      await ApiService.logout();
      gateA.open();
      expect(await a, isA<ApiSessionChangedException>());
      expect(ApiService.isAuthenticated, isFalse);
    });

    test('login vs another login method: a password login that is overtaken '
        'by an OTP login does not replace it', () async {
      final gateA = _srv.gates['login:A'] = _Gate();
      final a = outcome(viaPassword('A'));
      await gateA.reached;
      await viaOtp('0042'); // OTP login completes (account ph0042)
      gateA.open();

      expect(await a, isA<ApiSessionChangedException>());
      expect(ApiService.currentAccountId, 'ph0042');
      expect(await marker(), 'ph0042');
    });

    test('stale OTP verification: overtaken by a password login',
        () async {
      final gateP = _srv.gates['verify:ph0042'] = _Gate();
      final p = outcome(viaOtp('0042'));
      await gateP.reached;
      await viaPassword('B');
      gateP.open();

      expect(await p, isA<ApiSessionChangedException>());
      expect(ApiService.currentAccountId, 'B');
      expect(testJwtSubject(TokenStore.token), 'B');
      expect(testJwtSubject(TokenStore.refreshToken), 'B');
    });

    test('stale OTP verification vs logout', () async {
      final gateP = _srv.gates['verify:ph0042'] = _Gate();
      final p = outcome(viaOtp('0042'));
      await gateP.reached;
      await ApiService.clearTokens();
      gateP.open();
      expect(await p, isA<ApiSessionChangedException>());
      expect(ApiService.isAuthenticated, isFalse);
      expect(TokenStore.token, isNull);
    });

    test('a cancelled authentication attempt never installs, and a later '
        'attempt is unaffected', () async {
      final gateA = _srv.gates['login:A'] = _Gate();
      final a = outcome(viaPassword('A'));
      await gateA.reached;
      ApiService.cancelPendingAuthAttempts(); // user left the login screen
      gateA.open();
      expect(await a, isA<ApiSessionChangedException>());
      expect(ApiService.isAuthenticated, isFalse);

      await viaPassword('B'); // a fresh attempt still works
      expect(ApiService.currentAccountId, 'B');
    });

    test('AuthService: logging out while the login\'s profile is still '
        'loading leaves the user signed out', () async {
      final gateMe = _srv.gates['me:A'] = _Gate();
      final login = outcome(AuthService().login('A', 'pw'));
      await gateMe.reached; // credentials installed, profile in flight
      await AuthService().logout();
      gateMe.open();
      await login;

      expect(AuthService().isAuthenticated, isFalse,
          reason: 'a completed-late login must not resurrect the UI state');
      expect(ApiService.isAuthenticated, isFalse);
    });
  });

  // =========================================================================
  group('2. access / refresh pairing', () {
    test('setAccessToken for ANOTHER account drops the previous account\'s '
        'refresh token', () async {
      await signedInAs('A');
      final aRefresh = ApiService.refreshToken;
      expect(aRefresh, isNotNull);

      final bAccess = testJwt('B', nonce: 'x');
      await ApiService.setAccessToken(bAccess);

      expect(ApiService.currentAccountId, 'B');
      expect(ApiService.refreshToken, isNot(aRefresh),
          reason: "A's refresh token must not ride along with B's access");
      expect(ApiService.refreshToken, isNull);
      expect(TokenStore.refreshToken, isNull);
    });

    test('setAccessToken with an unprovable pairing (opaque token) drops '
        'the old refresh token too', () async {
      await signedInAs('A');
      await ApiService.setAccessToken('opaque_access_token');
      expect(ApiService.refreshToken, isNull);
      expect(TokenStore.refreshToken, isNull);
    });

    test('setAccessToken for the SAME account keeps its refresh token '
        '(legitimate rotation)', () async {
      await signedInAs('A');
      final aRefresh = ApiService.refreshToken;
      await ApiService.setAccessToken(testJwt('A', nonce: 'new'));
      expect(ApiService.currentAccountId, 'A');
      expect(ApiService.refreshToken, aRefresh);
      expect(TokenStore.refreshToken, aRefresh);
    });

    test('setRefreshToken for another account than the current access token '
        'is refused', () async {
      await signedInAs('A');
      final aRefresh = ApiService.refreshToken;
      await ApiService.setRefreshToken(testJwt('B', type: 'refresh'));
      expect(ApiService.refreshToken, aRefresh);
      expect(TokenStore.refreshToken, aRefresh);
      expect(ApiService.currentAccountId, 'A');
    });

    test('setRefreshToken for the same account is accepted', () async {
      await signedInAs('A');
      final next = testJwt('A', nonce: 'next', type: 'refresh');
      await ApiService.setRefreshToken(next);
      expect(ApiService.refreshToken, next);
    });

    test('setTokens with a mismatched pair never stores the foreign refresh '
        'token', () async {
      await ApiService.setTokens(
        accessToken: testJwt('A', nonce: 'p'),
        refreshToken: testJwt('B', nonce: 'p', type: 'refresh'),
      );
      expect(ApiService.refreshToken, isNull);
      expect(TokenStore.refreshToken, isNull);
      expect(ApiService.currentAccountId, 'A');
    });

    test('a login response that pairs account A\'s access with B\'s '
        'refresh token installs only the access token', () async {
      _srv.refreshSubjectOverride = 'B';
      await viaPassword('A');
      expect(ApiService.currentAccountId, 'A');
      expect(ApiService.refreshToken, isNull);
      expect(TokenStore.refreshToken, isNull);
    });

    test('control: legacy opaque access + opaque refresh pair (tests / old '
        'sessions) installs both through setTokens', () async {
      await ApiService.setTokens(
        accessToken: 'test_access_token',
        refreshToken: 'test_refresh_token',
      );
      expect(ApiService.refreshToken, 'test_refresh_token');
    });
  });
}
