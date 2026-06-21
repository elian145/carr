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

  testWidgets('Legacy chat conversation sends text via mock API', (tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed(
      '/chat/conversation',
      arguments: {
        'conversationId': 'list_car_1',
        'receiverId': 'seller_1',
      },
    );
    await tester.pump();

    var composerReady = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byIcon(Icons.send).evaluate().isNotEmpty) {
        composerReady = true;
        break;
      }
    }
    expect(composerReady, isTrue, reason: 'Chat composer should be ready');

    const outgoing = 'Hello from widget test';
    await tester.enterText(find.byType(TextField), outgoing);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    var sent = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text(outgoing).evaluate().isNotEmpty) {
        sent = true;
        break;
      }
    }

    expect(sent, isTrue, reason: 'Sent message should appear in conversation');
    expect(find.text('Send failed'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
