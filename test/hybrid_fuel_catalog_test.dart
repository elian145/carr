import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/features/home/home_filters_query.dart';
import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';
import 'package:car_listing_app/shared/i18n/listing_value_labels.dart';
import 'package:car_listing_app/shared/listings/listing_to_sell_draft.dart';

/// Hybrid / Plug-in Hybrid are first-class fuel options.
///
/// The bundled spec dataset only carries Petrol / Diesel / Electric in its
/// `fuel_type` field; the hybrid evidence lives in the row / trim names and in
/// "Electric + a combustion engine". The shared mapper
/// (`classifyCatalogFuelKey`) turns that into `Hybrid` / `Plug-in Hybrid`, so
/// Sell and Search (same resolver) both offer them.
void main() {
  late CarSpecIndex idx;

  setUpAll(() {
    CarCatalog.applyCatalogFromAsset(
      jsonDecode(File('assets/car_catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    idx = parseCarSpecDatasetJsonString(
      File('assets/car_spec_dataset.json').readAsStringSync(),
    ).index!
      ..attachIqCarsOverlay(IqCarsOverlay.parse(
        File('assets/car_iqcars_overlay.json').readAsStringSync(),
      ));
  });

  tearDownAll(CarCatalog.resetCatalogOverrideForTest);

  Set<String> sellFuels(String brand, String model, [int year = 2022]) =>
      idx
          .sellFieldOptionsUnion(
            brand,
            model,
            CarSpecIndex.catalogAutofillModelOnly,
            year,
          )!
          .fuelTypes
          .toSet();

  // The Search page's own default ladder (home_page.dart).
  const searchFuelDefaults = [
    'Any',
    'Gasoline',
    'Diesel',
    'Electric',
    'Hybrid',
    'Plug-in Hybrid',
  ];

  Set<String> searchFuels(String brand, String model) {
    final ctx = HomeVehicleContext(brand: brand, model: model);
    final o = HomeVehicleFieldOptions.resolve(
      catalog: resolveHomeVehicleCatalogOptions(idx, ctx),
      engineCatalog: resolveHomeVehicleEngineCatalogOptions(idx, ctx),
      defaults: const HomeVehicleFieldDefaults(
        bodyTypes: ['Any'],
        transmissions: ['Any'],
        fuelTypes: searchFuelDefaults,
        driveTypes: ['Any'],
        cylinderCounts: ['Any'],
        seatings: ['Any'],
        engineSizes: ['Any'],
      ),
      vehicleResolved: true,
    );
    return o.fuelTypes.where((e) => e != 'Any').toSet();
  }

  group('canonical classification', () {
    test('hybrid wording -> hybrid, plug-in wording -> plug-in hybrid', () {
      String c(String label, {String fuel = 'Petrol (Gasoline)', bool ice = true}) =>
          classifyCatalogFuelKey(
            datasetFuel: fuel,
            label: label,
            hasCombustionEngine: ice,
          );
      expect(c('Corolla 1.8 Hybrid'), kFuelHybrid);
      expect(c('Prius 1.8 HSD'), kFuelHybrid);
      expect(c('Camry 2.5 HEV'), kFuelHybrid);
      expect(c('Prius Prime 1.8 Plug-in Hybrid'), kFuelPlugInHybrid);
      expect(c('Sportage 1.6 PHEV'), kFuelPlugInHybrid);
      expect(c('Corolla 1.6 Gasoline'), kFuelGasoline);
      expect(c('Camry 2.2 D', fuel: 'Diesel'), kFuelDiesel);
      expect(c('Leaf 40 kWh', fuel: 'Electric', ice: false), kFuelElectric);
    });

    test('source "Electric" with a combustion engine is a plug-in hybrid', () {
      expect(
        classifyCatalogFuelKey(
          datasetFuel: 'Electric',
          label: 'X5 xDrive40e',
          hasCombustionEngine: true,
        ),
        kFuelPlugInHybrid,
      );
    });

    test('mild hybrids and "extended range" EVs are not reclassified', () {
      expect(
        classifyCatalogFuelKey(
          datasetFuel: 'Petrol (Gasoline)',
          label: 'Swift 1.2 Mild Hybrid',
          hasCombustionEngine: true,
        ),
        kFuelGasoline,
      );
      expect(
        classifyCatalogFuelKey(
          datasetFuel: 'Electric',
          label: 'Micra Electric Extended Range',
          hasCombustionEngine: false,
        ),
        kFuelElectric,
      );
    });

    test('canonicalFuelKey accepts every stored spelling', () {
      for (final s in ['Hybrid', 'HYBRID', ' hybrid ', 'hev', 'full hybrid']) {
        expect(canonicalFuelKey(s), kFuelHybrid, reason: s);
      }
      for (final s in [
        'Plug-in Hybrid',
        'plug-in hybrid',
        'plug_in_hybrid',
        'plugin hybrid',
        'PHEV',
        'range extender',
        'EREV',
      ]) {
        expect(canonicalFuelKey(s), kFuelPlugInHybrid, reason: s);
      }
      expect(canonicalFuelKey('Petrol'), kFuelGasoline);
      expect(canonicalFuelKey('Electric'), kFuelElectric);
      expect(canonicalFuelKey('Diesel'), kFuelDiesel);
      expect(canonicalFuelKey('mild hybrid'), isNull);
      expect(canonicalFuelKey(null), isNull);
    });

    test('hybrid, plug-in hybrid, electric and gasoline stay distinct', () {
      final keys = {
        for (final s in ['Hybrid', 'Plug-in Hybrid', 'Electric', 'Gasoline'])
          canonicalFuelKey(s),
      };
      expect(keys.length, 4);
    });
  });

  // ---------------------------------------------------------------------------
  // Accuracy audit regressions (final pre-merge review of a3b793f).
  // ---------------------------------------------------------------------------
  group('audit: classification accuracy', () {
    String c(
      String label, {
      String fuel = 'Petrol (Gasoline)',
      bool ice = true,
    }) =>
        classifyCatalogFuelKey(
          datasetFuel: fuel,
          label: label,
          hasCombustionEngine: ice,
        );

    test('Nissan e-POWER (gasoline generator) is a hybrid, never Electric', () {
      expect(c('Note e-POWER 1 2 (109 Hp) Hybrid Automatic'), kFuelHybrid);
      expect(c('X-Trail 1 5 VC-T (204 Hp) e-POWER Automatic'), kFuelHybrid);
      expect(c('Kicks e-Power 1 2 (129 Hp) Hybrid'), kFuelHybrid);
      // even if a source row mislabelled the fuel Electric, e-POWER is not BEV
      expect(c('Note e-POWER 1 2 (109 Hp)', fuel: 'Electric', ice: false),
          kFuelHybrid);
      expect(c('Note e-POWER 1 2 (109 Hp)', fuel: 'Electric'),
          kFuelPlugInHybrid);
    });

    test('a battery "Extended Range" (bigger pack) stays a pure BEV', () {
      for (final l in [
        'Micra 52 kWh (150 Hp) Electric Extended Range',
        'Mustang Mach-E Extended Range 98 7 kWh (294 Hp)',
        'EX30 69 kWh (272 Hp) Single Motor Extended Range',
        'Atto 3 Extended Range 60 48 kWh (204 Hp) BEV',
        'EV6 Long Range 77 4 kWh (229 Hp)',
      ]) {
        expect(c(l, fuel: 'Electric', ice: false), kFuelElectric, reason: l);
      }
    });

    test('a range extender whose engine has no displacement field is a '
        'plug-in hybrid (engine size is in the name)', () {
      for (final l in [
        'S07 1 5L 31 73 kWh (238 Hp) Extended Range',
        'G318 1 5T 35 07 kWh (430 Hp) 4WD Extended Range',
        'EZ-6 1 5L 28 4 kWh (218 Hp) Extended Range',
        'B10 1 5L 18 8 kWh (218 Hp) Hybrid EV',
      ]) {
        expect(c(l, fuel: 'Electric', ice: false), kFuelPlugInHybrid,
            reason: l);
      }
    });

    test('a hybrid-only nameplate without hybrid wording is a hybrid', () {
      expect(c('Prius 1 5 16V (58 Hp) Prius 1 5 16V (58 Hp)'), kFuelHybrid);
      expect(c('Insight 1 0 (68 Hp) Insight 1 0 (68 Hp)'), kFuelHybrid);
      // a Prius / Insight with explicit wording keeps its own classification
      expect(
          c('Prius Prime 1 8 (122 Hp) Plug-in Hybrid e-CVT',
              fuel: 'Electric'),
          kFuelPlugInHybrid);
      // other nameplates are never inferred from the name
      expect(c('Corolla 1 6 (110 Hp) Corolla 1 6 (110 Hp)'), kFuelGasoline);
      expect(c('Camry 2 5 (181 Hp)'), kFuelGasoline);
    });

    test('"M Hybrid" (Mazda) is a mild hybrid and keeps Gasoline', () {
      expect(c('3 2 0 SkyActiv-G M Hybrid (122 Hp)'), kFuelGasoline);
      expect(c('CX-5 2 5 e-SKYACTIV G 2 5 (141 Hp) M Hybrid'), kFuelGasoline);
      expect(c('2 1 5 (116 Hp) Hybrid CVT'), kFuelHybrid); // Mazda2 Hybrid
    });

    test('"e-Hybrid" is plug-in only through source evidence, never by name',
        () {
      // Jeep (48 V) / Ford Edge (self-charging): no plug-in evidence.
      expect(c('Avenger 1 2 (100 Hp) e-Hybrid e-DCS'), kFuelHybrid);
      expect(c('Edge 2 0T EcoBoost (275 Hp) E-Hybrid eCVT'), kFuelHybrid);
      // VW / Audi / Porsche: the source row is Electric + a combustion engine.
      expect(c('Golf 1 4 TSI (204 Hp) eHybrid DSG', fuel: 'Electric'),
          kFuelPlugInHybrid);
      expect(c('Cayenne 3 0 V6 (462 Hp) E-Hybrid Tiptronic S', fuel: 'Electric'),
          kFuelPlugInHybrid);
    });

    test('explicit FHEV / HEV wins over the Electric + engine rule', () {
      expect(c('C-X16 3 0 V6 (467 Hp) FHEV Automatic', fuel: 'Electric'),
          kFuelHybrid);
      expect(c('Kona 1 6 GDI (141 Hp) HEV DCT', fuel: 'Electric'),
          kFuelHybrid);
    });
  });

  group('audit: dataset-wide invariants (real bundled dataset)', () {
    late List<({String brand, String name, int? y0, int? y1, String fuel, bool ice, String result})> all;

    setUpAll(() {
      final d = jsonDecode(
              File('assets/car_spec_dataset.json').readAsStringSync())
          as Map<String, dynamic>;
      final brands = {
        for (final b in d['brands'] as List) (b as Map)['id']: b['name']
      };
      final models = {
        for (final m in d['models'] as List) (m as Map)['id']: m
      };
      final trims = {for (final t in d['trims'] as List) (t as Map)['id']: t};
      all = [
        for (final s in d['specs'] as List)
          () {
            final sp = s as Map<String, dynamic>;
            final t = trims[sp['trim_id']]!;
            final m = models[t['model_id']]!;
            final cc = (sp['displacement_cc'] as num?)?.toInt();
            final raw =
                (sp['raw_spec_pairs'] as Map)['Displacement:']?.toString();
            final ice = (cc ?? 0) > 0 ||
                (raw != null && RegExp(r'[1-9]').hasMatch(raw));
            final fuel = sp['fuel_type'].toString();
            return (
              brand: brands[m['brand_id']].toString(),
              name: '${m['name']} ${t['name']}',
              y0: t['year'] as int?,
              y1: t['year_end'] as int?,
              fuel: fuel,
              ice: ice,
              result: classifyCatalogFuelKey(
                datasetFuel: fuel,
                label: '${m['name']} ${t['name']}',
                hasCombustionEngine: ice,
              ),
            );
          }(),
      ];
    });

    bool has(String name, RegExp re) =>
        re.hasMatch(name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' '));

    test('no e-POWER row is ever classified Electric or Gasoline', () {
      final rows = all.where((r) => has(r.name, RegExp(r'e power'))).toList();
      expect(rows.length, greaterThan(10));
      for (final r in rows) {
        expect(r.result, kFuelHybrid, reason: r.name);
      }
    });

    test('no source-Electric row that names a combustion engine is a BEV', () {
      final engine = RegExp(r' \d \d{1,2}(l|t|ti|td|tci) ');
      final rows = all.where((r) =>
          r.fuel == 'Electric' &&
          engine.hasMatch(
              ' ${r.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} '));
      expect(rows, isNotEmpty);
      for (final r in rows) {
        expect(r.result, isNot(kFuelElectric), reason: r.name);
      }
    });

    test('no source-Electric row with a combustion displacement is a BEV', () {
      for (final r in all.where((r) => r.fuel == 'Electric' && r.ice)) {
        expect(r.result, isNot(kFuelElectric), reason: r.name);
      }
    });

    test('every Prius / Insight row is a hybrid or plug-in, never Gasoline', () {
      final rows = all
          .where((r) => has(r.name, RegExp(r'^(prius|insight) ')))
          .toList();
      expect(rows.length, greaterThan(15));
      for (final r in rows) {
        expect([kFuelHybrid, kFuelPlugInHybrid], contains(r.result),
            reason: r.name);
      }
    });

    test('the only Electric RAV4 rows are the real historical RAV4 EVs', () {
      final ev = all
          .where((r) =>
              r.brand == 'Toyota' &&
              has(r.name, RegExp(r'^rav ?4 ')) &&
              r.result == kFuelElectric)
          .toList();
      // Toyota RAV4 EV: 1997-2003 (NiMH) and 2012-2014 (Tesla powertrain).
      expect(ev, isNotEmpty);
      for (final r in ev) {
        final ok = (r.y0! >= 1997 && r.y1! <= 2003) ||
            (r.y0! >= 2012 && r.y1! <= 2014);
        expect(ok, isTrue, reason: '${r.name} ${r.y0}-${r.y1}');
        expect(r.ice, isFalse, reason: r.name);
        expect(has(r.name, RegExp(r'kwh')), isTrue, reason: r.name);
      }
      // every other RAV4 generation is never Electric
      for (final r in all.where((r) =>
          r.brand == 'Toyota' &&
          has(r.name, RegExp(r'^rav ?4 ')) &&
          r.y0! >= 2015)) {
        expect(r.result, isNot(kFuelElectric), reason: r.name);
      }
    });

    test('mild hybrids (wording or Mazda M Hybrid) never become Hybrid', () {
      final mild = RegExp(r'mild hybrid|mhev| 48v |hybrid assist| m hybrid ');
      for (final r in all.where((r) => has(r.name, mild))) {
        expect([kFuelHybrid], isNot(contains(r.result)), reason: r.name);
      }
    });
  });
  group('Sell and Search offer Hybrid where the model has hybrid variants', () {
    const hybridModels = <(String, String)>[
      ('Toyota', 'Corolla'),
      ('Toyota', 'Corolla Cross'),
      ('Toyota', 'Camry'),
      ('Toyota', 'RAV4'),
      ('Toyota', 'Prius'),
      ('Hyundai', 'Ioniq'),
      ('Hyundai', 'Tucson'),
      ('Kia', 'Niro'),
      ('Kia', 'Sportage'),
      ('Honda', 'Accord'),
      ('Honda', 'CR-V'),
      ('Lexus', 'RX'),
      ('Mercedes-Benz', 'C-Class'),
      ('Ford', 'Escape'),
    ];
    for (final (b, m) in hybridModels) {
      test('$b $m', () {
        expect(sellFuels(b, m), contains('Hybrid'), reason: 'Sell');
        expect(searchFuels(b, m), contains('Hybrid'), reason: 'Search');
        // Sell and Search come from the same resolver.
        expect(searchFuels(b, m), sellFuels(b, m));
      });
    }

    test('Corolla keeps Gasoline and Diesel, Corolla Cross Gasoline', () {
      expect(sellFuels('Toyota', 'Corolla'), {'Gasoline', 'Diesel', 'Hybrid'});
      expect(sellFuels('Toyota', 'Corolla Cross'), {'Gasoline', 'Hybrid'});
    });

    test('Corolla / Corolla Cross are not offered Electric', () {
      for (final m in ['Corolla', 'Corolla Cross']) {
        expect(sellFuels('Toyota', m), isNot(contains('Electric')));
        expect(sellFuels('Toyota', m), isNot(contains('Plug-in Hybrid')));
      }
    });

    test('hybrid-only nameplates never offer plain Gasoline / Diesel', () {
      expect(sellFuels('Toyota', 'Prius'), {'Hybrid', 'Plug-in Hybrid'});
      expect(sellFuels('Honda', 'Insight'), {'Hybrid'});
    });

    test('range extenders are Plug-in Hybrid, e-POWER is Hybrid', () {
      // S07 is sold both as a BEV and as a range-extender (EREV).
      expect(sellFuels('Deepal', 'S07'), {'Plug-in Hybrid', 'Electric'});
      for (final m in ['X-Trail', 'Qashqai', 'Kicks']) {
        expect(sellFuels('Nissan', m), contains('Hybrid'), reason: m);
      }
      expect(sellFuels('Nissan', 'Leaf'), {'Electric'});
    });

    test('plug-in hybrids are offered as Plug-in Hybrid, never as Electric', () {
      expect(sellFuels('Toyota', 'Prius Prime'), {'Plug-in Hybrid'});
      expect(sellFuels('Toyota', 'Prius'), contains('Plug-in Hybrid'));
      expect(sellFuels('BMW', 'X5'), contains('Plug-in Hybrid'));
      expect(sellFuels('BMW', 'X5'), isNot(contains('Electric')));
      expect(searchFuels('Toyota', 'Prius Prime'), {'Plug-in Hybrid'});
    });

    test('hybrid-only nameplates are not plain Gasoline', () {
      expect(sellFuels('Hyundai', 'Ioniq'),
          {'Hybrid', 'Plug-in Hybrid', 'Electric'});
      expect(sellFuels('Kia', 'Niro'),
          {'Hybrid', 'Plug-in Hybrid', 'Electric'});
    });

    test('Petrol / Diesel / Electric models are unaffected', () {
      expect(sellFuels('Nissan', 'Leaf'), {'Electric'});
      expect(sellFuels('Tesla', 'Model 3'), {'Electric'});
      expect(sellFuels('Chevrolet', 'Bolt'), {'Electric'});
      expect(sellFuels('Nissan', 'Micra'), {'Gasoline', 'Diesel', 'Electric'});
      expect(sellFuels('BMW', 'X5'), containsAll(['Gasoline', 'Diesel']));
    });

    test('a model with no spec rows still offers the full default ladder', () {
      // BYD has no dataset rows: nothing narrows the Search defaults.
      expect(searchFuels('BYD', 'Song Plus'),
          {'Gasoline', 'Diesel', 'Electric', 'Hybrid', 'Plug-in Hybrid'});
    });

    test('switching model updates the options; the year never does', () {
      expect(sellFuels('Toyota', 'Prius Prime'), {'Plug-in Hybrid'});
      expect(sellFuels('Toyota', 'Corolla Cross'), {'Gasoline', 'Hybrid'});
      expect(sellFuels('Nissan', 'Leaf'), {'Electric'});
      for (final y in [1995, 2012, 2020, 2024, 2030]) {
        expect(sellFuels('Toyota', 'Corolla', y),
            {'Gasoline', 'Diesel', 'Hybrid'},
            reason: 'year $y');
        expect(sellFuels('Toyota', 'Corolla Cross', y),
            {'Gasoline', 'Hybrid'},
            reason: 'year $y');
      }
    });
  });

  group('storage, query and filter compatibility', () {
    test('fuelStorageValue stores the canonical key, others unchanged', () {
      expect(fuelStorageValue('Hybrid'), 'hybrid');
      expect(fuelStorageValue('Plug-in Hybrid'), 'plug-in hybrid');
      expect(fuelStorageValue('plug_in_hybrid'), 'plug-in hybrid');
      expect(fuelStorageValue('Gasoline'), 'gasoline');
      expect(fuelStorageValue('Electric'), 'electric');
      expect(fuelStorageValue(' Diesel '), 'diesel');
    });

    test('the Hybrid filter is sent to /api/cars as hybrid', () {
      final q = homeFiltersToApiQuery(const HomeFiltersSnapshot(
        brand: 'Toyota',
        model: 'Corolla Cross',
        fuelType: 'Hybrid',
      ));
      expect(q['fuel_type'], 'hybrid');
      final p = homeFiltersToApiQuery(
        const HomeFiltersSnapshot(fuelType: 'Plug-in Hybrid'),
      );
      expect(p['fuel_type'], 'plug-in hybrid');
    });

    test('a saved hybrid listing matches the Hybrid filter only', () {
      Map<String, dynamic> listing(String fuel) => {
            'brand': 'toyota',
            'model': 'Corolla Cross',
            'fuel_type': fuel,
            'engine_type': fuel,
          };
      const hybrid = HomeFiltersSnapshot(fuelType: 'Hybrid');
      expect(listingMatchesHomeFilters(listing('hybrid'), hybrid), isTrue);
      expect(listingMatchesHomeFilters(listing('Hybrid'), hybrid), isTrue);
      expect(listingMatchesHomeFilters(listing('gasoline'), hybrid), isFalse);
      expect(listingMatchesHomeFilters(listing('electric'), hybrid), isFalse);
      expect(
          listingMatchesHomeFilters(listing('plug-in hybrid'), hybrid), isFalse);
      const gas = HomeFiltersSnapshot(fuelType: 'Gasoline');
      expect(listingMatchesHomeFilters(listing('hybrid'), gas), isFalse);
      expect(listingMatchesHomeFilters(listing('gasoline'), gas), isTrue);
    });

    test('editing a hybrid listing restores the exact picker labels', () {
      for (final (stored, label) in [
        ('hybrid', 'Hybrid'),
        ('plug-in hybrid', 'Plug-in Hybrid'),
        ('plug_in_hybrid', 'Plug-in Hybrid'),
      ]) {
        final d = listingToSellDraftSnapshot({
          'id': 'x',
          'brand': 'toyota',
          'model': 'Prius',
          'fuel_type': stored,
          'engine_type': stored,
        });
        final car = d['carData'] as Map<String, dynamic>;
        expect(car['fuel_type'], label, reason: stored);
        expect(car['engine_type'], label, reason: stored);
      }
    });
  });

  group('localization', () {
    // Material/Cupertino have no Kurdish delegate, so host the app strings in
    // a bare Localizations widget (the label lookup only needs AppLocalizations).
    Widget app(Locale locale, void Function(BuildContext) body) => Localizations(
          locale: locale,
          delegates: const [
            AppLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Builder(builder: (c) {
            body(c);
            return const SizedBox.shrink();
          }),
        );

    const expected = <String, (String, String)>{
      'en': ('Hybrid', 'Plug-in Hybrid'),
      'ar': ('هجين', 'هجين قابل للشحن'),
      'ku': ('هایبرید', 'پڵەگ-ئین هایبرید'),
    };
    expected.forEach((code, labels) {
      testWidgets('$code labels', (tester) async {
        await tester.pumpWidget(app(Locale(code), (c) {
          expect(translateListingValue(c, 'hybrid'), labels.$1);
          expect(translateListingValue(c, 'Hybrid'), labels.$1);
          expect(translateListingValue(c, 'plug-in hybrid'), labels.$2);
          expect(translateListingValue(c, 'plug_in_hybrid'), labels.$2);
          expect(translateListingValue(c, 'phev'), labels.$2);
          expect(translateListingValue(c, 'electric'),
              isNot(anyOf(labels.$1, labels.$2)));
        }));
      });
    });
  });
}
