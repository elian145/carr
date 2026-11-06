// An operation that STARTED WITHOUT credentials is still invalidated by ANY
// later authentication transition when it is account-sensitive.
//
// `ApiService.isSessionCurrent` used to treat an unauthenticated snapshot as
// valid forever (`!s.authenticated || ...`). A request that began as a guest
// and whose 401 arrived after Account B signed in could therefore refresh with
// B's refresh token, retry under B's credentials, or clear B's session; a slow
// logout started without credentials wiped B's fresh login.
//
// Genuinely public guest requests (no Authorization header, public data) are
// NOT account-sensitive and keep working across a login.
//
// Every race is forced with controlled barriers (the mock server parks one
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
  final List<String> log = <String>[];
  final List<String> refreshedBy = <String>[];
  int _n = 0;

  /// When true /auth/refresh rejects every refresh token (definitive 401).
  bool refreshRejects = false;

  http.Response _j(int code, Object body) => http.Response(
        json.encode(body),
        code,
        headers: {'content-type': 'application/json'},
      );

  Iterable<String> requestsAs(String actor) =>
      log.where((l) => l.endsWith(' as:$actor'));

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    final h = r.headers['Authorization'] ?? r.headers['authorization'];
    final bearer =
        (h != null && h.startsWith('Bearer ')) ? h.substring(7) : null;
    final Map<String, dynamic> body =
        r.body.isEmpty ? <String, dynamic>{} : json.decode(r.body);
    final actor = bearer == null ? 'guest' : testJwtSubject(bearer) ?? '?';
    log.add('${r.method} $path as:$actor');

    String issue(String acct) {
      final access = testJwt(acct, nonce: 'i${++_n}');
      valid.add(access);
      return access;
    }

    if (path.endsWith('/auth/login')) {
      final acct = (body['username'] ?? '').toString();
      return _j(200, {
        'access_token': issue(acct),
        'refresh_token': testJwt(acct, nonce: 'r$_n', type: 'refresh'),
      });
    }
    if (path.endsWith('/auth/logout')) {
      final g = gates['logout:$actor'];
      if (g != null) await g.hit();
      return _j(200, {});
    }
    if (path.endsWith('/auth/refresh')) {
      if (refreshRejects || bearer == null) {
        return _j(401, {'message': 'no'});
      }
      refreshedBy.add(actor);
      return _j(200, {
        'access_token': issue(actor),
        'refresh_token': testJwt(actor, nonce: 'rr${++_n}', type: 'refresh'),
      });
    }
    // Public browse endpoint: answers a guest.
    if (path.endsWith('/cars')) {
      final g = gates['public:$actor'];
      if (g != null) await g.hit();
      return _j(200, {'cars': <Object>[]});
    }
    // Everything else needs a valid access token.
    if (bearer == null || !valid.contains(bearer)) {
      final g = gates['401:$actor'];
      if (g != null) await g.hit();
      return _j(401, {'message': 'unauthorized'});
    }
    if (path.endsWith('/chats') || path.endsWith('/my_listings')) {
      return _j(200, <Object>[]);
    }
    if (path.contains('/chat/') && path.endsWith('/messages')) {
      return _j(200, {
        'messages': <Object>[],
        'per_page': 50,
        'total': 0,
        'has_more': false,
      });
    }
    if (path.endsWith('/contact')) {
      return _j(200, {'phones': <Object>[]});
    }
    return _j(200, {'ok': true, 'actor': actor});
  }
}

late _Srv _srv;
int _n = 0;

Future<Object?> outcome(Future<Object?> f) =>
    f.then<Object?>((v) => v, onError: (Object e) => e);

/// Signs the app in as [acct] with a valid access + matching refresh token.
Future<void> signedInAs(String acct) {
  final access = testJwt(acct, nonce: 's${++_n}');
  _srv.valid.add(access);
  return ApiService.setTokens(
    accessToken: access,
    refreshToken: testJwt(acct, nonce: 'sr$_n', type: 'refresh'),
  );
}

void expectStillSignedInAs(String acct, {String? access, String? refresh}) {
  expect(ApiService.isAuthenticated, isTrue, reason: 'session must survive');
  expect(ApiService.currentAccountId, acct);
  if (access != null) expect(ApiService.accessToken, access);
  if (refresh != null) expect(ApiService.refreshToken, refresh);
  expect(testJwtSubject(TokenStore.token), acct);
  expect(testJwtSubject(TokenStore.refreshToken), acct);
}

/// Account-sensitive entry points that can START without credentials and then
/// meet a 401. Each one must be abandoned when ANY transition happens first.
final Map<String, Future<Object?> Function()> _sensitiveCalls =
    <String, Future<Object?> Function()>{
  'POST via _makeAuthenticatedRequest (sendDeleteAccountCode)': () =>
      ApiService.sendDeleteAccountCode(),
  'GET via _makeAuthenticatedRequest (getMyListings)': () =>
      ApiService.getMyListings(),
  'GET list request (getMyListingsCompat)': () =>
      ApiService.getMyListingsCompat(),
  'GET listing contact (getCarContactPhones)': () =>
      ApiService.getCarContactPhones('c1'),
  'chat: getChats': () => ApiService.getChats(),
  'chat: getChatMessagesByConversation': () =>
      ApiService.getChatMessagesByConversation('conv1'),
};

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
  group('1. guest-started account-sensitive request, 401 arrives after B '
      'signs in', () {
    for (final entry in _sensitiveCalls.entries) {
      test('${entry.key}: cannot refresh, retry or clear B', () async {
        final gate = _srv.gates['401:guest'] = _Gate();
        final pending = outcome(entry.value());
        await gate.reached; // the guest request is on the wire, 401 parked

        await signedInAs('B'); // B signs in while it is outstanding
        final bAccess = ApiService.accessToken;
        final bRefresh = ApiService.refreshToken;
        gate.open(); // ... then the guest 401 arrives

        expect(await pending, isA<ApiSessionChangedException>());
        expect(_srv.refreshedBy, isEmpty,
            reason: "B's refresh token must never be used by a guest request");
        expect(_srv.requestsAs('B'), isEmpty,
            reason: 'nothing may be (re)sent under B on its behalf');
        expectStillSignedInAs('B', access: bAccess, refresh: bRefresh);
      });
    }

    test('B signs in through a real /auth/login (not just setTokens)',
        () async {
      final gate = _srv.gates['401:guest'] = _Gate();
      final pending = outcome(ApiService.sendDeleteAccountCode());
      await gate.reached;

      await ApiService.login('B', 'pw');
      final bAccess = ApiService.accessToken;
      final bRefresh = ApiService.refreshToken;
      gate.open();

      expect(await pending, isA<ApiSessionChangedException>());
      expect(_srv.refreshedBy, isEmpty);
      expect(_srv.requestsAs('B').where((l) => !l.contains('/auth/login')),
          isEmpty);
      expectStillSignedInAs('B', access: bAccess, refresh: bRefresh);
    });

    test('even when B\'s refresh token would be REJECTED the guest 401 must '
        'not clear B\'s session', () async {
      _srv.refreshRejects = true;
      final gate = _srv.gates['401:guest'] = _Gate();
      final pending = outcome(ApiService.sendDeleteAccountCode());
      await gate.reached;

      await signedInAs('B');
      final bAccess = ApiService.accessToken;
      final bRefresh = ApiService.refreshToken;
      gate.open();

      expect(await pending, isA<ApiSessionChangedException>());
      expectStillSignedInAs('B', access: bAccess, refresh: bRefresh);
    });

    test('a guest request overtaken by a logout/relogin of the SAME account '
        'is also abandoned (any transition counts)', () async {
      final gate = _srv.gates['401:guest'] = _Gate();
      final pending = outcome(ApiService.sendDeleteAccountCode());
      await gate.reached;

      await signedInAs('A');
      await ApiService.clearTokens();
      await signedInAs('A');
      final aAccess = ApiService.accessToken;
      gate.open();

      expect(await pending, isA<ApiSessionChangedException>());
      expect(_srv.refreshedBy, isEmpty);
      expectStillSignedInAs('A', access: aAccess);
    });
  });

  // =========================================================================
  group('2. slow logout started without credentials', () {
    test('B signs in before the logout request completes: B stays signed in',
        () async {
      final gate = _srv.gates['logout:guest'] = _Gate();
      final logout = outcome(ApiService.logout());
      await gate.reached; // /auth/logout (no credentials) is on the wire

      await signedInAs('B');
      final bAccess = ApiService.accessToken;
      final bRefresh = ApiService.refreshToken;
      gate.open();
      await logout;

      expectStillSignedInAs('B', access: bAccess, refresh: bRefresh);
    });

    test('B signs in through /auth/login before the guest logout completes',
        () async {
      final gate = _srv.gates['logout:guest'] = _Gate();
      final logout = outcome(ApiService.logout());
      await gate.reached;

      await ApiService.login('B', 'pw');
      final bAccess = ApiService.accessToken;
      gate.open();
      await logout;

      expectStillSignedInAs('B', access: bAccess);
    });
  });

  // =========================================================================
  group('3. legitimate behaviour is preserved', () {
    test('normal logout of a signed-in account still clears it', () async {
      await signedInAs('A');
      await ApiService.logout();
      expect(ApiService.isAuthenticated, isFalse);
      expect(TokenStore.token, isNull);
      expect(TokenStore.refreshToken, isNull);
    });

    test('logout with no credentials and no transition completes quietly',
        () async {
      await ApiService.logout();
      expect(ApiService.isAuthenticated, isFalse);
    });

    test('a slow logout of A is still skipped when B signs in (unchanged)',
        () async {
      await signedInAs('A');
      final gate = _srv.gates['logout:A'] = _Gate();
      final logout = outcome(ApiService.logout());
      await gate.reached;
      await signedInAs('B');
      final bAccess = ApiService.accessToken;
      gate.open();
      await logout;
      expectStillSignedInAs('B', access: bAccess);
    });

    test('guest 401 with NO transition: ordinary auth failure, no refresh',
        () async {
      final out = await outcome(ApiService.sendDeleteAccountCode());
      expect(out, isNot(isA<ApiSessionChangedException>()));
      expect(out, isA<Exception>());
      expect(_srv.refreshedBy, isEmpty);
    });

    test('public guest browsing is NOT cancelled by a login in flight',
        () async {
      final gate = _srv.gates['public:guest'] = _Gate();
      final browse = outcome(ApiService.getCarsRaw({'page': '1'}));
      await gate.reached;

      await signedInAs('B');
      final bAccess = ApiService.accessToken;
      gate.open();

      final res = await browse;
      expect(res, isA<http.Response>());
      expect((res as http.Response).statusCode, 200);
      expectStillSignedInAs('B', access: bAccess);
    });

    test('cold start: persisted session is restored for an authenticated '
        'call that began with empty memory', () async {
      final access = testJwt('A', nonce: 'cold');
      _srv.valid.add(access);
      await TokenStore.save(access);
      await TokenStore.saveRefresh(testJwt('A', nonce: 'coldr', type: 'refresh'));
      // memory is empty; nothing has restored the session yet
      final out = await outcome(ApiService.sendDeleteAccountCode());
      expect(out, isA<Map<String, dynamic>>());
      expect(_srv.requestsAs('A'), isNotEmpty);
      expect(ApiService.currentAccountId, 'A');
    });

    test('same-account refresh: 401 -> refresh -> retry under the SAME '
        'session still works', () async {
      // Access token the server no longer accepts, valid refresh token.
      await ApiService.setTokens(
        accessToken: testJwt('A', nonce: 'expired'),
        refreshToken: testJwt('A', nonce: 'rt', type: 'refresh'),
      );
      final out = await outcome(ApiService.sendDeleteAccountCode());
      expect(out, isA<Map<String, dynamic>>());
      expect(_srv.refreshedBy, <String>['A']);
      expect(ApiService.currentAccountId, 'A');
      expect(ApiService.isAuthenticated, isTrue);
    });

    test('same-account refresh through a chat path still works', () async {
      await ApiService.setTokens(
        accessToken: testJwt('A', nonce: 'expired2'),
        refreshToken: testJwt('A', nonce: 'rt2', type: 'refresh'),
      );
      final out = await outcome(ApiService.getChats());
      expect(out, isA<List<Map<String, dynamic>>>());
      expect(_srv.refreshedBy, <String>['A']);
    });
  });
}
