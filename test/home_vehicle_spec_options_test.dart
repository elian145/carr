import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/services/car_spec_index.dart';

/// Behavioral coverage for the shared vehicle-spec resolution mechanism that
/// Search/Filters and Sell step 2 both consume:
///
///   make/model/trim/year -> CarSpecIndex.sellFieldOptionsUnion (catalog)
///        -> narrowOptionsToCatalog (per-field fallback contract)
///        -> allowed values for every dependent field
///
/// Everything here runs against the REAL bundled catalog
/// (`assets/car_spec_dataset.json`); no model-specific behavior is hardcoded:
/// expectations are derived from the catalog resolver itself.

// Default/global lists as Search shows them when the catalog has nothing to say
// (kept identical to `_HomePageFields` in home_page.dart).
const _anyCylinders = ['Any', '1', '2', '3', '4', '5', '6', '8', '10', '12', '16'];
const _anySeatings = [
  'Any', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12',
];
const _anyBodies = [
  'Any', 'Sedan', 'SUV', 'Hatchback', 'Coupe', 'Convertible', 'Wagon',
  'Pickup', 'Van', 'Minivan',
];
const _anyFuels = [
  'Any', 'Gasoline', 'Diesel', 'Electric', 'Hybrid', 'Plug-in Hybrid',
];
const _anyDrives = ['Any', 'FWD', 'RWD', 'AWD'];
const _anyTransmissions = ['Any', 'Automatic', 'Manual'];
const _anyEngines = ['Any', '1.0', '1.5', '2.0', '2.5', '3.0', '4.0', '6.2'];

const _defaults = HomeVehicleFieldDefaults(
  bodyTypes: _anyBodies,
  transmissions: _anyTransmissions,
  fuelTypes: _anyFuels,
  driveTypes: _anyDrives,
  cylinderCounts: _anyCylinders,
  seatings: _anySeatings,
  engineSizes: _anyEngines,
);

Set<String> _real(List<String> l) => l.where((e) => e != 'Any').toSet();

void main() {
  late CarSpecIndex idx;

  setUpAll(() {
    final raw = File('assets/car_spec_dataset.json').readAsStringSync();
    final r = parseCarSpecDatasetJsonString(raw);
    expect(r.index, isNotNull, reason: 'bundled spec catalog must parse');
    idx = r.index!;
  });

  HomeVehicleFieldOptions searchOptions(
    String? brand,
    String? model, {
    String? trim,
    int? minYear,
    int? maxYear,
  }) {
    final ctx = HomeVehicleContext(
      brand: brand,
      model: model,
      trim: trim,
      minYear: minYear,
      maxYear: maxYear,
    );
    return HomeVehicleFieldOptions.resolve(
      catalog: resolveHomeVehicleCatalogOptions(idx, ctx),
      engineCatalog: resolveHomeVehicleEngineCatalogOptions(idx, ctx),
      defaults: _defaults,
    );
  }

  // The exact call Sell step 2 makes (`_computeCatalogSellOpts`): model-level,
  // one concrete year.
  CatalogSellFieldOptions sellOptions(String b, String m, int year) {
    final o = idx.sellFieldOptionsUnion(
      b,
      m,
      CarSpecIndex.catalogAutofillModelOnly,
      year,
    );
    expect(o, isNotNull, reason: '$b $m $year must be catalog-covered');
    return o!;
  }

  group('A. known model: Search == Sell/catalog-resolved options', () {
    test('every dependent field matches Sell for the same concrete year', () {
      const b = 'Chevrolet';
      const m = 'Camaro';
      // Policy D2: Camaro is a discontinued line, so its newest catalog year is
      // its last real year (no extrapolated 2024).
      final year = idx.yearsForCatalogStep(b, m, '').first;
      final sell = sellOptions(b, m, year);
      final search = searchOptions(b, m, minYear: year, maxYear: year);

      expect(_real(search.cylinderCounts), sell.cylinderCounts);
      expect(_real(search.transmissions), sell.transmissions);
      expect(_real(search.fuelTypes), sell.fuelTypes);
      expect(_real(search.driveTypes), sell.driveTypes);
      expect(_real(search.bodyTypes), sell.bodyTypes);
      expect(_real(search.seatings), sell.seatings);
      expect(_real(search.engineSizes), sell.engineSizes);
      // Same narrowing helper as Sell -> same labels; nothing outside the catalog.
      expect(
        search.narrowedFields,
        HomeVehicleField.values.toSet(),
        reason: 'Camaro has catalog data for all dependent fields',
      );
    });

    test('no year window unions every catalog year (superset of any year)', () {
      const b = 'Chevrolet';
      const m = 'Camaro';
      final all = searchOptions(b, m);
      final lastYear = idx.yearsForCatalogStep(b, m, '').first;
      final one = searchOptions(b, m, minYear: lastYear, maxYear: lastYear);
      for (final f in [
        (all.cylinderCounts, one.cylinderCounts),
        (all.transmissions, one.transmissions),
        (all.engineSizes, one.engineSizes),
      ]) {
        expect(_real(f.$1).containsAll(_real(f.$2)), isTrue);
      }
      final union = <String>{};
      for (final y in idx.yearsForCatalogStep(b, m, '')) {
        union.addAll(sellOptions(b, m, y).cylinderCounts);
      }
      expect(_real(all.cylinderCounts), union);
    });

    test('a year window never changes the options (brand + model only)', () {
      const b = 'Chevrolet';
      const m = 'Camaro';
      final any = searchOptions(b, m);
      for (final w in [(2018, 2020), (2018, 2018), (1800, 1801), (2030, 2031)]) {
        final windowed = searchOptions(b, m, minYear: w.$1, maxYear: w.$2);
        expect(windowed.engineSizes, any.engineSizes, reason: '$w');
        expect(windowed.cylinderCounts, any.cylinderCounts, reason: '$w');
        expect(windowed.fuelTypes, any.fuelTypes, reason: '$w');
        expect(windowed.transmissions, any.transmissions, reason: '$w');
        expect(windowed.bodyTypes, any.bodyTypes, reason: '$w');
        expect(windowed.driveTypes, any.driveTypes, reason: '$w');
        expect(windowed.seatings, any.seatings, reason: '$w');
      }
    });

    test('J. Chevrolet Camaro no longer shows unrelated global options', () {
      final o = searchOptions('Chevrolet', 'Camaro');
      void expectNarrower(List<String> narrowed, List<String> defaults) {
        expect(narrowed.length, lessThan(defaults.length));
        expect(_real(defaults).containsAll(_real(narrowed)), isTrue);
        expect(_real(narrowed), isNotEmpty);
      }

      expectNarrower(o.cylinderCounts, _anyCylinders);
      expectNarrower(o.seatings, _anySeatings);
      expectNarrower(o.bodyTypes, _anyBodies);
      expectNarrower(o.fuelTypes, _anyFuels);
      expectNarrower(o.driveTypes, _anyDrives);
      // Across all Camaro model years the catalog has automatic + manual, so
      // that list legitimately equals the default; it is still catalog-derived.
      expect(_real(o.transmissions), isNotEmpty);
      // The Cylinders regression specifically: 1/2/3/5/10/12/16 are not Camaro.
      expect(
        _real(o.cylinderCounts),
        idx
            .yearsForCatalogStep('Chevrolet', 'Camaro', '')
            .expand((y) => sellOptions('Chevrolet', 'Camaro', y).cylinderCounts)
            .toSet(),
      );
      expect(o.cylinderCounts, contains('Any'));
    });
  });

  group('B/C/I. fallback contract (per field, independent)', () {
    test('C. no model selected -> every field uses its default list', () {
      for (final o in [
        searchOptions(null, null),
        searchOptions('Chevrolet', null),
        searchOptions('Chevrolet', '  '),
        searchOptions(null, 'Camaro'),
      ]) {
        expect(o.narrowedFields, isEmpty);
        expect(identical(o.cylinderCounts, _anyCylinders), isTrue);
        expect(identical(o.bodyTypes, _anyBodies), isTrue);
        expect(identical(o.transmissions, _anyTransmissions), isTrue);
        expect(identical(o.fuelTypes, _anyFuels), isTrue);
        expect(identical(o.driveTypes, _anyDrives), isTrue);
        expect(identical(o.seatings, _anySeatings), isTrue);
        expect(identical(o.engineSizes, _anyEngines), isTrue);
      }
    });

    test('C. unknown model / catalog miss -> defaults, never an empty picker',
        () {
      for (final o in [
        searchOptions('Chevrolet', 'Definitely Not A Model'),
        searchOptions('Not A Make', 'Camaro'),
      ]) {
        expect(o.narrowedFields, isEmpty);
        expect(o.cylinderCounts, _anyCylinders);
        expect(o.engineSizes, _anyEngines);
      }
    });

    test('C. no catalog index loaded -> defaults', () {
      final catalog = resolveHomeVehicleCatalogOptions(
        null,
        const HomeVehicleContext(brand: 'Chevrolet', model: 'Camaro'),
      );
      expect(catalog, isNull);
      expect(
        HomeVehicleFieldOptions.resolve(
          catalog: catalog,
          engineCatalog: catalog,
          defaults: _defaults,
        ).narrowedFields,
        isEmpty,
      );
    });

    test('a year window that excludes every catalog year still narrows by model',
        () {
      final o = searchOptions('Chevrolet', 'Camaro', minYear: 1800, maxYear: 1801);
      expect(o.narrowedFields, HomeVehicleField.values.toSet());
      expect(o.cylinderCounts, searchOptions('Chevrolet', 'Camaro').cylinderCounts);
    });

    test('B/I. a field with no catalog data uses defaults; others stay narrowed',
        () {
      // Catalog knows the model but has NO cylinder data and NO engine data.
      const catalog = CatalogSellFieldOptions(
        transmissions: {'Manual'},
        fuelTypes: {'Diesel'},
        bodyTypes: {'SUV'},
        driveTypes: <String>{},
        cylinderCounts: <String>{},
        engineSizes: <String>{},
        seatings: {'7'},
      );
      final o = HomeVehicleFieldOptions.resolve(
        catalog: catalog,
        engineCatalog: catalog,
        defaults: _defaults,
      );
      expect(o.cylinderCounts, _anyCylinders, reason: 'missing -> defaults');
      expect(o.driveTypes, _anyDrives, reason: 'missing -> defaults');
      expect(o.engineSizes, _anyEngines, reason: 'missing -> defaults');
      expect(o.transmissions, ['Any', 'Manual'], reason: 'known stays narrowed');
      expect(o.fuelTypes, ['Any', 'Diesel']);
      expect(o.bodyTypes, ['Any', 'SUV']);
      expect(o.seatings, ['Any', '7']);
      expect(o.narrowedFields, {
        HomeVehicleField.transmission,
        HomeVehicleField.fuelType,
        HomeVehicleField.bodyType,
        HomeVehicleField.seating,
      });
    });

    test('catalog values that exist nowhere in the defaults never empty a list',
        () {
      expect(
        narrowOptionsToCatalog(const ['Any', 'A', 'B'], {'Z'}),
        const ['Any', 'A', 'B'],
      );
      expect(
        narrowOptionsToCatalog(const ['Any', 'A', 'B'], <String>{}),
        const ['Any', 'A', 'B'],
      );
      expect(
        narrowOptionsToCatalog(const ['Any', 'A', 'B'], null),
        const ['Any', 'A', 'B'],
      );
      expect(
        narrowOptionsToCatalog(const ['Any', 'A', 'B'], {'B'}),
        const ['Any', 'B'],
      );
    });
  });

  group('F. trim dependency (Sell step 2 is model-level, not trim-specific)', () {
    const b = 'Toyota';
    const m = 'Land Cruiser';
    const year = 2022;
    const trims = ['GX', 'VX', 'GR Sport', 'Base', 'Unmatched Trim'];

    test('six fields ignore trim: identical to Sell for every trim', () {
      final sell = sellOptions(b, m, year); // Sell never passes a trim
      for (final trim in trims) {
        final o = searchOptions(b, m, trim: trim, minYear: year, maxYear: year);
        expect(_real(o.cylinderCounts), sell.cylinderCounts, reason: trim);
        expect(_real(o.bodyTypes), sell.bodyTypes, reason: trim);
        expect(_real(o.transmissions), sell.transmissions, reason: trim);
        expect(_real(o.fuelTypes), sell.fuelTypes, reason: trim);
        expect(_real(o.driveTypes), sell.driveTypes, reason: trim);
        expect(_real(o.seatings), sell.seatings, reason: trim);
      }
    });

    test('selecting a trim never changes the six model-level lists', () {
      final noTrim = searchOptions(b, m, minYear: year, maxYear: year);
      for (final trim in trims) {
        final o = searchOptions(b, m, trim: trim, minYear: year, maxYear: year);
        expect(o.cylinderCounts, noTrim.cylinderCounts, reason: trim);
        expect(o.bodyTypes, noTrim.bodyTypes, reason: trim);
        expect(o.transmissions, noTrim.transmissions, reason: trim);
        expect(o.fuelTypes, noTrim.fuelTypes, reason: trim);
        expect(o.driveTypes, noTrim.driveTypes, reason: trim);
        expect(o.seatings, noTrim.seatings, reason: trim);
      }
    });

    test('engine size follows the same year-first resolver as Sell for every trim', () {
      final modelLevel = sellOptions(b, m, year).engineSizes;
      for (final trim in trims) {
        final direct = idx.sellFieldOptionsUnion(b, m, trim, year)!;
        final o = searchOptions(b, m, trim: trim, minYear: year, maxYear: year);
        expect(_real(o.engineSizes), direct.engineSizes, reason: trim);
        // Policy D2: the year applies first. A trim can never bring in rows that
        // are outside the selected year, so it can only equal or narrow the
        // model-level in-range set (it used to narrow only by dropping carried
        // expired rows).
        expect(modelLevel.containsAll(direct.engineSizes), isTrue, reason: trim);
      }
    });

    test('no trim == Sell step 2 (model-level) resolution', () {
      const b = 'Toyota';
      const m = 'Camry';
      final withNone = searchOptions(b, m, minYear: 2023, maxYear: 2023);
      final withBlank =
          searchOptions(b, m, trim: '   ', minYear: 2023, maxYear: 2023);
      final sell = sellOptions(b, m, 2023);
      expect(_real(withNone.cylinderCounts), sell.cylinderCounts);
      expect(withBlank.cylinderCounts, withNone.cylinderCounts);
    });
  });

  group('H. normalization resolves identically in Search and Sell', () {
    test('case / whitespace variants of make and model resolve the same', () {
      final lastYear =
          idx.yearsForCatalogStep('Chevrolet', 'Camaro', '').first;
      final canonical = searchOptions('Chevrolet', 'Camaro');
      for (final v in [
        ['chevrolet', 'camaro'],
        ['  Chevrolet ', ' Camaro  '],
        ['CHEVROLET', 'CAMARO'],
      ]) {
        final o = searchOptions(v[0], v[1]);
        expect(o.cylinderCounts, canonical.cylinderCounts, reason: '$v');
        expect(o.transmissions, canonical.transmissions, reason: '$v');
        expect(o.engineSizes, canonical.engineSizes, reason: '$v');
        // ...and Sell's resolver call agrees for the same spelling.
        final sell = idx.sellFieldOptionsUnion(
          v[0].trim(),
          v[1].trim(),
          '',
          lastYear,
        );
        expect(sell, isNotNull, reason: '$v');
        expect(
          _real(searchOptions(v[0], v[1], minYear: lastYear, maxYear: lastYear)
              .cylinderCounts),
          sell!.cylinderCounts,
          reason: '$v',
        );
      }
    });
  });

  group('D/E. parent change cleans only invalid dependents', () {
    HomeVehicleDependentSelections select(CatalogSellFieldOptions o) {
      String first(Set<String> s) => (s.toList()..sort()).first;
      return HomeVehicleDependentSelections(
        bodyType: o.bodyTypes.join(','),
        transmission: first(o.transmissions),
        fuelType: o.fuelTypes.join(','),
        driveType: o.driveTypes.join(','),
        cylinderCount: o.cylinderCounts.reduce(
          (a, b) => int.parse(a) >= int.parse(b) ? a : b,
        ),
        seating: first(o.seatings),
        engineSize: first(o.engineSizes),
      );
    }

    test('model A -> model B clears exactly the values B does not allow', () {
      final a = searchOptions('Chevrolet', 'Camaro');
      final b = searchOptions('Toyota', 'Camry');
      final catA = resolveHomeVehicleCatalogOptions(
        idx,
        const HomeVehicleContext(brand: 'Chevrolet', model: 'Camaro'),
      )!;
      final selA = select(catA);
      // Sanity: selections are valid for A (nothing cleared yet).
      expect(sanitizeHomeVehicleDependentSelections(selA, a), selA);

      final after = sanitizeHomeVehicleDependentSelections(selA, b);

      // Independent per-field expectation derived from B's allowed lists.
      String? expectSingle(String? v, List<String> allowed) =>
          allowed.contains(v) ? v : null;
      String? expectMulti(String? raw, List<String> allowed) {
        final kept =
            raw!.split(',').where((e) => allowed.contains(e)).toList();
        return kept.isEmpty ? null : kept.join(',');
      }

      expect(after.transmission, expectSingle(selA.transmission, b.transmissions));
      expect(after.cylinderCount, expectSingle(selA.cylinderCount, b.cylinderCounts));
      expect(after.seating, expectSingle(selA.seating, b.seatings));
      expect(after.engineSize, expectSingle(selA.engineSize, b.engineSizes));
      expect(after.bodyType, expectMulti(selA.bodyType, b.bodyTypes));
      expect(after.fuelType, expectMulti(selA.fuelType, b.fuelTypes));
      expect(after.driveType, expectMulti(selA.driveType, b.driveTypes));

      // The scenario must exercise both outcomes, or it proves nothing.
      final all = [
        after.transmission, after.cylinderCount, after.seating,
        after.engineSize, after.bodyType, after.fuelType, after.driveType,
      ];
      expect(all.where((v) => v == null), isNotEmpty,
          reason: 'some stale values must be cleared');
      expect(all.where((v) => v != null), isNotEmpty,
          reason: 'compatible values must survive');
    });

    test('multi-select drops only the invalid entries', () {
      final b = searchOptions('Toyota', 'Camry', minYear: 2023, maxYear: 2023);
      final after = sanitizeHomeVehicleDependentSelections(
        const HomeVehicleDependentSelections(bodyType: 'Pickup,Sedan'),
        b,
      );
      expect(after.bodyType, 'Sedan');
      final none = sanitizeHomeVehicleDependentSelections(
        const HomeVehicleDependentSelections(bodyType: 'Pickup'),
        b,
      );
      expect(none.bodyType, isNull);
    });

    test('E. a value valid for both models is preserved', () {
      final b = searchOptions('Toyota', 'Camry');
      final a = searchOptions('Chevrolet', 'Camaro');
      final shared = _real(a.cylinderCounts).intersection(_real(b.cylinderCounts));
      expect(shared, isNotEmpty, reason: 'both models are 4-cylinder lines');
      final v = shared.first;
      final after = sanitizeHomeVehicleDependentSelections(
        HomeVehicleDependentSelections(cylinderCount: v, fuelType: 'Gasoline'),
        b,
      );
      expect(after.cylinderCount, v);
      expect(after.fuelType, 'Gasoline');
    });

    test('fields the catalog did not narrow are never touched', () {
      const catalog = CatalogSellFieldOptions(
        transmissions: {'Manual'},
        fuelTypes: <String>{},
        bodyTypes: <String>{},
        driveTypes: <String>{},
        cylinderCounts: <String>{},
        engineSizes: <String>{},
        seatings: <String>{},
      );
      final o = HomeVehicleFieldOptions.resolve(
        catalog: catalog,
        engineCatalog: catalog,
        defaults: _defaults,
      );
      const before = HomeVehicleDependentSelections(
        transmission: 'Automatic', // ruled out
        cylinderCount: '16', // field has no catalog data: keep
        fuelType: 'Plug-in Hybrid', // no data: keep
        engineSize: '9.9', // no data: keep
        seating: '33',
      );
      final after = sanitizeHomeVehicleDependentSelections(before, o);
      expect(after.transmission, isNull);
      expect(after.cylinderCount, '16');
      expect(after.fuelType, 'Plug-in Hybrid');
      expect(after.engineSize, '9.9');
      expect(after.seating, '33');
    });

    test('Any / unset values and no-model state are left alone', () {
      final o = searchOptions('Toyota', 'Camry');
      const sel = HomeVehicleDependentSelections(
        transmission: 'Any',
        cylinderCount: 'any',
      );
      expect(sanitizeHomeVehicleDependentSelections(sel, o), sel);
      final none = searchOptions(null, null);
      const stale = HomeVehicleDependentSelections(cylinderCount: '16');
      expect(sanitizeHomeVehicleDependentSelections(stale, none), stale);
    });

    test('manually typed engine size is free text and is not pruned', () {
      final o = searchOptions('Toyota', 'Camry');
      const sel = HomeVehicleDependentSelections(engineSize: '9.9');
      expect(
        sanitizeHomeVehicleDependentSelections(sel, o, pruneEngineSize: false),
        sel,
      );
      expect(
        sanitizeHomeVehicleDependentSelections(sel, o).engineSize,
        isNull,
      );
    });
  });

  group('G. saved / restored filters', () {
    // Restored filters for a Camry with a model-year window (the window never
    // changes the model-level option lists).
    HomeVehicleFieldOptions camry2023() =>
        searchOptions('Toyota', 'Camry', minYear: 2023, maxYear: 2023);

    test('valid restored dependent values are preserved', () {
      final o = camry2023();
      final cyl = _real(o.cylinderCounts).first;
      final eng = _real(o.engineSizes).first;
      final sel = HomeVehicleDependentSelections(
        transmission: 'Automatic',
        cylinderCount: cyl,
        engineSize: eng,
        bodyType: 'Sedan',
        fuelType: 'Gasoline',
        seating: _real(o.seatings).first,
      );
      expect(sanitizeHomeVehicleDependentSelections(sel, o), sel);
    });

    test('stale restored values are sanitized, valid ones kept', () {
      final o = camry2023();
      const stale = HomeVehicleDependentSelections(
        transmission: 'Not A Transmission',
        cylinderCount: '16',
        bodyType: 'Pickup,Sedan',
        fuelType: 'Gasoline',
      );
      final after = sanitizeHomeVehicleDependentSelections(stale, o);
      expect(after.transmission, isNull);
      expect(after.cylinderCount, isNull);
      expect(after.bodyType, 'Sedan');
      expect(after.fuelType, 'Gasoline');
    });

    test('restored case differences (saved search maps) are tolerated', () {
      final o = camry2023();
      const sel = HomeVehicleDependentSelections(
        transmission: 'automatic',
        fuelType: 'gasoline',
      );
      expect(sanitizeHomeVehicleDependentSelections(sel, o), sel);
    });

    test('catalog not loaded yet (restore at startup) wipes nothing', () {
      final o = HomeVehicleFieldOptions.resolve(
        catalog: null,
        engineCatalog: null,
        defaults: _defaults,
      );
      const sel = HomeVehicleDependentSelections(
        transmission: 'Manual',
        cylinderCount: '8',
      );
      expect(sanitizeHomeVehicleDependentSelections(sel, o), sel);
    });
  });
}
