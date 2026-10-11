import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/production_account_pages.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

/// Final UI polish: Analytics must not appear as a Profile menu entry.
/// Per-listing analytics remain available from listing detail (owner icon).
///
/// Deliberately does NOT use the full `legacy.MyApp()` shell — that builds
/// `MainShell`/`BottomNavigationBar`, which currently crashes on this
/// Flutter 3.41.6 environment with a pre-existing, unrelated
/// `MediaQuery.withClampedTextScaling` assertion. Instead, this test mounts
/// the real `ProfilePage` widget (`embedInShell: true`) inside a minimal
/// `MaterialApp`.
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

  testWidgets(
    'Profile actions do not show an Analytics Dashboard entry',
    (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: AuthService(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ProfilePage(embedInShell: true),
            routes: {
              '/analytics': (context) => const Scaffold(
                body: Center(child: Text('Analytics route marker')),
              ),
              '/my_listings': (context) => const Scaffold(
                body: Center(child: Text('My listings route marker')),
              ),
            },
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(BottomNavigationBar), findsNothing);

      expect(
        find.text('Analytics Dashboard'),
        findsNothing,
        reason: 'Profile must not expose a top-level Analytics entry',
      );
      expect(find.text('Analytics'), findsNothing);

      // Sanity: other account actions still render.
      expect(find.text('My listings'), findsOneWidget);
      expect(find.byIcon(Icons.insights_outlined), findsNothing);
    },
  );
}
