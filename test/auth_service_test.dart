import 'package:flutter_test/flutter_test.dart';
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
}
