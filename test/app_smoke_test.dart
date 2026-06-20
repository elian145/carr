import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/legacy/main_legacy.dart' as legacy;

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

/// Boots the same widget tree as production (`main.dart` → `legacy.MyApp`).
///
/// Run: `flutter test` (starts an ephemeral local API stub automatically).
void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Production app smoke: boot and visit legacy routes', (
    tester,
  ) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    const guestRoutes = [
      '/sell',
      '/settings',
      '/favorites',
      '/dealers',
      '/chat',
      '/login',
      '/signup',
      '/profile',
      '/edit-profile',
      '/forgot-password',
      '/car_detail',
      '/chat/conversation',
      '/edit_listing',
      '/edit',
      '/my_listings',
      '/comparison',
      '/recently-viewed',
      '/analytics',
      '/help',
      '/reset-password',
      '/verify-email',
      '/dealer/profile',
      '/dealer/edit',
      '/admin/dealers',
      '/admin/reports',
    ];

    final args = <String, Object?>{
      '/sell': {'startFresh': true},
      '/car_detail': {'carId': '1'},
      '/chat/conversation': {'conversationId': '1'},
      '/edit_listing': {
        'car': <String, dynamic>{'id': 1, 'title': 'Test car'},
      },
      '/edit': {
        'car': <String, dynamic>{'id': 1, 'title': 'Test car'},
      },
      '/verify-email': {'token': 'test-token'},
      '/dealer/profile': {'dealerPublicId': 'dealer_test_1'},
      '/tiktok_scroll': {
        'cars': [
          <String, dynamic>{
            'id': '1',
            'title': 'Test car',
            'image_url': '',
          },
        ],
        'initialIndex': 0,
      },
    };

    for (final name in guestRoutes) {
      await smokePushNamed(tester, name: name, args: args[name]);
    }

    await smokePushNamed(tester, name: '/sell', args: {'showDraftGate': true});
    await smokePushNamed(
      tester,
      name: '/tiktok_scroll',
      args: args['/tiktok_scroll'],
    );

    await tester.pump(const Duration(seconds: 2));
  });
}
