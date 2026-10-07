import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

/// Field-aware coverage: the approved IQ overlay counts as coverage for the
/// SPECIFIC field it supplies, also for models the legacy CarNet spec dataset
/// has no rows for -- and for nothing else. Real bundled assets throughout.
void main() {
  late String specRaw;
  late IqCarsOverlay overlay;

  const searchCylinderDefaults = [
    'Any', '1', '2', '3', '4', '5', '6', '8', '10', '12', '16', //
  ];
  const sellCylinderDefaults = ['3', '4', '5', '6', '8', '10', '12'];
  const searchEngineDefaults = ['Any', 'default'];

  setUpAll(() {
    specRaw = File('assets/car_spec_dataset.json').readAsStringSync();
    overlay = IqCarsOverlay.parse(
      File('assets/car_iqcars_overlay.json').readAsStringSync(),
    );
    final cat = jsonDecode(File('assets/car_catalog.json').readAsStringSync())
        as Map<String, dynamic>;
    CarCatalog.applyCatalogFromAsset(cat);
  });

  tearDownAll(CarCatalog.resetCatalogOverrideForTest);

  late CarSpecIndex plainIdx;
  late CarSpecIndex iqIdx;
  setUpAll(() {
    plainIdx = parseCarSpecDatasetJsonString(specRaw).index!;
    iqIdx = parseCarSpecDatasetJsonString(specRaw).index!
      ..attachIqCarsOverlay(overlay);
  });

  HomeVehicleFieldDefaults defaults() => const HomeVehicleFieldDefaults(
        bodyTypes: ['Any', 'SUV'],
        transmissions: ['Any', 'Automatic', 'Manual'],
        fuelTypes: ['Any', 'Gasoline', 'Diesel'],
        driveTypes: ['Any', 'FWD', 'RWD', 'AWD', '4WD'],
        cylinderCounts: searchCylinderDefaults,
        seatings: ['Any', '5'],
        engineSizes: searchEngineDefaults,
      );

  /// Search, exactly as the Search screen resolves it.
  HomeVehicleFieldOptions search(
    CarSpecIndex idx,
    String b,
    String m, {
    String trim = '',
  }) {
    final ctx = HomeVehicleContext(brand: b, model: m, trim: trim);
    return HomeVehicleFieldOptions.resolve(
      catalog: resolveHomeVehicleCatalogOptions(idx, ctx),
      engineCatalog: resolveHomeVehicleEngineCatalogOptions(idx, ctx),
      defaults: defaults(),
    );
  }

  /// Sell step 2's option sets, exactly as the picker getters derive them.
  ({List<String> engines, List<String> cylinders}) sell(
    CarSpecIndex idx,
    String b,
    String m,
    int year,
  ) {
    // Same gate as `_computeCatalogSellOpts` (after "Apply specs").
    final o = idx.hasCoverage(b, m)
        ? idx.sellFieldOptionsUnion(b, m, CarSpecIndex.catalogAutofillModelOnly, year)
        : idx.iqOnlyFieldOptions(b, m, CarSpecIndex.catalogAutofillModelOnly);
    final engines = (o != null && o.engineSizes.isNotEmpty)
        ? <String>['Any', ...sortCatalogEngineSizeLabels(o.engineSizes)]
        : <String>['<full default ladder>'];
    return (
      engines: engines,
      cylinders: narrowCylinderOptionsToCatalog(
        sellCylinderDefaults,
        o?.cylinderCounts,
        o?.iqCylinderCounts,
      ),
    );
  }

  List<(String, String, IqCarsModelAdditions)> allOverlayModels() => [
        for (final b in overlay.entries)
          for (final m in b.value.entries) (b.key, m.key, m.value),
      ];

  group('overlay coverage API', () {
    test('field-specific, keyed, never a scan', () {
      expect(overlay.hasEngineSizes('Ford', 'Everest'), isTrue);
      expect(overlay.hasTrims('Ford', 'Everest'), isTrue);
      expect(overlay.hasCylinderCounts('Ford', 'Everest'), isTrue);
      expect(overlay.hasEngineSizes('Volkswagen', 'Golf R'), isFalse);
      expect(overlay.hasCylinderCounts('Volkswagen', 'Golf R'), isTrue);
      expect(overlay.hasEngineSizes(null, 'x'), isFalse);
      expect(IqCarsOverlay.empty.hasEngineSizes('Ford', 'Everest'), isFalse);
      // Land Cruiser / Prado are separate keys
      expect(overlay.hasEngineSizes('Toyota', 'Land Cruiser Prado'),
          overlay.additionsFor('Toyota', 'Land Cruiser Prado')!.engineLiters.isNotEmpty);
    });

    test('200k coverage probes stay cheap (memoised lookup)', () {
      final sw = Stopwatch()..start();
      var hits = 0;
      for (var i = 0; i < 200000; i++) {
        if (overlay.hasEngineSizes('Ford', 'Everest')) hits++;
        if (overlay.hasCylinderCounts('Toyota', 'Camry')) hits++;
      }
      sw.stop();
      expect(hits, greaterThan(0));
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });
  });

  group('A. covered model, no CarNet engines, approved IQ engines', () {
    test('Lincoln Corsair: Search and Sell receive the IQ engines', () {
      expect(plainIdx.hasCoverage('Lincoln', 'Corsair'), isTrue);
      final base = plainIdx.homeFilterFieldOptions('Lincoln', 'Corsair', '')!;
      expect(base.engineSizes, isEmpty, reason: 'CarNet has no engine data');
      expect(overlay.additionsFor('Lincoln', 'Corsair')!.engineLiters,
          containsAll([2.0, 2.3, 2.5]));

      final s = search(iqIdx, 'Lincoln', 'Corsair');
      expect(s.engineSizes, ['Any', '2.0 T', '2.3 T', '2.5']);
      expect(s.narrowedFields, contains(HomeVehicleField.engineSize));
      // not-IQ-supplied field keeps its existing behaviour
      expect(search(plainIdx, 'Lincoln', 'Corsair').engineSizes, searchEngineDefaults);

      final y = plainIdx
          .yearsForCatalogStep('Lincoln', 'Corsair', CarSpecIndex.catalogAutofillModelOnly)
          .first;
      expect(sell(iqIdx, 'Lincoln', 'Corsair', y).engines, ['Any', '2.0 T', '2.3 T', '2.5']);
      expect(sell(plainIdx, 'Lincoln', 'Corsair', y).engines, ['<full default ladder>']);
    });
  });

  group('B. covered model, no CarNet cylinders, approved IQ cylinders', () {
    test('Mazda MX-30: Search and Sell receive the IQ cylinders', () {
      expect(plainIdx.hasCoverage('Mazda', 'MX-30'), isTrue);
      final base = plainIdx.homeFilterFieldOptions('Mazda', 'MX-30', '')!;
      expect(base.cylinderCounts, isEmpty, reason: 'CarNet has no cylinder data');
      expect(overlay.additionsFor('Mazda', 'MX-30')!.cylinders, contains(4));

      expect(search(iqIdx, 'Mazda', 'MX-30').cylinderCounts, ['Any', '4']);
      expect(search(plainIdx, 'Mazda', 'MX-30').cylinderCounts, searchCylinderDefaults);

      final y = plainIdx
          .yearsForCatalogStep('Mazda', 'MX-30', CarSpecIndex.catalogAutofillModelOnly)
          .first;
      expect(sell(iqIdx, 'Mazda', 'MX-30', y).cylinders, ['4']);
      expect(sell(plainIdx, 'Mazda', 'MX-30', y).cylinders, sellCylinderDefaults);
    });
  });

  group('C. models with no legacy spec coverage at all', () {
    late List<(String, String, IqCarsModelAdditions)> blocked;
    setUpAll(() {
      blocked = [
        for (final e in allOverlayModels())
          if (!plainIdx.hasCoverage(e.$1, e.$2)) e,
      ];
    });

    test('they exist, and the legacy gate used to hide every IQ value', () {
      expect(blocked.length, greaterThan(500));
      for (final (b, m, a) in blocked) {
        if (a.engineLiters.isEmpty && a.cylinders.isEmpty) continue;
        // Old behaviour (no overlay attached): nothing to narrow with.
        expect(plainIdx.homeFilterFieldOptions(b, m, ''), isNull, reason: '$b $m');
        expect(plainIdx.sellFieldOptionsUnion(b, m, '', 2020), isNull, reason: '$b $m');
      }
    });

    test('Alfa Romeo Mito: IQ engines 1.3 / 1.4 and cylinder 4 now appear', () {
      expect(plainIdx.hasCoverage('Alfa Romeo', 'Mito'), isFalse);
      final a = overlay.additionsFor('Alfa Romeo', 'Mito')!;
      expect(a.engineLiters, [1.3, 1.4]);
      expect(a.cylinders, [4]);

      // before: full defaults
      final before = search(plainIdx, 'Alfa Romeo', 'Mito');
      expect(before.engineSizes, searchEngineDefaults);
      expect(before.cylinderCounts, searchCylinderDefaults);
      expect(before.narrowedFields, isEmpty);

      // after: IQ values, only for the fields IQ supplies
      final after = search(iqIdx, 'Alfa Romeo', 'Mito');
      expect(after.engineSizes, ['Any', '1.3 D', '1.4', '1.4 T']);
      expect(after.cylinderCounts, ['Any', '4']);
      expect(after.narrowedFields,
          {HomeVehicleField.engineSize, HomeVehicleField.cylinderCount});
      // fields IQ says nothing about keep the exact defaults
      expect(after.bodyTypes, ['Any', 'SUV']);
      expect(after.transmissions, ['Any', 'Automatic', 'Manual']);
      expect(after.fuelTypes, ['Any', 'Gasoline', 'Diesel']);
      expect(after.driveTypes, ['Any', 'FWD', 'RWD', 'AWD', '4WD']);
      expect(after.seatings, ['Any', '5']);

      final s = sell(iqIdx, 'Alfa Romeo', 'Mito', 2014);
      expect(s.engines, ['Any', '1.3 D', '1.4', '1.4 T']);
      expect(s.cylinders, ['4']);
    });

    test('field-specific: an engines-only IQ model keeps default cylinders', () {
      final e = blocked.firstWhere(
        (e) => e.$3.engineLiters.isNotEmpty && e.$3.cylinders.isEmpty,
        orElse: () => throw StateError('no engines-only model'),
      );
      final o = search(iqIdx, e.$1, e.$2);
      expect(o.engineSizes.first, 'Any');
      expect(o.engineSizes.length, e.$3.engineLiters.length + 1);
      expect(o.cylinderCounts, searchCylinderDefaults, reason: '${e.$1} ${e.$2}');
      expect(sell(iqIdx, e.$1, e.$2, 2020).cylinders, sellCylinderDefaults);
    });

    test('field-specific: a cylinders-only IQ model keeps the default engines', () {
      final e = blocked.firstWhere(
        (e) => e.$3.cylinders.isNotEmpty && e.$3.engineLiters.isEmpty,
        orElse: () => throw StateError('no cylinders-only model'),
      );
      final o = search(iqIdx, e.$1, e.$2);
      expect(o.engineSizes, searchEngineDefaults, reason: '${e.$1} ${e.$2}');
      expect(o.cylinderCounts.first, 'Any');
      expect(o.cylinderCounts.length, greaterThan(1));
      expect(sell(iqIdx, e.$1, e.$2, 2020).engines, ['<full default ladder>']);
    });
  });

  group('D. neither baseline nor IQ coverage keeps today\'s behaviour', () {
    test('no-coverage model with no IQ engines / cylinders: resolver stays null', () {
      final trimsOnly = [
        for (final e in allOverlayModels())
          if (!plainIdx.hasCoverage(e.$1, e.$2) &&
              e.$3.engineLiters.isEmpty &&
              e.$3.cylinders.isEmpty)
            e,
      ];
      expect(trimsOnly, isNotEmpty);
      for (final (b, m, _) in trimsOnly) {
        expect(iqIdx.homeFilterFieldOptions(b, m, ''), isNull, reason: '$b $m');
        expect(iqIdx.sellFieldOptionsUnion(b, m, '', 2020), isNull, reason: '$b $m');
        final o = search(iqIdx, b, m);
        expect(o.engineSizes, searchEngineDefaults);
        expect(o.cylinderCounts, searchCylinderDefaults);
        expect(o.narrowedFields, isEmpty);
      }
    });

    test('model unknown to both CarNet and IQ', () {
      expect(iqIdx.homeFilterFieldOptions('Not A Brand', 'Nope', ''), isNull);
      final o = search(iqIdx, 'Not A Brand', 'Nope');
      expect(o.engineSizes, searchEngineDefaults);
      expect(o.cylinderCounts, searchCylinderDefaults);
      expect(o.narrowedFields, isEmpty);
    });

    test('covered model without IQ entry is unchanged (Golf R)', () {
      final a = search(plainIdx, 'Volkswagen', 'Golf R');
      final b = search(iqIdx, 'Volkswagen', 'Golf R');
      expect(b.engineSizes, a.engineSizes);
      expect(b.cylinderCounts, a.cylinderCounts);
    });

    test('empty / missing overlay: every no-coverage model stays null', () {
      final idx = parseCarSpecDatasetJsonString(specRaw).index!;
      expect(idx.homeFilterFieldOptions('Alfa Romeo', 'Mito', ''), isNull);
      idx.attachIqCarsOverlay(IqCarsOverlay.empty);
      expect(idx.homeFilterFieldOptions('Alfa Romeo', 'Mito', ''), isNull);
    });
  });

  group('E. a selected trim never changes the model-level IQ lists', () {
    test('no-coverage model: the IQ lists are offered whatever the trim is', () {
      final noTrim = iqIdx.homeFilterFieldOptions('Alfa Romeo', 'Mito', '');
      expect(noTrim, isNotNull);
      final withTrim = iqIdx.homeFilterFieldOptions('Alfa Romeo', 'Mito', 'Veloce');
      expect(withTrim, isNotNull);
      expect(withTrim!.engineSizes, noTrim!.engineSizes);
      expect(withTrim.cylinderCounts, noTrim.cylinderCounts);
      expect(iqIdx.iqOnlyFieldOptions('Alfa Romeo', 'Mito', 'Veloce')!.engineSizes,
          noTrim.engineSizes);
      expect(
        search(iqIdx, 'Alfa Romeo', 'Mito', trim: 'Veloce').engineSizes,
        search(iqIdx, 'Alfa Romeo', 'Mito').engineSizes,
      );
    });

    test('covered model with empty engine baseline: trim never changes the options', () {
      final trim = CarCatalog.trimsFor('Lincoln', 'Corsair').first;
      final x = iqIdx.homeFilterFieldOptions('Lincoln', 'Corsair', '');
      final y = iqIdx.homeFilterFieldOptions('Lincoln', 'Corsair', trim);
      expect(y == null, x == null);
      if (x != null) {
        expect(y!.engineSizes, x.engineSizes);
        expect(y.cylinderCounts, x.cylinderCounts);
      }
      expect(search(iqIdx, 'Lincoln', 'Corsair', trim: trim).engineSizes,
          search(iqIdx, 'Lincoln', 'Corsair').engineSizes);
    });
  });

  group('Sell cylinder range: approved IQ counts bypass the generic 3-12', () {
    test('narrowCylinderOptionsToCatalog (unit)', () {
      List<String> n(Set<String>? known, Set<String>? iq) =>
          narrowCylinderOptionsToCatalog(sellCylinderDefaults, known, iq);
      expect(n({'16'}, {'16'}), ['16']);
      expect(n({'2'}, {'2'}), ['2']);
      expect(n({'4', '16'}, {'16'}), ['4', '16']);
      expect(n({'2', '4'}, {'2', '4'}), ['2', '4']);
      expect(n({'1', '2'}, {'1', '2'}), ['1', '2']);
      // no IQ extras -> exactly the legacy contract
      expect(n({'4', '16'}, null), narrowOptionsToCatalog(sellCylinderDefaults, {'4', '16'}));
      expect(n({'4', '16'}, <String>{}), ['4']);
      expect(n({'16'}, null), sellCylinderDefaults, reason: 'legacy: nothing usable -> defaults');
      expect(n(<String>{}, {'16'}), sellCylinderDefaults);
      expect(n(null, {'16'}), sellCylinderDefaults);
      // only IQ-approved values bypass: a non-IQ out-of-range count is still dropped
      expect(n({'4', '16'}, {'4'}), ['4']);
      // an "approved" count that is not in the known set is ignored (no inference)
      expect(n({'4'}, {'16'}), ['4']);
      // defaults are never expanded
      expect(sellCylinderDefaults, ['3', '4', '5', '6', '8', '10', '12']);
      // Search-style list keeps 'Any' first
      expect(
        narrowCylinderOptionsToCatalog(['Any', '3', '4'], {'4', '16'}, {'16'}),
        ['Any', '4', '16'],
      );
    });

    test('1. approved IQ 16-cylinder models: Sell offers 16 (and only the approved)', () {
      for (final m in ['Chiron', 'Veyron']) {
        expect(overlay.additionsFor('Bugatti', m)!.cylinders, [16]);
        expect(sell(iqIdx, 'Bugatti', m, 2018).cylinders, ['16'], reason: m);
        // before: the clamp discarded it and showed 3-12
        final old = narrowOptionsToCatalog(
          sellCylinderDefaults,
          iqIdx.iqOnlyFieldOptions('Bugatti', m, '')!.cylinderCounts,
        );
        expect(old, sellCylinderDefaults);
      }
    });

    test('2. approved IQ 2-cylinder models: Sell offers 2', () {
      expect(overlay.additionsFor('Polaris', 'RZR')!.cylinders, [2]);
      expect(sell(iqIdx, 'Polaris', 'RZR', 2020).cylinders, ['2']);
      expect(sell(iqIdx, 'Polaris', 'Ranger 570', 2020).cylinders, ['1']);
      // mixed: in-range and out-of-range approved counts together
      expect(overlay.additionsFor('Fiat', '500')!.cylinders, [2, 4]);
      expect(sell(iqIdx, 'Fiat', '500', 2015).cylinders, containsAll(['2', '4']));
      expect(sell(iqIdx, 'Fiat', '500', 2015).cylinders, isNot(contains('12')));
    });

    test('3. ordinary models keep the generic 3-12 behaviour exactly', () {
      // no IQ cylinders, no coverage
      expect(sell(iqIdx, 'Not A Brand', 'Nope', 2020).cylinders, sellCylinderDefaults);
      // covered, IQ supplies the full set (Everest 4/5/6): baseline UNION IQ
      expect(overlay.hasCylinderCounts('Ford', 'Everest'), isTrue);
      expect(sell(iqIdx, 'Ford', 'Everest', 2020).cylinders, ['4', '5', '6']);
      // covered, IQ set already contained in CarNet's (Golf R [4])
      expect(sell(iqIdx, 'Volkswagen', 'Golf R', 2020).cylinders,
          sell(plainIdx, 'Volkswagen', 'Golf R', 2020).cylinders);
      // an in-range IQ model is unchanged in kind: Mazda MX-30 -> [4]
      expect(sell(iqIdx, 'Mazda', 'MX-30', 2020).cylinders, ['4']);
      // no iqCylinderCounts leak into models without approved counts
      expect(iqIdx.sellFieldOptionsUnion('Volkswagen', 'Passat', '', 2020)?.iqCylinderCounts ?? <String>{},
          overlay.approvedCylinderLabels('Volkswagen', 'Passat'));
    });

    test('4. a selected trim never changes the model-level IQ cylinder values', () {
      // no coverage: the IQ-only cylinders are offered whatever the trim is
      expect(
        iqIdx.iqOnlyFieldOptions('Bugatti', 'Chiron', 'Sport')?.cylinderCounts,
        iqIdx.iqOnlyFieldOptions('Bugatti', 'Chiron', '')?.cylinderCounts,
      );
      expect(iqIdx.iqOnlyFieldOptions('Bugatti', 'Chiron', 'Sport')?.cylinderCounts,
          contains('16'));
      // covered model: the trim-scoped union equals the model-level one
      final trim = CarCatalog.trimsFor('Mazda', 'MX-30').first;
      final x = iqIdx.sellFieldOptionsUnion('Mazda', 'MX-30', '', 2022);
      final y = iqIdx.sellFieldOptionsUnion('Mazda', 'MX-30', trim, 2022);
      expect(y == null, x == null);
      if (x != null) {
        expect(y!.cylinderCounts, x.cylinderCounts);
        expect(y.iqCylinderCounts, x.iqCylinderCounts);
      }
    });

    test('5. contaminated default cylinder lists stay excluded', () {
      final exc = jsonDecode(File(
        'tools/catalog_enrichment/iqcars/generated/carnet_iqcars_overlay_exclusions.json',
      ).readAsStringSync()) as Map<String, dynamic>;
      final contaminated = (exc['unrestricted_default_cylinder_lists'] as List)
          .cast<Map<String, dynamic>>();
      expect(contaminated, isNotEmpty);
      for (final e in contaminated) {
        final b = e['brand'] as String, m = e['model'] as String;
        expect(overlay.hasCylinderCounts(b, m), isFalse, reason: '$b $m');
        // (IQ may still supply engines for such a model; never cylinders.)
        final only = iqIdx.iqOnlyFieldOptions(b, m, '');
        expect(only?.cylinderCounts ?? const <String>{}, isEmpty, reason: '$b $m');
        expect(only?.iqCylinderCounts ?? const <String>{}, isEmpty, reason: '$b $m');
        final o = iqIdx.sellFieldOptionsUnion(b, m, '', 2020);
        expect(o?.iqCylinderCounts ?? const <String>{}, isEmpty, reason: '$b $m');
        expect(sell(iqIdx, b, m, 2020).cylinders,
            sell(plainIdx, b, m, 2020).cylinders, reason: '$b $m');
      }
      // and no overlay model carries more than 6 counts or a count outside the known ladder
      for (final (b, m, a) in allOverlayModels()) {
        expect(a.cylinders.length, lessThanOrEqualTo(6), reason: '$b $m');
        expect(a.cylinders.every((c) => const [1, 2, 3, 4, 5, 6, 8, 10, 12, 16].contains(c)),
            isTrue, reason: '$b $m');
      }
    });
  });

  group('coverage report (real bundled assets)', () {
    test('how much additional coverage the field-aware gate unlocks', () {
      final all = allOverlayModels();
      final blocked = [
        for (final e in all)
          if (!plainIdx.hasCoverage(e.$1, e.$2)) e,
      ];
      var withEngines = 0, withCyl = 0, both = 0, defaultsOnly = 0;
      var searchEngNarrow = 0, searchCylNarrow = 0, sellEngNarrow = 0, sellCylNarrow = 0;
      var searchBothNarrow = 0, clampedOnly = 0;
      for (final (b, m, a) in blocked) {
        final hasE = a.engineLiters.isNotEmpty;
        final hasC = a.cylinders.isNotEmpty;
        if (hasE) withEngines++;
        if (hasC) withCyl++;
        if (hasE && hasC) both++;
        if (!hasE && !hasC) {
          defaultsOnly++;
          continue;
        }
        final s = search(iqIdx, b, m);
        final se = s.narrowedFields.contains(HomeVehicleField.engineSize);
        final sc = s.narrowedFields.contains(HomeVehicleField.cylinderCount);
        if (se) searchEngNarrow++;
        if (sc) searchCylNarrow++;
        if (se && sc) searchBothNarrow++;
        final sl = sell(iqIdx, b, m, 2020);
        if (sl.engines.first == 'Any') sellEngNarrow++;
        if (sl.cylinders.join(',') != sellCylinderDefaults.join(',')) sellCylNarrow++;
        // Formerly discarded by the 3-12 clamp: no approved count is a Sell default.
        if (hasC && !a.cylinders.any((c) => sellCylinderDefaults.contains('$c'))) {
          clampedOnly++;
          expect(sl.cylinders, a.cylinders.map((c) => '$c').toList(), reason: '$b $m');
        }
      }
      final msg = StringBuffer()
        ..writeln('overlay models total:                      ${all.length}')
        ..writeln('blocked by legacy coverage gate:           ${blocked.length}')
        ..writeln('  with IQ engines and/or cylinders:        ${withEngines + withCyl - both}')
        ..writeln('  gain IQ engines:                         $withEngines')
        ..writeln('  gain IQ cylinders:                       $withCyl')
        ..writeln('  gain both:                               $both')
        ..writeln('  stay on defaults (trims-only IQ data):   $defaultsOnly')
        ..writeln('Search effective narrowing: engines=$searchEngNarrow cylinders=$searchCylNarrow both=$searchBothNarrow')
        ..writeln('Sell   effective narrowing: engines=$sellEngNarrow cylinders=$sellCylNarrow')
        ..writeln('  of which previously blocked only by the 3-12 clamp: $clampedOnly');
      // ignore: avoid_print
      print(msg);
      File('${Directory.systemTemp.path}/iq_coverage_report.txt')
          .writeAsStringSync(msg.toString());

      expect(blocked.length, greaterThan(500));
      expect(withEngines + withCyl - both + defaultsOnly, blocked.length);
      expect(searchEngNarrow, withEngines, reason: 'every IQ engine list narrows Search');
      expect(sellEngNarrow, withEngines);
      expect(searchCylNarrow, lessThanOrEqualTo(withCyl));
      expect(sellCylNarrow, withCyl, reason: 'every approved cylinder list now reaches Sell');
      expect(sellCylNarrow, searchCylNarrow);
      expect(clampedOnly, 10);
    });
  });
}
