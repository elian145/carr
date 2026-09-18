import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/features/chat/chat_pages.dart' as carzo_chat;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

/// B-04: `NotificationsPage._loadNotifications()` previously caught every
/// load failure (timeout, `SocketException`/offline, 401, 500, malformed
/// response) and only set `_loading = false`, with no tracked failure
/// state — so a failed load rendered the exact same "No notifications yet"
/// `EmptyStatePanel` as a genuinely empty inbox. (Pull-to-refresh already
/// worked, so this was never a "permanently blank screen" as the original
/// audit wording claimed — the real defect was the failure being
/// indistinguishable from an empty inbox.)
///
/// This test covers the fix: a new `_loadFailed` flag distinguishes a
/// failed initial/refresh load from a genuinely empty inbox, surfacing a
/// distinct, retryable `EmptyStatePanel` (existing shared widget, reused
/// as-is) instead of inventing a new error widget. Retrying — via the new
/// button or via `RefreshIndicator.onRefresh`, both of which call the
/// exact same pre-existing `_loadNotifications(refresh: true)` — clears the
/// error state on success.
///
/// Deliberately mounts the real, unmodified `NotificationsPage` directly in
/// a minimal `MaterialApp`, matching the existing B-01/B-07 convention
/// (`legacy_profile_analytics_action_test.dart`,
/// `b07_dealer_application_notification_tap_test.dart`) of isolating a
/// single page-level fix from the full app shell. Reuses the
/// `notificationsOverride`/`markNotificationReadCalls` fake-API helpers
/// added for B-07, additively extended here with a `notificationsGetOverride`
/// to force a specific failure response for `GET /api/user/notifications`.
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
        'username': 'buyer',
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
    FakeApiServer.notificationsOverride = null;
    FakeApiServer.notificationsGetOverride = null;
    FakeApiServer.markNotificationReadCalls.clear();
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.notificationsOverride = null;
    FakeApiServer.notificationsGetOverride = null;
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
    );
  }

  testWidgets(
    '1) successful empty response shows the normal empty state, not the error state',
    (tester) async {
      FakeApiServer.notificationsOverride = [];

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.text('Failed to load notifications'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    },
  );

  testWidgets(
    '2) failed initial request shows the error state with a visible Retry action',
    (tester) async {
      FakeApiServer.notificationsGetOverride =
          () => http.Response('Internal Server Error', 500);

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Failed to load notifications'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Never the genuinely-empty-inbox copy at the same time.
      expect(find.text('No notifications yet'), findsNothing);
      // No raw exception text leaked into the UI.
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('500'), findsNothing);
    },
  );

  testWidgets(
    '3) tapping Retry after a failure, followed by success, clears the error and renders notifications',
    (tester) async {
      FakeApiServer.notificationsGetOverride =
          () => http.Response('Internal Server Error', 500);

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Failed to load notifications'), findsOneWidget);

      // Fix the backend, then retry via the error state's own button.
      FakeApiServer.notificationsGetOverride = null;
      FakeApiServer.notificationsOverride = [
        {
          'id': 'notif_1',
          'title': 'New message',
          'message': 'You have a new message',
          'notification_type': 'favorite',
          'is_read': false,
          'data': <String, dynamic>{},
          'created_at': '2026-01-01T12:00:00.000Z',
        },
      ];

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Failed to load notifications'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('New message'), findsOneWidget);
    },
  );

  testWidgets(
    '4) a successful reload (RefreshIndicator.onRefresh) clears a previous error state',
    (tester) async {
      FakeApiServer.notificationsGetOverride =
          () => http.Response('Internal Server Error', 500);

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Failed to load notifications'), findsOneWidget);

      FakeApiServer.notificationsGetOverride = null;
      FakeApiServer.notificationsOverride = [
        {
          'id': 'notif_2',
          'title': 'Reload success',
          'message': 'Loaded after refresh',
          'notification_type': 'favorite',
          'is_read': false,
          'data': <String, dynamic>{},
          'created_at': '2026-01-01T12:00:00.000Z',
        },
      ];

      // Invoke the exact same callback RefreshIndicator's pull-to-refresh
      // gesture would (`() => _loadNotifications(refresh: true)`) — this
      // proves the wiring without relying on a fragile drag gesture.
      final refreshIndicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await refreshIndicator.onRefresh();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Failed to load notifications'), findsNothing);
      expect(find.text('Reload success'), findsOneWidget);
    },
  );

  testWidgets(
    '5) a normally-populated notification list is unaffected by the error-state change',
    (tester) async {
      FakeApiServer.notificationsOverride = [
        {
          'id': 'notif_3',
          'title': 'Populated list item',
          'message': 'Everything renders as before',
          'notification_type': 'favorite',
          'is_read': false,
          'data': <String, dynamic>{},
          'created_at': '2026-01-01T12:00:00.000Z',
        },
      ];

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Populated list item'), findsOneWidget);
      expect(find.text('No notifications yet'), findsNothing);
      expect(find.text('Failed to load notifications'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    },
  );
}
