import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/app_shell.dart';
import 'package:car_listing_app/app/providers.dart';
import 'package:car_listing_app/pages/auth_pages.dart';
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

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Login page shows username and password fields', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: buildAppProviders(),
        child: MaterialApp(
          localizationsDelegates: CarNetAppShell.localizationDelegates,
          supportedLocales: CarNetAppShell.supportedLocales,
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('Login requires username and password', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: buildAppProviders(),
        child: MaterialApp(
          localizationsDelegates: CarNetAppShell.localizationDelegates,
          supportedLocales: CarNetAppShell.supportedLocales,
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your username or email'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
    expect(AuthService().isAuthenticated, isFalse);
  });
}
