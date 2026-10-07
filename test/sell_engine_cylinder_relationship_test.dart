import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/data/car_catalog_loader.dart';
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/models/online_spec_variant.dart';
import 'package:car_listing_app/models/sell_spec_reconcile.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/feature_flags.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';
import 'package:car_listing_app/shared/ui/filter_card_sections.dart';

import 'cached_image_store_test_support.dart';
import 'fake_api_server.dart';

/// Real Sell step 2 (`SellCarPage` -> `SellStep2Page`) with the real bundled
/// CarNet catalog, spec dataset and approved IQ overlay.
///
/// Trusted linked Sell specs: engine / cylinders / fuel are kept compatible by
/// ONE central resolver (`SellSpecReconciler`) that reads only the CarNet rows
/// scoped to the selected vehicle + year. The approved IQ model-level lists only
/// widen the options and never create a combination. The user's just-changed
/// field is preserved, and a selected engine label is never rewritten to
/// another label except when a cylinder / fuel pick contradicts it.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('sell_eng_cyl_test').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
    primeCachedImageStoreForTests();
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FeatureFlags.setCachedForTests(FeatureFlagsSnapshot.defaults());
  });

  tearDown(() {
    FeatureFlags.resetCacheForTests();
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalogLoader.debugResetForTest();
    IqCarsOverlay.debugResetForTest();
    rootBundle.evict(CarSpecIndex.assetPath);
    rootBundle.evict(IqCarsOverlay.assetPath);
    rootBundle.evict('assets/car_catalog.json');
  });

  /// What step 1 "Apply specs" leaves in `carData` for this vehicle + year
  /// (same keys / ordering as `_applyCatalogSellFieldUnionToCarData`), without
  /// pre-filling any engine / cylinder pick.
  Future<Map<String, dynamic>> appliedCarData(
    WidgetTester tester,
    String brand,
    String model,
    int year, {
    Map<String, dynamic> extra = const {},
  }) async {
    await tester.runAsync(() => IqCarsOverlay.ensureLoaded());
    final idx = (await tester.runAsync(() => CarSpecIndex.load()))!;
    final u = idx.sellFieldOptionsUnion(
      brand,
      model,
      CarSpecIndex.catalogAutofillModelOnly,
      year,
    )!;
    final vs = idx.catalogSellSpecVariants(
      brand,
      model,
      CarSpecIndex.catalogAutofillModelOnly,
      year,
    );
    double lit(String s) => double.tryParse(
          RegExp(r'^\d+(\.\d+)?').firstMatch(s)?.group(0) ?? '',
        ) ??
        0;
    final engines = u.engineSizes.toList()
      ..sort((a, b) {
        final c = lit(a).compareTo(lit(b));
        return c != 0 ? c : a.compareTo(b);
      });
    final cyl = u.cylinderCounts.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return <String, dynamic>{
      'brand': brand,
      'model': model,
      'trim': '',
      'year': '$year',
      '_catalog_specs_applied': 1,
      '_online_opts_transmission': u.transmissions.toList()..sort(),
      '_online_opts_drive': u.driveTypes.toList()..sort(),
      '_online_opts_body': u.bodyTypes.toList()..sort(),
      '_online_opts_fuel': u.fuelTypes.toList()..sort(),
      '_online_opts_engine_size': engines,
      '_online_opts_cylinder': cyl,
      '_online_opts_seating': u.seatings.toList()..sort(),
      '_online_spec_variants': vs.map((e) => e.toJson()).toList(),
      ...extra,
    };
  }

  Widget app(Map<String, dynamic> carData) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SellCarPage(
          initialDraftSnapshot: <String, dynamic>{
            'draftId': 'sell-eng-cyl-test',
            'currentStep': 1,
            'updatedAt': 1700000000000,
            'carData': carData,
          },
        ),
      );

  Future<dynamic> openStep2(
    WidgetTester tester,
    Map<String, dynamic> carData,
  ) async {
    tester.view.physicalSize = const Size(1000, 7000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(carData));
    await tester.pump();
    final s = tester.state(find.byType(SellStep2Page)) as dynamic;
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    // Wait for the spec index to arrive (the narrowed IQ lists are in place).
    while (!(s.getAvailableEngineSizes() as List).any((e) => '$e'.contains(' '))) {
      if (DateTime.now().isAfter(deadline)) fail('step 2 never narrowed');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pump();
    return s;
  }

  FilterDropdownField dropdown(WidgetTester tester, {required bool cylinders}) {
    final all = tester
        .widgetList<FilterDropdownField>(find.byType(FilterDropdownField))
        .toList();
    for (final d in all) {
      final v = d.items.map((e) => e.value ?? '').toList();
      if (v.isEmpty) continue;
      final isCyl = v.every((e) => int.tryParse(e) != null);
      final isEng = v.every((e) => RegExp(r'^\d+\.\d').hasMatch(e));
      if (cylinders ? isCyl : isEng) return d;
    }
    fail('dropdown (cylinders=$cylinders) not found among ${all.length}');
  }

  Future<void> pickCylinders(WidgetTester tester, String v) async {
    dropdown(tester, cylinders: true).onChanged!(v);
    await tester.pump();
  }

  Future<void> pickEngine(WidgetTester tester, String v) async {
    dropdown(tester, cylinders: false).onChanged!(v);
    await tester.pump();
  }


  String? eng(dynamic s) => s.selectedEngineSize as String?;
  String? cyl(dynamic s) => s.selectedCylinderCount as String?;
  List<String> engines(dynamic s) => (s.getAvailableEngineSizes() as List)
      .cast<String>()
      .where((e) => e != 'Any')
      .toList();
  List<String> cylinders(dynamic s) =>
      (s.getAvailableCylinderCounts() as List).cast<String>();

  List<OnlineSpecVariant> rowsOf(Map<String, dynamic> carData) =>
      (carData['_online_spec_variants'] as List)
          .map((e) => OnlineSpecVariant.fromJson(Map<String, dynamic>.from(e)))
          .toList();

  Map<String, dynamic> withRows(
    Map<String, dynamic> carData,
    List<OnlineSpecVariant> rows,
  ) =>
      {...carData, '_online_spec_variants': rows.map((e) => e.toJson()).toList()};

  OnlineSpecVariant row(double l, String sfx, int? c, {String? fuel}) =>
      OnlineSpecVariant(
        engineSizeLiters: l,
        displacementSuffix: sfx,
        cylinderCount: c,
        fuelType: fuel ?? (sfx.contains('D') ? 'diesel' : 'gasoline'),
      );

  group('trustedCylinderForEngine (pure resolver)', () {
    test('A exact rows agree -> that count; exact rows conflict -> null', () {
      expect(
        OnlineSpecVariant.trustedCylinderForEngine(
          [row(4.4, '', 8), row(4.4, '', 8), row(3.0, '', 6)],
          '4.4',
        ),
        8,
      );
      expect(
        OnlineSpecVariant.trustedCylinderForEngine(
          [row(3.0, '', 4), row(3.0, '', 6)],
          '3.0',
        ),
        isNull,
      );
    });
    test('B IQ-only engine inherits only from a unanimous displacement family',
        () {
      expect(
        OnlineSpecVariant.trustedCylinderForEngine(
          [row(3.0, '', 6), row(3.0, ' D', 6), row(4.4, '', 8)],
          '3.0 T',
        ),
        6,
      );
      // 3.0 D = 4 and 3.0 = 6 disagree: no inference
      expect(
        OnlineSpecVariant.trustedCylinderForEngine(
          [row(3.0, '', 6), row(3.0, ' D', 4)],
          '3.0 T',
        ),
        isNull,
      );
    });
    test('no rows of that displacement / no count / blank label -> null', () {
      expect(
        OnlineSpecVariant.trustedCylinderForEngine([row(3.0, '', 6)], '4.8'),
        isNull,
      );
      expect(
        OnlineSpecVariant.trustedCylinderForEngine([row(3.0, '', null)], '3.0 T'),
        isNull,
      );
      expect(
        OnlineSpecVariant.trustedCylinderForEngine([row(3.0, '', 6)], ''),
        isNull,
      );
      expect(
        OnlineSpecVariant.trustedCylinderForEngine([row(3.0, '', 6)], null),
        isNull,
      );
    });
    test('a unique exact row wins over a conflicting displacement family', () {
      expect(
        OnlineSpecVariant.trustedCylinderForEngine(
          [row(3.0, ' D', 6), row(3.0, '', 4)],
          '3.0 D',
        ),
        6,
      );
    });
  });

  SellSpecReconciler reconciler(
    List<OnlineSpecVariant> rows,
    List<String> engines,
  ) =>
      SellSpecReconciler(
        rows: rows,
        availableEngines: engines,
        fuelKeyOf: (r) => r.fuelType,
      );

  group('SellSpecReconciler (pure, central compatibility resolver)', () {
    final x5 = [
      row(3.0, '', 6, fuel: 'gasoline'),
      row(3.0, '', 6, fuel: 'electric'),
      row(3.0, ' D', 6, fuel: 'diesel'),
      row(4.4, '', 8, fuel: 'gasoline'),
    ];
    final engines = [
      '3.0', '3.0 D', '3.0 T', '3.0 TD', '4.4', '4.4 T', '4.8', //
    ];
    SellSpecSelection run(
      SellSpecSelection s,
      SellSpecField f, {
      List<OnlineSpecVariant>? rows,
    }) =>
        reconciler(rows ?? x5, engines).reconcile(s, f);

    test('engine: exact label kept; exact row -> cylinders + fuel', () {
      final r = run(
        const SellSpecSelection(engine: '4.4', cylinders: 6, fuel: 'diesel'),
        SellSpecField.engine,
      );
      expect([r.engine, r.cylinders, r.fuel], ['4.4', 8, 'gasoline']);
    });

    test('engine: IQ-only 3.0 T -> cylinders from unanimous family, fuel NOT '
        'inferred from a different-fuel 3.0 row', () {
      final r = run(
        const SellSpecSelection(engine: '3.0 T', cylinders: 8, fuel: 'diesel'),
        SellSpecField.engine,
      );
      expect([r.engine, r.cylinders, r.fuel], ['3.0 T', 6, 'diesel']);
    });

    test('engine: IQ-only 4.4 T -> 8 cylinders and gasoline (unanimous '
        'family, qualifier agrees)', () {
      final r = run(
        const SellSpecSelection(engine: '4.4 T'),
        SellSpecField.engine,
      );
      expect([r.engine, r.cylinders, r.fuel], ['4.4 T', 8, 'gasoline']);
    });

    test('cylinders: compatible current engine is kept', () {
      final r = run(
        const SellSpecSelection(engine: '4.4 T', cylinders: 8),
        SellSpecField.cylinders,
      );
      expect(r.engine, '4.4 T');
      final r2 = run(
        const SellSpecSelection(engine: '3.0 D', cylinders: 6, fuel: 'diesel'),
        SellSpecField.cylinders,
      );
      expect([r2.engine, r2.cylinders, r2.fuel], ['3.0 D', 6, 'diesel']);
    });

    test('cylinders 8: incompatible engine moves to the richest 8-cylinder '
        'label (4.4 T, not plain 4.4); cylinders and gasoline set', () {
      final r = run(
        const SellSpecSelection(engine: '3.0 T', cylinders: 8),
        SellSpecField.cylinders,
      );
      expect([r.engine, r.cylinders, r.fuel], ['4.4 T', 8, 'gasoline']);
    });

    test('cylinders 6 with diesel keeps a diesel engine (3.0 D, never 3.0 TD '
        'over the exact diesel row, never gasoline 3.0)', () {
      final r = run(
        const SellSpecSelection(engine: '4.4 T', cylinders: 6, fuel: 'diesel'),
        SellSpecField.cylinders,
      );
      expect([r.engine, r.cylinders, r.fuel], ['3.0 D', 6, 'diesel']);
    });

    test('deterministic: identical result across repeated runs', () {
      final seen = <String>{};
      for (var i = 0; i < 25; i++) {
        final r = run(
          const SellSpecSelection(engine: '3.0 T', cylinders: 8),
          SellSpecField.cylinders,
        );
        seen.add('$r');
      }
      expect(seen.length, 1);
    });

    test('fuel diesel: incompatible gasoline engine is replaced by a diesel '
        'engine and cylinders follow it', () {
      final r = run(
        const SellSpecSelection(engine: '4.4', cylinders: 8, fuel: 'diesel'),
        SellSpecField.fuel,
      );
      expect([r.engine, r.cylinders, r.fuel], ['3.0 D', 6, 'diesel']);
    });

    test('fuel diesel keeps an already compatible diesel engine; an engine '
        'with unknown fuel (3.0 T) is not replaced', () {
      final r = run(
        const SellSpecSelection(engine: '3.0 D', cylinders: 6, fuel: 'diesel'),
        SellSpecField.fuel,
      );
      expect([r.engine, r.cylinders], ['3.0 D', 6]);
      final r2 = run(
        const SellSpecSelection(engine: '3.0 T', cylinders: 6, fuel: 'diesel'),
        SellSpecField.fuel,
      );
      expect([r2.engine, r2.cylinders], ['3.0 T', 6]);
    });

    test('fuel gasoline: a D-qualified IQ engine cannot stay on gasoline', () {
      final r = run(
        const SellSpecSelection(engine: '3.0 TD', cylinders: 6, fuel: 'gasoline'),
        SellSpecField.fuel,
      );
      expect(r.engine, isNot('3.0 TD'));
      expect(r.cylinders, 6, reason: 'the compatible 6-cylinder config wins');
    });

    test('ambiguous evidence never guesses', () {
      // same displacement with BOTH 4 and 6 cylinders
      final amb = [
        row(3.0, '', 4, fuel: 'gasoline'),
        row(3.0, ' D', 6, fuel: 'diesel'),
      ];
      final r = run(
        const SellSpecSelection(engine: '3.0 T', cylinders: 8, fuel: 'diesel'),
        SellSpecField.engine,
        rows: amb,
      );
      expect([r.engine, r.cylinders, r.fuel], ['3.0 T', 8, 'diesel']);
      // an engine with no trusted cylinder is never picked for a cylinder count
      final r2 = run(
        const SellSpecSelection(engine: '3.0 T', cylinders: 8),
        SellSpecField.cylinders,
        rows: amb,
      );
      expect(r2.engine, '3.0 T');
    });

    test('IQ model-level lists alone never create a relationship', () {
      // available engines (IQ) but NO CarNet rows: nothing is derivable
      final r = reconciler(const [], engines).reconcile(
        const SellSpecSelection(cylinders: 8),
        SellSpecField.cylinders,
      );
      expect(r, const SellSpecSelection(cylinders: 8));
      final r2 = reconciler(const [], engines).reconcile(
        const SellSpecSelection(engine: '3.0 T', cylinders: 8, fuel: 'diesel'),
        SellSpecField.engine,
      );
      expect([r2.engine, r2.cylinders, r2.fuel], ['3.0 T', 8, 'diesel']);
    });
  });

  String? fuelOf(dynamic s) => s.selectedFuelType as String?;

  Future<void> pickFuel(WidgetTester tester, String label) async {
    final all = tester
        .widgetList<FilterIconCardSection>(find.byType(FilterIconCardSection))
        .where((w) => w.options.contains(label))
        .toList();
    if (all.isEmpty) fail('fuel section offering $label not found');
    all.first.onSelected(label);
    await tester.pump();
  }

  int? trustedCyl(Map<String, dynamic> d, String? e) =>
      e == null ? null : OnlineSpecVariant.trustedCylinderForEngine(rowsOf(d), e);

  testWidgets('BMW X5 2020: IQ engine 3.0 T is offered next to CarNet engines, '
      'cylinders 4/6/8', (tester) async {
    final s = await openStep2(
      tester,
      await appliedCarData(tester, 'BMW', 'X5', 2020),
    );
    expect(engines(s), containsAll(['3.0', '3.0 D', '3.0 T', '4.4']));
    expect(cylinders(s), containsAll(['4', '6', '8']));
    await _unmount(tester);
  });

  testWidgets('A: engine 3.0 T stays 3.0 T -> cylinders 6; fuel not invented '
      'from a different-fuel 3.0 row', (tester) async {
    final data = await appliedCarData(tester, 'BMW', 'X5', 2020);
    expect(
      rowsOf(data).any((r) => OnlineSpecVariant.engineLabelOf(r) == '3.0 T'),
      isFalse,
      reason: '3.0 T is IQ-only',
    );
    final s = await openStep2(tester, data);
    final fuelBefore = fuelOf(s);
    await pickEngine(tester, '3.0 T');
    expect([eng(s), cyl(s), fuelOf(s)], ['3.0 T', '6', fuelBefore]);
    await _unmount(tester);
  });

  testWidgets('X5 2.0: the only exact 2.0 row is a plug-in hybrid labelled '
      'Electric -> engine stays 2.0, fuel is NOT auto-selected as Electric',
      (tester) async {
    // Spec options are model-level (brand + model), so the X5 2.0 plug-in hybrid
    // (40e) is part of the X5 model whatever the listing year is.
    final data = await appliedCarData(tester, 'BMW', 'X5', 2020);
    final exact = rowsOf(data)
        .where((r) => OnlineSpecVariant.engineLabelOf(r) == '2.0')
        .toList();
    expect(exact, isNotEmpty);
    expect(exact.every((r) => r.fuelType == 'electric'), isTrue,
        reason: 'source fuel value is "Electric" with a 1997 cc engine');
    final s = await openStep2(tester, data);
    for (final start in <String?>[null, 'Diesel', 'Gasoline']) {
      s.setState(() => s.selectedFuelType = start);
      await tester.pump();
      await pickEngine(tester, '2.0');
      expect(eng(s), '2.0');
      expect(cyl(s), '4');
      expect(fuelOf(s), start, reason: 'fuel left as it was (start=$start)');
    }
    await _unmount(tester);
  });

  testWidgets('B: engine 4.4 T stays 4.4 T -> cylinders 8 and gasoline',
      (tester) async {
    final s = await openStep2(
      tester,
      await appliedCarData(tester, 'BMW', 'X5', 2020),
    );
    await pickEngine(tester, '4.4 T');
    expect([eng(s), cyl(s), fuelOf(s)], ['4.4 T', '8', 'Gasoline']);
    await pickEngine(tester, '4.4');
    expect([eng(s), cyl(s), fuelOf(s)], ['4.4', '8', 'Gasoline']);
    await _unmount(tester);
  });

  testWidgets('C+D: start 3.0 T / 6, cylinders 8 -> 4.4 T / 8; cylinders 6 -> '
      'a compatible 6-cylinder engine; engine picks follow', (tester) async {
    final data = await appliedCarData(
      tester,
      'BMW',
      'X5',
      2020,
      extra: {'engine_size': '3.0 T', 'cylinder_count': '6'},
    );
    final s = await openStep2(tester, data);
    expect([eng(s), cyl(s)], ['3.0 T', '6']);
    await pickCylinders(tester, '8');
    expect([eng(s), cyl(s), fuelOf(s)], ['4.4 T', '8', 'Gasoline']);
    await pickCylinders(tester, '6');
    expect(cyl(s), '6');
    expect(trustedCyl(data, eng(s)), 6, reason: 'engine ${eng(s)} must be a 6');
    expect(eng(s), isNot(contains('D')), reason: 'fuel is Gasoline');
    await pickEngine(tester, '4.4 T');
    expect([eng(s), cyl(s)], ['4.4 T', '8']);
    await pickEngine(tester, '3.0 T');
    expect([eng(s), cyl(s)], ['3.0 T', '6']);
    await _unmount(tester);
  });

  testWidgets('E: a cylinder pick the current engine already satisfies does '
      'not change the engine', (tester) async {
    final s = await openStep2(
      tester,
      await appliedCarData(tester, 'BMW', 'X5', 2020),
    );
    for (final e in const ['3.0 T', '3.0 D', '4.4 T', '4.4']) {
      await pickEngine(tester, e);
      final c = cyl(s);
      await pickCylinders(tester, c!);
      expect([eng(s), cyl(s)], [e, c], reason: 'engine $e');
    }
    await _unmount(tester);
  });

  testWidgets('F: the same cylinder pick settles on the same engine every '
      'run', (tester) async {
    final picked = <String?>[];
    for (var i = 0; i < 3; i++) {
      final s = await openStep2(
        tester,
        await appliedCarData(
          tester,
          'BMW',
          'X5',
          2020,
          extra: {'engine_size': '3.0 T', 'cylinder_count': '6'},
        ),
      );
      await pickCylinders(tester, '8');
      picked.add(eng(s));
      await _unmount(tester);
    }
    expect(picked.toSet().length, 1);
    expect(picked.first, '4.4 T');
  });

  testWidgets('G: ambiguous evidence (same displacement 4 AND 6) -> no '
      'relationship is invented', (tester) async {
    final data = withRows(
      await appliedCarData(tester, 'BMW', 'X5', 2020),
      [row(3.0, '', 4), row(3.0, ' D', 6), row(4.4, '', 8)],
    );
    final s = await openStep2(tester, data);
    await pickCylinders(tester, '8');
    await pickEngine(tester, '3.0 T');
    expect([eng(s), cyl(s)], ['3.0 T', '8'], reason: 'no trusted count');
    await pickCylinders(tester, '6');
    expect([eng(s), cyl(s)], ['3.0 T', '6'], reason: 'unknown -> kept');
    await _unmount(tester);

    // exact rows of one label that disagree: cylinders are not forced
    final data2 = withRows(
      await appliedCarData(tester, 'BMW', 'X5', 2020),
      [row(3.0, '', 4), row(3.0, '', 6)],
    );
    final s2 = await openStep2(tester, data2);
    await pickCylinders(tester, '8');
    await pickEngine(tester, '3.0');
    expect([eng(s2), cyl(s2)], ['3.0', '8']);
    await _unmount(tester);
  });

  testWidgets('G2: IQ-only data with NO CarNet rows never fabricates a '
      'relationship', (tester) async {
    final data = withRows(
      await appliedCarData(tester, 'BMW', 'X5', 2020),
      const [],
    );
    // (an empty row list is treated as "no rows" by the form)
    final s = await openStep2(tester, {...data}..remove('_online_spec_variants'));
    await pickEngine(tester, '3.0 T');
    expect([eng(s), cyl(s)], ['3.0 T', null]);
    await pickCylinders(tester, '8');
    expect([eng(s), cyl(s)], ['3.0 T', '8']);
    await _unmount(tester);
  });

  testWidgets('F1 Fuel Diesel: gasoline engine replaced by a compatible '
      'diesel engine, cylinders follow', (tester) async {
    final data = await appliedCarData(
      tester,
      'BMW',
      'X5',
      2020,
      extra: {
        'engine_size': '4.4',
        'cylinder_count': '8',
        'fuel_type': 'Gasoline',
      },
    );
    final s = await openStep2(tester, data);
    expect([eng(s), cyl(s), fuelOf(s)], ['4.4', '8', 'Gasoline']);
    await pickFuel(tester, 'Diesel');
    expect(fuelOf(s), 'Diesel');
    expect(eng(s), anyOf('3.0 D', '2.0 D'));
    expect(trustedCyl(data, eng(s)), int.parse(cyl(s)!));
    await _unmount(tester);
  });

  testWidgets('F2 Fuel Gasoline: diesel engine replaced by a compatible '
      'gasoline engine, cylinders follow', (tester) async {
    final data = await appliedCarData(
      tester,
      'BMW',
      'X5',
      2020,
      extra: {
        'engine_size': '3.0 D',
        'cylinder_count': '6',
        'fuel_type': 'Diesel',
      },
    );
    final s = await openStep2(tester, data);
    expect([eng(s), cyl(s), fuelOf(s)], ['3.0 D', '6', 'Diesel']);
    await pickFuel(tester, 'Gasoline');
    expect(fuelOf(s), 'Gasoline');
    expect(eng(s), isNot('3.0 D'));
    expect(eng(s), isNot(contains('D')));
    expect(trustedCyl(data, eng(s)), int.parse(cyl(s)!));
    await _unmount(tester);
  });

  testWidgets('user-selection priority: the field the user just changed is '
      'preserved; an engine with unknown fuel is not moved by a fuel pick',
      (tester) async {
    final s = await openStep2(
      tester,
      await appliedCarData(tester, 'BMW', 'X5', 2020),
    );
    await pickEngine(tester, '3.0 T');
    await pickFuel(tester, 'Diesel');
    expect([eng(s), cyl(s), fuelOf(s)], ['3.0 T', '6', 'Diesel']);
    await pickCylinders(tester, '8');
    expect(cyl(s), '8', reason: 'the picked cylinders are preserved');
    expect(fuelOf(s), isNotNull);
    await _unmount(tester);
  });

  testWidgets('cylinders -> compatible engine and fuel (8 and 6)',
      (tester) async {
    final data = await appliedCarData(tester, 'BMW', 'X5', 2020);
    final s = await openStep2(tester, data);
    await pickCylinders(tester, '8');
    expect([eng(s), cyl(s), fuelOf(s)], ['4.4 T', '8', 'Gasoline']);
    await pickCylinders(tester, '6');
    expect(trustedCyl(data, eng(s)), 6);
    await _unmount(tester);
  });

  testWidgets('draft restore: exact engine kept, trusted cylinders / fuel '
      'recomputed (engine authoritative); a stored qualified engine is never '
      'swapped for a plain one', (tester) async {
    final base = await appliedCarData(tester, 'BMW', 'X5', 2020);
    final s = await openStep2(tester, {
      ...base,
      'engine_size': '3.0 T',
      'cylinder_count': '8',
    });
    expect([eng(s), cyl(s)], ['3.0 T', '6']);
    await _unmount(tester);

    final s2 = await openStep2(tester, {
      ...base,
      'engine_size': '4.4 T',
      'cylinder_count': '6',
      'fuel_type': 'Diesel',
    });
    expect([eng(s2), cyl(s2), fuelOf(s2)], ['4.4 T', '8', 'Gasoline']);
    await _unmount(tester);

    // compatible pair is kept as stored
    final s3 = await openStep2(tester, {
      ...base,
      'engine_size': '3.0 D',
      'cylinder_count': '6',
      'fuel_type': 'Diesel',
    });
    expect([eng(s3), cyl(s3), fuelOf(s3)], ['3.0 D', '6', 'Diesel']);
    await _unmount(tester);

    // cylinders only: the engine is not invented on restore
    final s4 = await openStep2(tester, {...base, 'cylinder_count': '8'});
    expect([eng(s4), cyl(s4)], [null, '8']);
    await _unmount(tester);
  });

  testWidgets('draft restore: conflicting evidence leaves the stored '
      'cylinder alone', (tester) async {
    final base = withRows(
      await appliedCarData(tester, 'BMW', 'X5', 2020),
      [row(3.0, '', 4), row(3.0, ' D', 6)],
    );
    final s = await openStep2(tester, {
      ...base,
      'engine_size': '3.0 T',
      'cylinder_count': '8',
    });
    expect([eng(s), cyl(s)], ['3.0 T', '8']);
    await _unmount(tester);
  });

  testWidgets('an engine the MODEL does not offer clears ONLY the engine; the '
      'valid cylinder stays', (tester) async {
    // The BMW X5 line has no 5.7 L engine (whatever the year is).
    final data = await appliedCarData(
      tester,
      'BMW',
      'X5',
      2009,
      extra: {'engine_size': '5.7', 'cylinder_count': '8'},
    );
    final s = await openStep2(tester, data);
    expect(engines(s), isNot(contains('5.7')));
    expect(eng(s), isNull);
    expect(cyl(s), '8');
    await _unmount(tester);
  });

  testWidgets('a cylinder count the MODEL does not offer clears ONLY the '
      'cylinder', (tester) async {
    // The BMW X5 line has no 12-cylinder (whatever the year is).
    final data = await appliedCarData(
      tester,
      'BMW',
      'X5',
      2012,
      extra: {'cylinder_count': '12'},
    );
    final s = await openStep2(tester, data);
    expect(cylinders(s), isNot(contains('12')));
    expect(cyl(s), isNull);
    await _unmount(tester);
  });

  testWidgets('listing year never changes the engine / cylinder options or a '
      'concrete linked selection (BMW X5 4.4 T / 8)', (tester) async {
    List<String>? engines0;
    List<String>? cyls0;
    for (final y in const [2018, 2020, 2024, 2026]) {
      final data = await appliedCarData(
        tester,
        'BMW',
        'X5',
        y,
        extra: {'engine_size': '4.4 T', 'cylinder_count': '8'},
      );
      final s = await openStep2(tester, data);
      expect(engines(s), containsAll(['2.0', '3.0 T', '4.4', '4.4 T']),
          reason: 'X5 $y');
      engines0 ??= engines(s);
      cyls0 ??= cylinders(s);
      expect(engines(s), engines0, reason: 'engines X5 $y');
      expect(cylinders(s), cyls0, reason: 'cylinders X5 $y');
      expect([eng(s), cyl(s)], ['4.4 T', '8'], reason: 'selection X5 $y');
      await _unmount(tester);
    }
  });

  // ---- Apply Specs prefills SELECTED values only; it never shrinks the lists.
  testWidgets('Apply specs: option lists are the Brand + Model union before and '
      'after Apply, whatever the year / trim (BMW X5)', (tester) async {
    tester.view.physicalSize = const Size(1000, 7000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => IqCarsOverlay.ensureLoaded());
    final idx = (await tester.runAsync(() => CarSpecIndex.load()))!;
    final union = idx.sellFieldOptionsUnion(
      'BMW',
      'X5',
      CarSpecIndex.catalogAutofillModelOnly,
    )!;

    Widget appAt(int step, Map<String, dynamic> carData) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SellCarPage(
            initialDraftSnapshot: <String, dynamic>{
              'draftId': 'sell-apply-test',
              'currentStep': step,
              'updatedAt': 1700000000000,
              'carData': carData,
            },
          ),
        );

    Map<String, Set<String>> lists(dynamic s) => {
          'engines': engines(s).toSet(),
          'cylinders': cylinders(s).where((e) => e != 'Any').toSet(),
          'fuels': (s.getAvailableFuelTypes() as List)
              .cast<String>()
              .where((e) => e != 'Any')
              .toSet(),
          'transmissions': (s.getAvailableTransmissions() as List)
              .cast<String>()
              .where((e) => e != 'Any')
              .toSet(),
          'bodies': (s.getAvailableBodyTypes() as List)
              .cast<String>()
              .where((e) => e != 'Any')
              .toSet(),
          'drivetrains': (s.getAvailableDriveTypes() as List)
              .cast<String>()
              .where((e) => e != 'Any')
              .toSet(),
          'seats': (s.getAvailableSeatings() as List)
              .cast<String>()
              .where((e) => e != 'Any')
              .toSet(),
        };

    Future<dynamic> openStep2At(Map<String, dynamic> carData) async {
      await tester.pumpWidget(appAt(1, carData));
      await tester.pump();
      final s = tester.state(find.byType(SellStep2Page)) as dynamic;
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!engines(s).contains('4.4 T')) {
        if (DateTime.now().isAfter(deadline)) fail('step 2 never loaded X5');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pump();
      return s;
    }

    Future<Map<String, dynamic>> applyAt(int year, String trim) async {
      await tester.pumpWidget(appAt(0, <String, dynamic>{
        'brand': 'BMW',
        'model': 'X5',
        'trim': trim,
        'year': '$year',
        '_catalog_year': '$year',
      }));
      await tester.pump();
      final apply = find.text('Apply specs');
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (apply.evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) fail('Apply specs never shown');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.ensureVisible(apply);
      await tester.pump();
      await tester.tap(apply);
      await tester.pump();
      final page = tester.state(find.byType(SellCarPage)) as dynamic;
      // Keep what Apply wrote (spec values + option lists), not the wizard shell.
      final data = <String, dynamic>{
        for (final e in (page.carData as Map).entries)
          if (!{
            'sell_wizard_v2',
            'original_images',
            'blurred_images',
            'original_damage_images',
            'images',
            'damage_images',
            'videos',
            'images_processed',
            'primary_image_index',
          }.contains(e.key))
            e.key as String: e.value,
      };
      expect(data['_catalog_specs_applied'], isNotNull, reason: 'applied');
      return data;
    }

    // Complete model-level lists straight from the index.
    final want = <String, Set<String>>{
      'engines': union.engineSizes,
      'cylinders': union.cylinderCounts,
      'fuels': union.fuelTypes,
      'transmissions': union.transmissions,
      'bodies': union.bodyTypes,
      'drivetrains': union.driveTypes,
      'seats': union.seatings,
    };
    expect(
      union.engineSizes,
      containsAll(<String>[
        '2.0', '2.0 D', '2.9 D', '3.0', '3.0 D', '3.0 T', '3.0 TD', '4.4',
        '4.4 T', '4.6', '4.8', //
      ]),
    );

    // BEFORE Apply (year + trim chosen but nothing applied yet).
    final before = lists(await openStep2At(<String, dynamic>{
      'brand': 'BMW',
      'model': 'X5',
      'trim': '',
      'year': '2020',
    }));
    expect(before, want, reason: 'before Apply = Brand + Model union');
    await _unmount(tester);

    // Apply for several years / trims; every result is the same union.
    for (final (year, trim) in const [
      (2020, 'xDrive30d'),
      (2018, 'xDrive40i'),
      (2024, 'M50i'),
      (2012, 'sDrive35i'),
    ]) {
      final applied = await applyAt(year, trim);
      // Apply may prefill selected values...
      expect(applied['cylinder_count'], isNotNull, reason: 'prefilled $year/$trim');
      // ...but the stored option lists are the full union.
      expect((applied['_online_opts_engine_size'] as List).toSet(),
          union.engineSizes,
          reason: 'carData engines $year/$trim');
      await _unmount(tester);
      final s = await openStep2At(applied);
      expect(lists(s), want, reason: 'after Apply $year/$trim');
      // The user can still open Engine and choose any other X5 engine.
      for (final e in union.engineSizes) {
        await pickEngine(tester, e);
        expect(eng(s), e, reason: 'can choose $e after Apply $year/$trim');
        expect(lists(s), want, reason: 'lists after choosing $e');
      }
      await _unmount(tester);
    }
  });
  // ---- Linked reconciliation changes SELECTED values only; the Brand + Model
  // option lists never shrink. IQ-only labels (3.0 T / 4.4 T) inherit trusted
  // relationships from the unanimous same-displacement CarNet family only.
  testWidgets('X5 linked selections never shrink the option lists (3.0 T, 4.4 T, '
      '2.0, fuel and cylinder changes)', (tester) async {
    Map<String, List<String>> lists(dynamic s) => {
          'engines': engines(s),
          'cylinders': cylinders(s),
          'fuels': (s.getAvailableFuelTypes() as List).cast<String>(),
          'transmissions': (s.getAvailableTransmissions() as List).cast<String>(),
          'bodies': (s.getAvailableBodyTypes() as List).cast<String>(),
          'drivetrains': (s.getAvailableDriveTypes() as List).cast<String>(),
          'seats': (s.getAvailableSeatings() as List).cast<String>(),
        };
    final data = await appliedCarData(tester, 'BMW', 'X5', 2020);
    final s = await openStep2(tester, data);
    final want = lists(s);
    expect(want['engines'],
        containsAll(['2.0', '2.0 D', '2.9 D', '3.0', '3.0 D', '3.0 T', '3.0 TD',
          '4.4', '4.4 T', '4.6', '4.8']));
    void same(String when) {
      final now = lists(s);
      for (final k in want.keys) {
        expect(now[k], want[k], reason: '$k $when');
      }
    }

    // A. 3.0 T: exact label, cylinders 6, fuel not guessed (3.0 family is
    // gasoline + plug-in hybrid).
    s.setState(() {
      s.selectedFuelType = null;
      s.selectedCylinderCount = null;
      s.selectedEngineSize = null;
    });
    await tester.pump();
    await pickEngine(tester, '3.0 T');
    expect([eng(s), cyl(s), fuelOf(s)], ['3.0 T', '6', null]);
    same('after 3.0 T');

    // B. 4.4 T: exact label, cylinders 8, Gasoline (unanimous 4.4 family).
    await pickEngine(tester, '4.4 T');
    expect([eng(s), cyl(s), fuelOf(s)], ['4.4 T', '8', 'Gasoline']);
    same('after 4.4 T');

    // C. 2.0: exact label, no Electric auto-selection.
    s.setState(() {
      s.selectedFuelType = null;
      s.selectedCylinderCount = null;
      s.selectedEngineSize = null;
    });
    await tester.pump();
    await pickEngine(tester, '2.0');
    expect(eng(s), '2.0');
    expect(fuelOf(s), isNot('Electric'));
    expect(fuelOf(s), isNull);
    same('after 2.0');

    // D. fuel / cylinder changes reconcile selections, never the lists.
    await pickEngine(tester, '4.4 T');
    expect([eng(s), cyl(s), fuelOf(s)], ['4.4 T', '8', 'Gasoline']);
    await pickFuel(tester, 'Diesel');
    expect(fuelOf(s), 'Diesel');
    expect(eng(s), isNot('4.4 T'), reason: 'moved to a compatible diesel engine');
    same('after Diesel');
    await pickCylinders(tester, '8');
    same('after cylinders 8');
    await pickCylinders(tester, '6');
    expect(cyl(s), '6');
    same('after cylinders 6');
    await _unmount(tester);

    // D. A different listing year: same lists, and a stored selection survives.
    final other = await appliedCarData(
      tester,
      'BMW',
      'X5',
      2024,
      extra: {'engine_size': '4.4 T', 'cylinder_count': '8'},
    );
    final s2 = await openStep2(tester, other);
    expect([eng(s2), cyl(s2)], ['4.4 T', '8']);
    final now = lists(s2);
    for (final k in want.keys) {
      expect(now[k], want[k], reason: '$k at 2024');
    }
    await _unmount(tester);
  });
  // Sweep: whatever is picked (engine, cylinders, fuel), no pair the scoped
  // CarNet rows can resolve is left incompatible; the picked field and every
  // exact engine label survive.
  for (final v in const [
    ('BMW', 'X5', 2020),
    ('Toyota', 'Land Cruiser Prado', 2020),
    ('Ford', 'Everest', 2020),
    ('Toyota', 'Land Cruiser', 2020),
  ]) {
    testWidgets('relationship sweep: ${v.$1} ${v.$2} ${v.$3}', (tester) async {
      final data = await appliedCarData(tester, v.$1, v.$2, v.$3);
      final s = await openStep2(tester, data);
      final es = engines(s);
      final cs = cylinders(s);
      expect(es, isNotEmpty);
      expect(cs, isNotEmpty);
      void consistent(String why) {
        final e = eng(s);
        final c = cyl(s);
        final t = trustedCyl(data, e);
        if (e != null && c != null && t != null) {
          expect(int.parse(c), t, reason: '${v.$2} $why: $e / $c');
        }
      }

      var trustedSeen = 0;
      for (final c in cs) {
        await pickCylinders(tester, c);
        expect(cyl(s), c, reason: '${v.$2}: picked cylinders $c preserved');
        if (es.any((e) => trustedCyl(data, e) == int.parse(c))) {
          consistent('after cylinders $c');
        }
        for (final e in es) {
          await pickEngine(tester, e);
          expect(eng(s), e, reason: '${v.$2}: label $e never rewritten');
          final t = trustedCyl(data, e);
          if (t != null) {
            trustedSeen++;
            expect(cyl(s), '$t', reason: '${v.$2}: $e -> $t');
          }
          consistent('after engine $e');
          // a cylinder pick afterwards never leaves an incompatible pair
          final beforeEngine = eng(s);
          await pickCylinders(tester, c);
          expect(cyl(s), c);
          if (es.any((e) => trustedCyl(data, e) == int.parse(c))) {
            consistent('after cylinders $c with engine $beforeEngine');
          }
          if (t == null || '$t' == c) {
            expect(eng(s), beforeEngine, reason: 'compatible engine kept');
          }
        }
      }
      expect(trustedSeen, greaterThan(0), reason: '${v.$2} has trusted pairs');
      await _unmount(tester);
    });
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 15));
}
