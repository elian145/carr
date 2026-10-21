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
