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
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Future<void> openSignup(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/signup');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Legacy signup page shows registration fields', (tester) async {
    await openSignup(tester);

    expect(find.text('Sign Up'), findsWidgets);
    expect(find.text('Choose Authentication Method:'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);
  });

  testWidgets('Legacy signup keeps create account disabled until terms accepted',
      (tester) async {
    await openSignup(tester);

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Create account'),
    );
    expect(button.onPressed, isNull);
  });
}
