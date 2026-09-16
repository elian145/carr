import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/carzo_shared.dart' show AuthGuard;
import 'package:car_listing_app/features/chat/chat_pages.dart' as carzo_chat;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/prefs/chat_pending_send_prefs.dart';

import 'fake_api_server.dart';

/// F-11 regression coverage: a REST chat text send that fails with a
/// retryable (transient) error must not silently vanish once the
/// conversation page is disposed — it must remain visible/re-triggerable
/// as a pending bubble the next time the same conversation is opened
/// (durable recovery via `ChatPendingSendPrefs`/`OutgoingChatSendService`).
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

  Future<void> pumpIgnoringUnrelatedErrors(
    WidgetTester tester, {
    int times = 40,
  }) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();
    }
  }

  testWidgets(
    'a failed-but-retryable text send remains a pending bubble after the '
    'conversation page is disposed and reopened',
    (tester) async {
      const carId = 'f11_chat_car_1';

      // Every REST chat send for this test fails with a transient (500)
      // error, so it is never expected to resolve successfully.
      FakeApiServer.chatSendOverride =
          (request, callIndex) => http.Response('', 500);

      await tester.pumpWidget(
        harness(
          AuthGuard(
            child: carzo_chat.ChatConversationPage(
              carId: carId,
              receiverId: 'buyer_1',
              carTitle: 'Toyota Camry 2020',
            ),
          ),
        ),
      );
      await pumpIgnoringUnrelatedErrors(tester);

      // Type a message and tap send.
      await tester.enterText(find.byType(TextField), 'hello offline world');
      await pumpIgnoringUnrelatedErrors(tester, times: 5);
      await tester.tap(find.byIcon(Icons.send));
      await pumpIgnoringUnrelatedErrors(tester);

      // A pending ("clock") bubble must appear immediately for the failed
      // send, and a durable pending record must have been persisted.
      expect(
        find.byIcon(Icons.schedule),
        findsWidgets,
        reason: 'The failed-but-retryable send should show a pending bubble',
      );
      var pending = await ChatPendingSendPrefs.loadForConversation(carId);
      expect(pending, hasLength(1));
      expect(pending.single.content, 'hello offline world');
      final idempotencyKey = pending.single.idempotencyKey;

      // Dispose the conversation page entirely (navigate away).
      await tester.pumpWidget(harness(const SizedBox.shrink()));
      await pumpIgnoringUnrelatedErrors(tester, times: 5);

      // The durable record must have survived page disposal untouched.
      pending = await ChatPendingSendPrefs.loadForConversation(carId);
      expect(
        pending,
        hasLength(1),
        reason: 'Pending send must survive conversation page disposal',
      );
      expect(pending.single.idempotencyKey, idempotencyKey);

      // Reopen the same conversation (simulates the user coming back, or a
      // fresh page instance being created — the durable record does not
      // depend on the disposed State object at all).
      await tester.pumpWidget(
        harness(
          AuthGuard(
            child: carzo_chat.ChatConversationPage(
              carId: carId,
              receiverId: 'buyer_1',
              carTitle: 'Toyota Camry 2020',
            ),
          ),
        ),
      );
      await pumpIgnoringUnrelatedErrors(tester);

      // The pending bubble must reappear — the send is visible/
      // re-triggerable, not silently gone.
      expect(
        find.byIcon(Icons.schedule),
        findsWidgets,
        reason:
            'Reopening the conversation must show the still-pending send '
            'again instead of it having silently disappeared',
      );
      // Whether or not a bounded automatic retry has fired again this soon
      // (it is throttled by OutgoingChatSendService.minAutoRetryInterval),
      // every attempt actually made for this logical send — including the
      // original one — must carry the exact same idempotency key. No
      // attempt may ever have used a different (freshly-generated) key.
      expect(
        FakeApiServer.chatSendIdempotencyKeys,
        everyElement(idempotencyKey),
        reason: 'Every retry of the same logical send must reuse one key',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
