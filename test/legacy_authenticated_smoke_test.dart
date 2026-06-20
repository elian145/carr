import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/legacy/main_legacy.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
    await AuthService().adoptTestSession(
      user: {
        'id': 1,
        'username': 'test',
        'is_admin': true,
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

  testWidgets('Authenticated legacy routes smoke', (tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    const routes = [
      '/sell',
      '/chat',
      '/my_listings',
      '/analytics',
      '/admin/dealers',
      '/admin/reports',
      '/dealer/edit',
      '/edit-profile',
    ];

    await smokeVisitRoutes(tester, routes);

    await smokePushNamed(
      tester,
      name: '/chat/conversation',
      args: {'conversationId': '1', 'receiverId': '2'},
    );
    await smokePushNamed(
      tester,
      name: '/edit_listing',
      args: {
        'car': <String, dynamic>{'id': 1, 'title': 'Test car'},
      },
    );

    await tester.pump(const Duration(seconds: 2));
  });
}
