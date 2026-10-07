import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/data/car_catalog_loader.dart';
import 'package:car_listing_app/features/home/home_flow.dart' show HomePage;
import 'package:car_listing_app/features/home/home_multi_select_filter.dart'
    show homeFilterDecodeList;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/models/online_spec_variant.dart';
import 'package:car_listing_app/models/search_spec_reconcile.dart';
import 'package:car_listing_app/models/sell_spec_reconcile.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';
import 'package:car_listing_app/shared/ui/filter_card_sections.dart';

import 'cached_image_store_test_support.dart';
import 'fake_api_server.dart';

/// Trusted linked Search specs (Fuel Type / Engine Size / Cylinders).
///
/// Search reuses the SAME pure resolver as Sell (`SellSpecReconciler`, built on
/// `OnlineSpecVariant.trustedCylinderForEngine`) through the thin
/// `SearchSpecReconciler` adapter, which only adds Search's `Any` / multi-fuel
/// semantics. `Any` is an unselected constraint: it never forces a
/// configuration and never constrains compatibility.
void main() {
  // ---------------------------------------------------------------- pure ----
  OnlineSpecVariant row(double l, String sfx, int? c, {String? fuel}) =>
      OnlineSpecVariant(
        engineSizeLiters: l,
        displacementSuffix: sfx,
        cylinderCount: c,
        fuelType: fuel ?? (sfx.contains('D') ? 'diesel' : 'gasoline'),
      );

  final x5Rows = [
    row(3.0, '', 6, fuel: 'gasoline'),
    row(3.0, '', 6, fuel: 'electric'),
    row(3.0, ' D', 6, fuel: 'diesel'),
    row(2.0, ' D', 4, fuel: 'diesel'),
    row(4.4, '', 8, fuel: 'gasoline'),
  ];
  final x5Engines = [
    '2.0 D', '3.0', '3.0 D', '3.0 T', '3.0 TD', '4.4', '4.4 T', '4.8', //
  ];
  SearchSpecReconciler search([List<OnlineSpecVariant>? rows]) =>
      SearchSpecReconciler(
        SellSpecReconciler(
          rows: rows ?? x5Rows,
          availableEngines: x5Engines,
          fuelKeyOf: (r) => r.fuelType,
        ),
      );

  group('SearchSpecReconciler (pure adapter over the shared resolver)', () {
    test('engine keeps its exact qualified label; cylinders + fuel follow', () {
      final r = search().afterEngine(
        const SearchSpecState(engine: '3.0 T', cylinders: 8),
      );
      expect(r.engine, '3.0 T');
      expect(r.cylinders, 6);
      final g = search().afterEngine(
        const SearchSpecState(engine: '4.4 T'),
      );
      expect(g.engine, '4.4 T');
      expect(g.cylinders, 8);
      expect(g.fuels, ['gasoline']);
    });

    test('a plug-in hybrid labelled Electric never proves a single fuel', () {
      // X5 40e: 2.0 L / 4 cyl, source fuel "Electric".
      final phev = search([
        row(2.0, '', 4, fuel: 'electric'),
        row(2.0, ' D', 4, fuel: 'diesel'),
      ]);
      final r = phev.afterEngine(const SearchSpecState(engine: '2.0'));
      expect(r.engine, '2.0');
      expect(r.cylinders, 4);
      expect(r.fuels, isEmpty, reason: 'no overconfident Electric');
      // Compatible with gasoline/electric/hybrid, never with diesel.
      expect(phev.core.fuelFor('2.0'), isNull);
      expect(phev.core.fuelCompatible('2.0', 'gasoline'), isTrue);
      expect(phev.core.fuelCompatible('2.0', 'electric'), isTrue);
      expect(phev.core.fuelCompatible('2.0', 'diesel'), isFalse);
      // Contradicting explicit fuel + ambiguous engine fuels: user set kept.
      final k = phev.afterEngine(
        const SearchSpecState(engine: '2.0', fuels: ['diesel']),
      );
      expect(k.fuels, ['diesel']);
    });

    test('exact rows with several fuels -> no fuel; unanimous -> that fuel',
        () {
      final multi = search([
        row(2.0, '', 4, fuel: 'gasoline'),
        row(2.0, '', 4, fuel: 'diesel'),
      ]);
      expect(multi.core.fuelFor('2.0'), isNull);
      final one = search([
        row(2.0, '', 4, fuel: 'gasoline'),
        row(2.0, '', 4, fuel: 'gasoline'),
      ]);
      expect(one.core.fuelFor('2.0'), 'gasoline');
      // IQ-only label: family must be unanimous.
      expect(one.core.fuelFor('2.0 T'), 'gasoline');
      expect(multi.core.fuelFor('2.0 T'), isNull);
    });

    test('engine with several fuels / unknown fuel does not guess a fuel', () {
      final r = search().afterEngine(const SearchSpecState(engine: '3.0'));
      expect(r.cylinders, 6);
      expect(r.fuels, isEmpty); // gasoline + electric: ambiguous
      final t = search().afterEngine(const SearchSpecState(engine: '3.0 T'));
      expect(t.fuels, isEmpty); // IQ-only, mixed family
    });

    test('cylinders: compatible engine kept; incompatible -> trusted engine',
        () {
      expect(
        search().afterCylinders(
          const SearchSpecState(engine: '3.0 T', cylinders: 6),
        ).engine,
        '3.0 T',
      );
      final r = search().afterCylinders(
        const SearchSpecState(engine: '3.0 T', cylinders: 8),
      );
      expect(r.engine, '4.4 T');
      expect(r.cylinders, 8);
      expect(r.fuels, isEmpty, reason: 'fuel was Any: not fabricated');
      final six = search().afterCylinders(
        const SearchSpecState(engine: '4.4 T', cylinders: 6),
      );
      expect(six.cylinders, 6);
      expect(
        SellSpecReconciler(
          rows: x5Rows,
          availableEngines: x5Engines,
          fuelKeyOf: (r) => r.fuelType,
        ).cylindersFor(six.engine!),
        6,
      );
    });

    test('cylinders with Any engine never fabricates an engine', () {
      const s = SearchSpecState(cylinders: 8);
      expect(search().afterCylinders(s), s);
    });

    test('fuel: compatible engine kept; incompatible -> compatible engine', () {
      final keep = search().afterFuel(
        const SearchSpecState(engine: '3.0 D', cylinders: 6, fuels: ['diesel']),
        added: 'diesel',
      );
      expect(keep.engine, '3.0 D');
      final r = search().afterFuel(
        const SearchSpecState(engine: '4.4 T', cylinders: 8, fuels: ['diesel']),
        added: 'diesel',
      );
      expect(r.engine, anyOf('3.0 D', '2.0 D'));
      expect(r.engine!.contains('D'), isTrue);
      expect(r.fuels, ['diesel']);
    });

    test('fuel with Any engine / no fuel never fabricates a configuration', () {
      const a = SearchSpecState(fuels: ['diesel']);
      expect(search().afterFuel(a, added: 'diesel'), a);
      const b = SearchSpecState(engine: '4.4 T', cylinders: 8);
      expect(search().afterFuel(b), b);
    });

    test('fuel REMOVED (no added fuel): final set drives the reconcile', () {
      // {Gasoline, Diesel} -> {Diesel}: 4.4 T is no longer compatible.
      final r = search().afterFuel(
        const SearchSpecState(engine: '4.4 T', cylinders: 8, fuels: ['diesel']),
      );
      expect(r.engine, anyOf('3.0 D', '2.0 D'));
      expect(r.fuels, ['diesel'], reason: 'user fuel set never rewritten');
      // {Diesel, Gasoline} -> {Gasoline}: diesel-only engine moves.
      final g = search().afterFuel(
        const SearchSpecState(
          engine: '3.0 D',
          cylinders: 6,
          fuels: ['gasoline'],
        ),
      );
      expect(g.engine!.contains('D'), isFalse);
      expect(g.fuels, ['gasoline']);
      // {Diesel} -> {}: Any never moves the engine.
      const none = SearchSpecState(engine: '3.0 D', cylinders: 6);
      expect(search().afterFuel(none), none);
    });

    test('a multi-fuel selection that includes a compatible fuel keeps engine',
        () {
      const s = SearchSpecState(
        engine: '4.4 T',
        cylinders: 8,
        fuels: ['diesel', 'gasoline'],
      );
      expect(search().afterFuel(s, added: 'diesel'), s);
    });

    test('restore: engine authoritative, conflicting concrete values follow',
        () {
      final r = search().afterRestore(
        const SearchSpecState(
          engine: '4.4 T',
          cylinders: 6,
          fuels: ['diesel'],
        ),
      );
      expect(r.engine, '4.4 T');
      expect(r.cylinders, 8);
      expect(r.fuels, ['gasoline']);
      // Compatible / unknown stays; Any stays Any.
      const keep = SearchSpecState(engine: '3.0 T', cylinders: 6);
      expect(search().afterRestore(keep), keep);
    });

    test('ambiguous or missing evidence changes nothing', () {
      final noRows = search(const <OnlineSpecVariant>[]);
      const s = SearchSpecState(engine: '3.0 T', cylinders: 8, fuels: ['diesel']);
      expect(noRows.afterEngine(s).cylinders, 8);
      expect(noRows.afterCylinders(s), s);
      expect(noRows.afterRestore(s), s);
    });
  });

  // -------------------------------------------------------------- widget ----
  late CarSpecIndex idx;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('search_linked_test').path;
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
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
    'Search keeps Fuel / Engine / Cylinders trusted-compatible (BMW X5 and '
    'regression models), with Any as an unselected constraint',
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

      Future<void> useVehicle(String brand, String model, int year) async {
        final expected = idx.homeFilterFieldOptions(
          brand,
          model,
          '',
          rangeMinYear: year,
          rangeMaxYear: year,
        )!;
        s.setState(() {
          s.selectedBrand = brand;
          s.selectedModel = model;
          s.selectedTrim = null;
          s.selectedMinYear = '$year';
          s.selectedMaxYear = '$year';
          s.selectedEngineSize = null;
          s.selectedCylinderCount = null;
          s.selectedFuelType = null;
          s.isEngineSizeDropdown = true;
        });
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (!real(s.getAvailableEngineSizes())
                .containsAll(expected.engineSizes) ||
            expected.engineSizes.isEmpty) {
          if (DateTime.now().isAfter(deadline)) {
            fail('catalog never loaded for $brand $model');
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        await tester.pump();
      }

      Finder dropdown(String label) => find.byWidgetPredicate(
            (w) => w is FilterDropdownField && w.label == label,
          );

      Future<void> pick(String label, String value) async {
        final f = dropdown(label);
        expect(f, findsOneWidget, reason: '$label dropdown');
        tester.widget<FilterDropdownField>(f).onChanged!(value);
        await tester.pump();
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
      String? engine() => s.selectedEngineSize as String?;
      String? cyl() => s.selectedCylinderCount as String?;

      // Same scoped rows the page resolves (model-level, year window).
      SellSpecReconciler oracle(String b, String m, int y) {
        final rows = idx
            .homeFilterSpecVariantsUnion(
              b,
              m,
              CarSpecIndex.catalogAutofillModelOnly,
              rangeMinYear: y,
              rangeMaxYear: y,
            );
        return SellSpecReconciler(
          rows: rows,
          availableEngines: real(s.getAvailableEngineSizes()).toList(),
          fuelKeyOf: (r) => r.fuelType,
        );
      }

      // ================================ BMW X5 2020 ========================
      await useVehicle('BMW', 'X5', 2020);
      final x5 = oracle('BMW', 'X5', 2020);
      expect(real(s.getAvailableEngineSizes()),
          containsAll(<String>['3.0', '3.0 T', '4.4', '4.4 T']));

      // ---- A0. Engine = 2.0: only exact row is a PHEV labelled Electric. ----
      expect(
        idx
            .homeFilterSpecVariantsUnion(
              'BMW',
              'X5',
              CarSpecIndex.catalogAutofillModelOnly,
              rangeMinYear: 2020,
              rangeMaxYear: 2020,
            )
            .where((r) => OnlineSpecVariant.engineLabelOf(r) == '2.0')
            .every((r) => r.fuelType == 'electric'),
        isTrue,
      );
      await pick(loc.engineSizeL, '2.0');
      expect(engine(), '2.0', reason: 'exact label kept');
      expect(cyl(), '4');
      expect(fuels(), isEmpty, reason: 'no overconfident Electric');
      // An explicit user fuel is never rewritten by the engine pick.
      await setRaw(fuel: 'Diesel');
      await pick(loc.engineSizeL, '2.0');
      expect(fuels(), {'Diesel'});
      await setRaw();

      // ---- B. Engine = 3.0 T stays 3.0 T; cylinders 6. ----
      await pick(loc.engineSizeL, '3.0 T');
      expect(engine(), '3.0 T', reason: 'exact label never rewritten');
      expect(cyl(), '6');

      // ---- C. Engine = 4.4 T stays 4.4 T; cylinders 8; Gasoline. ----
      await pick(loc.engineSizeL, '4.4 T');
      expect(engine(), '4.4 T');
      expect(cyl(), '8');
      expect(fuels(), {'Gasoline'}, reason: 'trusted family fuel');

      // ---- D. 3.0 T/6 + cylinders 8 -> 8-cyl engine (4.4 T). ----
      await setRaw();
      await pick(loc.engineSizeL, '3.0 T');
      expect(cyl(), '6');
      await pick(loc.cylinderCount, '8');
      expect(engine(), '4.4 T');
      expect(cyl(), '8');

      // ---- E. cylinders 6 (from an 8-cyl engine) -> a 6-cyl engine. ----
      await pick(loc.cylinderCount, '6');
      expect(x5.cylindersFor(engine()!), 6);
      // (the model-level X5 line also has older 6-cylinder engines such as 2.9 D)
      expect(cyl(), '6');
      // Compatible engine is kept when the cylinder pick agrees with it.
      final keptEngine = engine();
      await pick(loc.cylinderCount, '6');
      expect(engine(), keptEngine);

      // ---- A. Fuel = Diesel: incompatible engine -> compatible diesel one. ----
      await setRaw(engine: '4.4 T', cyl: '8');
      await toggleFuel('Diesel');
      expect(fuels(), contains('Diesel'));
      expect(engine(), anyOf('3.0 D', '2.0 D'));
      expect(x5.fuelsOf(engine()!), contains('diesel'));
      expect(cyl(), '${x5.cylindersFor(engine()!)}');

      // Fuel = Gasoline from a diesel engine -> compatible gasoline engine.
      await setRaw(engine: '3.0 D', cyl: '6');
      await toggleFuel('Gasoline');
      expect(fuels(), contains('Gasoline'));
      expect(engine()!.contains('D'), isFalse);
      expect(x5.fuelsOf(engine()!), contains('gasoline'));
      expect(cyl(), '${x5.cylindersFor(engine()!)}');

      // A compatible engine is kept when a fuel is added.
      await setRaw(engine: '4.4 T', cyl: '8');
      await toggleFuel('Gasoline');
      expect(engine(), '4.4 T');
      expect(cyl(), '8');

      // ---- F. Any semantics. ----
      // Any engine clears the constraint; others stay; nothing is forced.
      await setRaw(engine: '4.4 T', cyl: '8', fuel: 'Gasoline');
      await pick(loc.engineSizeL, '');
      expect(engine(), isNull);
      expect(cyl(), '8');
      expect(fuels(), {'Gasoline'});
      // Any engine + concrete cylinders: engine stays Any (not fabricated).
      await pick(loc.cylinderCount, '6');
      expect(engine(), isNull, reason: 'Any engine is never forced');
      expect(cyl(), '6');
      // Any cylinders clears; nothing else moves.
      await setRaw(engine: '3.0 T', cyl: '6', fuel: 'Diesel');
      await pick(loc.cylinderCount, '');
      expect(cyl(), isNull);
      expect(engine(), '3.0 T');
      expect(fuels(), {'Diesel'});
      // Fuel switched on while engine is Any: engine stays Any.
      await setRaw();
      await toggleFuel('Diesel');
      expect(engine(), isNull);
      expect(cyl(), isNull);
      expect(fuels(), {'Diesel'});

      // ---- Multi-fuel add / remove: always reconciles from the FINAL set. ----
      await setRaw();
      await useVehicle('BMW', 'X5', 2020);
      await pick(loc.engineSizeL, '4.4 T');
      expect(fuels(), {'Gasoline'});
      expect(cyl(), '8');
      // add Diesel -> {Gasoline, Diesel}: engine may stay (one compatible fuel)
      await toggleFuel('Diesel');
      expect(fuels(), {'Gasoline', 'Diesel'}, reason: 'user set untouched');
      expect(engine(), '4.4 T');
      expect(cyl(), '8');
      // remove Gasoline -> {Diesel}: immediately a diesel engine + its cylinders
      await toggleFuel('Gasoline');
      expect(fuels(), {'Diesel'}, reason: 'removed fuel is never re-added');
      expect(engine(), anyOf('3.0 D', '2.0 D'));
      expect(x5.fuelsOf(engine()!), contains('diesel'));
      expect(cyl(), '${x5.cylindersFor(engine()!)}');
      final dieselEngine = engine();
      // add Gasoline again -> {Diesel, Gasoline}: the diesel engine may stay
      await toggleFuel('Gasoline');
      expect(fuels(), {'Diesel', 'Gasoline'});
      expect(engine(), dieselEngine);
      // remove Diesel -> {Gasoline}: diesel-only engine moves to a gasoline one
      await toggleFuel('Diesel');
      expect(fuels(), {'Gasoline'});
      expect(engine()!.contains('D'), isFalse);
      expect(x5.fuelsOf(engine()!), contains('gasoline'));
      expect(cyl(), '${x5.cylindersFor(engine()!)}');
      // one fuel -> none: the engine is NOT moved because the set emptied
      await toggleFuel('Gasoline');
      expect(fuels(), isEmpty);
      final keptEngine2 = engine();
      expect(keptEngine2, isNotNull);
      expect(cyl(), '${x5.cylindersFor(keptEngine2!)}');
      await pick(loc.engineSizeL, '3.0 D');
      expect(fuels(), {'Diesel'}, reason: 'diesel engine -> Diesel (trusted)');
      await toggleFuel('Gasoline');
      expect(fuels(), {'Diesel', 'Gasoline'});
      expect(engine(), '3.0 D', reason: 'diesel engine may stay');
      await toggleFuel('Diesel');
      expect(fuels(), {'Gasoline'});
      expect(engine()!.contains('D'), isFalse);
      expect(x5.fuelsOf(engine()!), contains('gasoline'));
      await toggleFuel('Gasoline');
      await setRaw(engine: '3.0 D', cyl: '6', fuel: 'Diesel');
      await toggleFuel('Diesel');
      expect(fuels(), isEmpty);
      expect(engine(), '3.0 D', reason: '{Diesel} -> {} keeps the engine');
      expect(cyl(), '6');

      // ---- Saved-filter restore. ----
      // Compatible -> kept (incl. an exact qualified label).
      await setRaw(engine: '3.0 T', cyl: '6', fuel: 'Diesel');
      s.setState(() => s.syncDependentFiltersToVehicle());
      expect(engine(), '3.0 T');
      expect(cyl(), '6');
      expect(fuels(), {'Diesel'});
      // Conflicting concrete cylinders / fuel follow the trusted engine.
      await setRaw(engine: '4.4 T', cyl: '6', fuel: 'Diesel');
      s.setState(() => s.syncDependentFiltersToVehicle());
      expect(engine(), '4.4 T', reason: 'exact label preserved');
      expect(cyl(), '8');
      expect(fuels(), {'Gasoline'});
      // Any dependents stay Any (nothing fabricated).
      await setRaw(engine: '4.4 T');
      s.setState(() => s.syncDependentFiltersToVehicle());
      expect(engine(), '4.4 T');
      expect(cyl(), isNull);
      expect(fuels(), isEmpty);

      // The free-typed engine text field never reconciles.
      await setRaw(cyl: '8');
      s.setState(() {
        s.isEngineSizeDropdown = false;
      });
      await tester.pump();
      s.setState(() => s.selectedEngineSize = '3.0');
      expect(cyl(), '8');

      // ====== Regression models: qualified labels never rewritten ==========
      for (final m in <List<Object>>[
        ['Toyota', 'Land Cruiser Prado', 2020],
        ['Toyota', 'Land Cruiser', 2020],
        ['Ford', 'Everest', 2020],
      ]) {
        final b = m[0] as String;
        final model = m[1] as String;
        final y = m[2] as int;
        await useVehicle(b, model, y);
        final o = oracle(b, model, y);
        final engines = real(s.getAvailableEngineSizes()).toList();
        expect(engines, isNotEmpty, reason: '$model engines');
        for (final e in engines) {
          await setRaw(cyl: '99');
          s.setState(() => s.selectedCylinderCount = null);
          await pick(loc.engineSizeL, e);
          expect(engine(), e, reason: '$model: "$e" label rewritten');
          final t = o.cylindersFor(e);
          if (t != null) {
            expect(cyl(), '$t', reason: '$model "$e" cylinders');
          } else {
            expect(cyl(), isNull, reason: '$model "$e": nothing fabricated');
          }
          final fs = o.fuelsOf(e);
          if (fs.length == 1) {
            expect(fuels().map((x) => x.toLowerCase()), {fs.first},
                reason: '$model "$e" fuel');
          }
        }
        for (final c in real(s.getAvailableCylinderCounts())) {
          for (final e in engines) {
            await setRaw(engine: e);
            await pick(loc.cylinderCount, c);
            expect(cyl(), c, reason: '$model: user cylinder preserved');
            final ec = o.cylindersFor(engine()!);
            // The engine may only stay incompatible with the pick when NO
            // engine is trusted for it (ambiguous -> no guess, never cleared
            // or fabricated).
            final trustedCandidate =
                engines.any((x) => o.cylindersFor(x) == int.parse(c));
            expect(ec == null || '$ec' == c || !trustedCandidate, isTrue,
                reason: '$model: $c cyl with "${engine()}" incompatible '
                    'although a trusted engine exists');
            if (o.cylindersFor(e) == int.parse(c)) {
              expect(engine(), e, reason: '$model: compatible engine kept');
            }
          }
        }
      }

      // Let the image cache's cleanup timer fire before the test ends.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
