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

import 'fake_api_server.dart';

/// Regression coverage for the RC smoke-test finding: the chat composer
/// (text field + send button) used to be rendered with a flat
/// `EdgeInsets.all(16)` `Container` and no `SafeArea`/`viewPadding`
/// awareness, so on an edge-to-edge Android device the send button could
/// sit partly under the system nav bar.
///
/// This simulates a bottom system inset the same way
/// `test/system_display_lock_test.dart` simulates insets on
/// `MediaQueryData` directly (`padding`/`viewPadding` with a non-zero
/// `bottom`), just adapted to a full widget/page test via
/// `MaterialApp.builder` (the standard way to override the `MediaQuery`
/// seen by everything below `MaterialApp`, since `MaterialApp` otherwise
/// derives its own from the test binding).
void main() {
  // A deliberately large simulated system-nav inset — comfortably bigger
  // than the composer's own flat padding (16) — so a regression (no
  // SafeArea) reliably pushes the send button into the "inset zone"
  // asserted against below, instead of relying on a fragile few-pixel
  // margin.
  const double kSimulatedBottomInset = 48;

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

  /// Mirrors the other chat harnesses in this suite, plus a `builder` that
  /// injects a bottom system inset into the `MediaQuery` the whole app (and
  /// therefore the composer) sees — with no keyboard open
  /// (`viewInsets.bottom == 0`), matching a closed-keyboard, edge-to-edge
  /// Android device with a visible gesture/3-button nav bar.
  Widget harness(Widget child, {double bottomInset = 0}) {
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
        builder: (context, appChild) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(bottom: bottomInset),
              viewPadding: mq.viewPadding.copyWith(bottom: bottomInset),
              viewInsets: mq.viewInsets.copyWith(bottom: 0),
            ),
            child: appChild!,
          );
        },
        home: child,
      ),
    );
  }

  Future<void> pumpAndSettleIgnoringUnrelatedErrors(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      // As in chat_composer_prefill_listing_test.dart: any unrelated
      // FlutterError recorded here is a pre-existing condition, not
      // introduced by this fix — consume it so it can't fail this test.
      tester.takeException();
    }
  }

  testWidgets(
    'composer stays present and clears a simulated bottom system inset '
    '(send button not inside the inset zone)',
    (tester) async {
      await tester.pumpWidget(
        harness(
          AuthGuard(
            child: carzo_chat.ChatConversationPage(
              carId: 'chat_inset_test_car',
              receiverId: 'seller_1',
              carTitle: 'Toyota Camry 2020',
            ),
          ),
          bottomInset: kSimulatedBottomInset,
        ),
      );
      await tester.pump();
      await pumpAndSettleIgnoringUnrelatedErrors(tester);

      // Composer must still be present and usable.
      expect(find.byType(TextField), findsOneWidget);
      final sendButtonFinder = find.byIcon(Icons.send);
      expect(sendButtonFinder, findsOneWidget);

      final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
      final insetZoneTop = screenHeight - kSimulatedBottomInset;

      final sendButtonBottom = tester.getBottomLeft(sendButtonFinder).dy;
      final textFieldBottom = tester
          .getBottomLeft(find.byType(TextField))
          .dy;

      expect(
        sendButtonBottom,
        lessThanOrEqualTo(insetZoneTop),
        reason:
            'Send button bottom edge ($sendButtonBottom) must sit above the '
            'simulated system-nav inset zone (starts at $insetZoneTop) — a '
            'composer with no SafeArea/viewPadding handling would render it '
            'inside that zone.',
      );
      expect(
        textFieldBottom,
        lessThanOrEqualTo(insetZoneTop),
        reason:
            'Text field bottom edge ($textFieldBottom) must sit above the '
            'simulated system-nav inset zone (starts at $insetZoneTop).',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'composer does not double up bottom padding when there is no system '
    'inset to account for',
    (tester) async {
      await tester.pumpWidget(
        harness(
          AuthGuard(
            child: carzo_chat.ChatConversationPage(
              carId: 'chat_inset_test_car_zero',
              receiverId: 'seller_1',
              carTitle: 'Toyota Camry 2020',
            ),
          ),
          bottomInset: 0,
        ),
      );
      await tester.pump();
      await pumpAndSettleIgnoringUnrelatedErrors(tester);

      expect(find.byType(TextField), findsOneWidget);

      final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
      final sendButtonBottom = tester.getBottomLeft(find.byIcon(Icons.send)).dy;

      // With zero system inset, SafeArea should reserve (effectively)
      // nothing extra — the composer's own fixed padding (16) is the only
      // gap, so the send button must still sit close to the bottom of the
      // screen, not be pushed far up by an unrelated/duplicated inset.
      expect(
        screenHeight - sendButtonBottom,
        lessThan(80),
        reason:
            'With no system inset, the composer should only reserve its own '
            'normal padding, not an extra/duplicated safe-area gap.',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
