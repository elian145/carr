import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/data/car_catalog_loader.dart';
import 'package:car_listing_app/features/home/home_flow.dart' show HomePage;
import 'package:car_listing_app/features/home/home_multi_select_filter.dart'
    show homeFilterDecodeList;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/models/online_spec_variant.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';
import 'package:car_listing_app/shared/ui/filter_card_sections.dart';

import 'cached_image_store_test_support.dart';
import 'fake_api_server.dart';

/// Spec option policy: vehicle spec option lists (engine / variant, cylinders,
/// fuel, transmission, body, drivetrain, seats) depend on BRAND + MODEL only.
/// Year is an independent field: it never narrows, widens, clears or
/// reselects any spec field.
void main() {
  late CarSpecIndex idx;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('model_level_test').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
    primeCachedImageStoreForTests();
    await FakeApiServer.ensureStarted();
    final raw = File('assets/car_spec_dataset.json').readAsStringSync();
    idx = parseCarSpecDatasetJsonString(raw).index!;
    idx.attachIqCarsOverlay(IqCarsOverlay.parse(
      File('assets/car_iqcars_overlay.json').readAsStringSync(),
    ));
    CarCatalog.applyCatalogFromAsset(
      jsonDecode(File('assets/car_catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Each widget test runs in its own FakeAsync zone: the bundle's cached asset
  // futures (and the one-time overlay load) must not leak into the next one.
  tearDown(() {
    IqCarsOverlay.debugResetForTest();
    rootBundle.evict(CarSpecIndex.assetPath);
    rootBundle.evict(IqCarsOverlay.assetPath);
    rootBundle.evict('assets/car_catalog.json');
  });

  const vehicles = <(String, String)>[
    ('BMW', 'X5'),
    ('Toyota', 'Land Cruiser'),
    ('Toyota', 'Land Cruiser Prado'),
    ('Toyota', 'Camry'),
    ('Toyota', 'Corolla'),
    ('Ford', 'Everest'),
    ('Volkswagen', 'Golf'),
    ('Volkswagen', 'Golf R'),
    ('Lexus', 'LX'),
    ('Nissan', 'Patrol'),
  ];
  const years = <int>[1995, 2009, 2012, 2018, 2020, 2024, 2026, 2030];

  Map<String, List<String>> shape(CatalogSellFieldOptions o) => {
        'engines': o.engineSizes.toList()..sort(),
        'cylinders': o.cylinderCounts.toList()..sort(),
        'fuels': o.fuelTypes.toList()..sort(),
        'transmissions': o.transmissions.toList()..sort(),
        'bodies': o.bodyTypes.toList()..sort(),
        'drivetrains': o.driveTypes.toList()..sort(),
        'seats': o.seatings.toList()..sort(),
      };

  List<String> variantKeys(List<OnlineSpecVariant> rows) => [
        for (final r in rows)
          '${OnlineSpecVariant.engineLabelOf(r)}|${r.cylinderCount}|'
              '${r.fuelType}|${r.transmission}|${r.bodyType}|${r.drivetrain}|'
              '${r.seating}|${r.fuelEconomy}',
      ];

  group('index: options depend on brand + model only', () {
    for (final v in vehicles) {
      test('${v.$1} ${v.$2}: every year / window exposes identical options',
          () {
        final base = idx.homeFilterFieldOptions(
          v.$1,
          v.$2,
          CarSpecIndex.catalogAutofillModelOnly,
        );
        expect(base, isNotNull, reason: '${v.$2} must be in the catalog');
        final want = shape(base!);
        for (final k in want.keys) {
          expect(want[k], isNotNull, reason: k);
        }

        final union = idx.sellFieldOptionsUnion(
          v.$1,
          v.$2,
          CarSpecIndex.catalogAutofillModelOnly,
        );
        expect(union, isNotNull);

        for (final y in years) {
          // Sell: the listing year never changes the option union.
          final sell = idx.sellFieldOptionsUnion(
            v.$1,
            v.$2,
            CarSpecIndex.catalogAutofillModelOnly,
            y,
          );
          expect(shape(sell!), shape(union!), reason: 'sell ${v.$2} $y');
          // Search: single-year window.
          final win = idx.homeFilterFieldOptions(
            v.$1,
            v.$2,
            CarSpecIndex.catalogAutofillModelOnly,
            rangeMinYear: y,
            rangeMaxYear: y,
          )!;
          expect(shape(win), want, reason: 'search ${v.$2} $y');
          expect(
            variantKeys(idx.catalogSellSpecVariants(
              v.$1,
              v.$2,
              CarSpecIndex.catalogAutofillModelOnly,
              y,
            )),
            variantKeys(idx.catalogSellSpecVariants(
              v.$1,
              v.$2,
              CarSpecIndex.catalogAutofillModelOnly,
            )),
            reason: 'spec variants ${v.$2} $y',
          );
        }
        // Search: multi-year range window.
        final range = idx.homeFilterFieldOptions(
          v.$1,
          v.$2,
          CarSpecIndex.catalogAutofillModelOnly,
          rangeMinYear: 2018,
          rangeMaxYear: 2024,
        )!;
        expect(shape(range), want, reason: 'search ${v.$2} 2018-2024');
        expect(
          variantKeys(idx.homeFilterSpecVariantsUnion(
            v.$1,
            v.$2,
            CarSpecIndex.catalogAutofillModelOnly,
            rangeMinYear: 2018,
            rangeMaxYear: 2024,
          )),
          variantKeys(idx.homeFilterSpecVariantsUnion(
            v.$1,
            v.$2,
            CarSpecIndex.catalogAutofillModelOnly,
          )),
          reason: 'spec variants window ${v.$2}',
        );
      });
    }

    test('BMW X5: Any Year, 2018, 2020, 2024 and 2018-2024 are identical', () {
      List<String> engines({int? lo, int? hi}) =>
          idx.homeFilterFieldOptions(
            'BMW',
            'X5',
            CarSpecIndex.catalogAutofillModelOnly,
            rangeMinYear: lo,
            rangeMaxYear: hi,
          )!.engineSizes.toList()
            ..sort();
      final any = engines();
      expect(any, containsAll(<String>['2.0', '2.0 D', '3.0', '3.0 D', '4.4']));
      expect(any, containsAll(<String>['3.0 T', '4.4 T']),
          reason: 'approved qualified overlay variants');
      expect(engines(lo: 2018, hi: 2018), any);
      expect(engines(lo: 2020, hi: 2020), any);
      expect(engines(lo: 2024, hi: 2024), any);
      expect(engines(lo: 2018, hi: 2024), any);
    });

    test('X5 2.0 is offered for every year but is a plug-in hybrid row, so '
        'it never proves Electric', () {
      final rows = idx.catalogSellSpecVariants(
        'BMW',
        'X5',
        CarSpecIndex.catalogAutofillModelOnly,
        2020,
      );
      final two = rows
          .where((r) => OnlineSpecVariant.engineLabelOf(r) == '2.0')
          .toList();
      expect(two, isNotEmpty);
      expect(two.every((r) => r.fuelType == 'electric'), isTrue);
    });

    test('Sell: the listing year only picks the default row, not the options',
        () {
      final a = idx.representativeForCatalogSell(
        'BMW',
        'X5',
        CarSpecIndex.catalogAutofillModelOnly,
        2018,
      );
      final b = idx.representativeForCatalogSell(
        'BMW',
        'X5',
        CarSpecIndex.catalogAutofillModelOnly,
        2024,
      );
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(
        shape(idx.sellFieldOptionsUnion(
          'BMW',
          'X5',
          CarSpecIndex.catalogAutofillModelOnly,
          2018,
        )!),
        shape(idx.sellFieldOptionsUnion(
          'BMW',
          'X5',
          CarSpecIndex.catalogAutofillModelOnly,
          2024,
        )!),
      );
    });

    test('year list is independent of spec rows (recent tail up to cap)', () {
      final ys = idx.yearsForCatalogStep(
        'BMW',
        'X5',
        CarSpecIndex.catalogAutofillModelOnly,
      );
      expect(ys, isNotEmpty);
      final cap = DateTime.now().year + 1;
      expect(ys.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(cap));
      expect(ys, contains(2024));
    });
  });

  group('index: a selected trim never changes the options either', () {
    for (final v in vehicles) {
      test('${v.$1} ${v.$2}: every trim exposes the unset-trim options (IQ included)', () {
        final trims = <String>{...CarCatalog.trimsFor(v.$1, v.$2), 'Not A Real Trim'};
        final base = idx.homeFilterFieldOptions(
          v.$1,
          v.$2,
          CarSpecIndex.catalogAutofillModelOnly,
        )!;
        final want = shape(base);
        final baseKeys = variantKeys(idx.homeFilterSpecVariantsUnion(
          v.$1,
          v.$2,
          CarSpecIndex.catalogAutofillModelOnly,
        ));
        var checked = 0;
        for (final t in trims) {
          if (t.trim().isEmpty) continue;
          expect(shape(idx.homeFilterFieldOptions(v.$1, v.$2, t)!), want,
              reason: 'search ${v.$2} / $t');
          expect(shape(idx.sellFieldOptionsUnion(v.$1, v.$2, t, 2020)!), want,
              reason: 'sell ${v.$2} / $t');
          expect(variantKeys(idx.homeFilterSpecVariantsUnion(v.$1, v.$2, t)),
              baseKeys,
              reason: 'spec variants ${v.$2} / $t');
          checked++;
        }
        expect(checked, greaterThan(0));
      });
    }

    test('IQ overlay additions survive a selected trim (BMW X5 3.0 T / 4.4 T)', () {
      for (final t in CarCatalog.trimsFor('BMW', 'X5').take(8)) {
        final o = idx.homeFilterFieldOptions('BMW', 'X5', t)!;
        expect(o.engineSizes, containsAll(<String>['3.0 T', '4.4 T']),
            reason: t);
      }
    });

    test('IQ additions never create an engine -> cylinder / fuel relationship', () {
      final rows = idx.homeFilterSpecVariantsUnion(
        'BMW',
        'X5',
        'xDrive40i',
      );
      // "3.0 T" / "4.4 T" are IQ-only labels: no CarNet row carries them.
      final labels = rows.map(OnlineSpecVariant.engineLabelOf).toSet();
      expect(labels, isNot(contains('3.0 T')));
      expect(labels, isNot(contains('4.4 T')));
    });
  });

  // ---------------------------------------------------------------- widget ----
  Widget harness() => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomePage.searchFilters(),
      );

  Set<String> real(dynamic list) =>
      (list as List).cast<String>().where((e) => e != 'Any').toSet();

  testWidgets(
    'Search: changing the year never changes the options or any spec field '
    '(BMW X5 4.4 T / 8 / Gasoline)',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 30000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() => CarCatalogLoader.ensureLoaded());
      await tester.pumpWidget(harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final s = tester.state(find.byType(HomePage)) as dynamic;
      final loc = AppLocalizations.of(tester.element(find.byType(HomePage)))!;

      final expected = idx.homeFilterFieldOptions(
        'BMW',
        'X5',
        CarSpecIndex.catalogAutofillModelOnly,
      )!;
      s.setState(() {
        s.selectedBrand = 'BMW';
        s.selectedModel = 'X5';
        s.selectedTrim = null;
        s.selectedMinYear = null;
        s.selectedMaxYear = null;
        s.selectedEngineSize = '4.4 T';
        s.selectedCylinderCount = '8';
        s.selectedFuelType = 'Gasoline';
        s.isEngineSizeDropdown = true;
      });
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!real(s.getAvailableEngineSizes())
          .containsAll(expected.engineSizes)) {
        if (DateTime.now().isAfter(deadline)) fail('catalog never loaded');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pump();

      Map<String, Set<String>> lists() => {
            'engines': real(s.getAvailableEngineSizes()),
            'cylinders': real(s.getAvailableCylinderCounts()),
            'fuels': real(s.getAvailableFuelTypes()),
            'transmissions': real(s.getAvailableTransmissions()),
            'bodies': real(s.getAvailableBodyTypes()),
            'drivetrains': real(s.getAvailableDriveTypes()),
            'seats': real(s.getAvailableSeatings()),
          };

      Future<void> pickYear(String label, String value) async {
        final f = find.byWidgetPredicate(
          (w) => w is FilterDropdownField && w.label == label,
        );
        expect(f, findsOneWidget, reason: '$label dropdown');
        tester.widget<FilterDropdownField>(f).onChanged!(value);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }

      final baseline = lists();
      expect(baseline['engines'], containsAll(<String>['4.4 T', '3.0 T']));

      void unchanged(String when) {
        expect(s.selectedEngineSize, '4.4 T', reason: 'engine $when');
        expect(s.selectedCylinderCount, '8', reason: 'cylinders $when');
        expect(homeFilterDecodeList(s.selectedFuelType as String?).toSet(),
            {'Gasoline'},
            reason: 'fuel $when');
        final now = lists();
        for (final k in baseline.keys) {
          expect(now[k], baseline[k], reason: '$k $when');
        }
      }

      for (final y in ['2018', '2020', '2024', '2026']) {
        await pickYear(loc.minYear, y);
        unchanged('after min year $y');
        await pickYear(loc.maxYear, y);
        unchanged('after max year $y');
      }
      // A multi-year range, then back to Any.
      await pickYear(loc.minYear, '2018');
      await pickYear(loc.maxYear, '2024');
      unchanged('for 2018-2024');

      // Trim is irrelevant to the option sets too (and to the selected specs).
      final trims = CarCatalog.trimsFor('BMW', 'X5');
      expect(trims.length, greaterThan(1));
      for (final t in trims.take(4)) {
        await pickYear(loc.trimLabel, t);
        expect(s.selectedTrim, t);
        unchanged('after trim $t');
      }
      // Trim + year together, in either order.
      await pickYear(loc.minYear, '2020');
      await pickYear(loc.maxYear, '2020');
      unchanged('for trim + 2020');
      await pickYear(loc.trimLabel, trims.last);
      unchanged('after switching trim at 2020');
      expect(baseline['engines'], containsAll(<String>['3.0 T', '4.4 T']),
          reason: 'IQ additions are never withheld by year or trim');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
    },
  );

  testWidgets(
    'Search: IQ-only 3.0 T / 4.4 T inherit trusted links from the unanimous '
    'CarNet family, 2.0 never forces Electric, and the lists never shrink',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 30000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() => CarCatalogLoader.ensureLoaded());
      await tester.pumpWidget(harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final s = tester.state(find.byType(HomePage)) as dynamic;
      final loc = AppLocalizations.of(tester.element(find.byType(HomePage)))!;

      final expected = idx.homeFilterFieldOptions(
        'BMW',
        'X5',
        CarSpecIndex.catalogAutofillModelOnly,
      )!;
      s.setState(() {
        s.selectedBrand = 'BMW';
        s.selectedModel = 'X5';
        s.selectedTrim = null;
        s.selectedMinYear = null;
        s.selectedMaxYear = null;
        s.selectedEngineSize = null;
        s.selectedCylinderCount = null;
        s.selectedFuelType = null;
        s.isEngineSizeDropdown = true;
      });
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!real(s.getAvailableEngineSizes())
          .containsAll(expected.engineSizes)) {
        if (DateTime.now().isAfter(deadline)) fail('catalog never loaded');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pump();

      Map<String, Set<String>> lists() => {
            'engines': real(s.getAvailableEngineSizes()),
            'cylinders': real(s.getAvailableCylinderCounts()),
            'fuels': real(s.getAvailableFuelTypes()),
            'transmissions': real(s.getAvailableTransmissions()),
            'bodies': real(s.getAvailableBodyTypes()),
            'drivetrains': real(s.getAvailableDriveTypes()),
            'seats': real(s.getAvailableSeatings()),
          };
      final want = lists();
      expect(
        want['engines'],
        containsAll(<String>[
          '2.0', '2.0 D', '2.9 D', '3.0', '3.0 D', '3.0 T', '3.0 TD', '4.4',
          '4.4 T', '4.6', '4.8', //
        ]),
      );
      void same(String when) {
        final now = lists();
        for (final k in want.keys) {
          expect(now[k], want[k], reason: '$k $when');
        }
      }

      Future<void> pick(String label, String value) async {
        final f = find.byWidgetPredicate(
          (w) => w is FilterDropdownField && w.label == label,
        );
        expect(f, findsOneWidget, reason: '$label dropdown');
        tester.widget<FilterDropdownField>(f).onChanged!(value);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }

      Future<void> setRaw({String? engine, String? cyl, String? fuel}) async {
        s.setState(() {
          s.selectedEngineSize = engine;
          s.selectedCylinderCount = cyl;
          s.selectedFuelType = fuel;
        });
        await tester.pump();
      }

      Future<void> toggleFuel(String label) async {
        final t = find.text(label).first;
        await tester.ensureVisible(t);
        await tester.pump();
        await tester.tap(t);
        await tester.pump();
      }

      Set<String> fuels() =>
          homeFilterDecodeList(s.selectedFuelType as String?).toSet();

      // A. 3.0 T: exact label, cylinders 6, fuel not guessed (ambiguous family).
      await pick(loc.engineSizeL, '3.0 T');
      expect(s.selectedEngineSize, '3.0 T');
      expect(s.selectedCylinderCount, '6');
      expect(fuels(), isEmpty, reason: '3.0 family is fuel-ambiguous');
      same('after 3.0 T');

      // B. 4.4 T: exact label, cylinders 8, Gasoline (unanimous 4.4 family).
      await pick(loc.engineSizeL, '4.4 T');
      expect(s.selectedEngineSize, '4.4 T');
      expect(s.selectedCylinderCount, '8');
      expect(fuels(), {'Gasoline'});
      same('after 4.4 T');

      // C. 2.0: exact label, no Electric auto-selection.
      await setRaw();
      await pick(loc.engineSizeL, '2.0');
      expect(s.selectedEngineSize, '2.0');
      expect(fuels(), isEmpty);
      expect(fuels(), isNot(contains('Electric')));
      same('after 2.0');

      // D. Year, trim, fuel and cylinder changes: selections may reconcile
      // where trusted; the Brand + Model lists never change.
      await setRaw(engine: '4.4 T', cyl: '8', fuel: 'Gasoline');
      await pick(loc.minYear, '2018');
      await pick(loc.maxYear, '2024');
      final trims = CarCatalog.trimsFor('BMW', 'X5');
      await pick(loc.trimLabel, trims.first);
      expect([s.selectedEngineSize, s.selectedCylinderCount], ['4.4 T', '8']);
      same('after year + trim');
      await toggleFuel('Diesel');
      expect(fuels(), contains('Diesel'));
      same('after fuel Diesel');
      await pick(loc.cylinderCount, '6');
      expect(s.selectedCylinderCount, '6');
      same('after cylinders 6');
      await pick(loc.minYear, '2020');
      await pick(loc.maxYear, '2020');
      same('after year 2020');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
    },
  );
}
