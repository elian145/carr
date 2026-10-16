// Regression tests: "Failed to load your listings" right after a successful
// submission + background/foreground (Galaxy A17).
//
// Root cause pinned here: the page's listings GET had NO retry, so one
// transient failure (a socket the OS killed while the app was backgrounded, a
// 5xx, a session-refresh blip) became the visible error; a request that was
// in flight across the resume then failed AFTER the resume check had already
// run, and nothing ever replaced it; and a refresh wiped the list it was
// refreshing. Pressing Retry "worked" only because the network was back by
// then.
//
// Every test drives the page with a scripted MockClient and Completers; no
// real network, no real timing.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
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

const _failedText = 'Failed to load your listings';
const _listingsPath = '/api/user/my-listings';

http.Response _json(int status, Object body) => http.Response(
  json.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _car(String id, String model) => {
  'id': id,
  'public_id': id,
  'brand': 'toyota',
  'model': model,
  'title': 'Toyota $model',
  'year': 2020,
  'price': 12000,
  'mileage': 1000,
  'city': 'baghdad',
  'status': 'pending',
  'images': <dynamic>[],
};

http.Response _listing(List<Map<String, dynamic>> cars) => _json(200, {
  'cars': cars,
  'pagination': {'has_next': false},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    TokenStore.testMode = true;
    debugTransientGetRetryDelays = const [Duration.zero, Duration.zero];
    await ApiService.setTokens(
      accessToken: 'access_rs',
      refreshToken: 'refresh_rs',
    );
  });

  tearDown(() async {
    ApiService.testHttpClient = null;
    debugTransientGetRetryDelays = null;
    await ApiService.clearTokens();
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  Future<void> settle(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

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
    await settle(tester);
  }

  void emitSubmissionSuccess() {
    PendingSellSubmissionService.instance.debugEmit(
      const SellSubmissionEvent(
        draftId: 'd1',
        success: true,
        needsAttention: false,
        carId: 'car_new',
      ),
    );
  }

  testWidgets(
    'A. submission succeeds, the first listings fetch fails transiently and '
    'the next succeeds: the listing appears automatically, the error is '
    'never shown, nothing is logged out',
    (tester) async {
      var calls = 0;
      var phase = 0; // 0: initial empty list; 1: after submission
      var failuresLeft = 1;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path != _listingsPath) return _json(200, {});
        calls++;
        if (phase == 0) return _listing([]);
        if (failuresLeft > 0) {
          failuresLeft--;
          throw const SocketException('Software caused connection abort');
        }
        return _listing([_car('car_new', 'Camry')]);
      });

      await pumpPage(tester);
      expect(calls, 1);
      expect(find.textContaining('Camry'), findsNothing);

      // The background worker finishes the submission -> the page reloads.
      phase = 1;
      emitSubmissionSuccess();
      await settle(tester);

      expect(find.text(_failedText), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(
        find.textContaining('Camry'),
        findsWidgets,
        reason: 'the new listing shows up without a manual Retry',
      );
      expect(calls, 3, reason: '1 initial + failed attempt + retry');
      expect(ApiService.isAuthenticated, isTrue, reason: 'no logout');
    },
  );

  testWidgets(
    'B. background -> foreground while the first request is in flight: the '
    'request that dies on the dead socket AFTER the resume is superseded, so '
    'it can neither show an error nor overwrite the fresh result',
    (tester) async {
      var calls = 0;
      final firstInFlight = Completer<http.Response>();
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path != _listingsPath) return _json(200, {});
        calls++;
        if (calls == 1) return firstInFlight.future; // rides a dying socket
        return _listing([_car('car_1', 'Corolla')]);
      });

      // Page opens; its first request hangs.
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
      await settle(tester, 4);
      expect(calls, 1);

      // App goes to the background and comes back with the request still
      // outstanding: a fresh request supersedes it.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(calls, 2, reason: 'resume started a replacement request');
      expect(find.textContaining('Corolla'), findsWidgets);

      // The old request finally dies (the OS killed its socket).
      // (A transient error that ApiService's own one-shot stale-socket retry
      // does not swallow, so only the page's supersede guard is under test.)
      firstInFlight.completeError(
        const SocketException('Network is unreachable'),
      );
      await settle(tester);

      expect(find.text(_failedText), findsNothing);
      expect(find.textContaining('Corolla'), findsWidgets);
      expect(calls, 2, reason: 'the stale request was not retried either');
    },
  );

  testWidgets(
    'C. an OLD failed fetch that completes after a newer successful fetch '
    'cannot overwrite it (non-retryable failure, so this is the pure '
    'stale-result guard)',
    (tester) async {
      var calls = 0;
      final first = Completer<http.Response>();
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path != _listingsPath) return _json(200, {});
        calls++;
        if (calls == 1) return first.future;
        return _listing([_car('car_2', 'Yaris')]);
      });

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
      await settle(tester, 4);

      // Newer refresh (e.g. the submission-success reload) wins first.
      emitSubmissionSuccess();
      await settle(tester);
      expect(find.textContaining('Yaris'), findsWidgets);

      // Then the old one completes with a hard (non-transient) failure.
      first.complete(_json(400, {'message': 'stale request rejected'}));
      await settle(tester);

      expect(find.text('stale request rejected'), findsNothing);
      expect(find.text(_failedText), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('Yaris'), findsWidgets);
    },
  );

  testWidgets(
    'D. a temporary 401 whose session refresh fails on the network, and a '
    'temporary 503, are retried automatically: the list loads, the session '
    'is NOT cleared',
    (tester) async {
      var listingCalls = 0;
      var refreshCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          refreshCalls++;
          throw const SocketException('radio asleep'); // transient
        }
        if (request.url.path != _listingsPath) return _json(200, {});
        listingCalls++;
        if (listingCalls == 1) {
          return _json(401, {'message': 'Token has expired'});
        }
        if (listingCalls == 2) {
          return _json(503, {'message': 'warming up'});
        }
        return _listing([_car('car_3', 'Avalon')]);
      });

      await pumpPage(tester);

      expect(listingCalls, 3, reason: '401(+refresh blip) -> 503 -> 200');
      expect(refreshCalls, 1);
      expect(find.text(_failedText), findsNothing);
      expect(find.textContaining('Avalon'), findsWidgets);
      expect(
        ApiService.accessToken,
        'access_rs',
        reason: 'a temporary refresh failure must not log the seller out',
      );
      expect(ApiService.isAuthenticated, isTrue);
    },
  );

  testWidgets(
    'E. a persistent failure is bounded (no infinite retry loop), still '
    'shows the error with Retry, and Retry recovers once the server is back',
    (tester) async {
      var calls = 0;
      var serverUp = false;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path != _listingsPath) return _json(200, {});
        calls++;
        if (!serverUp) return _json(503, {'message': 'down'});
        return _listing([_car('car_4', 'Hilux')]);
      });

      await pumpPage(tester);
      expect(calls, 3, reason: '1 attempt + exactly 2 bounded retries');
      expect(find.text('down'), findsOneWidget, reason: 'error is shown');
      expect(find.text('Retry'), findsOneWidget);

      // Time passing alone never triggers more requests.
      await settle(tester, 40);
      expect(calls, 3, reason: 'no retry loop');

      serverUp = true;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(calls, 4);
      expect(find.text('down'), findsNothing);
      expect(find.textContaining('Hilux'), findsWidgets);
    },
  );

  testWidgets(
    'E2. listings already on screen stay visible when a later refresh fails '
    'persistently; the failure is an inline banner with Retry, not a wiped '
    'screen',
    (tester) async {
      var calls = 0;
      var serverUp = true;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path != _listingsPath) return _json(200, {});
        calls++;
        if (!serverUp) return _json(503, {'message': 'down'});
        return _listing([_car('car_5', 'Prius')]);
      });

      await pumpPage(tester);
      expect(find.textContaining('Prius'), findsWidgets);

      serverUp = false;
      emitSubmissionSuccess(); // triggers a refresh that fails persistently
      await settle(tester);

      expect(find.textContaining('Prius'), findsWidgets,
          reason: 'existing data stays visible');
      expect(
        find.byKey(const ValueKey<String>('my-listings-inline-error')),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      serverUp = true;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('my-listings-inline-error')),
        findsNothing,
      );
      expect(find.textContaining('Prius'), findsWidgets);
      expect(calls, 5);
    },
  );
}
