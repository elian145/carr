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
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Future<void> openForgotPassword(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/forgot-password');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Legacy forgot password shows recovery method UI', (tester) async {
    await openForgotPassword(tester);

    expect(find.text('Forgot Password'), findsWidgets);
    expect(find.text('Choose authentication method:'), findsOneWidget);
    expect(find.text('Send Reset Link'), findsOneWidget);
  });

  testWidgets('Legacy forgot password validates empty email', (tester) async {
    await openForgotPassword(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Reset Link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Email'), findsWidgets);
  });
}
