import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

/// Data-quality fix: the app resolves the SAME model families as the tooling
/// (hyphen/space spelling, brand spelling, one reviewed alias), the runtime
/// overlay carries FULL trusted cylinder sets that the app unions with its own
/// CarNet baseline, Geely Cityray's contradicted cylinder stays out, and Search
/// shows only `Any` for engine/cylinder when a selected model has no trusted
/// data. Real bundled assets throughout.
void main() {
  late String specRaw;
  late Map<String, dynamic> spec;
  late Map<String, dynamic> catalogJson;
  late IqCarsOverlay overlay;
  late CarSpecIndex plainIdx;
  late CarSpecIndex iqIdx;

  const searchCylinderDefaults = [
    'Any', '1', '2', '3', '4', '5', '6', '8', '10', '12', '16', //
  ];
  const sellCylinderDefaults = ['3', '4', '5', '6', '8', '10', '12'];
  const searchEngineDefaults = ['Any', 'generic-engine-ladder'];

  // The 19 families the app failed to resolve while the tooling did.
  const gapModels = <(String, String)>[
    ('BMW', '1-Series'), ('BMW', '2-Series'), ('BMW', '3-Series'),
    ('BMW', '4-Series'), ('BMW', '5-Series'), ('BMW', '6-Series'),
    ('BMW', '7-Series'), ('BMW', '8-Series'),
    ('Cadillac', 'ATS-V'), ('Cadillac', 'CTS-V'),
    ('Ram', '2500'),
    ('Rolls Royce', 'Cullinan'), ('Rolls Royce', 'Dawn'),
    ('Rolls Royce', 'Ghost'), ('Rolls Royce', 'Phantom'),
    ('Rolls Royce', 'Silver Seraph'), ('Rolls Royce', 'Silver Spur'),
    ('Rolls Royce', 'Spectre'), ('Rolls Royce', 'Wraith'),
  ];

  setUpAll(() {
    specRaw = File('assets/car_spec_dataset.json').readAsStringSync();
    spec = jsonDecode(specRaw) as Map<String, dynamic>;
    catalogJson = jsonDecode(File('assets/car_catalog.json').readAsStringSync())
        as Map<String, dynamic>;
    CarCatalog.applyCatalogFromAsset(catalogJson);
    overlay = IqCarsOverlay.parse(
      File('assets/car_iqcars_overlay.json').readAsStringSync(),
    );
    plainIdx = parseCarSpecDatasetJsonString(specRaw).index!;
    iqIdx = parseCarSpecDatasetJsonString(specRaw).index!
      ..attachIqCarsOverlay(overlay);
  });

  tearDownAll(CarCatalog.resetCatalogOverrideForTest);

  HomeVehicleFieldDefaults defaults() => const HomeVehicleFieldDefaults(
        bodyTypes: ['Any', 'SUV'],
        transmissions: ['Any', 'Automatic', 'Manual'],
        fuelTypes: ['Any', 'Gasoline', 'Diesel'],
        driveTypes: ['Any', 'FWD', 'RWD', 'AWD', '4WD'],
        cylinderCounts: searchCylinderDefaults,
        seatings: ['Any', '5'],
        engineSizes: searchEngineDefaults,
      );

  /// Search exactly as the Search screen resolves it (Brand + Model selected,
  /// catalog index loaded => `vehicleResolved`).
  HomeVehicleFieldOptions search(
    CarSpecIndex idx,
    String b,
    String m, {
    bool vehicleResolved = true,
    String trim = '',
  }) {
    final ctx = HomeVehicleContext(brand: b, model: m, trim: trim);
    return HomeVehicleFieldOptions.resolve(
      catalog: resolveHomeVehicleCatalogOptions(idx, ctx),
      engineCatalog: resolveHomeVehicleEngineCatalogOptions(idx, ctx),
      defaults: defaults(),
      vehicleResolved: vehicleResolved,
    );
  }

  /// Sell step 2's option sets, exactly as the picker getters derive them.
  ({List<String> engines, List<String> cylinders}) sell(
    CarSpecIndex idx,
    String b,
    String m,
    int year,
  ) {
    final o = idx.hasCoverage(b, m)
        ? idx.sellFieldOptionsUnion(
            b, m, CarSpecIndex.catalogAutofillModelOnly, year)
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

  Set<String> cyls(CatalogSellFieldOptions? o) => o?.cylinderCounts ?? <String>{};

  // ------------------------------------------------------------------ matcher
  group('model-family matching (same safe families as the tooling)', () {
    bool m(String brand, String family, String dataset) =>
        carSpecDatasetNameMatchesFamily(brand, family, dataset);

    test('hyphen <-> space spelling is bridged, whole words only', () {
      expect(m('BMW', '4-Series', '4 Series'), isTrue);
      expect(m('BMW', '5-Series', '5 Series 540i'), isTrue);
      expect(m('BMW', '5 Series', '5-Series 540i'), isTrue);
      expect(m('Cadillac', 'ATS-V', 'ATS V 3 6 V6'), isTrue);
      expect(m('Cadillac', 'CTS-V', 'CTS V 6 2 V8'), isTrue);
      expect(m('Rolls Royce', 'Ghost', 'Ghost 6 6 V12'), isTrue);
      // never a raw prefix / loose substring
      expect(m('BMW', '4-Series', '4 Seriesx'), isFalse);
      expect(m('BMW', '4-Series', '14 Series'), isFalse);
      expect(m('BMW', '5-Series', '4 Series 5'), isFalse);
      expect(m('Cadillac', 'ATS-V', 'ATS 2 0 T'), isFalse);
      expect(m('Cadillac', 'ATS-V', 'ATSV 3 6'), isFalse);
    });

    test('Ram 2500 resolves through ONE explicit reviewed alias, not fuzzily', () {
      expect(m('Ram', '2500', '2500/3500 2500 6 4 HEMI V8 (405 Hp) 4x4'), isTrue);
      expect(m('Ram', '2500', '2500/3500 3500 6 7 Cummins'), isFalse);
      expect(m('Ram', '1500', '2500/3500 2500 6 4 HEMI V8'), isFalse);
      expect(m('Ram', '2500', '2500 6 4'), isTrue, reason: 'legacy rule unchanged');
      // other brands never use the alias
      expect(m('Dodge', '2500', '2500/3500 2500 6 4 HEMI V8'), isFalse);
      // slash is NOT a separator: other "A/B" dataset families stay unmatched
      expect(m('BYD', 'S6', 'S6/S7 2 0L (140 Hp)'), isFalse);
      expect(m('Hyundai', 'Grandeur', 'Grandeur/Azera 2 0i (120 Hp)'), isFalse);
      expect(m('Genesis', 'G90', 'G90/EQ900 3 3 T-GDi V6'), isFalse);
      expect(m('Chevrolet', 'Sail', 'Sail/S-RV 1 3 (103 Hp)'), isFalse);
    });

    test('brand spelling: Rolls Royce == Rolls-Royce (and nothing else collides)', () {
      expect(carSpecSpacedNameKey('Rolls-Royce'), carSpecSpacedNameKey('Rolls Royce'));
      expect(plainIdx.datasetBrandId('Rolls Royce'), isNotNull);
      expect(plainIdx.datasetBrandId('Rolls Royce'), plainIdx.datasetBrandId('Rolls-Royce'));
      final keys = <String, String>{};
      for (final b in (spec['brands'] as List).cast<Map<String, dynamic>>()) {
        final name = b['name'] as String;
        final k = carSpecSpacedNameKey(name);
        expect(keys.containsKey(k), isFalse,
            reason: 'brand spellings "$name" and "${keys[k]}" must not collide');
        keys[k] = name;
      }
    });

    test('sibling model identities stay distinct (tooling must_remain_distinct)', () {
      final rules = jsonDecode(
        File('tools/catalog_enrichment/rules/model_boundaries.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final groups = (rules['must_remain_distinct'] as List).cast<dynamic>();
      expect(groups, isNotEmpty);
      for (final g in groups) {
        final names = (g is Map ? (g['models'] ?? g['names']) : g) as List;
        final keys = names.map((e) => carSpecSpacedNameKey('$e')).toList();
        expect(keys.toSet().length, keys.length, reason: '$names');
      }
      const pairs = <(String, String, String)>[
        ('Toyota', 'Land Cruiser', 'Land Cruiser Prado'),
        ('Volkswagen', 'Golf', 'Golf R'),
        ('Toyota', 'Corolla', 'Corolla Cross'),
        ('Ford', 'Bronco', 'Bronco Sport'),
        ('Mitsubishi', 'Pajero', 'Pajero Sport'),
        ('Land Rover', 'Discovery', 'Discovery Sport'),
        ('Volkswagen', 'Passat', 'Passat CC'),
      ];
      for (final (brand, shorter, longer) in pairs) {
        expect(carSpecSpacedNameKey(shorter), isNot(carSpecSpacedNameKey(longer)));
        // the more specific line never absorbs the shorter line's rows
        expect(m(brand, longer, '$shorter 2 0 (150 Hp)'), isFalse,
            reason: '$longer must not match a "$shorter" row');
        expect(m(brand, longer, '$longer 2 0 (150 Hp)'), isTrue);
      }
    });

    test('over the whole catalog ONLY the 19 intended families change', () {
      final brandsById = {
        for (final b in (spec['brands'] as List).cast<Map<String, dynamic>>())
          b['id']: b['name'] as String,
      };
      final rowsByBrandLower = <String, List<String>>{};
      final rowsByBrandSpaced = <String, List<String>>{};
      for (final r in (spec['models'] as List).cast<Map<String, dynamic>>()) {
        final b = brandsById[r['brand_id']]!;
        rowsByBrandLower.putIfAbsent(b.toLowerCase().trim(), () => []).add(r['name'] as String);
        rowsByBrandSpaced.putIfAbsent(carSpecSpacedNameKey(b), () => []).add(r['name'] as String);
      }
      bool legacy(String dn, String fam) {
        final d = dn.trim().toLowerCase();
        final f = fam.trim().toLowerCase();
        if (d.isEmpty || f.isEmpty) return false;
        return d == f || d.startsWith('$f ') || d.split(RegExp(r'\s+')).first == f;
      }

      final changed = <(String, String)>[];
      final models = (catalogJson['models'] as Map<String, dynamic>);
      for (final b in models.entries) {
        final oldRows = rowsByBrandLower[b.key.toLowerCase().trim()] ?? const <String>[];
        final newRows = rowsByBrandSpaced[carSpecSpacedNameKey(b.key)] ?? const <String>[];
        for (final mo in (b.value as List).cast<String>()) {
          final before = oldRows.where((n) => legacy(n, mo)).toSet();
          final after = newRows.where((n) => carSpecDatasetNameMatchesFamily(b.key, mo, n)).toSet();
          expect(after.containsAll(before), isTrue,
              reason: '${b.key} $mo lost rows');
          if (after.length != before.length) {
            changed.add((b.key, mo));
            expect(before, isEmpty,
                reason: '${b.key} $mo: only previously-unresolved families may change');
          }
        }
      }
      expect(changed.toSet(), gapModels.toSet());
    });
  });

  // ------------------------------------------------------------------ the 19
  group('the 19 matcher-gap models resolve in the app', () {
    test('every one is covered by the legacy CarNet spec dataset now', () {
      for (final (b, mo) in gapModels) {
        expect(plainIdx.hasCoverage(b, mo), isTrue, reason: '$b $mo');
      }
    });

    test('BMW 4-Series: CarNet baseline [3,4,6] + IQ [4,6]', () {
      final base = cyls(plainIdx.homeFilterFieldOptions('BMW', '4-Series', ''));
      expect(base, {'3', '4', '6'});
      expect(overlay.additionsFor('BMW', '4-Series')!.cylinders, [4, 6]);
      expect(cyls(iqIdx.homeFilterFieldOptions('BMW', '4-Series', '')), {'3', '4', '6'});
      expect(search(iqIdx, 'BMW', '4-Series').cylinderCounts, ['Any', '3', '4', '6']);
      // Model-level: the year (2020) does not narrow the cylinder options.
      expect(sell(iqIdx, 'BMW', '4-Series', 2020).cylinders, ['3', '4', '6']);
    });

    test('BMW 5-Series: CarNet [4,6,8] + FULL IQ [4,6,8,10] -> 4,6,8,10', () {
      expect(cyls(plainIdx.homeFilterFieldOptions('BMW', '5-Series', '')), {'4', '6', '8'});
      expect(overlay.additionsFor('BMW', '5-Series')!.cylinders, [4, 6, 8, 10]);
      expect(search(iqIdx, 'BMW', '5-Series').cylinderCounts,
          ['Any', '4', '6', '8', '10']);
      expect(sell(iqIdx, 'BMW', '5-Series', 2020).cylinders, ['4', '6', '8', '10']);
    });

    test('BMW 6-Series: same union semantics', () {
      final base = cyls(plainIdx.homeFilterFieldOptions('BMW', '6-Series', ''));
      final iq = overlay.additionsFor('BMW', '6-Series')!.cylinders.map((c) => '$c');
      expect(overlay.additionsFor('BMW', '6-Series')!.cylinders, [6, 8, 10]);
      expect(cyls(iqIdx.homeFilterFieldOptions('BMW', '6-Series', '')), {...base, ...iq});
      expect(search(iqIdx, 'BMW', '6-Series').cylinderCounts,
          ['Any', ...({...base, ...iq}.toList()..sort((a, b) => int.parse(a).compareTo(int.parse(b))))]);
    });

    test('Cadillac ATS-V / CTS-V, Rolls Royce and Ram 2500 get CarNet baselines', () {
      expect(cyls(plainIdx.homeFilterFieldOptions('Cadillac', 'ATS-V', '')), isNotEmpty);
      expect(cyls(plainIdx.homeFilterFieldOptions('Cadillac', 'CTS-V', '')), isNotEmpty);
      expect(cyls(plainIdx.homeFilterFieldOptions('Rolls Royce', 'Phantom', '')), contains('12'));
      expect(cyls(plainIdx.homeFilterFieldOptions('Ram', '2500', '')), {'6', '8'});
      for (final (b, mo) in gapModels) {
        final base = cyls(plainIdx.homeFilterFieldOptions(b, mo, ''));
        final iq = (overlay.additionsFor(b, mo)?.cylinders ?? const <int>[]).map((c) => '$c');
        final eff = cyls(iqIdx.homeFilterFieldOptions(b, mo, ''));
        expect(eff, {...base, ...iq}, reason: '$b $mo effective = baseline UNION IQ');
      }
    });
  });

  // ------------------------------------------------------------------ overlay
  group('runtime overlay: FULL trusted cylinder sets, unioned in the app', () {
    Set<String> merged(IqCarsOverlay o, Set<String> baseline, String b, String m) {
      final s = {...baseline};
      o.addCylinderCounts(s, b, m);
      return s;
    }

    test('format 3 `cylinders` is read; legacy `cylinders_add` still is', () {
      final o = IqCarsOverlay.parse(
        '{"X":{"A":{"cylinders":[4,6,8,10]},"B":{"cylinders_add":[10]}}}',
      );
      expect(o.additionsFor('X', 'A')!.cylinders, [4, 6, 8, 10]);
      expect(o.additionsFor('X', 'B')!.cylinders, [10]);
    });

    test('empty baseline + FULL IQ set -> the whole set', () {
      final o = IqCarsOverlay.parse('{"X":{"A":{"cylinders":[4,6,8,10]}}}');
      expect(merged(o, <String>{}, 'X', 'A'), {'4', '6', '8', '10'});
    });

    test('populated baseline + overlapping IQ set -> union, duplicates removed', () {
      final o = IqCarsOverlay.parse('{"X":{"A":{"cylinders":[4,6,8,10,10,4]}}}');
      expect(o.additionsFor('X', 'A')!.cylinders, [4, 6, 8, 10]);
      expect(merged(o, {'4', '6', '8'}, 'X', 'A'), {'4', '6', '8', '10'});
    });

    test('rare legitimate counts survive; nothing is invented or removed', () {
      final o = IqCarsOverlay.parse(
        '{"X":{"A":{"cylinders":[1]},"B":{"cylinders":[2,4]},"C":{"cylinders":[16]},'
        '"D":{"cylinders":[10,12]}}}',
      );
      expect(merged(o, <String>{}, 'X', 'A'), {'1'});
      expect(merged(o, {'3'}, 'X', 'B'), {'2', '3', '4'});
      expect(merged(o, <String>{}, 'X', 'C'), {'16'});
      expect(merged(o, {'8'}, 'X', 'D'), {'8', '10', '12'});
      expect(merged(o, {'8'}, 'X', 'Missing'), {'8'});
    });

    test('malformed entries are ignored', () {
      final o = IqCarsOverlay.parse(
        '{"X":{"A":{"cylinders":["x",0,-3,null,6]}}}',
      );
      expect(o.additionsFor('X', 'A')!.cylinders, [6]);
    });

    test('real asset: BMW 5-Series carries the FULL set, never the diff [10]', () {
      expect(overlay.additionsFor('BMW', '5-Series')!.cylinders, [4, 6, 8, 10]);
      expect(overlay.additionsFor('BMW', '4-Series')!.cylinders, [4, 6]);
    });

    test('Geely Cityray is quarantined: it never gains 3 cylinders', () {
      expect(overlay.additionsFor('Geely', 'Cityray')?.cylinders ?? const <int>[],
          isNot(contains(3)));
      for (final idx in [plainIdx, iqIdx]) {
        expect(cyls(idx.homeFilterFieldOptions('Geely', 'Cityray', '')), isNot(contains('3')));
        expect(cyls(idx.iqOnlyFieldOptions('Geely', 'Cityray', CarSpecIndex.catalogAutofillModelOnly)),
            isNot(contains('3')));
      }
      expect(search(iqIdx, 'Geely', 'Cityray').cylinderCounts, isNot(contains('3')));
      expect(overlay.approvedCylinderLabels('Geely', 'Cityray'), isNot(contains('3')));
    });

    test('contaminated default-list models never export cylinders', () {
      final exc = jsonDecode(File(
        'tools/catalog_enrichment/iqcars/generated/carnet_iqcars_overlay_exclusions.json',
      ).readAsStringSync()) as Map<String, dynamic>;
      final dflt = (exc['unrestricted_default_cylinder_lists'] as List).cast<Map<String, dynamic>>();
      expect(dflt, isNotEmpty);
      for (final e in dflt) {
        expect(overlay.additionsFor('${e['brand']}', '${e['model']}')?.cylinders ?? const <int>[],
            isEmpty, reason: '${e['brand']} ${e['model']}');
      }
    });
  });

  // ------------------------------------------------------------------ engines
  group('engine semantics are unchanged (displacement + qualifier)', () {
    test('Prado keeps both 2.4 D and 2.4 T; Land Cruiser stays a separate entry', () {
      final eng = iqIdx.homeFilterFieldOptions('Toyota', 'Land Cruiser Prado', '')!.engineSizes;
      expect(eng, containsAll(<String>['2.4 D', '2.4 T']));
      expect(overlay.additionsFor('Toyota', 'Land Cruiser'),
          isNot(same(overlay.additionsFor('Toyota', 'Land Cruiser Prado'))));
      expect(overlay.additionsFor('Toyota', 'Land Cruiser Prado')!.engineVariants.map((v) => v.label),
          contains('2.4 T'));
    });

    test('BMW 5-Series engines carry IQ qualifier variants', () {
      final eng = iqIdx.homeFilterFieldOptions('BMW', '5-Series', '')!.engineSizes;
      expect(eng, containsAll(<String>['3.0', '3.0 T', '3.0 TD']));
    });
  });

  // ------------------------------------------------------------------ Search
  group('Search: engine/cylinder for a selected Brand + Model', () {
    test('no trusted data anywhere -> only `Any` (not the generic ladder)', () {
      for (final (b, mo) in const [
        ('Toyota', 'bZ4X'),
        ('Kia', 'EV6'),
      ]) {
        final pre = iqIdx.homeFilterFieldOptions(b, mo, '');
        expect(pre?.cylinderCounts ?? <String>{}, isEmpty,
            reason: 'precondition: $b $mo has no trusted cylinder data');
        expect(pre?.engineSizes ?? <String>{}, isEmpty,
            reason: 'precondition: $b $mo has no trusted engine data');
        final o = search(iqIdx, b, mo);
        expect(o.cylinderCounts, ['Any'], reason: '$b $mo');
        expect(o.engineSizes, ['Any'], reason: '$b $mo');
        expect(o.narrowedFields,
            containsAll(<HomeVehicleField>[HomeVehicleField.cylinderCount, HomeVehicleField.engineSize]));
        // other fields keep their defaults
        expect(o.bodyTypes, defaults().bodyTypes);
      }
    });

    test('before a model is selected (or index not ready) the generic ladder stays', () {
      final o = search(iqIdx, 'Toyota', 'bZ4X', vehicleResolved: false);
      expect(o.cylinderCounts, searchCylinderDefaults);
      expect(o.engineSizes, searchEngineDefaults);
      final none = HomeVehicleFieldOptions.resolve(
        catalog: null,
        engineCatalog: null,
        defaults: defaults(),
      );
      expect(none.cylinderCounts, searchCylinderDefaults);
      expect(none.engineSizes, searchEngineDefaults);
    });

    test('trusted CarNet-only, IQ-only and union models show the effective union', () {
      // CarNet only (no IQ cylinders)
      final carnetOnly = search(plainIdx, 'BMW', '5-Series');
      expect(carnetOnly.cylinderCounts, ['Any', '4', '6', '8']);
      // union
      expect(search(iqIdx, 'BMW', '5-Series').cylinderCounts, ['Any', '4', '6', '8', '10']);
      // IQ-only (no legacy coverage)
      expect(plainIdx.hasCoverage('Bugatti', 'Veyron'), isFalse);
      expect(search(iqIdx, 'Bugatti', 'Veyron').cylinderCounts, ['Any', '16']);
    });

    test('a selected trim never changes the model-level IQ values', () {
      final trim = CarCatalog.trimsFor('BMW', '5-Series').first;
      final x = iqIdx.homeFilterFieldOptions('BMW', '5-Series', '');
      final y = iqIdx.homeFilterFieldOptions('BMW', '5-Series', trim);
      expect(y?.cylinderCounts, x?.cylinderCounts);
      expect(y?.engineSizes, x?.engineSizes);
    });
  });

  // ------------------------------------------------------------------ Sell
  group('Sell: narrows to the effective union, else keeps the manual default ladder', () {
    test('neither source has data -> the existing default Sell ladder (EV included)', () {
      final r = sell(iqIdx, 'Toyota', 'bZ4X', 2024);
      expect(r.cylinders, sellCylinderDefaults);
      expect(r.engines, ['<full default ladder>']);
    });

    test('empty CarNet baseline + FULL IQ set is the whole set (not just the diff)', () {
      final modelsWithEmptyBaseline = <(String, String)>[];
      for (final b in overlay.entries) {
        for (final m in b.value.entries) {
          if (m.value.cylinders.length < 2) continue;
          if (!plainIdx.hasCoverage(b.key, m.key) ||
              cyls(plainIdx.homeFilterFieldOptions(b.key, m.key, '')).isEmpty) {
            modelsWithEmptyBaseline.add((b.key, m.key));
          }
        }
      }
      expect(modelsWithEmptyBaseline, isNotEmpty);
      for (final (b, mo) in modelsWithEmptyBaseline) {
        final want = overlay.additionsFor(b, mo)!.cylinders.map((c) => '$c').toSet();
        final got = cyls(iqIdx.homeFilterFieldOptions(b, mo, '') ??
            iqIdx.iqOnlyFieldOptions(b, mo, CarSpecIndex.catalogAutofillModelOnly));
        expect(got, want, reason: '$b $mo');
      }
    });

    test('rare IQ counts bypass the generic 3-12 clamp only when approved', () {
      expect(sell(iqIdx, 'Bugatti', 'Veyron', 2012).cylinders, ['16']);
      expect(sell(iqIdx, 'Polaris', 'Ranger 570', 2020).cylinders, ['1']);
    });
  });
}
