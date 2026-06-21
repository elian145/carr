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
        'username': 'seller',
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

  testWidgets('Legacy edit listing hydrates form from car payload', (tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed(
      '/edit_listing',
      arguments: {
        'car': <String, dynamic>{
          'id': 'list_car_1',
          'title': 'Test car',
          'brand': 'toyota',
          'model': 'camry',
          'year': 2020,
          'mileage': 45000,
          'price': 10000,
          'location': 'Erbil',
          'description': 'Well maintained',
          'color': 'white',
          'condition': 'used',
        },
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Test car'), findsWidgets);
    expect(find.text('toyota'), findsOneWidget);
    expect(find.text('camry'), findsOneWidget);
    expect(find.text('Erbil'), findsOneWidget);
    expect(find.text('2020'), findsOneWidget);
    expect(find.text('45000'), findsOneWidget);
  });
}
