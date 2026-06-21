import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Legacy saved searches shows empty state', (tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final routes = legacy.buildLegacyFallbackRoutes();
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(
      MaterialPageRoute<void>(
        builder: routes['/legacy_saved_searches']!,
      ),
    );
    await tester.pump();

    var ready = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('No saved searches yet').evaluate().isNotEmpty) {
        ready = true;
        break;
      }
    }

    expect(ready, isTrue, reason: 'Saved searches should show empty state');
    expect(find.text('Saved Searches'), findsWidgets);
  });
}
