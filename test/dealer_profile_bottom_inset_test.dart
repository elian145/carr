import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/dealer_profile_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

/// Regression coverage for the RC smoke-test finding: the dealer profile
/// page ("dealer details") renders its scrollable content (`RefreshIndicator`
/// + `CustomScrollView`) directly as the `Scaffold.body` with no
/// `bottomNavigationBar` and no `SafeArea`/`viewPadding` awareness, so on an
/// edge-to-edge Android device the bottom of that content (the listings
/// grid's empty-state card, or the last item of the "About" section) could
/// render partly under the system nav bar.
///
/// Simulates a bottom system inset the same way
/// `test/chat_composer_bottom_inset_test.dart` does — via `MaterialApp`'s
/// `builder`, which is the standard way to override the `MediaQuery` seen by
/// everything below `MaterialApp` in a widget test.
void main() {
  const double kSimulatedBottomInset = 48;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

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

  Future<void> pumpUntilDealerLoaded(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();
      if (find.text('Test Dealer').evaluate().isNotEmpty) return;
    }
  }

  testWidgets(
    'dealer page scroll viewport is inset from a simulated bottom system '
    'nav bar, not extended underneath it',
    (tester) async {
      await tester.pumpWidget(
        harness(
          const DealerProfilePage(dealerPublicId: 'dealer_test_1'),
          bottomInset: kSimulatedBottomInset,
        ),
      );
      await tester.pump();
      await pumpUntilDealerLoaded(tester);

      // Sanity: the page actually loaded the dealer (not stuck on a
      // loading spinner) before asserting on layout below.
      expect(find.text('Test Dealer'), findsOneWidget);

      // A `CustomScrollView`'s viewport always expands to fill the space
      // its parent gives it (that's how scrolling within a fixed-size
      // window works) — so its rendered bottom edge directly reflects
      // whether something above it (here, the new `SafeArea`) reserved
      // room for the system nav bar, regardless of how much content is
      // actually inside it.
      final scrollableFinder = find.byWidgetPredicate(
        (widget) => widget is CustomScrollView,
      );
      expect(scrollableFinder, findsOneWidget);

      final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
      final insetZoneTop = screenHeight - kSimulatedBottomInset;
      final scrollableBottom = tester.getBottomLeft(scrollableFinder).dy;

      expect(
        scrollableBottom,
        lessThanOrEqualTo(insetZoneTop),
        reason:
            'The dealer page\'s scroll viewport bottom edge '
            '($scrollableBottom) must sit above the simulated system-nav '
            'inset zone (starts at $insetZoneTop) — a page with no '
            'SafeArea/viewPadding handling would let the viewport (and '
            'therefore its content, once scrolled to the end) extend '
            'underneath the bar instead.',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
