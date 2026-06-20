import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/app_shell.dart';
import 'package:car_listing_app/app/providers.dart';
import 'package:car_listing_app/pages/car_detail_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

Future<void> _pumpTestShell(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: buildAppProviders(),
      child: MaterialApp(
        localizationsDelegates: CarNetAppShell.localizationDelegates,
        supportedLocales: CarNetAppShell.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _waitForAnyText(
  WidgetTester tester,
  Iterable<String> texts, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    for (final text in texts) {
      if (find.text(text).evaluate().isNotEmpty) return;
    }
  }
  fail('Timed out waiting for any of: ${texts.join(', ')}');
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'cache_car_1': json.encode({
        'id': '1',
        'title': 'Test car',
        'brand': 'toyota',
        'model': 'camry',
        'year': 2020,
        'price': 10000,
        'currency': 'USD',
        'location': 'Erbil',
        'image_url': '',
        'images': <dynamic>[],
        'seller': {'id': 'seller_1', 'username': 'seller'},
      }),
    });
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Car detail renders cached listing data', (tester) async {
    await _pumpTestShell(tester, const CarDetailPage(carId: '1'));
    await _waitForAnyText(tester, ['Toyota', 'Camry', 'Test Car']);

    expect(find.text('Listing'), findsOneWidget);
    expect(find.text('Erbil'), findsWidgets);
    expect(find.byType(Form), findsNothing);
  });
}
