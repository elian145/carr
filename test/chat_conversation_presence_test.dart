// Real-widget regression tests for foreground chat notifications: the REAL
// chat list + REAL conversation page + REAL push handler, with the native
// local-notification call replaced by a recorder.
//
// Covered: the conversation registers on open and is cleared on close / dispose
// (no duplicates, no stale state, also across re-parenting and locale changes);
// the banner is suppressed only while the matching conversation is the top
// route of a resumed app with a live socket; covering routes/dialogs, other
// conversations, other listings, paused/inactive app and a dead socket all keep
// the banner; a buyer who opened a listing without naming the seller is matched
// through the loaded messages and never guessed.
import 'package:firebase_messaging/firebase_messaging.dart';
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
import 'package:car_listing_app/services/foreground_notification_policy.dart';
import 'package:car_listing_app/services/push_notification_service.dart';
import 'package:car_listing_app/services/websocket_service.dart';
import 'package:car_listing_app/shared/debug/app_log.dart';

import 'fake_api_server.dart';
import 'support/fake_ws_socket.dart';
import 'support/test_jwt.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<FakeWsSocket> sockets;
  late List<RemoteMessage> shown;
  final registry = ChatConversationPresence.instance;

  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  Future<void> signInAs(String id) async {
    await AuthService().adoptTestSession(
      user: {
        'id': id,
        'username': id,
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
    await ApiService.setTokens(
      accessToken: testJwt(id, nonce: 'p1'),
      refreshToken: testJwt(id, type: 'refresh'),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
    sockets = [];
    shown = [];
    registry.debugClear();
    debugLogNonFatalOverride = (error, stackTrace, context) {};
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    PushNotificationService.debugResetForTests();
    PushNotificationService.debugLocalNotificationPresenter = (m) async {
      shown.add(m);
    };
    WebSocketService.debugSocketFactory = (base, options) {
      final s = FakeWsSocket(options);
      sockets.add(s);
      return s;
    };
    await signInAs('seller_1');
  });

  tearDown(() async {
    registry.debugClear();
    PushNotificationService.debugResetForTests();
    WebSocketService.debugReset();
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.chatsOverride = null;
    FakeApiServer.chatMessagesByPeer = null;
    FakeApiServer.chatMessagesRequestedPeers.clear();
    debugLogNonFatalOverride = null;
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

  Widget wrap(Widget home, {Locale locale = const Locale('en')}) {
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
        home: home,
      ),
    );
  }

  Widget listApp({Locale locale = const Locale('en')}) =>
      wrap(AuthGuard(child: carzo_chat.ChatListPage()), locale: locale);

  Future<void> pumpFor(WidgetTester tester, {int frames = 30}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
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

  RemoteMessage push({
    String car = 'list_car_1',
    required String sender,
    String id = 'm',
  }) => RemoteMessage(
    messageId: id,
    notification: RemoteNotification(title: 'New message', body: 'hi'),
    data: {'type': 'chat_message', 'car_id': car, 'sender_id': sender},
  );

  /// Runs ONE foreground push through the real handler; true when a banner
  /// was posted.
  Future<bool> bannerFor(RemoteMessage m) async {
    final before = shown.length;
    await PushNotificationService.handleForegroundMessage(m);
    return shown.length == before + 1;
  }

  void connectSocket(WidgetTester tester, {String userId = 'seller_1'}) {
    final socket = sockets.last;
    socket.fire('connect');
    socket.fire('connected', {'authenticated': true, 'user_id': userId});
  }

  Future<void> openFromList(WidgetTester tester, String preview) async {
    await tester.tap(find.text(preview));
    await pumpFor(tester);
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    WebSocketService.disconnect();
    await pumpFor(tester, frames: 3);
  }

  testWidgets(
    'seller: banner is suppressed only for the conversation that is on screen',
    (tester) async {
      seedTwoBuyers();
      await tester.pumpWidget(listApp());
      await pumpFor(tester);

      // On the chat list (no conversation open): exactly one banner.
      expect(registry.registeredCount, 0);
      expect(await bannerFor(push(sender: 'buyer_a', id: 'list')), isTrue);

      await openFromList(tester, 'preview from A');
      expect(find.byType(carzo_chat.ChatConversationPage), findsOneWidget);
      connectSocket(tester);
      await pumpFor(tester, frames: 3);
      expect(registry.registeredCount, 1);

      // Viewing Alice's conversation: Alice's message is not bannered...
      final a = await PushNotificationService.handleForegroundMessage(
        push(sender: 'buyer_a', id: 'a'),
      );
      expect(a.suppress, isTrue, reason: '$a');
      expect(a.reason, ForegroundNotificationReason.activeConversation);

      // ...but Bob's (same listing, other buyer) and other listings are.
      expect(await bannerFor(push(sender: 'buyer_b', id: 'b')), isTrue);
      expect(
        await bannerFor(push(car: 'other_car', sender: 'buyer_a', id: 'c')),
        isTrue,
      );
      // Unrelated notification types are never swallowed.
      expect(
        await bannerFor(
          RemoteMessage(
            notification: RemoteNotification(title: 't', body: 'b'),
            data: {'type': 'price_drop', 'car_id': 'list_car_1'},
          ),
        ),
        isTrue,
      );

      await teardownTree(tester);
      expect(registry.registeredCount, 0);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'route visibility: covered by another page or dialog => banner; popped '
    'back => suppressed again',
    (tester) async {
      seedTwoBuyers();
      await tester.pumpWidget(listApp());
      await pumpFor(tester);
      await openFromList(tester, 'preview from A');
      connectSocket(tester);
      await pumpFor(tester, frames: 3);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));

      expect(await bannerFor(push(sender: 'buyer_a', id: '1')), isFalse);

      // Another page on top of the (still mounted) conversation.
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await pumpFor(tester);
      expect(registry.registeredCount, 1, reason: 'still mounted underneath');
      expect(await bannerFor(push(sender: 'buyer_a', id: '2')), isTrue);

      nav.pop();
      await pumpFor(tester);
      expect(await bannerFor(push(sender: 'buyer_a', id: '3')), isFalse);

      // A dialog on top is also "covered".
      showDialog<void>(
        context: tester.element(find.byType(carzo_chat.ChatConversationPage)),
        builder: (_) => const AlertDialog(content: Text('dialog')),
      );
      await pumpFor(tester);
      expect(find.text('dialog'), findsOneWidget);
      expect(await bannerFor(push(sender: 'buyer_a', id: '4')), isTrue);

      nav.pop();
      await pumpFor(tester);
      expect(find.text('dialog'), findsNothing);
      expect(await bannerFor(push(sender: 'buyer_a', id: '5')), isFalse);

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'app lifecycle and socket state: inactive/paused app or dead socket keeps '
    'the banner',
    (tester) async {
      seedTwoBuyers();
      await tester.pumpWidget(listApp());
      await pumpFor(tester);
      await openFromList(tester, 'preview from A');
      connectSocket(tester);
      await pumpFor(tester, frames: 3);

      expect(await bannerFor(push(sender: 'buyer_a', id: 'r')), isFalse);

      // Legal lifecycle order: resumed -> inactive -> hidden -> paused.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
        expect(
          await bannerFor(push(sender: 'buyer_a', id: '$state')),
          isTrue,
          reason: '$state must not count as actively viewing',
        );
      }
      // Valid return path: paused -> hidden -> inactive -> resumed.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFor(tester, frames: 3);
      expect(await bannerFor(push(sender: 'buyer_a', id: 'r2')), isFalse);

      // Socket drops: messages would only arrive with the 12 s poll, so the
      // banner stays until realtime is back.
      sockets.last.fire('disconnect');
      expect(await bannerFor(push(sender: 'buyer_a', id: 'down')), isTrue);
      sockets.last.fire('connect');
      expect(await bannerFor(push(sender: 'buyer_a', id: 'up')), isFalse);

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'registration lifecycle: cleared on close, no duplicates or stale state '
    'across conversations, re-parenting and locale changes',
    (tester) async {
      seedTwoBuyers();
      await tester.pumpWidget(listApp());
      await pumpFor(tester);

      await openFromList(tester, 'preview from A');
      connectSocket(tester);
      await pumpFor(tester, frames: 3);
      expect(registry.registeredCount, 1);

      // Locale change re-runs didChangeDependencies: still ONE registration.
      await tester.pumpWidget(listApp(locale: const Locale('ar')));
      await pumpFor(tester);
      expect(find.byType(carzo_chat.ChatConversationPage), findsOneWidget);
      expect(registry.registeredCount, 1);
      expect(await bannerFor(push(sender: 'buyer_a', id: 'loc')), isFalse);

      // Back to the list: cleared => Alice's push is bannered again.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await pumpFor(tester);
      expect(registry.registeredCount, 0);
      expect(await bannerFor(push(sender: 'buyer_a', id: 'closed')), isTrue);

      // Bob's conversation: only Bob is tracked, Alice is not stale.
      await openFromList(tester, 'preview from B');
      connectSocket(tester);
      await pumpFor(tester, frames: 3);
      expect(registry.registeredCount, 1);
      expect(await bannerFor(push(sender: 'buyer_b', id: 'b')), isFalse);
      expect(await bannerFor(push(sender: 'buyer_a', id: 'a')), isTrue);

      // Reopen / close repeatedly: never leaks.
      for (var i = 0; i < 3; i++) {
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await pumpFor(tester);
        expect(registry.registeredCount, 0);
        await openFromList(tester, 'preview from B');
        expect(registry.registeredCount, 1);
      }

      // Tearing the whole tree down releases it too.
      await teardownTree(tester);
      expect(registry.registeredCount, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  testWidgets(
    'account switch: a screen of the previous account never suppresses',
    (tester) async {
      seedTwoBuyers();
      await tester.pumpWidget(listApp());
      await pumpFor(tester);
      await openFromList(tester, 'preview from A');
      connectSocket(tester);
      await pumpFor(tester, frames: 3);
      expect(await bannerFor(push(sender: 'buyer_a', id: 'mine')), isFalse);

      // The signed-in account changes underneath the (still open) screen.
      await ApiService.setTokens(
        accessToken: testJwt('someone_else', nonce: 'p2'),
        refreshToken: testJwt('someone_else', type: 'refresh'),
      );
      expect(await bannerFor(push(sender: 'buyer_a', id: 'other')), isTrue);

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'buyer opening a listing without naming the seller: matched only once the '
    'counterpart is known from the messages, never guessed',
    (tester) async {
      await signInAs('buyer_1');
      // Only my own opening message, with no receiver recorded: the seller is
      // not derivable from the history.
      FakeApiServer.chatMessagesByPeer = {
        '': [message('m0', 'buyer_1', '', 'my first message')],
      };
      sockets.clear();
      await tester.pumpWidget(
        wrap(const carzo_chat.ChatConversationPage(carId: 'list_car_1')),
      );
      await pumpFor(tester);
      connectSocket(tester, userId: 'buyer_1');
      await pumpFor(tester, frames: 3);
      expect(registry.registeredCount, 1);

      // Counterpart unknown => cannot be matched with certainty => banner.
      final early = await PushNotificationService.handleForegroundMessage(
        push(sender: 'seller_1', id: 'early'),
      );
      expect(early.suppress, isFalse);
      expect(early.reason, ForegroundNotificationReason.peerUnknown);
      expect(shown, hasLength(1));

      // The seller's message arrives live and is on screen: counterpart known.
      sockets.last.fire(
        'new_message',
        message('s1', 'seller_1', 'buyer_1', 'hello from seller'),
      );
      await pumpFor(tester, frames: 5);
      expect(find.text('hello from seller'), findsOneWidget);

      expect(await bannerFor(push(sender: 'seller_1', id: 'seller')), isFalse);
      // Anyone else is still bannered.
      expect(await bannerFor(push(sender: 'stranger', id: 'x')), isTrue);

      await teardownTree(tester);
      expect(registry.registeredCount, 0);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}