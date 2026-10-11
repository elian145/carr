// Saved search → Home filter restore.
//
// Root cause: SavedSearchesPage is routed without Home `parentState`, so
// apply only wrote one-time SharedPreferences. Home consumes those prefs
// solely in its first post-frame callback — which never re-runs while Home
// stays alive inside MainShell's IndexedStack. Snackbar still claimed
// success. Fix: HomeTabActions delivers filters onto live Home state.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/widgets/home_tab_actions.dart';
import 'package:car_listing_app/features/home/home_flow.dart';
import 'package:car_listing_app/features/saved_searches/saved_search_home_bridge.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

Widget _homeHarness() {
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

http.Response _json(int code, Object body) => http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json'},
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
    FakeApiServer.carsResponseOverride = null;
    FakeApiServer.carsRequestedQueries.clear();
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
  });

  tearDown(() async {
    HomeTabActions.onApplySavedSearchFilters = null;
    HomeTabActions.onConsumePendingSavedSearch = null;
    HomeTabActions.onScrollToTop = null;
    FakeApiServer.carsResponseOverride = null;
    FakeApiServer.carsRequestedQueries.clear();
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  Future<void> disposeHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // cached_network_image / home timers
    await tester.pump(const Duration(seconds: 15));
  }

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  group('bridge serialization', () {
    test('persistFiltersForHome keeps keyword + price range keys', () async {
      await SavedSearchHomeBridge.persistFiltersForHome({
        'brand': 'Toyota',
        'model': 'Camry',
        'q': 'hybrid',
        'min_price': '10000',
        'max_price': '25000',
        'min_year': '2018',
        'max_year': '2024',
        'city': 'Erbil',
        'min_mileage': '0',
        'max_mileage': '80000',
      });

      final filters = await SavedSearchHomeBridge.consumeOneTimeFilters();
      expect(filters, isNotNull);
      expect(filters!['brand'], 'Toyota');
      expect(filters['model'], 'Camry');
      expect(filters['keyword'], 'hybrid');
      expect(filters['price_min'], '10000');
      expect(filters['price_max'], '25000');
      expect(filters['year_min'], '2018');
      expect(filters['year_max'], '2024');
      expect(filters['city'], 'Erbil');
      expect(filters['min_mileage'], '0');
      expect(filters['max_mileage'], '80000');
    });
  });

  group('HomeTabActions apply path', () {
    testWidgets(
      '1-6: apply Toyota+Camry+price restores Home state and API query',
      (tester) async {
        final captured = <Map<String, String>>[];
        FakeApiServer.carsResponseOverride = (params) {
          captured.add(Map<String, String>.from(params));
          return _json(200, {
            'cars': <dynamic>[],
            'pagination': {'has_next': false, 'total': 0},
          });
        };

        await tester.pumpWidget(_homeHarness());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(HomeTabActions.onApplySavedSearchFilters, isNotNull);

        final applied = await HomeTabActions.applySavedSearchFilters({
          'brand': 'Toyota',
          'model': 'Camry',
          'min_price': '12000',
          'max_price': '30000',
        });
        expect(applied, isTrue);

        await tester.pump();
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final s = tester.state(find.byType(HomePage)) as dynamic;
        expect(s.selectedBrand, 'Toyota');
        expect(s.selectedModel, 'Camry');
        expect(s.selectedMinPrice, '12000');
        expect(s.selectedMaxPrice, '30000');

        expect(captured, isNotEmpty);
        final q = captured.last;
        expect(q['brand'], 'Toyota');
        expect(q['model'], 'Camry');
        expect(q['min_price'], '12000');
        expect(q['max_price'], '30000');
        expect(q['model_match'], 'exact');
        await disposeHome(tester);
      },
    );

    testWidgets(
      '7: applying a different saved search replaces previous filters',
      (tester) async {
        FakeApiServer.carsResponseOverride = (_) => _json(200, {
              'cars': <dynamic>[],
              'pagination': {'has_next': false, 'total': 0},
            });

        await tester.pumpWidget(_homeHarness());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await HomeTabActions.applySavedSearchFilters({
          'brand': 'Toyota',
          'model': 'Camry',
          'min_price': '10000',
        });
        await tester.pump();

        await HomeTabActions.applySavedSearchFilters({
          'brand': 'BMW',
          'model': '3-Series',
          'city': 'Erbil',
          'min_year': '2020',
        });
        await tester.pump();

        final s = tester.state(find.byType(HomePage)) as dynamic;
        expect(s.selectedBrand, 'BMW');
        expect(s.selectedModel, '3-Series');
        expect(s.selectedCity, 'Erbil');
        expect(s.selectedMinYear, '2020');
        expect(s.selectedMinPrice, isNull,
            reason: 'prior price filter must be replaced, not merged');
        expect(s.selectedMaxPrice, isNull);
        await disposeHome(tester);
      },
    );

    testWidgets(
      '8: clearing filters restores unfiltered browsing query',
      (tester) async {
        final captured = <Map<String, String>>[];
        FakeApiServer.carsResponseOverride = (params) {
          captured.add(Map<String, String>.from(params));
          return _json(200, {
            'cars': <dynamic>[],
            'pagination': {'has_next': false, 'total': 0},
          });
        };

        await tester.pumpWidget(_homeHarness());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await HomeTabActions.applySavedSearchFilters({
          'brand': 'Toyota',
          'model': 'Camry',
        });
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        // Empty saved-search map → full reset (same as clear-all path).
        await HomeTabActions.applySavedSearchFilters(<String, dynamic>{});
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final s = tester.state(find.byType(HomePage)) as dynamic;
        expect(s.selectedBrand, isNull);
        expect(s.selectedModel, isNull);

        expect(captured, isNotEmpty);
        final q = captured.last;
        expect(q.containsKey('brand'), isFalse);
        expect(q.containsKey('model'), isFalse);
        await disposeHome(tester);
      },
    );

    testWidgets(
      '9: year, mileage, location restore onto Home',
      (tester) async {
        FakeApiServer.carsResponseOverride = (_) => _json(200, {
              'cars': <dynamic>[],
              'pagination': {'has_next': false, 'total': 0},
            });

        await tester.pumpWidget(_homeHarness());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await HomeTabActions.applySavedSearchFilters({
          'brand': 'Honda',
          'min_year': '2015',
          'max_year': '2022',
          'min_mileage': '1000',
          'max_mileage': '90000',
          'city': 'Sulaymaniyah',
          'transmission': 'Automatic',
          'fuel_type': 'Gasoline',
        });
        await tester.pump();

        final s = tester.state(find.byType(HomePage)) as dynamic;
        expect(s.selectedBrand, 'Honda');
        expect(s.selectedMinYear, '2015');
        expect(s.selectedMaxYear, '2022');
        expect(s.selectedMinMileage, '1000');
        expect(s.selectedMaxMileage, '90000');
        expect(s.selectedCity, 'Sulaymaniyah');
        expect(s.selectedTransmission?.toString().toLowerCase(), 'automatic');
        expect(s.selectedFuelType?.toString().toLowerCase(), 'gasoline');
        await disposeHome(tester);
      },
    );

    testWidgets(
      'trim, color, condition, and sort_by restore when stored',
      (tester) async {
        final captured = <Map<String, String>>[];
        FakeApiServer.carsResponseOverride = (params) {
          captured.add(Map<String, String>.from(params));
          return _json(200, {
            'cars': <dynamic>[],
            'pagination': {'has_next': false, 'total': 0},
          });
        };

        await tester.pumpWidget(_homeHarness());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await HomeTabActions.applySavedSearchFilters({
          'brand': 'Toyota',
          'model': 'Camry',
          'trim': 'SE',
          'color': 'White',
          'condition': 'Used',
          'sort_by': 'price_asc',
        });
        await tester.pump();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final s = tester.state(find.byType(HomePage)) as dynamic;
        expect(s.selectedBrand, 'Toyota');
        expect(s.selectedModel, 'Camry');
        expect(s.selectedTrim, 'SE');
        expect(s.selectedColor?.toString().toLowerCase(), 'white');
        expect(s.selectedCondition?.toString().toLowerCase(), 'used');
        expect(s.selectedSortBy, isNotNull);
        expect(
          s.selectedSortBy.toString().toLowerCase(),
          anyOf(contains('price'), contains('low'), contains('asc')),
        );

        expect(captured, isNotEmpty);
        final q = captured.last;
        expect(q['brand'], 'Toyota');
        expect(q['model'], 'Camry');
        expect(q['trim'], 'SE');
        expect(q['color']?.toLowerCase(), 'white');
        expect(q['condition']?.toLowerCase(), 'used');
        expect(q['sort_by'], 'price_asc');
        await disposeHome(tester);
      },
    );

    test('success path requires a registered Home host', () async {
      // Plain `test` (not testWidgets): Future.delayed retries must run on
      // the real event loop. No Home mounted → apply must fail.
      HomeTabActions.onApplySavedSearchFilters = null;
      HomeTabActions.onConsumePendingSavedSearch = null;
      final applied = await HomeTabActions.applySavedSearchFilters(
        {'brand': 'Toyota'},
        maxAttempts: 2,
        interval: const Duration(milliseconds: 10),
      );
      expect(applied, isFalse);
    });

    testWidgets(
      'consumePending path applies prefs written by the bridge',
      (tester) async {
        final captured = <Map<String, String>>[];
        FakeApiServer.carsResponseOverride = (params) {
          captured.add(Map<String, String>.from(params));
          return _json(200, {
            'cars': <dynamic>[],
            'pagination': {'has_next': false, 'total': 0},
          });
        };

        await tester.pumpWidget(_homeHarness());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await SavedSearchHomeBridge.persistFiltersForHome({
          'brand': 'Kia',
          'model': 'Sportage',
          'min_price': '5000',
        });

        final applied =
            await HomeTabActions.onConsumePendingSavedSearch!.call();
        expect(applied, isTrue);
        await tester.pump();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final s = tester.state(find.byType(HomePage)) as dynamic;
        expect(s.selectedBrand, 'Kia');
        expect(s.selectedModel, 'Sportage');
        expect(s.selectedMinPrice, '5000');
        expect(captured, isNotEmpty);
        expect(captured.last['brand'], 'Kia');
        expect(captured.last['model'], 'Sportage');
        await disposeHome(tester);
      },
    );
  });
}
