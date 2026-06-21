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

  testWidgets('Legacy dealer profile loads mock dealer profile', (tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed(
      '/dealer/profile',
      arguments: {'dealerPublicId': 'dealer_test_1'},
    );
    await tester.pump();

    var ready = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Test Dealer').evaluate().isNotEmpty) {
        ready = true;
        break;
      }
    }

    expect(ready, isTrue, reason: 'Dealer profile should load dealership name');
    expect(find.text('Dealer'), findsWidgets);
    expect(find.text('Listings'), findsWidgets);
  });
}
