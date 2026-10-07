// READ-ONLY audit probe (not part of the app and not picked up by `flutter test`
// with no arguments, because it lives under tools/). Run explicitly:
//
//   flutter test tools/catalog_enrichment/iqcars/audit/effective_options_dump_test.dart
//
// For EVERY Brand + Model of the bundled CarNet catalog it records what the app
// really offers, by calling the SAME resolvers the Search and Sell screens call:
//
//   * baseline : CarSpecIndex WITHOUT the IQ overlay
//   * effective: CarSpecIndex WITH the runtime overlay attached
//   * Search   : HomeVehicleFieldOptions.resolve over the real default ladders
//   * Sell     : narrowCylinderOptionsToCatalog over the real Sell 3-12 ladder
//
// Output: tools/catalog_enrichment/iqcars/generated/iqcars_audit_effective_options.json
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

const searchCylinderDefaults = [
  'Any', '1', '2', '3', '4', '5', '6', '8', '10', '12', '16', //
];
const sellCylinderDefaults = ['3', '4', '5', '6', '8', '10', '12'];
const genericEngineMarker = <String>['Any', '<GENERIC_ENGINE_LADDER>'];

List<String> sortedNum(Iterable<String> v) =>
    v.toList()..sort((a, b) => (int.tryParse(a) ?? 999).compareTo(int.tryParse(b) ?? 999));

void main() {
  test('dump effective options for every catalog model', () {
    final raw = File('assets/car_spec_dataset.json').readAsStringSync();
    final catalogJson = jsonDecode(File('assets/car_catalog.json').readAsStringSync())
        as Map<String, dynamic>;
    final overlay = IqCarsOverlay.parse(
      File('assets/car_iqcars_overlay.json').readAsStringSync(),
    );
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalog.applyCatalogFromAsset(catalogJson);

    final plain = parseCarSpecDatasetJsonString(raw).index!;
    final iq = parseCarSpecDatasetJsonString(raw).index!..attachIqCarsOverlay(overlay);

    HomeVehicleFieldDefaults defaults() => const HomeVehicleFieldDefaults(
          bodyTypes: ['Any'],
          transmissions: ['Any'],
          fuelTypes: ['Any'],
          driveTypes: ['Any'],
          cylinderCounts: searchCylinderDefaults,
          seatings: ['Any'],
          engineSizes: genericEngineMarker,
        );

    HomeVehicleFieldOptions search(CarSpecIndex idx, String b, String m) {
      final ctx = HomeVehicleContext(brand: b, model: m);
      return HomeVehicleFieldOptions.resolve(
        catalog: resolveHomeVehicleCatalogOptions(idx, ctx),
        engineCatalog: resolveHomeVehicleEngineCatalogOptions(idx, ctx),
        defaults: defaults(),
        // Brand + Model selected on a loaded index (every catalog model is a known model).
        vehicleResolved: true,
      );
    }

    final out = <Map<String, dynamic>>[];
    final models = (catalogJson['models'] as Map<String, dynamic>);
    for (final be in models.entries) {
      for (final m in (be.value as List).cast<String>()) {
        final b = be.key;
        final baseHome = plain.homeFilterFieldOptions(b, m, '');
        final effHome = iq.homeFilterFieldOptions(b, m, '');
        final sBase = search(plain, b, m);
        final sEff = search(iq, b, m);

        final effCyl = effHome?.cylinderCounts ?? const <String>{};
        final effIqCyl = effHome?.iqCylinderCounts ?? const <String>{};
        final sellEff = narrowCylinderOptionsToCatalog(
          sellCylinderDefaults,
          effCyl,
          effIqCyl,
        );
        final sellBase = narrowCylinderOptionsToCatalog(
          sellCylinderDefaults,
          baseHome?.cylinderCounts,
          const <String>{},
        );

        // Sell step 2 resolves per catalog year; count the years that fall back.
        final years = iq.yearsForCatalogStep(b, m, '');
        var yearsEmptyCyl = 0, yearsNull = 0;
        for (final y in years) {
          final o = iq.sellFieldOptionsUnion(
            b, m, CarSpecIndex.catalogAutofillModelOnly, y,
          );
          if (o == null) {
            yearsNull++;
          } else if (o.cylinderCounts.isEmpty) {
            yearsEmptyCyl++;
          }
        }

        out.add({
          'brand': b,
          'model': m,
          'has_coverage': plain.hasCoverage(b, m),
          // ignore: invalid_use_of_visible_for_testing_member
          'family_rows': (plain.debugFamilyDatasetModelNames(b, m).toList()..sort()),
          'baseline_other': {
            'body': (baseHome?.bodyTypes.toList() ?? <String>[])..sort(),
            'fuel': (baseHome?.fuelTypes.toList() ?? <String>[])..sort(),
            'drive': (baseHome?.driveTypes.toList() ?? <String>[])..sort(),
            'transmission': (baseHome?.transmissions.toList() ?? <String>[])..sort(),
            'seating': (baseHome?.seatings.toList() ?? <String>[])..sort(),
          },
          'baseline_home_null': baseHome == null,
          'baseline_cylinders': sortedNum(baseHome?.cylinderCounts ?? const <String>{}),
          'baseline_engines': sortCatalogEngineSizeLabels(baseHome?.engineSizes ?? const <String>{}),
          'effective_home_null': effHome == null,
          'effective_cylinders': sortedNum(effCyl),
          'effective_iq_cylinders': sortedNum(effIqCyl),
          'effective_engines': sortCatalogEngineSizeLabels(effHome?.engineSizes ?? const <String>{}),
          'search_baseline_cylinders': sBase.cylinderCounts,
          'search_cylinders': sEff.cylinderCounts,
          'search_cylinders_generic': sEff.cylinderCounts.length == searchCylinderDefaults.length &&
              !sEff.narrowedFields.contains(HomeVehicleField.cylinderCount),
          'search_cylinders_any_only': sEff.cylinderCounts.length == 1,
          'search_engines_any_only': sEff.engineSizes.length == 1,
          'search_baseline_cylinders_generic': !sBase.narrowedFields.contains(HomeVehicleField.cylinderCount),
          'search_engines': sEff.engineSizes,
          'search_engines_generic': !sEff.narrowedFields.contains(HomeVehicleField.engineSize),
          'search_baseline_engines_generic': !sBase.narrowedFields.contains(HomeVehicleField.engineSize),
          'sell_cylinders': sellEff,
          'sell_baseline_cylinders': sellBase,
          'sell_cylinders_generic': sellEff.length == sellCylinderDefaults.length &&
              (effCyl.isEmpty || !effCyl.any(sellCylinderDefaults.contains)),
          'sell_years': years.length,
          'sell_years_null': yearsNull,
          'sell_years_empty_cylinders': yearsEmptyCyl,
        });
      }
    }
    final file = File(
      'tools/catalog_enrichment/iqcars/generated/iqcars_audit_effective_options.json',
    );
    file.writeAsStringSync(const JsonEncoder().convert({'models': out}));
    // ignore: avoid_print
    print('dumped ${out.length} models -> ${file.path}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
