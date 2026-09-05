import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  test('adoptTestSession sets authenticated user without HTTP', () async {
    await AuthService().adoptTestSession();
    expect(AuthService().isAuthenticated, isTrue);
    expect(AuthService().currentUser?['username'], 'test');
    expect(ApiService.isAuthenticated, isTrue);
  });

  test('resetTestSession clears auth flags', () async {
    await AuthService().adoptTestSession();
    AuthService().resetTestSession();
    expect(AuthService().isAuthenticated, isFalse);
    expect(AuthService().currentUser, isNull);
  });

  test('login via mock API sets authenticated user', () async {
    await AuthService().login('testuser', 'secret');
    expect(AuthService().isAuthenticated, isTrue);
    expect(AuthService().currentUser?['username'], 'test');
  });

  test('userMapFrom accepts generic Map payloads from JSON', () {
    final raw = <dynamic, dynamic>{'username': 'elian', 'id': 'abc123'};
    expect(AuthService.userMapFrom(raw)?['username'], 'elian');
  });

  test('userMapFrom stringifies numeric user ids', () {
    final raw = <String, dynamic>{'username': 'buyer', 'id': 1};
    expect(AuthService.userMapFrom(raw)?['id'], '1');
    expect(AuthService().userId, isNull);
  });

  test('login survives stale profile load from startup init', () async {
    await ApiService.setTokens(
      accessToken: 'stale_access_token',
      refreshToken: 'stale_refresh_token',
    );
    final initFuture = AuthService().initialize();
    final loginFuture = AuthService().login('testuser', 'secret');
    await Future.wait([initFuture, loginFuture]);
    expect(AuthService().isAuthenticated, isTrue);
    expect(AuthService().currentUser?['username'], 'test');
    expect(ApiService.accessToken, 'test_access_token');
  });

  // --------------------------------------------------------------------
  // Regression tests: transient (non-401) /auth/me failure must not
  // permanently strand ApiService.isAuthenticated == true while
  // AuthService.isAuthenticated stays false forever (production bug that
  // left AuthGuard-protected pages, e.g. Chat, spinning indefinitely).
  // --------------------------------------------------------------------

  http.Response _jsonResponse(int status, Object body) => http.Response(
        json.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  /// A minimal `/auth/me`-only mock client: the Nth call (1-indexed) returns
  /// [firstStatus]; every call after that returns 200 with a valid profile.
  /// Any other endpoint is stubbed with an empty 200 (not exercised by these
  /// tests — `_loadUserProfile()` only calls `/auth/me`).
  MockClient _profileFlakyThenOkClient({required int firstStatus}) {
    var call = 0;
    return MockClient((request) async {
      if (request.url.path == '/api/auth/me') {
        call++;
        if (call == 1) {
          return firstStatus == 401
              ? _jsonResponse(401, {'message': 'Token has expired'})
              : _jsonResponse(firstStatus, {'message': 'temporary failure'});
        }
        return _jsonResponse(200, {
          'id': 1,
          'username': 'testuser',
          'account_type': 'individual',
        });
      }
      return _jsonResponse(200, <String, dynamic>{});
    });
  }

  test(
    'A: existing valid authentication still succeeds normally',
    () async {
      await ApiService.setTokens(
        accessToken: 'good_token',
        refreshToken: 'good_refresh',
      );
      await AuthService().initialize();
      expect(AuthService().isAuthenticated, isTrue);
      expect(AuthService().currentUser?['username'], 'testuser');
      expect(ApiService.isAuthenticated, isTrue);
    },
  );

  test(
    'B+C: a transient non-401 /auth/me failure does not permanently strand '
    'the session, and the bounded auto-retry recovers it',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);

      ApiService.testHttpClient = _profileFlakyThenOkClient(firstStatus: 500);
      await ApiService.setTokens(
        accessToken: 'flaky_token',
        refreshToken: 'flaky_refresh',
      );

      await AuthService().initialize();

      // Immediately after the transient failure: token must NOT be cleared
      // (this is not a real auth failure), but the profile-derived
      // `isAuthenticated` flag has not been set yet — this is exactly the
      // `ApiService.isAuthenticated == true && AuthService.isAuthenticated
      // == false` combination that used to strand AuthGuard forever.
      expect(ApiService.isAuthenticated, isTrue);
      expect(ApiService.accessToken, 'flaky_token');
      expect(AuthService().isAuthenticated, isFalse);

      // The bounded internal retry (first attempt delay: 2s) must recover
      // the session on its own, with no external caller (e.g. AuthGuard)
      // ever needing to invoke anything.
      await Future.delayed(const Duration(seconds: 3));

      expect(AuthService().isAuthenticated, isTrue);
      expect(AuthService().currentUser?['username'], 'testuser');
    },
  );

  test(
    'D: a genuine 401 on /auth/me still clears auth state',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);

      ApiService.testHttpClient = _profileFlakyThenOkClient(firstStatus: 401);
      await ApiService.setTokens(
        accessToken: 'expired_token',
        refreshToken: 'expired_refresh',
      );

      await AuthService().initialize();

      // A real 401 must still clear the session immediately — no retry,
      // no lingering authenticated token.
      expect(AuthService().isAuthenticated, isFalse);
      expect(ApiService.isAuthenticated, isFalse);
      expect(ApiService.accessToken, isNull);
    },
  );
}
