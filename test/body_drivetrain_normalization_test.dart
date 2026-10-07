import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

/// Body type + drivetrain are EVIDENCE-ONLY model facts.
///
/// An unknown / blank / unsupported source value must never become a factual
/// spec (the old `unknown -> Sedan` and `blank -> FWD` defaults are gone), for
/// Search, Sell and the catalog apply. Real bundled assets are used for the
/// acceptance models; a tiny synthetic dataset is used for blank/unknown rows.
void main() {
  const searchBodyLadder = [
    'Any', 'Sedan', 'SUV', 'Hatchback', 'Coupe', 'Convertible', 'Wagon',
    'Pickup', 'Van', 'Minivan', //
  ];
  const searchDriveLadder = ['Any', 'FWD', 'RWD', 'AWD'];
  const sellBodyLadder = [
    'Sedan', 'SUV', 'Hatchback', 'Coupe', 'Convertible', 'Wagon', 'Pickup',
    'Van', 'Minivan', //
  ];

  late Map<String, dynamic> catalogJson;
  late String specRaw;
  late Map<String, dynamic> spec;
  late CarSpecIndex idx;

  setUpAll(() {
    specRaw = File('assets/car_spec_dataset.json').readAsStringSync();
    spec = jsonDecode(specRaw) as Map<String, dynamic>;
    catalogJson = jsonDecode(File('assets/car_catalog.json').readAsStringSync())
        as Map<String, dynamic>;
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalog.applyCatalogFromAsset(catalogJson);
    final overlay = IqCarsOverlay.parse(
      File('assets/car_iqcars_overlay.json').readAsStringSync(),
    );
    idx = parseCarSpecDatasetJsonString(specRaw).index!
      ..attachIqCarsOverlay(overlay);
  });

  tearDownAll(CarCatalog.resetCatalogOverrideForTest);

  HomeVehicleFieldOptions search(CarSpecIndex i, String b, String m) {
    final ctx = HomeVehicleContext(brand: b, model: m);
    return HomeVehicleFieldOptions.resolve(
      catalog: resolveHomeVehicleCatalogOptions(i, ctx),
      engineCatalog: resolveHomeVehicleEngineCatalogOptions(i, ctx),
      defaults: const HomeVehicleFieldDefaults(
        bodyTypes: searchBodyLadder,
        transmissions: ['Any', 'Automatic', 'Manual'],
        fuelTypes: ['Any', 'Gasoline', 'Diesel', 'Electric', 'Hybrid'],
        driveTypes: searchDriveLadder,
        cylinderCounts: ['Any'],
        seatings: ['Any', '5'],
        engineSizes: ['Any'],
      ),
      vehicleResolved: true,
    );
  }

  List<String> real(List<String> l) => l.where((e) => e != 'Any').toList();

  // ---------------------------------------------------------------- BODY rules
  group('body: explicit alias table', () {
    Set<String> b(String? raw) => carSpecBodyKeys(raw);

    test('approved mappings', () {
      expect(b('Pick-up'), {'pickup'});
      expect(b('Pickup'), {'pickup'});
      expect(b('Pick up'), {'pickup'});
      expect(b('Minivan'), {'minivan'});
      expect(b('MPV'), {'minivan'});
      expect(b('Station wagon (estate)'), {'wagon'});
      expect(b('Estate'), {'wagon'});
      expect(b('Variant'), {'wagon'});
      expect(b('Cabriolet'), {'convertible'});
      expect(b('Roadster'), {'convertible'});
      expect(b('Targa'), {'convertible'});
      expect(b('Crossover'), {'suv'});
      expect(b('CUV'), {'suv'});
      expect(b('SAV'), {'suv'});
      expect(b('SAC'), {'suv'});
      expect(b('Off-road vehicle'), {'suv'});
      expect(b('SUV'), {'suv'});
      expect(b('Liftback'), {'hatchback'});
      expect(b('Hatchback'), {'hatchback'});
      expect(b('Coupe'), {'coupe'});
      expect(b('Sedan'), {'sedan'});
      expect(b('Van'), {'van'});
    });

    test('Minivan is never Van (specific mappings win over any "van" substring)', () {
      expect(b('Minivan'), isNot(contains('van')));
      expect(b('Minivan, MPV'), {'minivan'});
      expect(b('MPV, Van'), {'minivan', 'van'}); // explicit Van token only
      expect(sellFlowBodyLabel('minivan'), 'Minivan');
      expect(sellFlowBodyLabel('van'), 'Van');
    });

    test('case / spacing variants of the same token map identically', () {
      expect(b('pick-up'), {'pickup'});
      expect(b('PICK UP'), {'pickup'});
      expect(b(' Station Wagon (Estate) '), {'wagon'});
      expect(b('SUV '), {'suv'});
    });

    test('unknown / blank / unsupported -> no option, and NEVER Sedan', () {
      for (final raw in <String?>[
        null, '', '   ', 'Fastback', 'Grand Tourer', 'Quadricycle',
        'Spaceship', 'unknown', 'Truck', '???', 'Sport wagon',
      ]) {
        expect(b(raw), isEmpty, reason: '$raw');
        expect(b(raw), isNot(contains('sedan')), reason: '$raw');
      }
      expect(sellFlowBodyLabel(null), isNull);
      expect(sellFlowBodyLabel(''), isNull);
      expect(sellFlowBodyLabel('fastback'), isNull);
      expect(sellFlowBodyLabel('whatever'), isNull);
    });

    test('combined values emit every explicitly recognised category', () {
      expect(b('Station wagon (estate), Crossover'), {'wagon', 'suv'});
      expect(b('Coupe, SUV'), {'coupe', 'suv'});
      expect(b('Coupe - Cabriolet'), {'coupe', 'convertible'});
      expect(b('Coupe - Cabriolet, Roadster'), {'coupe', 'convertible'});
      expect(b('Off-road vehicle, Cabriolet, SUV'), {'suv', 'convertible'});
      expect(b('Station wagon (estate), MPV'), {'wagon', 'minivan'});
      expect(b('Pick-up, Targa'), {'pickup', 'convertible'});
    });

    test('unrecognised parts of a combined value contribute nothing (never Sedan)', () {
      expect(b('Sedan, Fastback'), {'sedan'});
      expect(b('Coupe, Fastback'), {'coupe'});
      expect(b('Crossover, Fastback'), {'suv'});
      expect(b('Fastback, Grand Tourer'), isEmpty);
    });

    test('single-body helper never picks arbitrarily', () {
      expect(carSpecSingleBodyKey({'suv'}), 'suv');
      expect(carSpecSingleBodyKey({'suv', 'wagon'}), isNull);
      expect(carSpecSingleBodyKey(<String>{}), isNull);
    });
  });

  // ------------------------------------------------------------ DRIVETRAIN rules
  group('drivetrain: evidence only', () {
    String? d(String? a, String? b) => carSpecDriveKey(a, b);

    test('D: blank + blank / unknown -> no option, never FWD', () {
      expect(d('', null), isNull);
      expect(d(null, null), isNull);
      expect(d('', ''), isNull);
      expect(d('  ', 'unknown'), isNull);
      expect(d('Chain', 'Belt'), isNull);
      expect(sellFlowDriveLabel(null), isNull);
      expect(sellFlowDriveLabel(''), isNull);
      expect(sellFlowDriveLabel('xyz'), isNull);
    });

    test('A: both fields agree', () {
      expect(d('FWD', 'Front wheel drive'), 'fwd');
      expect(d('RWD', 'Rear wheel drive'), 'rwd');
      expect(d('AWD', 'All wheel drive (4x4)'), 'awd');
    });

    test('B: only one field is recognised', () {
      expect(d('', 'Rear wheel drive'), 'rwd');
      expect(d(null, 'Front wheel drive'), 'fwd');
      expect(d('RWD', null), 'rwd');
      expect(d('AWD', ''), 'awd');
      expect(d('', 'All wheel drive (4x4)'), 'awd');
    });

    test('4x4 / 4WD are CarNet AWD', () {
      expect(d('4WD', null), 'awd');
      expect(d(null, '4x4'), 'awd');
      expect(d('', 'Four wheel drive'), 'awd');
      expect(sellFlowDriveLabel('4wd'), 'AWD');
      expect(sellFlowDriveLabel('awd'), 'AWD');
    });

    test('C: recognised but different -> no option', () {
      expect(d('RWD', 'Front wheel drive'), isNull);
      expect(d('FWD', 'Rear wheel drive'), isNull);
      expect(d('AWD', 'Front wheel drive'), isNull);
    });

    test('a field naming several layouts is not evidence', () {
      expect(d('FWD/RWD', null), isNull);
    });
  });

  // ------------------------------------------------------ blank rows (synthetic)
  group('blank / unknown source rows contribute nothing', () {
    CarSpecIndex synthetic(List<Map<String, dynamic>> specs) {
      final models = <Map<String, dynamic>>[];
      final trims = <Map<String, dynamic>>[];
      final out = <Map<String, dynamic>>[];
      for (var i = 0; i < specs.length; i++) {
        models.add({'id': i + 1, 'brand_id': 1, 'name': 'Zeta 1 6 (${100 + i} Hp)'});
        trims.add({'id': i + 1, 'model_id': i + 1, 'year': 2010, 'year_end': 2012, 'name': 'x'});
        out.add({
          'trim_id': i + 1,
          'fuel_type': 'Petrol (Gasoline)',
          'transmission': 'Manual',
          'seats': 5,
          'displacement_cc': 1598,
          ...specs[i],
        });
      }
      return parseCarSpecDatasetJsonString(jsonEncode({
        'brands': [
          {'id': 1, 'name': 'ZBrand'},
        ],
        'models': models,
        'trims': trims,
        'specs': out,
      })).index!;
    }

    test('model with only blank / unknown body + drivetrain: no options, Search = Any only', () {
      final i = synthetic([
        {'body_type': 'Fastback', 'drivetrain': '', 'raw_spec_pairs': <String, String>{}},
        {'body_type': 'Grand Tourer', 'drivetrain': '', 'raw_spec_pairs': <String, String>{}},
      ]);
      final o = i.sellFieldOptionsUnion('ZBrand', 'Zeta', CarSpecIndex.catalogAutofillModelOnly, 2011)!;
      expect(o.bodyTypes, isEmpty);
      expect(o.driveTypes, isEmpty);
      final s = search(i, 'ZBrand', 'Zeta');
      expect(s.bodyTypes, ['Any']);
      expect(s.driveTypes, ['Any']);
      // the manual Sell ladder is untouched when the catalog has nothing
      expect(narrowOptionsToCatalog(sellBodyLadder, o.bodyTypes), same(sellBodyLadder));
      expect(narrowOptionsToCatalog(const ['FWD', 'RWD', 'AWD'], o.driveTypes), const ['FWD', 'RWD', 'AWD']);
      final rep = i.representativeForCatalogSell('ZBrand', 'Zeta', CarSpecIndex.catalogAutofillModelOnly, 2011)!;
      expect(rep.fields.bodyType, isNull); // nothing pre-selected
      expect(rep.fields.driveType, isNull);
      expect(rep.fields.bodyTypes, isEmpty);
    });

    test('blank rows do not add FWD next to evidenced rows; conflicting row adds nothing', () {
      final i = synthetic([
        {'body_type': 'Sedan', 'drivetrain': 'RWD', 'raw_spec_pairs': {'Traction:': 'Rear wheel drive'}},
        {'body_type': 'Sedan', 'drivetrain': '', 'raw_spec_pairs': <String, String>{}},
        {'body_type': 'Sedan', 'drivetrain': 'RWD', 'raw_spec_pairs': {'Traction:': 'Front wheel drive'}},
        {'body_type': 'Sedan', 'drivetrain': '', 'raw_spec_pairs': {'Traction:': 'Rear wheel drive'}},
      ]);
      final o = i.sellFieldOptionsUnion('ZBrand', 'Zeta', CarSpecIndex.catalogAutofillModelOnly, 2011)!;
      expect(o.driveTypes, {'RWD'});
      expect(o.bodyTypes, {'Sedan'});
    });

    test('combined body: Search/Sell options get every category, the form pre-selects none', () {
      final i = synthetic([
        {
          'body_type': 'Station wagon (estate), Crossover',
          'drivetrain': 'AWD',
          'raw_spec_pairs': {'Traction:': 'All wheel drive (4x4)'},
        },
      ]);
      final o = i.sellFieldOptionsUnion('ZBrand', 'Zeta', CarSpecIndex.catalogAutofillModelOnly, 2011)!;
      expect(o.bodyTypes, {'Wagon', 'SUV'});
      expect(search(i, 'ZBrand', 'Zeta').bodyTypes, ['Any', 'SUV', 'Wagon']);
      final rep = i.representativeForCatalogSell('ZBrand', 'Zeta', CarSpecIndex.catalogAutofillModelOnly, 2011)!;
      expect(rep.fields.bodyTypes, {'wagon', 'suv'});
      expect(rep.fields.bodyType, isNull); // no arbitrary single pick
      expect(rep.fields.driveType, 'awd');
    });
  });

  // -------------------------------------------------------------- acceptance
  group('acceptance models (real assets)', () {
    test('Volkswagen Golf', () {
      final s = search(idx, 'Volkswagen', 'Golf');
      expect(real(s.bodyTypes), ['SUV', 'Hatchback', 'Convertible', 'Wagon', 'Minivan']);
      expect(s.bodyTypes, isNot(contains('Sedan'))); // no Sedan from Station wagon / Cabriolet
      expect(s.bodyTypes, isNot(contains('Van'))); // Minivan displays as Minivan
      expect(real(s.driveTypes), ['FWD', 'AWD']); // malformed GLi RWD row adds nothing
      expect(s.driveTypes, isNot(contains('RWD')));
    });

    test('Volkswagen Golf R no longer gets Sedan', () {
      final s = search(idx, 'Volkswagen', 'Golf R');
      expect(s.bodyTypes, isNot(contains('Sedan')));
      expect(real(s.bodyTypes), ['Hatchback', 'Convertible', 'Wagon']);
    });

    test('Toyota Land Cruiser: the three Pick-up rows are Pickup, not Sedan', () {
      final s = search(idx, 'Toyota', 'Land Cruiser');
      expect(real(s.bodyTypes), ['SUV', 'Pickup']);
      expect(s.bodyTypes, isNot(contains('Sedan')));
      expect(real(s.driveTypes), ['AWD']);
    });

    test('Toyota Land Cruiser Prado is unchanged', () {
      final s = search(idx, 'Toyota', 'Land Cruiser Prado');
      expect(real(s.bodyTypes), ['SUV']);
      expect(real(s.driveTypes), ['AWD']);
    });

    test('Toyota Hilux: Pickup, no longer Sedan-only; blank rows do not manufacture FWD', () {
      final s = search(idx, 'Toyota', 'Hilux');
      expect(real(s.bodyTypes), ['Pickup']);
      expect(real(s.driveTypes), ['RWD', 'AWD']);
      expect(s.driveTypes, isNot(contains('FWD')));
    });

    test('BMW X1 / X3 / X5: SAV rows are SUV and never create Sedan', () {
      for (final m in ['X1', 'X3', 'X5']) {
        final s = search(idx, 'BMW', m);
        expect(real(s.bodyTypes), ['SUV'], reason: m);
        expect(s.bodyTypes, isNot(contains('Sedan')), reason: m);
      }
      expect(real(search(idx, 'BMW', 'X1').driveTypes), ['FWD', 'RWD', 'AWD']);
      expect(real(search(idx, 'BMW', 'X3').driveTypes), ['RWD', 'AWD']);
      expect(real(search(idx, 'BMW', 'X5').driveTypes), ['RWD', 'AWD']);
    });

    test('Ford Mustang: Cabriolet is Convertible; Fastback stays unmapped (no Sedan)', () {
      final s = search(idx, 'Ford', 'Mustang');
      expect(real(s.bodyTypes), ['Coupe', 'Convertible']);
      expect(s.bodyTypes, isNot(contains('Sedan')));
      expect(real(s.driveTypes), ['RWD']);
    });

    test('Nissan Patrol: blank-drivetrain rows do not create FWD', () {
      final s = search(idx, 'Nissan', 'Patrol');
      expect(s.driveTypes, isNot(contains('FWD')));
      expect(real(s.driveTypes), ['AWD']);
      expect(real(s.bodyTypes), ['SUV', 'Wagon']);
    });
  });

  // ---------------------------------------------------- whole catalog invariants
  group('every catalog model (1,635): nothing is manufactured', () {
    test('Sedan / FWD only with explicit evidence; no evidence -> Any only', () {
      final brands = {
        for (final b in (spec['brands'] as List)) (b as Map)['id']: carSpecSpacedNameKey(b['name'] as String),
      };
      final trims = {for (final t in (spec['trims'] as List)) (t as Map)['model_id']: t};
      final specByTrim = {for (final s in (spec['specs'] as List)) (s as Map)['trim_id']: s};
      final byBrandName = <String, List<Map<String, dynamic>>>{};
      for (final m in (spec['models'] as List).cast<Map<String, dynamic>>()) {
        (byBrandName['${brands[m['brand_id']]}|${m['name']}'] ??= []).add(m);
      }

      var models = 0, bodyAnyOnly = 0, driveAnyOnly = 0;
      for (final be in (catalogJson['models'] as Map<String, dynamic>).entries) {
        for (final m in (be.value as List).cast<String>()) {
          models++;
          final brandKey = carSpecSpacedNameKey(be.key);
          final bodies = <String>{};
          final drives = <String>{};
          var sawSedanToken = false, sawFwdEvidence = false;
          for (final name in idx.debugFamilyDatasetModelNames(be.key, m).toSet()) {
            for (final row in byBrandName['$brandKey|$name'] ?? const <Map<String, dynamic>>[]) {
              final t = trims[row['id']];
              final s = t == null ? null : specByTrim[t['id']];
              if (s == null) continue;
              final raw = (s['body_type'] ?? '').toString().toLowerCase();
              if (RegExp(r'\b(sedan|saloon)\b').hasMatch(raw)) sawSedanToken = true;
              final dr = '${s['drivetrain'] ?? ''} ${(s['raw_spec_pairs'] as Map?)?['Traction:'] ?? ''}'
                  .toLowerCase();
              if (dr.contains('fwd') || dr.contains('front wheel')) sawFwdEvidence = true;
              bodies.addAll(carSpecBodyKeys(s['body_type']?.toString()));
              final dk = carSpecDriveKey(
                s['drivetrain']?.toString(),
                (s['raw_spec_pairs'] as Map?)?['Traction:']?.toString(),
              );
              if (dk != null) drives.add(dk);
            }
          }
          final s = search(idx, be.key, m);
          if (s.bodyTypes.contains('Sedan')) {
            expect(sawSedanToken, isTrue, reason: '${be.key} $m: Sedan without a Sedan source row');
          }
          if (s.driveTypes.contains('FWD')) {
            expect(sawFwdEvidence, isTrue, reason: '${be.key} $m: FWD without FWD evidence');
          }
          // the Search list is exactly the evidenced set (Any only when none)
          expect(real(s.bodyTypes).length, lessThanOrEqualTo(bodies.length), reason: '${be.key} $m');
          expect(real(s.driveTypes).length, lessThanOrEqualTo(drives.length), reason: '${be.key} $m');
          if (bodies.isEmpty) {
            expect(s.bodyTypes, ['Any'], reason: '${be.key} $m body');
            bodyAnyOnly++;
          }
          if (drives.isEmpty) {
            expect(s.driveTypes, ['Any'], reason: '${be.key} $m drive');
            driveAnyOnly++;
          }
        }
      }
      expect(models, 1635);
      expect(bodyAnyOnly, greaterThan(0));
      expect(driveAnyOnly, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 10)));
  });

  // ------------------------------------------------ Search before model selection
  test('before Brand + Model is selected the generic ladders are unchanged', () {
    final o = HomeVehicleFieldOptions.resolve(
      catalog: null,
      engineCatalog: null,
      defaults: const HomeVehicleFieldDefaults(
        bodyTypes: searchBodyLadder,
        transmissions: ['Any'],
        fuelTypes: ['Any'],
        driveTypes: searchDriveLadder,
        cylinderCounts: ['Any', '4'],
        seatings: ['Any'],
        engineSizes: ['Any'],
      ),
    );
    expect(o.bodyTypes, searchBodyLadder);
    expect(o.driveTypes, searchDriveLadder);
  });
}
