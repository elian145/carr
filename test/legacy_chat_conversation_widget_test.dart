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
    SharedPreferences.setMockInitialValues({'push_enabled': false});
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
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
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
    'Legacy chat conversation shows composer and empty history',
    (tester) async {
      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed(
        '/chat/conversation',
        arguments: {
          'conversationId': 'list_car_1',
          'receiverId': 'buyer_1',
        },
      );
      await tester.pump();

      var ready = false;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byIcon(Icons.send).evaluate().isNotEmpty &&
            find.text('No messages yet. Start a conversation!').evaluate().isNotEmpty) {
          ready = true;
          break;
        }
      }

      expect(ready, isTrue, reason: 'Chat conversation should show send button and empty state');
      expect(find.byIcon(Icons.send), findsWidgets);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
