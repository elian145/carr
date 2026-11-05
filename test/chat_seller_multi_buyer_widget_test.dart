import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/carzo_shared.dart' show AuthGuard;
import 'package:car_listing_app/features/chat/chat_pages.dart' as carzo_chat;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/websocket_service.dart';

import 'fake_api_server.dart';
import 'support/fake_ws_socket.dart';
import 'support/test_jwt.dart';


/// F-05 / F-25 UI-level regression: one SELLER, several BUYERS, ONE listing.
///
/// The seller has buyer_1's conversation open. Realtime traffic of buyer_2 --
/// about the very same listing -- must not appear in it: not their messages,
/// not their typing indicator. Buyer_1's traffic does, and what the seller
/// types is addressed to buyer_1 only.
void main() {
  late List<FakeWsSocket> sockets;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
    sockets = [];
    WebSocketService.debugSocketFactory = (base, options) {
      final s = FakeWsSocket(options);
      sockets.add(s);
      return s;
    };
    await AuthService().adoptTestSession(
      user: {
        'id': 'seller_1',
        'username': 'seller_1',
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
    await ApiService.setTokens(
      accessToken: testJwt('seller_1', nonce: 'w1'),
      refreshToken: testJwt('seller_1', type: 'refresh'),
    );
  });

  tearDown(() async {
    WebSocketService.debugReset();
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Widget harness(Widget child) {
    return ChangeNotifierProvider<AuthService>.value(
      value: AuthService(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  Future<void> settle(WidgetTester tester, {int times = 30}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();
    }
  }

  Map<String, dynamic> message(String id, String from, String to, String text) =>
      <String, dynamic>{
        'id': id,
        'car_id': 'car_x',
        'sender_id': from,
        'receiver_id': to,
        'content': text,
        'message_type': 'text',
        'is_read': false,
        'created_at': DateTime(2026, 1, 1, 12).toIso8601String(),
      };

  testWidgets(
    'seller with buyer_1 open: buyer_2\'s messages and typing never show',
    (tester) async {
      await tester.pumpWidget(harness(AuthGuard(
        child: carzo_chat.ChatConversationPage(
          carId: 'car_x',
          receiverId: 'buyer_1',
          carTitle: 'Toyota Camry 2020',
        ),
      )));
      await settle(tester);

      expect(sockets, isNotEmpty, reason: 'the page opened a realtime socket');
      final socket = sockets.last;
      socket.fire('connect');
      socket.fire('connected', {'authenticated': true, 'user_id': 'seller_1'});
      await settle(tester, times: 5);

      expect(socket.emits('join_chat'), [
        {'car_id': 'car_x', 'peer_id': 'buyer_1'},
      ], reason: 'the seller joins the thread with buyer_1 only');

      // Concurrent traffic from two buyers about the same listing.
      socket.fire('new_message',
          message('m2', 'buyer_2', 'seller_1', 'buyer two secret offer'));
      socket.fire('new_message',
          message('m1', 'buyer_1', 'seller_1', 'hello from buyer one'));
      socket.fire('new_message',
          message('m3', 'seller_1', 'buyer_2', 'reply to buyer two'));
      socket.fire('new_message',
          message('m4', 'buyer_2', 'buyer_1', 'between two other people'));
      await settle(tester, times: 5);

      expect(find.text('hello from buyer one'), findsOneWidget);
      expect(find.text('buyer two secret offer'), findsNothing);
      expect(find.text('reply to buyer two'), findsNothing);
      expect(find.text('between two other people'), findsNothing);

      // Typing indicators.
      socket.fire('typing', {
        'car_id': 'car_x',
        'user_id': 'buyer_2',
        'peer_id': 'seller_1',
        'user_name': 'Buyer Two',
        'typing': true,
      });
      await settle(tester, times: 3);
      expect(find.textContaining('Buyer Two'), findsNothing,
          reason: "buyer_2 typing must not show in buyer_1's thread");

      socket.fire('typing', {
        'car_id': 'car_x',
        'user_id': 'buyer_1',
        'peer_id': 'seller_1',
        'user_name': 'Buyer One',
        'typing': true,
      });
      await settle(tester, times: 3);
      expect(find.textContaining('Buyer One is typing'), findsOneWidget);

      // What the seller types is addressed to buyer_1 only.
      await tester.enterText(find.byType(TextField), 'draft');
      await settle(tester, times: 5);
      expect(socket.emits('typing_start'), [
        {'car_id': 'car_x', 'peer_id': 'buyer_1'},
      ]);

      // Unmount: nothing may leak out of the closed conversation.
      await tester.pumpWidget(harness(const SizedBox.shrink()));
      WebSocketService.disconnect();
      await settle(tester, times: 3);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
