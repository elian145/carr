// READ-ONLY diagnostic probe (lives under tools/, not picked up by plain `flutter test`).
//
//   flutter test tools/catalog_enrichment/iqcars/audit/provenance_probe_test.dart
//
// For Toyota Corolla / Land Cruiser / Land Cruiser Prado it runs the REAL app
// resolvers over the REAL bundled assets and writes, per model:
//   * the dataset rows of the family exactly as `_familyModels` accepts them, each with the
//     engine label(s) THAT ROW alone produces (a one-row index is built per row so the label
//     is the app's own `_mapSpecToFormFields` output),
//   * BASELINE engines (CarNet only), IQ engines (overlay only), SEARCH effective, SELL effective,
//   * the same engine sets per selected model year (no year / earliest / representative / latest).
// Output: _provenance_probe.json in the repo root (temporary).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

const targets = <(String, String)>[
  ('Toyota', 'Corolla'),
  ('Toyota', 'Land Cruiser'),
  ('Toyota', 'Land Cruiser Prado'),
];

void main() {
  test('provenance probe', () {
    final specRaw = File('assets/car_spec_dataset.json').readAsStringSync();
    final spec = jsonDecode(specRaw) as Map<String, dynamic>;
    final catalogJson =
        jsonDecode(File('assets/car_catalog.json').readAsStringSync()) as Map<String, dynamic>;
    final overlay = IqCarsOverlay.parse(File('assets/car_iqcars_overlay.json').readAsStringSync());
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalog.applyCatalogFromAsset(catalogJson);

    final plain = parseCarSpecDatasetJsonString(specRaw).index!;
    final iq = parseCarSpecDatasetJsonString(specRaw).index!..attachIqCarsOverlay(overlay);

    final brands = {for (final b in (spec['brands'] as List)) (b as Map)['id']: b['name'] as String};
    final models = (spec['models'] as List).cast<Map<String, dynamic>>();
    final trimsByModel = <int, List<Map<String, dynamic>>>{};
    for (final t in (spec['trims'] as List).cast<Map<String, dynamic>>()) {
      (trimsByModel[t['model_id'] as int] ??= []).add(t);
    }
    final specByTrim = {
      for (final s in (spec['specs'] as List).cast<Map<String, dynamic>>()) s['trim_id'] as int: s,
    };

    const defaults = HomeVehicleFieldDefaults(
      bodyTypes: ['Any'],
      transmissions: ['Any'],
      fuelTypes: ['Any'],
      driveTypes: ['Any'],
      cylinderCounts: ['Any', '1', '2', '3', '4', '5', '6', '8', '10', '12', '16'],
      seatings: ['Any'],
      engineSizes: ['Any', '<GENERIC>'],
    );

    List<String> sorted(Iterable<String> v) => sortCatalogEngineSizeLabels(v.toSet());

    HomeVehicleFieldOptions search(CarSpecIndex idx, String b, String m) {
      final ctx = HomeVehicleContext(brand: b, model: m);
      return HomeVehicleFieldOptions.resolve(
        catalog: resolveHomeVehicleCatalogOptions(idx, ctx),
        engineCatalog: resolveHomeVehicleEngineCatalogOptions(idx, ctx),
        defaults: defaults,
        vehicleResolved: true,
      );
    }

    final out = <String, dynamic>{};
    for (final (b, m) in targets) {
      // ignore: invalid_use_of_visible_for_testing_member
      final famNames = plain.debugFamilyDatasetModelNames(b, m).toSet();
      final rows = <Map<String, dynamic>>[];
      for (final r in models) {
        if (brands[r['brand_id']] != b) continue;
        final name = r['name'] as String;
        if (!famNames.contains(name)) continue;
        final trims = trimsByModel[r['id']] ?? const [];
        final specs = [for (final t in trims) if (specByTrim[t['id']] != null) specByTrim[t['id']]!];
        // engine label(s) produced by THIS row alone (one-row index, same resolver)
        final mini = <String, dynamic>{
          'brands': (spec['brands'] as List).where((x) => (x as Map)['id'] == r['brand_id']).toList(),
          'models': [r],
          'trims': trims,
          'specs': specs,
        };
        final one = parseCarSpecDatasetJsonString(jsonEncode(mini)).index!;
        final o = one.homeFilterFieldOptions(b, m, '');
        rows.add({
          'dataset_model_id': r['id'],
          'raw_name': name,
          'years': [for (final t in trims) '${t['year']}-${t['year_end']}'],
          'fuel': {for (final s in specs) s['fuel_type']}.toList(),
          'displacement_cc': {for (final s in specs) s['displacement_cc']}.toList(),
          'cylinders_raw': {for (final s in specs) (s['raw_spec_pairs'] as Map?)?['Cylinders alignment:']}.toList(),
          'row_engine_labels': sorted(o?.engineSizes ?? const <String>{}),
          'row_cylinders': (o?.cylinderCounts ?? const <String>{}).toList()..sort(),
        });
      }

      final base = plain.homeFilterFieldOptions(b, m, '');
      final iqEng = <String>{};
      final iqCyl = <String>{};
      overlay.addEngineSizes(iqEng, b, m);
      overlay.addCylinderCounts(iqCyl, b, m);
      final eff = iq.homeFilterFieldOptions(b, m, '');
      final s = search(iq, b, m);
      final sBase = search(plain, b, m);

      final years = iq.yearsForCatalogStep(b, m, '');
      final perYear = <String, dynamic>{};
      final probeYears = <int>{
        if (years.isNotEmpty) years.first,
        if (years.isNotEmpty) years.last,
        for (final y in [1995, 2005, 2015, 2024, 2025]) if (years.contains(y)) y,
      }.toList()..sort();
      for (final y in probeYears) {
        final o = iq.sellFieldOptionsUnion(b, m, CarSpecIndex.catalogAutofillModelOnly, y);
        final ob = plain.sellFieldOptionsUnion(b, m, CarSpecIndex.catalogAutofillModelOnly, y);
        perYear['$y'] = {
          'sell_engines_effective': sorted(o?.engineSizes ?? const <String>{}),
          'sell_engines_baseline_only': sorted(ob?.engineSizes ?? const <String>{}),
          'sell_cylinders_effective': (o?.cylinderCounts ?? const <String>{}).toList()..sort(),
        };
      }
      // per-year engines for EVERY supported year (to see where each value appears)
      final engineYears = <String, List<int>>{};
      for (final y in years) {
        final ob = plain.sellFieldOptionsUnion(b, m, CarSpecIndex.catalogAutofillModelOnly, y);
        for (final e in (ob?.engineSizes ?? const <String>{})) {
          (engineYears[e] ??= []).add(y);
        }
      }

      out['$b|$m'] = {
        // ignore: invalid_use_of_visible_for_testing_member
        'family_row_count': plain.debugFamilyDatasetModelNames(b, m).length,
        'catalog_longer_siblings': [
          for (final x in (catalogJson['models'] as Map)[b] as List)
            if ((x as String).toLowerCase().startsWith('${m.toLowerCase()} ')) x,
        ],
        'years_supported': years.isEmpty ? [] : [years.first, years.last],
        'baseline_engines': sorted(base?.engineSizes ?? const <String>{}),
        'baseline_cylinders': (base?.cylinderCounts ?? const <String>{}).toList()..sort(),
        'iq_engines': sorted(iqEng),
        'iq_cylinders': iqCyl.toList()..sort(),
        'effective_model_level_engines': sorted(eff?.engineSizes ?? const <String>{}),
        'search_effective_engines': s.engineSizes,
        'search_effective_cylinders': s.cylinderCounts,
        'search_baseline_only_engines': sBase.engineSizes,
        'sell_effective_engines_no_year_union': sorted(eff?.engineSizes ?? const <String>{}),
        'sell_per_year': perYear,
        'baseline_engine_years': {for (final e in engineYears.entries) e.key: [e.value.first, e.value.last, e.value.length]},
        'rows': rows,
      };
    }
    File('_provenance_probe.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    // ignore: avoid_print
    print('wrote _provenance_probe.json');
    CarCatalog.resetCatalogOverrideForTest();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
