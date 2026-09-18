import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/features/chat/chat_pages.dart' as carzo_chat;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

/// B-07: `dealer_application` notifications previously no-op'd on tap —
/// `_onNotificationTap` (`lib/features/chat/chat_notifications_page.dart`)
/// contained `if (type == 'dealer_application') { return; }`, marking the
/// notification read but never navigating anywhere, even though a real
/// destination (`/dealer-onboarding`, already showing the user's current
/// dealer application/status) exists. This test covers the fix: tapping now
/// navigates to `/dealer-onboarding` while preserving the existing
/// mark-as-read behavior, and other notification types are unaffected.
///
/// Deliberately mounts the real, unmodified `NotificationsPage` directly in
/// a minimal `MaterialApp` — with lightweight marker routes standing in for
/// the real `/dealer-onboarding` and `/car_detail` destinations — rather
/// than the full app shell, matching the existing convention in
/// `legacy_profile_analytics_action_test.dart` (B-01) for isolating a single
/// navigation-wiring fix from unrelated app-shell setup.
void main() {
  const dealerOnboardingMarkerKey = ValueKey<String>(
    'dealer-onboarding-route-marker',
  );
  const carDetailMarkerKey = ValueKey<String>('car-detail-route-marker');

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
        'username': 'buyer',
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
    FakeApiServer.notificationsOverride = null;
    FakeApiServer.markNotificationReadCalls.clear();
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.notificationsOverride = null;
    FakeApiServer.markNotificationReadCalls.clear();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Widget buildApp() {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const carzo_chat.NotificationsPage(),
      routes: {
        '/dealer-onboarding': (context) => Scaffold(
              body: Center(
                child: Text(
                  'Dealer onboarding route marker',
                  key: dealerOnboardingMarkerKey,
                ),
              ),
            ),
        '/car_detail': (context) => Scaffold(
              body: Center(
                child: Text(
                  'Car detail route marker',
                  key: carDetailMarkerKey,
                ),
              ),
            ),
      },
    );
  }

  testWidgets(
    'tapping a dealer_application notification navigates to /dealer-onboarding '
    'and still marks it read',
    (tester) async {
      FakeApiServer.notificationsOverride = [
        {
          'id': 'notif_dealer_1',
          'title': 'Dealer application submitted',
          'message': 'Your dealership details were received and are ready for review.',
          'notification_type': 'dealer_application',
          'is_read': false,
          'data': {'application_id': 'app_1', 'status': 'pending'},
          'created_at': '2026-01-01T12:00:00.000Z',
        },
      ];

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final tile = find.text('Dealer application submitted');
      expect(tile, findsOneWidget);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(
        find.byKey(dealerOnboardingMarkerKey),
        findsOneWidget,
        reason:
            'Tapping a dealer_application notification should navigate to /dealer-onboarding',
      );

      expect(
        FakeApiServer.markNotificationReadCalls,
        ['notif_dealer_1'],
        reason: 'Existing mark-as-read behavior must be preserved',
      );
    },
  );

  testWidgets(
    'dealer_application navigation does not depend on listing_id and does not throw',
    (tester) async {
      FakeApiServer.notificationsOverride = [
        {
          'id': 'notif_dealer_2',
          'title': 'Dealer application approved',
          'message': 'Your dealership is verified and active.',
          'notification_type': 'dealer_application',
          'is_read': false,
          // Deliberately no listing_id / car_id / carId anywhere in data —
          // dealer_application navigation must not depend on it.
          'data': {'application_id': 'app_2', 'status': 'approved'},
          'created_at': '2026-01-01T12:00:00.000Z',
        },
      ];

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final tile = find.text('Dealer application approved');
      expect(tile, findsOneWidget);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(dealerOnboardingMarkerKey), findsOneWidget);
    },
  );

  testWidgets(
    'an unrelated notification type keeps its existing navigation behavior unchanged',
    (tester) async {
      FakeApiServer.notificationsOverride = [
        {
          'id': 'notif_listing_1',
          'title': 'New favorite',
          'message': 'Someone favorited your listing',
          'notification_type': 'favorite',
          'is_read': false,
          'data': {'listing_id': 'car_123'},
          'created_at': '2026-01-01T12:00:00.000Z',
        },
      ];

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final tile = find.text('New favorite');
      expect(tile, findsOneWidget);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(
        find.byKey(carDetailMarkerKey),
        findsOneWidget,
        reason: 'Unrelated notification types must keep navigating to /car_detail, unchanged',
      );
      expect(FakeApiServer.markNotificationReadCalls, ['notif_listing_1']);
    },
  );
}
