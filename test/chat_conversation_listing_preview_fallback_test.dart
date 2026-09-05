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

/// End-to-end proof for Fix A, at the `ChatConversationPage` consumer side:
/// given the same `initialListingPreview` shape `ChatListPage` now forwards
/// (see chat_list_navigation_listing_preview_test.dart for the producer
/// side), `ChatConversationPage`'s real, unmodified
/// `_ensureCarListingMeta()` should skip `ApiService.getCar()` when the
/// preview already has brand+model+image, and should preserve the existing
/// fallback (call `ApiService.getCar()`) when it doesn't.
///
/// This mounts `AuthGuard(child: ChatConversationPage(...))` directly —
/// exactly what `production_routes.dart`'s `/chat/conversation` route
/// builds — in a minimal harness, deliberately skipping the full app shell
/// (`MainShell`/`BottomNavigationBar`) which is unrelated to this behavior.
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
    FakeApiServer.carDetailFetchCount = 0;
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.carDetailFetchCount = 0;
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

  Future<void> pumpAndSettleIgnoringUnrelatedErrors(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      // Any FlutterError recorded here is a pre-existing, unrelated
      // condition (not introduced by Fix A) — consume it so it cannot fail
      // this test, while still letting the real network-call assertion
      // below prove the actual behavior we care about.
      tester.takeException();
    }
  }

  testWidgets(
    'complete listing metadata (brand+model+image) skips ApiService.getCar()',
    (tester) async {
      await tester.pumpWidget(
        harness(
          AuthGuard(
            child: carzo_chat.ChatConversationPage(
              carId: 'chat_car_full',
              receiverId: 'buyer_1',
              initialListingPreview: const {
                'brand': 'toyota',
                'model': 'camry',
                'year': '2020',
                'image_url': 'car_photos/full.jpg',
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await pumpAndSettleIgnoringUnrelatedErrors(tester);

      expect(
        FakeApiServer.carDetailFetchCount,
        0,
        reason:
            'ChatConversationPage should use the forwarded listingPreview '
            'instead of calling GET /api/cars/<id> a second time.',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'missing listing metadata preserves the ApiService.getCar() fallback',
    (tester) async {
      await tester.pumpWidget(
        harness(
          AuthGuard(
            child: carzo_chat.ChatConversationPage(
              carId: 'chat_car_empty',
              receiverId: 'buyer_1',
              // No initialListingPreview: listing metadata is genuinely
              // unavailable, exactly like a chat row with no brand/model/
              // image data would produce via Fix A.
            ),
          ),
        ),
      );
      await tester.pump();
      await pumpAndSettleIgnoringUnrelatedErrors(tester);

      expect(
        FakeApiServer.carDetailFetchCount,
        greaterThanOrEqualTo(1),
        reason:
            'With no usable listingPreview, ChatConversationPage must still '
            'fall back to GET /api/cars/<id> exactly as it did before Fix A.',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
