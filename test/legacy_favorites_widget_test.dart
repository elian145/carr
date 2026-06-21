import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/legacy/main_legacy.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Legacy favorites prompts guest to log in', (tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/favorites');
    await tester.pump();

    var ready = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('You are not logged in').evaluate().isNotEmpty) {
        ready = true;
        break;
      }
    }

    expect(ready, isTrue, reason: 'Guest favorites should show login prompt');
    expect(find.text('Favorites'), findsWidgets);
  });
}
