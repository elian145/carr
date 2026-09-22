// Regression test for the "search 'Land Cruiser', still see 'Land Cruiser
// Prado'" bug -- the SECOND, distinct root cause found after the earlier
// request-generation race-condition fix (see
// `home_search_race_condition_test.dart`) turned out not to be sufficient.
//
// RUNTIME EVIDENCE (traced live against a real device + the production
// API, `https://carr-5hrm.onrender.com`):
//
//   Entered query:  Land Cruiser
//   Trigger:        tapping the "Land Cruiser" model suggestion in the
//                   keyword search field's autocomplete panel (NOT typing
//                   `q=Land Cruiser` and pressing search -- that path was
//                   already correct)
//   Request made:   GET /api/cars?model=Land+Cruiser&brand=Toyota&...
//   API models received (logcat `[search-trace] RESPONSE`):
//                   [8ae0...:Land Cruiser, eb66...:Land Cruiser Prado,
//                    55a4...:Land Cruiser Prado]
//   Models in Flutter state (logcat `[search-trace] STATE-APPLIED`):
//                   same 3 rows, unfiltered
//   Models rendered (logcat `[search-trace] RENDER`):
//                   same 3 rows -- two "Land Cruiser Prado" cards visible
//                   on screen
//
// ROOT CAUSE: selecting a model suggestion sends `model=Land Cruiser` (a
// separate query param from the free-text `q` keyword search) to
// `/api/cars`. The backend filters `model` with
// `Car.model.ilike(f"%{model}%")` (`kk/routes/cars.py`) -- a *substring*
// match, not an exact one -- so the (verified-correct, as-designed)
// response for `model=Land Cruiser` legitimately includes every model
// containing that substring, e.g. "Land Cruiser Prado" and "Land Cruiser
// 70". Every prior fix (the request-generation race guard, the
// featured-mix gating) left this response's rows completely unfiltered
// once assigned to `cars` -- so whatever the substring match returned is
// exactly what rendered. This confirms scenario A from the investigation
// checklist ("another/this API request returns Prado") combined with I
// ("a post-processing layer" was *missing* where one was needed) -- NOT
// state/cache/widget-key/multi-instance bugs B/C/F/G/H/J.
//
// FIX (this repo, client-side only -- per instructions, the backend is not
// modified): `applyExactModelListingFilter` (`home_filters_query.dart`),
// threaded into every place an API response is assigned to `cars` via the
// renamed `_applyClientPostFilters` (`home_fetch_core.dart`/
// `home_fetch.dart`), drops any row whose `model` isn't an exact
// (case-insensitive, trimmed) match for the selected model before it ever
// reaches `cars`/the UI.
//
// This test drives the real UI trigger end-to-end (open search -> type
// "Land Cruiser" -> tap the model suggestion -> submit) against a fake
// `/api/cars` that reproduces the real backend's substring-match response
// verbatim (one exact "Land Cruiser" row plus two "Land Cruiser Prado"
// rows), and proves no "Land Cruiser Prado" card is ever rendered. Without
// the fix in `_applyClientPostFilters`, this test fails exactly like the
// live repro did.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/data/car_catalog_loader.dart';
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
    // Real asset + isolate decode (see `car_catalog_loader_test.dart`), run
    // once up front so the "Land Cruiser" / "Land Cruiser Prado" model
    // suggestions used below are guaranteed available before any widget
    // pump -- avoids any dependency on fake-clock timer pumping to
    // resolve this real async load.
    await CarCatalogLoader.ensureLoaded();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FakeApiServer.carsResponseOverride = null;
    FakeApiServer.carsRequestedQueries.clear();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets(
    'selecting the "Land Cruiser" model suggestion never renders a "Land '
    'Cruiser Prado" card, even though the (real, traced) backend model '
    'filter is a substring match that legitimately returns Prado rows too',
    (tester) async {
      // Reproduces the exact production response captured in the live
      // device trace: one exact "Land Cruiser" row plus two "Land Cruiser
      // Prado" rows, for a `model=Land Cruiser` request.
      FakeApiServer.carsResponseOverride = (params) {
        if (params['model'] == 'Land Cruiser') {
          return _jsonResponse(200, {
            'cars': [
              _car('lc_1', 'Toyota', 'Land Cruiser'),
              _car('prado_1', 'Toyota', 'Land Cruiser Prado'),
              _car('prado_2', 'Toyota', 'Land Cruiser Prado'),
            ],
            'pagination': {'has_next': false, 'total': 3},
          });
        }
        return null;
      };

      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Search Cars'), findsOneWidget);

      // Type the same text the user actually typed before tapping the
      // suggestion (the autocomplete panel below the field is keyed off
      // this text; it never becomes the `q` param since the suggestion
      // tap clears it and sets `selectedModel`/`selectedBrand` instead).
      await tester.enterText(find.byType(TextField).first, 'Land Cruiser');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap the exact "Land Cruiser" model suggestion tile -- distinct
      // from "Land Cruiser Prado"/"Land Cruiser 70"/etc, which also match
      // the typed substring but are separate suggestion entries with
      // different exact label text.
      final suggestion = find.widgetWithText(ListTile, 'Land Cruiser');
      expect(
        suggestion,
        findsOneWidget,
        reason:
            'The "Land Cruiser" model suggestion tile was not found -- the '
            'car catalog asset may not have loaded in time for this test.',
      );
      await tester.tap(suggestion);
      await tester.pump();

      // Submit ("Show Cars"), exactly like the race-condition test does.
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpTicks(tester, 15);

      // Canary: prove the override above was actually exercised (i.e. the
      // request really carried `model=Land Cruiser`) -- otherwise this
      // test would vacuously pass against the generic fallback stub
      // instead of reproducing the real bug.
      expect(
        find.text('Toyota Land Cruiser'),
        findsOneWidget,
        reason:
            'The exact "Land Cruiser" listing never rendered -- the fake '
            "server's model-based override was not hit as expected, so "
            'this test is not actually exercising the traced bug path.',
      );

      // The actual regression: the substring-matched "Land Cruiser Prado"
      // rows the (correct, as-designed) API response included must never
      // reach the UI once a specific model was selected.
      expect(
        find.textContaining('Land Cruiser Prado'),
        findsNothing,
        reason:
            'A "Land Cruiser Prado" card rendered after searching for the '
            'exact model "Land Cruiser" -- this is the exact bug reported '
            '("search Land Cruiser, see Land Cruiser Prado"), caused by '
            'the backend\'s substring-match `model` filter response being '
            'applied to `cars` unfiltered.',
      );
    },
  );
}
