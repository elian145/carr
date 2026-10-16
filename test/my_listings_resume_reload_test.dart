// Regression test: My Listings must recover after the app returns from the
// background.
//
// Real-device bug (Galaxy A17): the list load that ran while the app was
// being backgrounded failed (dead socket / session refresh not possible yet)
// and the page then sat on its error state until the seller manually tapped
// Retry. It now reloads by itself when the app is foregrounded -- but only
// when it is actually in an error state (no needless traffic otherwise).
import 'dart:convert';

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/my_listings_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/net/transient_get_retry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    TokenStore.testMode = true;
    // Zero-delay retries: the retry BUDGET (3 attempts) still applies.
    debugTransientGetRetryDelays = const [Duration.zero, Duration.zero];
    await ApiService.setTokens(
      accessToken: 'access_ml',
      refreshToken: 'refresh_ml',
    );
  });

  tearDown(() async {
    ApiService.testHttpClient = null;
    debugTransientGetRetryDelays = null;
    await ApiService.clearTokens();
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: AuthService(),
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: MyListingsPage(),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'ML1. a persistently failed list load is retried when the app is '
    'foregrounded; a healthy page is not reloaded',
    (tester) async {
      var calls = 0;
      var serverUp = false;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/user/my-listings') {
          calls++;
          if (!serverUp) {
            return http.Response(
              json.encode({'message': 'temporarily unavailable'}),
              503,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({
              'cars': <dynamic>[],
              'pagination': {'has_next': false},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(json.encode(<String, dynamic>{}), 200);
      });

      await pumpPage(tester);
      expect(calls, 3, reason: 'initial load: 1 attempt + 2 bounded retries');
      expect(find.text('Retry'), findsOneWidget, reason: 'failed state shown');

      // Background -> foreground while the backend is still down: one more
      // bounded round (and it fails again), without a manual tap.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(calls, 6, reason: 'foregrounding retried the failed load');
      expect(find.text('Retry'), findsOneWidget);

      // Network is back; next foreground recovers without any tap.
      serverUp = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(calls, 7);
      expect(find.text('Retry'), findsNothing, reason: 'recovered');

      // Healthy now: foregrounding again must not refetch the list.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(calls, 7, reason: 'no needless reload for a healthy page');
    },
  );
}
