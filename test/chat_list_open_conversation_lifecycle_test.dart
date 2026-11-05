import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/carzo_shared.dart' show AuthGuard;
import 'package:car_listing_app/app/production_routes.dart';
import 'package:car_listing_app/features/chat/chat_pages.dart' as carzo_chat;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/websocket_service.dart';

import 'fake_api_server.dart';
import 'support/fake_ws_socket.dart';
import 'support/test_jwt.dart';

/// Real-device regression (Samsung A17): opening a conversation from the chat
/// list showed Flutter's red screen
///
///   dependOnInheritedWidgetOfExactType<_LocalizationsScope>() or
///   dependOnInheritedElement() was called before
///   _ChatConversationPageState.initState() completed.
///
/// Cause: `ChatConversationPage.initState` localized the listing title from
/// `initialListingPreview` through `BuildContext`. The production
/// `/chat/conversation` route passes only that preview (no `carTitle`), so the
/// call ran on every open from the list.
///
/// This test goes through the REAL chat list and the REAL production route,
/// with localization delegates enabled, and -- unlike the other chat widget
/// tests -- never swallows exceptions: any Flutter error fails it.
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
      accessToken: testJwt('seller_1', nonce: 'l1'),
      refreshToken: testJwt('seller_1', type: 'refresh'),
    );
  });

  tearDown(() async {

    WebSocketService.debugReset();
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.chatsOverride = null;
    FakeApiServer.chatMessagesByPeer = null;
    FakeApiServer.chatMessagesRequestedPeers.clear();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Map<String, dynamic> chatRow(String buyerId, String buyerName, String text) =>
      <String, dynamic>{
        'conversation_id': 'list_car_1',
        'car_id': 'list_car_1',
        'car_title': 'Toyota Camry 2020',
        'car_brand': 'toyota',
        'car_model': 'camry',
        'car_year': 2020,
        'other_user': {'id': buyerId, 'name': buyerName},
        'last_message': {
          'id': 'row_$buyerId',
          'car_id': 'list_car_1',
          'content': text,
          'message_type': 'text',
          'created_at': '2026-01-01T12:00:00.000Z',
          'sender_id': buyerId,
          'receiver_id': 'seller_1',
        },
        'unread_count': 0,
      };

  Map<String, dynamic> message(String id, String from, String to, String text) =>
      <String, dynamic>{
        'id': id,
        'car_id': 'list_car_1',
        'sender_id': from,
        'receiver_id': to,
        'content': text,
        'message_type': 'text',
        'is_read': true,
        'created_at': DateTime(2026, 1, 1, 12).toIso8601String(),
      };

  Widget app({Locale locale = const Locale('en')}) {
    final routes = buildProductionRoutes();
    return ChangeNotifierProvider<AuthService>.value(
      value: AuthService(),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routes: {'/chat/conversation': routes['/chat/conversation']!},
        home: AuthGuard(child: carzo_chat.ChatListPage()),
      ),
    );
  }

  // Plain pumps: nothing is taken from the tester, so a build/lifecycle error
  // is still pending for `expectNoFlutterError` below.
  Future<void> pumpFor(WidgetTester tester, {int frames = 30}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void expectNoFlutterError(WidgetTester tester) {
    expect(
      tester.takeException(),
      isNull,
      reason: 'opening a conversation must not raise any Flutter error',
    );
  }

  // The list shows the listing title plus the last-message preview, so the
  // two buyers' rows are told apart by their preview.
  Future<void> openFromList(WidgetTester tester, String preview) async {
    await tester.tap(find.text(preview));
    await pumpFor(tester);
  }

  void seedTwoBuyers() {
    FakeApiServer.chatsOverride = [
      chatRow('buyer_a', 'Alice BuyerA', 'preview from A'),
      chatRow('buyer_b', 'Bob BuyerB', 'preview from B'),
    ];
    FakeApiServer.chatMessagesByPeer = {
      'buyer_a': [message('a1', 'buyer_a', 'seller_1', 'history from A')],
      'buyer_b': [message('b1', 'buyer_b', 'seller_1', 'history from B')],
    };
  }

  testWidgets(
    'opening a conversation from the chat list raises no Flutter error and '
    'stays buyer-isolated',
    (tester) async {
      seedTwoBuyers();
      await tester.pumpWidget(app());
      await pumpFor(tester);

      expect(find.text('preview from A'), findsOneWidget);
      expect(find.text('preview from B'), findsOneWidget);
      expectNoFlutterError(tester);

      await openFromList(tester, 'preview from A');
      expectNoFlutterError(tester);

      // The conversation really is on screen: Alice's history, not Bob's.
      expect(find.byType(carzo_chat.ChatConversationPage), findsOneWidget);
      expect(find.text('history from A'), findsOneWidget);
      expect(find.text('history from B'), findsNothing);
      expect(FakeApiServer.chatMessagesRequestedPeers, ['buyer_a']);

      // Listing title localized from the preview, with no carTitle passed.
      expect(find.textContaining('camry'), findsOneWidget);

      // Realtime: joined Alice's room only; Bob's traffic never shows.
      expect(sockets, isNotEmpty);
      final socket = sockets.last;
      socket.fire('connect');
      socket.fire('connected', {'authenticated': true, 'user_id': 'seller_1'});
      await pumpFor(tester, frames: 5);
      expect(socket.emits('join_chat'), [
        {'car_id': 'list_car_1', 'peer_id': 'buyer_a'},
      ]);

      socket.fire('new_message',
          message('b2', 'buyer_b', 'seller_1', 'secret from B'));
      socket.fire('new_message',
          message('a2', 'buyer_a', 'seller_1', 'live from A'));
      socket.fire('typing', {
        'car_id': 'list_car_1',
        'user_id': 'buyer_b',
        'peer_id': 'seller_1',
        'user_name': 'Bob BuyerB',
        'typing': true,
      });
      await pumpFor(tester, frames: 5);
      expect(find.text('live from A'), findsOneWidget);
      expect(find.text('secret from B'), findsNothing);
      expect(find.textContaining('Bob BuyerB is typing'), findsNothing);

      socket.fire('typing', {
        'car_id': 'list_car_1',
        'user_id': 'buyer_a',
        'peer_id': 'seller_1',
        'user_name': 'Alice BuyerA',
        'typing': true,
      });
      await pumpFor(tester, frames: 5);
      expect(find.textContaining('Alice BuyerA is typing'), findsOneWidget);
      expectNoFlutterError(tester);

      // Back to the list, then into Bob's conversation.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await pumpFor(tester);
      expectNoFlutterError(tester);
      expect(find.byType(carzo_chat.ChatConversationPage), findsNothing);

      await openFromList(tester, 'preview from B');
      expectNoFlutterError(tester);
      expect(find.text('history from B'), findsOneWidget);
      expect(find.text('history from A'), findsNothing);
      expect(find.text('live from A'), findsNothing);
      expect(FakeApiServer.chatMessagesRequestedPeers, ['buyer_a', 'buyer_b']);

      await tester.pumpWidget(const SizedBox.shrink());
      WebSocketService.disconnect();
      await pumpFor(tester, frames: 3);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'listing title follows a locale change while the conversation is open',
    (tester) async {
      seedTwoBuyers();
      await tester.pumpWidget(app());
      await pumpFor(tester);
      await openFromList(tester, 'preview from A');
      expectNoFlutterError(tester);
      expect(find.byType(carzo_chat.ChatConversationPage), findsOneWidget);
      expect(find.textContaining('camry'), findsOneWidget);

      await tester.pumpWidget(app(locale: const Locale('ar')));
      await pumpFor(tester);
      expectNoFlutterError(tester);
      expect(find.byType(carzo_chat.ChatConversationPage), findsOneWidget);
      // A locale change re-runs didChangeDependencies: no error, and the
      // title (still derived from the preview) is intact. The Arabic name
      // pack loads asynchronously and is not part of this test.
      expect(find.textContaining('camry'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      WebSocketService.disconnect();
      await pumpFor(tester, frames: 3);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
