import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/trust_config.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() {
    TrustConfig.resetCacheForTests();
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Legacy help center shows FAQ sections', (tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/help');
    await tester.pump();

    var ready = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('How can we help?').evaluate().isNotEmpty) {
        ready = true;
        break;
      }
    }

    expect(ready, isTrue, reason: 'Help center should finish loading FAQ content');
    expect(find.text('Help & Support'), findsWidgets);
    expect(find.text('Buying'), findsOneWidget);
    expect(find.text('Selling'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('support@test.example'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('support@test.example'), findsOneWidget);
  });
}
