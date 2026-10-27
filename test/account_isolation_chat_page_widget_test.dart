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
import 'support/test_jwt.dart';

/// F-35 UI-level regression: a conversation screen only shows -- and only
/// ever acts on -- pending sends that belong to the signed-in account, even
/// when two accounts open the very same conversation id.
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

  Future<void> signInAs(String account) async {
    // adoptTestSession installs opaque placeholder tokens, so it must run
    // BEFORE the JWT-bearing tokens are installed.
    await AuthService().adoptTestSession(
      user: {
        'id': account,
        'username': account,
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
    await ApiService.setTokens(
      accessToken:
          testJwt(account, nonce: DateTime.now().microsecondsSinceEpoch),
      refreshToken: testJwt(account, type: 'refresh'),
    );
  }

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

  Widget page(String carId) => harness(
        AuthGuard(
          child: carzo_chat.ChatConversationPage(
            carId: carId,
            receiverId: 'seller_1',
            carTitle: 'Toyota Camry 2020',
          ),
        ),
      );

  Future<void> settle(WidgetTester tester, {int times = 40}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();
    }
  }

  testWidgets(
    "account B never sees A's pending bubble in the same conversation; A "
    'sees it again after signing back in',
    (tester) async {
      const carId = 'iso_chat_car_1';
      FakeApiServer.chatSendOverride =
          (request, callIndex) => http.Response('', 500);

      await signInAs('acct_A');
      await tester.pumpWidget(page(carId));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'A private offer');
      await settle(tester, times: 5);
      await tester.tap(find.byIcon(Icons.send));
      await settle(tester);
      expect(find.byIcon(Icons.schedule), findsWidgets,
          reason: "A's failed-but-retryable send shows as pending for A");
      expect(
        await ChatPendingSendPrefs.loadForOwner('acct_A'),
        hasLength(1),
      );

      // A signs out, B signs in and opens the very same conversation.
      await tester.pumpWidget(harness(const SizedBox.shrink()));
      await settle(tester, times: 5);
      await ApiService.logout();
      FakeApiServer.chatSendOverride = null;
      FakeApiServer.chatSendCallCount = 0;
      await signInAs('acct_B');
      await tester.pumpWidget(page(carId));
      await settle(tester);

      expect(find.byType(TextField), findsWidgets,
          reason: 'the conversation screen is actually shown to B');
      expect(find.byIcon(Icons.schedule), findsNothing,
          reason: "B must not see A's pending bubble");
      expect(find.text('A private offer'), findsNothing);
      expect(FakeApiServer.chatSendCallCount, 0,
          reason: "A's pending message must never be (re)sent while B is "
              'signed in');

      // Back to A: the record is still there and visible again.
      await tester.pumpWidget(harness(const SizedBox.shrink()));
      await settle(tester, times: 5);
      await ApiService.logout();
      FakeApiServer.chatSendOverride =
          (request, callIndex) => http.Response('', 500);
      await signInAs('acct_A');
      await tester.pumpWidget(page(carId));
      await settle(tester);
      expect(find.byIcon(Icons.schedule), findsWidgets,
          reason: "A's pending send is kept for A");
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
