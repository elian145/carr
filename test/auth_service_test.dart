import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
