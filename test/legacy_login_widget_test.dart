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

  Future<void> openLogin(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/login');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Login page shows personal phone auth fields', (tester) async {
    await openLogin(tester);

    expect(find.text('Login'), findsWidgets);
    expect(find.text('Personal account'), findsOneWidget);
    expect(find.text('Dealer'), findsOneWidget);
    expect(
      find.text('Enter your phone number to log in or create an account.'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('Login validates empty phone before submit', (tester) async {
    await openLogin(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Required'), findsWidgets);
    expect(AuthService().isAuthenticated, isFalse);
  });

  testWidgets('Dealer mode uses same phone fields as personal', (tester) async {
    await openLogin(tester);

    await tester.tap(find.text('Dealer'));
    await tester.pumpAndSettle();

    expect(find.text('Dealer account'), findsOneWidget);
    expect(find.text('Dealership name'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
