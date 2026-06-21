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

  testWidgets('Legacy home shows bottom navigation shell', (tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();

    var navReady = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Home').evaluate().isNotEmpty &&
          find.text('Saved').evaluate().isNotEmpty &&
          find.text('Dealerships').evaluate().isNotEmpty &&
          find.text('Profile').evaluate().isNotEmpty) {
        navReady = true;
        break;
      }
    }

    expect(navReady, isTrue, reason: 'Home shell should show bottom navigation');
    expect(find.byType(BottomNavigationBar), findsWidgets);
  });
}
