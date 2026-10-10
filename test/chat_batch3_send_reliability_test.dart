import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/carzo_shared.dart' show AuthGuard;
import 'package:car_listing_app/features/chat/chat_live_transport.dart';
import 'package:car_listing_app/features/chat/chat_pages.dart' as carzo_chat;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/outgoing_chat_send_service.dart';
import 'package:car_listing_app/shared/prefs/chat_pending_send_prefs.dart';

import 'fake_api_server.dart';

/// CHAT-2: text send must use reliable REST, never silent WebSocket drop.
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
    FakeApiServer.chatSendOverride = null;
    FakeApiServer.chatSendCallCount = 0;
    FakeApiServer.chatSendIdempotencyKeys.clear();
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.chatSendOverride = null;
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  group('CHAT-2 transport policy', () {
    test('never prefers WebSocket text send, even when socket is connected', () {
      expect(chatTextSendUsesWebSocket(socketConnected: true), isFalse);
      expect(chatTextSendUsesWebSocket(socketConnected: false), isFalse);
    });

    test('collapses pending by id or FIFO sender+type (not content)', () {
      expect(
        shouldCollapsePendingChatBubble(
          incomingIsPending: false,
          incomingId: 'srv-1',
          incomingSenderId: '1',
          incomingMessageType: 'text',
          pendingId: 'temp-9',
          pendingIsPending: true,
          pendingSenderId: '1',
          pendingMessageType: 'text',
        ),
        isTrue,
      );
      expect(
        shouldCollapsePendingChatBubble(
          incomingIsPending: false,
          incomingId: 'srv-1',
          incomingSenderId: '1',
          incomingMessageType: 'text',
          pendingId: 'temp-9',
          pendingIsPending: true,
          pendingSenderId: '2',
          pendingMessageType: 'text',
        ),
        isFalse,
      );
      expect(
        shouldCollapsePendingChatBubble(
          incomingIsPending: false,
          incomingId: 'srv-1',
          incomingSenderId: '1',
          incomingMessageType: 'text',
          pendingId: 'temp-media',
          pendingIsPending: true,
          pendingSenderId: '1',
          pendingMessageType: 'image',
        ),
        isFalse,
      );
      expect(
        shouldCollapsePendingChatBubble(
          incomingIsPending: false,
          incomingId: 'srv-1',
          incomingSenderId: '1',
          incomingMessageType: 'text',
          pendingId: 'srv-1',
          pendingIsPending: false,
          pendingSenderId: '1',
          pendingMessageType: 'text',
        ),
        isTrue,
      );
    });

    test('two identical intentional texts remain two messages (FIFO)', () {
      var rows = <(String, String, String, bool)>[
        ('temp-a', '1', 'text', true),
        ('temp-b', '1', 'text', true),
      ];
      rows = mergeChatMessageAvoidingPendingDup(
        rows,
        ('srv-1', '1', 'text', false),
      );
      rows = mergeChatMessageAvoidingPendingDup(
        rows,
        ('srv-2', '1', 'text', false),
      );
      expect(rows.map((r) => r.$1).toList(), ['srv-1', 'srv-2']);
      expect(rows.every((r) => !r.$4), isTrue);
    });
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

  Future<void> pumpQuiet(WidgetTester tester, {int times = 40}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();
    }
  }

  testWidgets('successful text send goes through REST with pending bubble', (
    tester,
  ) async {
    const carId = 'chat3_car_ok';
    const outgoing = 'Reliable REST hello';

    await tester.pumpWidget(
      harness(
        AuthGuard(
          child: carzo_chat.ChatConversationPage(
            carId: carId,
            receiverId: 'seller_1',
          ),
        ),
      ),
    );
    await pumpQuiet(tester);

    await tester.enterText(find.byType(TextField), outgoing);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await pumpQuiet(tester, times: 80);

    expect(FakeApiServer.chatSendCallCount, greaterThanOrEqualTo(1));
    expect(find.text(outgoing), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text ?? '', isEmpty);
  });

  testWidgets('failed send restores text — no silent loss', (tester) async {
    const carId = 'chat3_car_fail';
    const outgoing = 'Must not disappear';

    FakeApiServer.chatSendOverride =
        (request, callIndex) => http.Response('{"error":"forbidden"}', 403);

    await tester.pumpWidget(
      harness(
        AuthGuard(
          child: carzo_chat.ChatConversationPage(
            carId: carId,
            receiverId: 'seller_1',
          ),
        ),
      ),
    );
    await pumpQuiet(tester);

    await tester.enterText(find.byType(TextField), outgoing);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await pumpQuiet(tester, times: 80);

    expect(FakeApiServer.chatSendCallCount, greaterThanOrEqualTo(1));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, outgoing);
  });

  testWidgets('retryable failure keeps pending and can recover', (tester) async {
    const carId = 'chat3_car_retry';
    const outgoing = 'Retry me';
    FakeApiServer.chatSendOverride = (request, callIndex) {
      if (callIndex == 0) {
        return http.Response('', 500);
      }
      return null; // fall through to FakeApiServer success path
    };

    await tester.pumpWidget(
      harness(
        AuthGuard(
          child: carzo_chat.ChatConversationPage(
            carId: carId,
            receiverId: 'seller_1',
          ),
        ),
      ),
    );
    await pumpQuiet(tester);

    await tester.enterText(find.byType(TextField), outgoing);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await pumpQuiet(tester, times: 60);

    expect(find.text(outgoing), findsWidgets);
    expect(find.byIcon(Icons.schedule), findsWidgets);

    final pending = await ChatPendingSendPrefs.loadForConversation(carId);
    expect(pending, hasLength(1));
    final rec = pending.single;
    // Bypass minAutoRetryInterval without sleeping (same pattern as F-11 tests).
    await ChatPendingSendPrefs.upsert(
      rec.copyWith(
        lastAttemptAt: DateTime.now()
            .subtract(const Duration(seconds: 30))
            .millisecondsSinceEpoch,
      ),
    );

    await OutgoingChatSendService.instance.recoverPendingSends(
      conversationId: carId,
    );
    await pumpQuiet(tester, times: 80);

    expect(FakeApiServer.chatSendCallCount, greaterThanOrEqualTo(2));
    expect(
      FakeApiServer.chatSendIdempotencyKeys.toSet().length,
      1,
      reason: 'retries must reuse one idempotency key',
    );
  });
}
