import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/app_shell.dart';
import 'package:car_listing_app/app/providers.dart';
import 'package:car_listing_app/pages/sell_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/shared/auth/auth_guard.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    CarSpecIndex.debugLoadWithResult = CarSpecIndex.testEmptyLoadResult();
    await AuthService().adoptTestSession();
  });

  tearDown(() async {
    CarSpecIndex.resetLoadCacheForTest();
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Sell page shows listing form when authenticated', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: buildAppProviders(),
        child: MaterialApp(
          localizationsDelegates: CarNetAppShell.localizationDelegates,
          supportedLocales: CarNetAppShell.supportedLocales,
          home: const AuthGuard(
            sellFlow: true,
            child: SellPage(startFresh: true),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Sell'), findsOneWidget);
    expect(find.byType(Form), findsOneWidget);
    expect(find.text('Brand'), findsOneWidget);
  });
}
