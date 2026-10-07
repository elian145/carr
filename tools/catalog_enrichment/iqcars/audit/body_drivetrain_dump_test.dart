// READ-ONLY audit probe (lives under tools/, not picked up by plain `flutter test`).
//
//   flutter test tools/catalog_enrichment/iqcars/audit/body_drivetrain_dump_test.dart
//
// Runs the REAL app resolvers over the REAL bundled assets and writes
// `_body_drive_probe.json` (repo root, temporary) with:
//
//   * `combos`: for every distinct (body_type, drivetrain, Traction:, fuel, transmission) tuple of
//     the dataset, the app value produced by the app's own `_mapSpecToFormFields` (a one-row
//     synthetic dataset is built per tuple and read back through `homeFilterFieldOptions`).
//   * `models`: for EVERY brand + model of the bundled catalog: the dataset family names
//     (post sibling isolation + reviewed exclusions), the baseline / effective sets, and the
//     real Search lists (real default ladders from home_page.dart) for body and drivetrain.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

const searchBodyLadder = [
  'Any', 'Sedan', 'SUV', 'Hatchback', 'Coupe', 'Convertible', 'Wagon', 'Pickup', 'Van', 'Minivan', //
];
const searchDriveLadder = ['Any', 'FWD', 'RWD', 'AWD'];

String code(int i) {
  // unique, non-prefix names: Zaaa, Zaab, ...
  final a = String.fromCharCode(97 + (i ~/ 676) % 26);
  final b = String.fromCharCode(97 + (i ~/ 26) % 26);
  final c = String.fromCharCode(97 + i % 26);
  return 'Z$a$b$c';
}

void main() {
  test('dump body/drivetrain provenance', () {
    final raw = File('assets/car_spec_dataset.json').readAsStringSync();
    final spec = jsonDecode(raw) as Map<String, dynamic>;
    final catalogJson =
        jsonDecode(File('assets/car_catalog.json').readAsStringSync()) as Map<String, dynamic>;
    final overlay = IqCarsOverlay.parse(File('assets/car_iqcars_overlay.json').readAsStringSync());
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalog.applyCatalogFromAsset(catalogJson);

    // ---------- 1. combos ----------
    final specs = (spec['specs'] as List).cast<Map<String, dynamic>>();
    String key(Map<String, dynamic> s) => jsonEncode([
          s['body_type'],
          s['drivetrain'],
          (s['raw_spec_pairs'] as Map?)?['Traction:'],
          s['fuel_type'],
          s['transmission'],
        ]);
    final seen = <String, Map<String, dynamic>>{};
    final counts = <String, int>{};
    for (final s in specs) {
      final k = key(s);
      seen.putIfAbsent(k, () => s);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final comboModels = <Map<String, dynamic>>[];
    final comboTrims = <Map<String, dynamic>>[];
    final comboSpecs = <Map<String, dynamic>>[];
    final keys = seen.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      final s = seen[keys[i]]!;
      comboModels.add({'id': i + 1, 'brand_id': 1, 'name': code(i)});
      comboTrims.add({'id': i + 1, 'model_id': i + 1, 'year': 2000, 'year_end': 2001, 'name': code(i)});
      comboSpecs.add({
        'trim_id': i + 1,
        'raw_spec_pairs': s['raw_spec_pairs'],
        'fuel_type': s['fuel_type'],
        'transmission': s['transmission'],
        'drivetrain': s['drivetrain'],
        'body_type': s['body_type'],
        'seats': 5,
        'displacement_cc': 1998,
      });
    }
    final comboIdx = parseCarSpecDatasetJsonString(jsonEncode({
      'brands': [
        {'id': 1, 'name': 'ZBrand'},
      ],
      'models': comboModels,
      'trims': comboTrims,
      'specs': comboSpecs,
    })).index!;
    final combos = <Map<String, dynamic>>[];
    for (var i = 0; i < keys.length; i++) {
      final o = comboIdx.homeFilterFieldOptions('ZBrand', code(i), '');
      final s = seen[keys[i]]!;
      combos.add({
        'body_raw': s['body_type'],
        'drivetrain_raw': s['drivetrain'],
        'traction_raw': (s['raw_spec_pairs'] as Map?)?['Traction:'],
        'fuel_raw': s['fuel_type'],
        'transmission_raw': s['transmission'],
        'rows': counts[keys[i]],
        'app_body': (o?.bodyTypes.toList() ?? <String>[])..sort(),
        'app_drive': (o?.driveTypes.toList() ?? <String>[])..sort(),
        'app_fuel': (o?.fuelTypes.toList() ?? <String>[])..sort(),
        'app_transmission': (o?.transmissions.toList() ?? <String>[])..sort(),
      });
    }

    // ---------- 2. every catalog model ----------
    final plain = parseCarSpecDatasetJsonString(raw).index!;
    final iq = parseCarSpecDatasetJsonString(raw).index!..attachIqCarsOverlay(overlay);
    const defaults = HomeVehicleFieldDefaults(
      bodyTypes: searchBodyLadder,
      transmissions: ['Any', 'Automatic', 'Manual'],
      fuelTypes: ['Any', 'Gasoline', 'Diesel', 'Electric', 'Hybrid'],
      driveTypes: searchDriveLadder,
      cylinderCounts: ['Any'],
      seatings: ['Any', '2', '4', '5', '6', '7', '8'],
      engineSizes: ['Any'],
    );
    final models = <Map<String, dynamic>>[];
    final catModels = catalogJson['models'] as Map<String, dynamic>;
    for (final be in catModels.entries) {
      for (final m in (be.value as List).cast<String>()) {
        final b = be.key;
        final ctx = HomeVehicleContext(brand: b, model: m);
        final s = HomeVehicleFieldOptions.resolve(
          catalog: resolveHomeVehicleCatalogOptions(iq, ctx),
          engineCatalog: resolveHomeVehicleEngineCatalogOptions(iq, ctx),
          defaults: defaults,
          vehicleResolved: true,
        );
        final base = plain.homeFilterFieldOptions(b, m, '');
        models.add({
          'brand': b,
          'model': m,
          'has_coverage': plain.hasCoverage(b, m),
          // ignore: invalid_use_of_visible_for_testing_member
          'family_names': (plain.debugFamilyDatasetModelNames(b, m).toSet().toList()..sort()),
          'baseline_null': base == null,
          'baseline_body': (base?.bodyTypes.toList() ?? <String>[])..sort(),
          'baseline_drive': (base?.driveTypes.toList() ?? <String>[])..sort(),
          'search_body': s.bodyTypes,
          'search_drive': s.driveTypes,
          'search_body_narrowed': s.narrowedFields.contains(HomeVehicleField.bodyType),
          'search_drive_narrowed': s.narrowedFields.contains(HomeVehicleField.driveType),
        });
      }
    }
    File('_body_drive_probe.json').writeAsStringSync(
      const JsonEncoder().convert({'combos': combos, 'models': models}),
    );
    // ignore: avoid_print
    print('combos=${combos.length} models=${models.length}');
    CarCatalog.resetCatalogOverrideForTest();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
