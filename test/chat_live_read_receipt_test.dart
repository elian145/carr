// Real-widget regression tests for LIVE read receipts: the REAL chat list +
// REAL conversation page + REAL WebSocketService over an in-memory socket.
//
// A message that arrives while the conversation is actually on screen is
// reported with `mark_read` (debounced, one emit per burst). Nothing is
// reported just because the socket is connected, and nothing is reported while
// the page is covered, the app is not resumed or the socket is down -- it is
// reported once the conversation is viewable again. The sender's double-check
// handling (`messages_read`) and the foreground-notification suppression keep
// working, and no message is duplicated.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/carzo_shared.dart' show AuthGuard;
import 'package:car_listing_app/app/production_routes.dart';
import 'package:car_listing_app/features/chat/chat_live_transport.dart';
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
    FakeApiServer.chatMessagesRequestedMarkRead.clear();
    FakeApiServer.chatMessagesFailNext = 0;
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

  Map<String, dynamic> message(
    String id,
    String from,
    String to,
    String text, {
    bool isRead = false,
  }) => <String, dynamic>{
    'id': id,
    'car_id': 'list_car_1',
    'sender_id': from,
    'receiver_id': to,
    'content': text,
    'message_type': 'text',
    'is_read': isRead,
    'created_at': DateTime(2026, 1, 1, 12).toIso8601String(),
  };

  Widget wrap(Widget home) {
    final routes = buildProductionRoutes();
    return ChangeNotifierProvider<AuthService>.value(
      value: AuthService(),
      child: MaterialApp(
        locale: const Locale('en'),
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

  Widget listApp() =>
      wrap(AuthGuard(child: carzo_chat.ChatListPage()));

  Future<void> pumpFor(WidgetTester tester, {int frames = 30}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Longer than the debounce, so a scheduled `mark_read` has fired.
  Future<void> pastDebounce(WidgetTester tester) async {
    await tester.pump(kChatMarkReadDebounce + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  void seedBuyers({List<Map<String, dynamic>>? aHistory}) {
    FakeApiServer.chatsOverride = [
      chatRow('buyer_a', 'Alice BuyerA', 'preview from A'),
      chatRow('buyer_b', 'Bob BuyerB', 'preview from B'),
    ];
    FakeApiServer.chatMessagesByPeer = {
      'buyer_a':
          aHistory ??
          [message('a0', 'buyer_a', 'seller_1', 'history from A', isRead: true)],
      'buyer_b': [
        message('b0', 'buyer_b', 'seller_1', 'history from B', isRead: true),
      ],
    };
  }

  void connectSocket() {
    final socket = sockets.last;
    socket.fire('connect');
    socket.fire('connected', {'authenticated': true, 'user_id': 'seller_1'});
  }

  Future<void> openAlice(WidgetTester tester) async {
    await tester.pumpWidget(listApp());
    await pumpFor(tester);
    await tester.tap(find.text('preview from A'));
    await pumpFor(tester);
    expect(find.byType(carzo_chat.ChatConversationPage), findsOneWidget);
    connectSocket();
    await pumpFor(tester, frames: 3);
  }

  List<Map<String, dynamic>> markReads() => sockets.last.emits('mark_read');

  void incoming(String id, {String from = 'buyer_a', String text = 'hello'}) =>
      sockets.last.fire('new_message', message(id, from, 'seller_1', text));

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    WebSocketService.disconnect();
    await pumpFor(tester, frames: 3);
  }

  RemoteMessage push(String sender, String id) => RemoteMessage(
    messageId: id,
    notification: RemoteNotification(title: 'New message', body: 'hi'),
    data: {'type': 'chat_message', 'car_id': 'list_car_1', 'sender_id': sender},
  );

  testWidgets(
    'message arrives while the conversation is open => mark_read is sent '
    '(and only then); the banner is still suppressed and nothing is duplicated',
    (tester) async {
      seedBuyers();
      await openAlice(tester);

      // Open + connected socket + opening history: nothing is reported by the
      // client just because the socket stays connected.
      await tester.pump(const Duration(seconds: 3));
      expect(markReads(), isEmpty);

      incoming('a1', text: 'live message');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('live message'), findsOneWidget);
      expect(markReads(), isEmpty, reason: 'debounced, not yet sent');
      await pastDebounce(tester);

      expect(markReads(), [
        {'car_id': 'list_car_1', 'peer_id': 'buyer_a'},
      ]);
      // Foreground notification suppression is unchanged.
      final decision = await PushNotificationService.handleForegroundMessage(
        push('buyer_a', 'p1'),
      );
      expect(decision.suppress, isTrue);
      expect(decision.reason, ForegroundNotificationReason.activeConversation);
      expect(shown, isEmpty, reason: 'no duplicate banner');

      // A message I send myself is never reported.
      sockets.last.fire(
        'new_message',
        message('s1', 'seller_1', 'buyer_a', 'my own reply'),
      );
      await pastDebounce(tester);
      expect(markReads(), hasLength(1));

      // A later incoming message is reported again.
      incoming('a2', text: 'second');
      await pastDebounce(tester);
      expect(markReads(), hasLength(2));

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'a burst of messages sends ONE mark_read, shows each message once, and a '
    'repeated delivery of the same message does not duplicate it',
    (tester) async {
      seedBuyers();
      await openAlice(tester);

      for (var i = 1; i <= 6; i++) {
        incoming('burst$i', text: 'burst message $i');
        await tester.pump(const Duration(milliseconds: 30));
      }
      incoming('burst3', text: 'burst message 3'); // duplicate delivery
      await pastDebounce(tester);

      expect(markReads(), hasLength(1));
      await pumpFor(tester, frames: 12); // let the list scroll to the bottom
      for (var i = 1; i <= 6; i++) {
        expect(find.text('burst message $i'), findsOneWidget);
      }

      // A slow trickle: one report per debounce window, never a flood.
      for (var i = 0; i < 5; i++) {
        incoming('slow$i', text: 'slow $i');
        await pastDebounce(tester);
      }
      expect(markReads(), hasLength(6));

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'covered by a page or a dialog => stays unread; uncovered => reported',
    (tester) async {
      seedBuyers();
      await openAlice(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));

      // Covered by another page.
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await pumpFor(tester);
      incoming('c1', text: 'while covered by a page');
      await pastDebounce(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(markReads(), isEmpty, reason: 'covered => not read');

      nav.pop();
      await pumpFor(tester);
      await pastDebounce(tester);
      expect(markReads(), hasLength(1), reason: 'uncovered => reported once');

      // Covered by a dialog.
      showDialog<void>(
        context: tester.element(find.byType(carzo_chat.ChatConversationPage)),
        builder: (_) => const AlertDialog(content: Text('dialog')),
      );
      await pumpFor(tester);
      incoming('c2', text: 'while covered by a dialog');
      await pastDebounce(tester);
      expect(markReads(), hasLength(1));

      nav.pop();
      await pumpFor(tester);
      await pastDebounce(tester);
      expect(markReads(), hasLength(2));

      // Uncovering with nothing unread reports nothing.
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await pumpFor(tester);
      nav.pop();
      await pumpFor(tester);
      await pastDebounce(tester);
      expect(markReads(), hasLength(2));

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'backgrounded / inactive app => stays unread; resumed => reported',
    (tester) async {
      seedBuyers();
      await openAlice(tester);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      incoming('l1', text: 'while inactive');
      await pastDebounce(tester);
      expect(markReads(), isEmpty);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      incoming('l2', text: 'while paused');
      await pastDebounce(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(markReads(), isEmpty, reason: 'a live socket is not "viewing"');

      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pastDebounce(tester);
      expect(markReads(), hasLength(1));

      // Resuming again with nothing new does not report again.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pastDebounce(tester);
      expect(markReads(), hasLength(1));

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'socket down: never queued behind the connection; reported after '
    'reconnect, only if still viewing',
    (tester) async {
      seedBuyers();
      await openAlice(tester);

      sockets.last.fire('disconnect');
      await tester.pump(const Duration(milliseconds: 50));
      final queuedBefore = WebSocketService.debugPendingEmitCount;
      incoming('d1', text: 'arrived around a drop');
      await pastDebounce(tester);
      expect(markReads(), isEmpty);
      expect(
        WebSocketService.debugPendingEmitCount,
        queuedBefore,
        reason: 'mark_read must not be queued for a later, blind delivery',
      );

      sockets.last.fire('connect');
      await pastDebounce(tester);
      expect(markReads(), hasLength(1), reason: 'retried on reconnect');

      // Dropped again, then reconnected while the conversation is covered:
      // not reported until it is uncovered.
      sockets.last.fire('disconnect');
      incoming('d2', text: 'second drop');
      await pastDebounce(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await pumpFor(tester);
      sockets.last.fire('connect');
      await pastDebounce(tester);
      expect(markReads(), hasLength(1));
      nav.pop();
      await pumpFor(tester);
      await pastDebounce(tester);
      expect(markReads(), hasLength(2));

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'another conversation of the same listing, and another account, never '
    'trigger mark_read',
    (tester) async {
      seedBuyers();
      await openAlice(tester);

      incoming('x1', from: 'buyer_b', text: "bob's message");
      await pastDebounce(tester);
      expect(markReads(), isEmpty, reason: "Bob's thread is not on screen");
      expect(find.text("bob's message"), findsNothing);

      // The signed-in account changes underneath the open screen.
      await ApiService.setTokens(
        accessToken: testJwt('someone_else', nonce: 'p2'),
        refreshToken: testJwt('someone_else', type: 'refresh'),
      );
      incoming('x2', text: 'after account switch');
      await pastDebounce(tester);
      expect(markReads(), isEmpty);

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'sender: double check appears live from messages_read, only for the '
    'right conversation and the named messages',
    (tester) async {
      seedBuyers(
        aHistory: [
          message('m1', 'seller_1', 'buyer_a', 'my first'),
          message('m2', 'seller_1', 'buyer_a', 'my second'),
        ],
      );
      await openAlice(tester);
      expect(find.byIcon(Icons.done_all), findsNothing);
      expect(find.byIcon(Icons.check), findsNWidgets(2));

      // Bob (another conversation) reading does nothing here.
      sockets.last.fire('messages_read', {
        'car_id': 'list_car_1',
        'reader_id': 'buyer_b',
        'message_ids': ['m1', 'm2'],
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.done_all), findsNothing);

      // Alice read only m1: exactly one double check, live.
      sockets.last.fire('messages_read', {
        'car_id': 'list_car_1',
        'reader_id': 'buyer_a',
        'message_ids': ['m1'],
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      sockets.last.fire('messages_read', {
        'car_id': 'list_car_1',
        'reader_id': 'buyer_a',
        'message_ids': ['m2'],
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.done_all), findsNWidgets(2));
      expect(find.byIcon(Icons.check), findsNothing);

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ---- Reconnect: join_chat reports the REAL visibility ----------------------
  //
  // `join_chat` marks the conversation read on the server, so a reconnect
  // re-join sends `visible`. A covered / backgrounded conversation is joined
  // for live delivery only; the messages it missed are fetched WITHOUT being
  // reported (`mark_read=0`), stay unread, and are reported once the user is
  // looking again.

  List<Map<String, dynamic>> joins() => sockets.last.emits('join_chat');

  Map<String, dynamic> joinPayload({bool? visible}) => <String, dynamic>{
    'car_id': 'list_car_1',
    'peer_id': 'buyer_a',
    if (visible != null) 'visible': visible,
  };

  /// What the server holds for Alice's thread after the socket was down.
  void serverGainsMissedMessages() {
    FakeApiServer.chatMessagesByPeer!['buyer_a'] = [
      message('a0', 'buyer_a', 'seller_1', 'history from A', isRead: true),
      message('mi1', 'buyer_a', 'seller_1', 'missed one'),
      message('mi2', 'buyer_a', 'seller_1', 'missed two'),
    ];
  }

  /// The socket drops, messages are sent meanwhile, the socket reconnects.
  Future<void> dropMissAndReconnect(WidgetTester tester) async {
    sockets.last.fire('disconnect');
    await tester.pump(const Duration(milliseconds: 50));
    serverGainsMissedMessages();
    sockets.last.fire('connect');
    await pumpFor(tester, frames: 20);
  }

  testWidgets(
    'reconnect while VISIBLE: re-join says visible:true, the missed messages '
    'appear, and nothing extra is reported by the client',
    (tester) async {
      seedBuyers();
      await openAlice(tester);
      // Opening the chat is the user's own action: that join carries no flag.
      expect(joins(), [joinPayload()]);

      await dropMissAndReconnect(tester);

      expect(joins(), [joinPayload(), joinPayload(visible: true)]);
      expect(find.text('missed one'), findsOneWidget);
      expect(find.text('missed two'), findsOneWidget);
      expect(
        FakeApiServer.chatMessagesRequestedMarkRead.last,
        '',
        reason: 'visible => the default fetch, which the server marks read',
      );
      await pastDebounce(tester);
      expect(markReads(), isEmpty, reason: 'the join + fetch already did it');

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'reconnect while COVERED BY A PAGE: visible:false, missed messages are '
    'shown but NOT read; reported once, on return',
    (tester) async {
      seedBuyers();
      await openAlice(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await pumpFor(tester);

      await dropMissAndReconnect(tester);

      expect(joins().last, joinPayload(visible: false));
      expect(FakeApiServer.chatMessagesRequestedMarkRead.last, '0');
      expect(find.text('missed one', skipOffstage: false), findsOneWidget);
      await pastDebounce(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(markReads(), isEmpty, reason: 'covered => nothing is reported');

      nav.pop();
      await pumpFor(tester);
      await pastDebounce(tester);
      expect(markReads(), [
        {'car_id': 'list_car_1', 'peer_id': 'buyer_a'},
      ], reason: 'back on screen => the missed messages are reported');

      // No further reports when nothing new arrived.
      await tester.pump(const Duration(seconds: 3));
      expect(markReads(), hasLength(1));

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'reconnect while COVERED BY A DIALOG: same -- unread until the dialog closes',
    (tester) async {
      seedBuyers();
      await openAlice(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      showDialog<void>(
        context: tester.element(find.byType(carzo_chat.ChatConversationPage)),
        builder: (_) => const AlertDialog(content: Text('dialog')),
      );
      await pumpFor(tester);

      await dropMissAndReconnect(tester);

      expect(joins().last, joinPayload(visible: false));
      expect(FakeApiServer.chatMessagesRequestedMarkRead.last, '0');
      await pastDebounce(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(markReads(), isEmpty);

      nav.pop();
      await pumpFor(tester);
      await pastDebounce(tester);
      expect(markReads(), hasLength(1));
      expect(find.text('missed one'), findsOneWidget);

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'reconnect while the app is BACKGROUNDED: visible:false, nothing read; '
    'reported on resume',
    (tester) async {
      seedBuyers();
      await openAlice(tester);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await dropMissAndReconnect(tester);

      expect(joins().last, joinPayload(visible: false));
      expect(FakeApiServer.chatMessagesRequestedMarkRead.last, '0');
      await pastDebounce(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(markReads(), isEmpty, reason: 'backgrounded => nothing reported');

      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFor(tester, frames: 5);
      await pastDebounce(tester);
      expect(markReads(), [
        {'car_id': 'list_car_1', 'peer_id': 'buyer_a'},
      ]);
      expect(find.text('missed one'), findsOneWidget);
      expect(find.text('missed two'), findsOneWidget);

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'a live message received while covered AND a reconnect while covered are '
    'reported together, exactly once, when uncovered',
    (tester) async {
      seedBuyers();
      await openAlice(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await pumpFor(tester);

      incoming('p1', text: 'live while covered');
      await pastDebounce(tester);
      await dropMissAndReconnect(tester);
      await pastDebounce(tester);
      expect(markReads(), isEmpty);

      nav.pop();
      await pumpFor(tester);
      await pastDebounce(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(markReads(), hasLength(1), reason: 'ONE report covers everything');

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'the missed-message fetch fails while covered: retried a bounded number of '
    'times without reading anything; on return it fetches (and so reads) again',
    (tester) async {
      seedBuyers();
      await openAlice(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await pumpFor(tester);
      final requestsBefore = FakeApiServer.chatMessagesRequestedMarkRead.length;

      FakeApiServer.chatMessagesFailNext = 3;
      await dropMissAndReconnect(tester);
      for (var i = 0; i < 4; i++) {
        await tester.pump(kChatCatchUpRetryDelay + const Duration(seconds: 1));
        await pumpFor(tester, frames: 3);
      }

      final during = FakeApiServer.chatMessagesRequestedMarkRead
          .skip(requestsBefore)
          .toList();
      expect(during, ['0', '0', '0'], reason: 'bounded: 1 try + 2 retries');
      expect(find.text('missed one', skipOffstage: false), findsNothing);
      expect(markReads(), isEmpty);

      // Back on screen: fetch again -- visible now, so the server marks them
      // read -- and the messages show up.
      nav.pop();
      await pumpFor(tester);
      await tester.pump(const Duration(seconds: 1));
      await pastDebounce(tester);
      await pumpFor(tester, frames: 5);
      expect(FakeApiServer.chatMessagesRequestedMarkRead.last, '');
      expect(find.text('missed one'), findsOneWidget);
      expect(find.text('missed two'), findsOneWidget);

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'a first connect is not a reconnect: no extra fetch, join carries no flag',
    (tester) async {
      seedBuyers();
      await openAlice(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(joins(), [joinPayload()]);
      // Exactly one history request: the one that opened the chat.
      expect(FakeApiServer.chatMessagesRequestedMarkRead, ['']);

      await teardownTree(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
