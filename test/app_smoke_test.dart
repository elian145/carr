import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/legacy/main_legacy.dart' as legacy;

import 'fake_api_server.dart';

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

    Future<void> pushNamed(String name, {Object? args}) async {
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed(name, arguments: args);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
      final ex = tester.takeException();
      expect(ex, isNull, reason: 'Exception while opening route: $name');

      if (nav.canPop()) {
        nav.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        final ex2 = tester.takeException();
        expect(ex2, isNull, reason: 'Exception while closing route: $name');
      }
    }

    await pushNamed('/legacy_home');
    await pushNamed('/sell');
    await pushNamed('/sell', args: {'startFresh': true});
    await pushNamed('/settings');
    await pushNamed('/favorites');
    await pushNamed('/dealers');
    await pushNamed('/chat');
    await pushNamed('/login');
    await pushNamed('/signup');
    await pushNamed('/profile');
    await pushNamed('/edit-profile');
    await pushNamed('/forgot-password');
    await pushNamed('/car_detail', args: {'carId': '1'});
    await pushNamed('/chat/conversation', args: {'conversationId': '1'});
    await pushNamed(
      '/edit_listing',
      args: {
        'car': <String, dynamic>{'id': 1, 'title': 'Test car'},
      },
    );
    await pushNamed(
      '/edit',
      args: {
        'car': <String, dynamic>{'id': 1, 'title': 'Test car'},
      },
    );
    await pushNamed('/my_listings');
    await pushNamed('/comparison');
    await pushNamed('/recently-viewed');
    await pushNamed('/analytics');
    await pushNamed('/help');
    await pushNamed('/reset-password');
    await pushNamed('/verify-email', args: {'token': 'test-token'});
    await pushNamed(
      '/dealer/profile',
      args: {'dealerPublicId': 'dealer_test_1'},
    );
    await pushNamed('/dealer/edit');
    await pushNamed('/admin/dealers');
    await pushNamed('/admin/reports');

    await tester.pump(const Duration(seconds: 5));
  });
}
