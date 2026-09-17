import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/production_account_pages.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

/// B-01: `AnalyticsPage` was routed at `/analytics` but had zero live
/// `pushNamed('/analytics')` call sites — a dead screen. This test covers
/// the fix: a visible "Analytics Dashboard" action on the profile actions
/// screen that navigates to `/analytics`.
///
/// Deliberately does NOT use the full `legacy.MyApp()` shell — that builds
/// `MainShell`/`BottomNavigationBar`, which currently crashes on this
/// Flutter 3.41.6 environment with a pre-existing, unrelated
/// `MediaQuery.withClampedTextScaling` assertion (reproduced identically by
/// untouched tests such as `legacy_profile_widget_test.dart` and
/// `legacy_analytics_empty_widget_test.dart`). Instead, this test mounts the
/// real, unmodified `ProfilePage` widget (`embedInShell: true`, which itself
/// skips `buildFloatingBottomNav`/`BottomNavigationBar`) inside a minimal
/// `MaterialApp` with only the providers/routes it actually needs, and a
/// simple marker widget standing in for the real `AnalyticsPage` at
/// `/analytics` — so the test proves the actual navigation wiring without
/// loading the real `AnalyticsPage` or its backend calls.
void main() {
  const analyticsMarkerKey = ValueKey<String>('analytics-route-marker');

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
    'Profile actions show a localized Analytics Dashboard entry that navigates to /analytics',
    (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: AuthService(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ProfilePage(embedInShell: true),
            routes: {
              '/analytics': (context) =>
                  const Scaffold(body: Center(child: Text('Analytics route marker', key: analyticsMarkerKey))),
            },
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // The BottomNavigationBar/MainShell tree must not be present — this
      // test targets ProfilePage directly, not the full legacy app shell.
      expect(find.byType(BottomNavigationBar), findsNothing);

      // The action is visible and uses the existing localized
      // `analyticsDashboard` key (English value from app_en.arb), not an
      // inline/hardcoded string.
      final analyticsAction = find.text('Analytics Dashboard');
      expect(
        analyticsAction,
        findsOneWidget,
        reason: 'Analytics Dashboard action should be visible on the profile actions screen',
      );

      await tester.tap(analyticsAction);
      await tester.pumpAndSettle();

      // Tapping navigates to the real `/analytics` route name (proved here
      // via a lightweight marker route rather than the real AnalyticsPage).
      expect(
        find.byKey(analyticsMarkerKey),
        findsOneWidget,
        reason: 'Tapping the Analytics Dashboard action should navigate to /analytics',
      );
    },
  );
}
