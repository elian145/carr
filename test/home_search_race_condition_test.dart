// Regression test for the reported "searching 'Land Cruiser' still shows
// 'Land Cruiser Prado'" bug.
//
// Investigation summary (see the accompanying chat report for the full
// trace): the backend's `/api/cars?q=Land%20Cruiser` response was already
// verified correct (exactly one "Land Cruiser" listing, zero "Land Cruiser
// Prado"), and the Flutter request-building layer
// (`homeFiltersToApiQuery`/`homeFeedDefaultSortAllowed`, already covered by
// `home_filters_query_test.dart`'s CN-SEARCH-01 tests) sends the exact same
// `q=Land Cruiser` the user typed, with no ambient sort override.
//
// The actual remaining bug was a client-side race condition in
// `home_fetch_core.dart`'s `fetchCars()`/`_loadMore()`/
// `_fetchFromApiCars()`/`_fetchWithoutSort()` (and `home_fetch.dart`'s sort
// fallback chain): none of these guarded against out-of-order responses.
// Every one of them unconditionally did `setState(() => cars = ...)` with
// whatever response arrived, regardless of whether a *newer* fetchCars()
// call (e.g. the user editing/re-running their search) had since started.
//
// Concretely: if an older, broader request (the unfiltered home feed on
// first load, or a previous, broader search like "Land Cruiser Prado")
// happened to still be in flight when the user's next/actual search
// ("Land Cruiser") was issued, and the older request's response arrived
// *after* the newer one's, it would silently overwrite the correct, narrow
// result set with the older/broader one -- so the UI could show listings
// (e.g. "Land Cruiser Prado") that were never part of the *current*
// search's actual API response, exactly matching the bug report.
//
// The fix adds a monotonic `_feedRequestGeneration` counter (see its doc
// comment on `_HomePageFields` in `home_page.dart`): every fetchCars() call
// claims a new generation, and every place that would otherwise mutate
// `cars`/pagination state from a response checks its captured generation
// against the current one first, discarding stale results instead of
// applying them.
//
// This test drives that race directly and deterministically (no
// timers/sleeps) via `FakeApiServer.carsQueryGates`: it starts an older,
// broader search ("Land Cruiser Prado"), then a newer, narrower search
// ("Land Cruiser") before the first resolves, completes the *newer*
// request's response first (as the backend/network genuinely would for the
// user's actual, current search), and only *then* completes the *older*
// request's response -- proving the stale "Land Cruiser Prado" data can
// never clobber the already-applied, correct "Land Cruiser" results.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/features/home/home_flow.dart' show HomePage;
import 'package:car_listing_app/l10n/app_localizations.dart';

import 'fake_api_server.dart';

http.Response _jsonResponse(int status, Object body) => http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _car(String id, String brand, String model) => {
      'id': id,
      'title': '$brand $model',
      'brand': brand,
      'model': model,
      'year': 2020,
      'price': 20000,
      'currency': 'USD',
      'location': 'Erbil',
      'image_url': '',
      'images': <dynamic>[],
      'videos': <dynamic>[],
      'seller': {'id': 'seller_1', 'username': 'seller'},
    };

Widget _harness() {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HomePage(),
  );
}

Future<void> _pumpTicks(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FakeApiServer.carsQueryGates = null;
    FakeApiServer.carsRequestedQueries.clear();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets(
    'a newer, narrower search is never overwritten by an older, broader '
    "search's response arriving later (Land Cruiser vs Land Cruiser Prado)",
    (tester) async {
      final oldGate = Completer<http.Response>();
      final newGate = Completer<http.Response>();
      FakeApiServer.carsQueryGates = {
        'Land Cruiser Prado': oldGate,
        'Land Cruiser': newGate,
      };

      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // --- First (older, broader) search: "Land Cruiser Prado" ---
      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Search Cars'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).first,
        'Land Cruiser Prado',
      );
      await tester.pump();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Let fetchCars() for the first search run up to (and block on) the
      // gated GET /api/cars?q=Land+Cruiser+Prado request.
      await _pumpTicks(tester, 15);

      // --- Second (newer, narrower) search: "Land Cruiser" ---
      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(find.byType(TextField).first, 'Land Cruiser');
      await tester.pump();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await _pumpTicks(tester, 15);

      // Sanity: both requests actually reached the server before either
      // resolves, in the order the user issued them.
      expect(
        FakeApiServer.carsRequestedQueries.contains('Land Cruiser Prado'),
        isTrue,
      );
      expect(
        FakeApiServer.carsRequestedQueries.contains('Land Cruiser'),
        isTrue,
      );

      // Resolve the NEWER (current) search first -- exactly like the
      // verified-correct backend response for the user's actual query.
      newGate.complete(
        _jsonResponse(200, {
          'cars': [_car('lc_1', 'Toyota', 'Land Cruiser')],
          'pagination': {'has_next': false, 'total': 1},
        }),
      );
      await _pumpTicks(tester, 15);

      expect(find.textContaining('Land Cruiser Prado'), findsNothing);
      expect(find.textContaining('Land Cruiser'), findsWidgets);

      // Now resolve the OLDER, broader (now-stale) search's response.
      // Without the fix, this overwrites `cars` with these Prado rows even
      // though the user is no longer searching for them.
      oldGate.complete(
        _jsonResponse(200, {
          'cars': [
            _car('prado_1', 'Toyota', 'Land Cruiser Prado'),
            _car('prado_2', 'Toyota', 'Land Cruiser Prado'),
          ],
          'pagination': {'has_next': false, 'total': 2},
        }),
      );
      await _pumpTicks(tester, 15);

      // The stale, older response must never clobber the newer, correct
      // result: still only "Land Cruiser", never "Land Cruiser Prado".
      expect(
        find.textContaining('Land Cruiser Prado'),
        findsNothing,
        reason:
            'A stale response from an older, broader search overwrote the '
            'current, correct search results -- this is the exact bug '
            'reported ("search Land Cruiser, see Land Cruiser Prado").',
      );
      expect(find.textContaining('Land Cruiser'), findsWidgets);
    },
  );

  testWidgets(
    'a fresh search replaces previous results instead of appending to them',
    (tester) async {
      final firstGate = Completer<http.Response>();
      final secondGate = Completer<http.Response>();
      FakeApiServer.carsQueryGates = {
        'Corolla': firstGate,
        'Corolla Cross': secondGate,
      };

      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).first, 'Corolla');
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpTicks(tester, 15);

      firstGate.complete(
        _jsonResponse(200, {
          'cars': [_car('corolla_1', 'Toyota', 'Corolla')],
          'pagination': {'has_next': false, 'total': 1},
        }),
      );
      await _pumpTicks(tester, 15);

      expect(find.textContaining('Toyota Corolla'), findsOneWidget);
      expect(find.textContaining('Corolla Cross'), findsNothing);

      // New search for a different model.
      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).first, 'Corolla Cross');
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpTicks(tester, 15);

      secondGate.complete(
        _jsonResponse(200, {
          'cars': [_car('corolla_cross_1', 'Toyota', 'Corolla Cross')],
          'pagination': {'has_next': false, 'total': 1},
        }),
      );
      await _pumpTicks(tester, 15);

      // The previous search's "Corolla" result must be gone (replaced),
      // not still present alongside the new "Corolla Cross" result. Uses
      // the exact card title (not `textContaining`) because the active
      // keyword filter chip ("Search: Corolla Cross") also legitimately
      // contains this substring.
      expect(find.text('Toyota Corolla Cross'), findsOneWidget);
      expect(find.text('Toyota Corolla'), findsNothing);
    },
  );
}
