import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
    await ApiService.clearTokens();
    await AuthService().adoptTestSession(
      user: {
        'id': 1,
        'username': 'buyer',
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Legacy recently viewed opens for authenticated user', (tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/recently-viewed');
    await tester.pump();

    var ready = false;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Recently viewed').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().length <= 1) {
        ready = true;
        break;
      }
    }

    expect(ready, isTrue, reason: 'Recently viewed route should render for auth user');
    expect(find.text('Recently viewed'), findsWidgets);
    expect(AuthService().isAuthenticated, isTrue);
    expect(tester.takeException(), isNull);
  });
}
