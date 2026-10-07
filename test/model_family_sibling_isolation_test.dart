import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

/// Sibling isolation in BOTH directions: a shorter catalog model never absorbs
/// the dataset rows of a more specific sibling ("Land Cruiser" vs "Land Cruiser
/// Prado"), and the specific sibling never absorbs the shorter one's rows.
/// Longest canonical catalog model wins (same boundary as the tooling's
/// `ModelIndex.resolve`). Real bundled assets.
void main() {
  late CarSpecIndex idx;
  late CarSpecIndex iqIdx;
  late IqCarsOverlay overlay;
  late Map<String, List<String>> catalogModels;

  setUpAll(() {
    final catalogJson = jsonDecode(File('assets/car_catalog.json').readAsStringSync())
        as Map<String, dynamic>;
    CarCatalog.applyCatalogFromAsset(catalogJson);
    catalogModels = {
      for (final e in (catalogJson['models'] as Map<String, dynamic>).entries)
        e.key: (e.value as List).cast<String>(),
    };
    final raw = File('assets/car_spec_dataset.json').readAsStringSync();
    overlay = IqCarsOverlay.parse(
      File('assets/car_iqcars_overlay.json').readAsStringSync(),
    );
    idx = parseCarSpecDatasetJsonString(raw).index!;
    iqIdx = parseCarSpecDatasetJsonString(raw).index!
      ..attachIqCarsOverlay(overlay);
  });

  tearDownAll(CarCatalog.resetCatalogOverrideForTest);

  Set<String> rows(String brand, String model) =>
      idx.debugFamilyDatasetModelNames(brand, model).toSet();

  String key(String s) => carSpecSpacedNameKey(s);

  group('named sibling pairs: A must not absorb B AND B must not absorb A', () {
    const pairs = <(String, String, String)>[
      ('Toyota', 'Land Cruiser', 'Land Cruiser Prado'),
      ('Toyota', 'Corolla', 'Corolla Cross'),
      ('Volkswagen', 'Golf', 'Golf R'),
      ('Ford', 'Bronco', 'Bronco Sport'),
      ('Mitsubishi', 'Pajero', 'Pajero Sport'),
      ('Land Rover', 'Discovery', 'Discovery Sport'),
      ('Volkswagen', 'Passat', 'Passat CC'),
      ('Renault', 'Megane', 'Megane GT'),
    ];

    for (final (brand, a, b) in pairs) {
      test('$brand: $a != $b', () {
        final ra = rows(brand, a);
        final rb = rows(brand, b);
        expect(ra, isNotEmpty);
        expect(rb, isNotEmpty);
        expect(ra.intersection(rb), isEmpty, reason: 'no row is shared');
        // the shorter model absorbs none of the longer sibling's rows ...
        for (final n in ra) {
          expect(
            carSpecDatasetNameMatchesFamily(brand, b, n),
            isFalse,
            reason: '"$a" family wrongly contains the "$b" row "$n"',
          );
        }
        // ... and the longer model owns every row named after it
        for (final n in rb) {
          expect(carSpecDatasetNameMatchesFamily(brand, b, n), isTrue);
        }
        final datasetNamesOfB = idx
            .debugFamilyDatasetModelNames(brand, b)
            .where((n) => key(n) == key(b) || key(n).startsWith('${key(b)} '));
        expect(datasetNamesOfB.toSet(), rb,
            reason: 'every "$b ..." row belongs to $b');
        // the specific sibling holds no row that is only a shorter-model row
        for (final n in rb) {
          expect(key(n) == key(b) || key(n).startsWith('${key(b)} '), isTrue,
              reason: '"$n" in $b is not named after $b');
        }
      });
    }
  });

  group('every catalog prefix pair, whole catalog', () {
    test('families of a shorter model and of any longer extension are disjoint', () {
      var pairsChecked = 0;
      for (final be in catalogModels.entries) {
        final models = be.value;
        for (final a in models) {
          for (final b in models) {
            if (a == b || !key(b).startsWith('${key(a)} ')) continue;
            pairsChecked++;
            final ra = rows(be.key, a);
            final rb = rows(be.key, b);
            expect(ra.intersection(rb), isEmpty, reason: '${be.key}: $a vs $b');
            for (final n in ra) {
              expect(carSpecDatasetNameMatchesFamily(be.key, b, n), isFalse,
                  reason: '${be.key}: "$a" absorbed the "$b" row "$n"');
            }
          }
        }
      }
      expect(pairsChecked, greaterThan(100));
    });

    test('tooling must_remain_distinct groups: all ordered prefix pairs isolate', () {
      final rules = jsonDecode(
        File('tools/catalog_enrichment/rules/model_boundaries.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      var checked = 0;
      for (final g in (rules['must_remain_distinct'] as List).cast<Map<String, dynamic>>()) {
        final brand = g['brand'] as String;
        final ms = (g['models'] as List).cast<String>();
        for (final a in ms) {
          for (final b in ms) {
            if (a == b || !key(b).startsWith('${key(a)} ')) continue;
            checked++;
            expect(rows(brand, a).intersection(rows(brand, b)), isEmpty,
                reason: '$brand: $a vs $b');
          }
        }
      }
      expect(checked, greaterThan(15));
    });
  });

  group('Toyota Land Cruiser acceptance', () {
    test('Land Cruiser receives zero Prado rows; Prado zero Land-Cruiser-only rows', () {
      final lc = rows('Toyota', 'Land Cruiser');
      final prado = rows('Toyota', 'Land Cruiser Prado');
      // dataset model entries (some names repeat): was 151 / 77
      expect(idx.debugFamilyDatasetModelNames('Toyota', 'Land Cruiser').length, 74);
      expect(idx.debugFamilyDatasetModelNames('Toyota', 'Land Cruiser Prado').length, 77);
      expect(lc.where((n) => key(n).startsWith('land cruiser prado')), isEmpty);
      expect(prado.every((n) => key(n).startsWith('land cruiser prado')), isTrue);
      expect(lc.intersection(prado), isEmpty);
    });

    test('Prado engines stay 2.4 D and (IQ) 2.4 T; Land Cruiser no longer inherits Prado-only engines', () {
      final prado = iqIdx.homeFilterFieldOptions('Toyota', 'Land Cruiser Prado', '')!.engineSizes;
      expect(prado, containsAll(<String>['2.4 D', '2.4 T']));
      final lcBase = idx.homeFilterFieldOptions('Toyota', 'Land Cruiser', '')!.engineSizes;
      for (final prodOnly in ['2.8 TD', '3.0 TD', '3.4']) {
        expect(lcBase, isNot(contains(prodOnly)), reason: prodOnly);
      }
      final pradoBase = idx.homeFilterFieldOptions('Toyota', 'Land Cruiser Prado', '')!.engineSizes;
      expect(pradoBase, containsAll(<String>['2.8 TD', '3.0 TD', '3.4']));
    });

    test('IQ overlay additions stay attached to the right canonical model', () {
      final lc = overlay.additionsFor('Toyota', 'Land Cruiser')!;
      final pr = overlay.additionsFor('Toyota', 'Land Cruiser Prado')!;
      expect(lc.engineVariants.map((v) => v.label), containsAll(<String>['4.5', '4.5 TD', '3.5 T']));
      expect(lc.engineVariants.map((v) => v.label), isNot(contains('2.4 T')));
      expect(pr.engineVariants.map((v) => v.label), contains('2.4 T'));
      expect(pr.engineVariants.map((v) => v.label), isNot(contains('4.5 TD')));
      // effective Land Cruiser engines = strict baseline UNION its own IQ variants only
      final eff = iqIdx.homeFilterFieldOptions('Toyota', 'Land Cruiser', '')!.engineSizes;
      expect(eff, containsAll(<String>['4.5 TD', '3.5 T']));
      expect(eff, isNot(contains('2.8 TD')));
    });
  });

  group('regressions: the accepted naming fixes survive strict matching', () {
    test('BMW N-Series, Rolls Royce, Cadillac -V, Ram 2500 still resolve', () {
      for (final n in [1, 2, 3, 4, 5, 6, 7, 8]) {
        expect(idx.hasCoverage('BMW', '$n-Series'), isTrue, reason: '$n-Series');
      }
      expect(idx.hasCoverage('Rolls Royce', 'Phantom'), isTrue);
      expect(idx.hasCoverage('Cadillac', 'ATS-V'), isTrue);
      expect(idx.hasCoverage('Cadillac', 'CTS-V'), isTrue);
      expect(rows('Ram', '2500'), isNotEmpty);
      expect(rows('Ram', '2500').every((n) => n.startsWith('2500/3500 2500')), isTrue);
    });

    test('"/" families stay unresolved (ambiguous, not reviewed)', () {
      expect(idx.hasCoverage('BYD', 'S6'), isFalse);
      expect(idx.hasCoverage('Hyundai', 'Grandeur'), isFalse);
      expect(idx.hasCoverage('Chevrolet', 'Sail'), isFalse);
      expect(idx.hasCoverage('Genesis', 'G90'), isFalse);
    });

    test('BMW 4/5/6-Series effective cylinders', () {
      expect(iqIdx.homeFilterFieldOptions('BMW', '4-Series', '')!.cylinderCounts, {'3', '4', '6'});
      expect(iqIdx.homeFilterFieldOptions('BMW', '5-Series', '')!.cylinderCounts, {'4', '6', '8', '10'});
      expect(iqIdx.homeFilterFieldOptions('BMW', '6-Series', '')!.cylinderCounts, {'4', '6', '8', '10'});
    });

    test('ATS keeps its own rows, ATS-V keeps the -V rows (hyphen sibling boundary)', () {
      final ats = rows('Cadillac', 'ATS');
      final atsV = rows('Cadillac', 'ATS-V');
      expect(ats.intersection(atsV), isEmpty);
      expect(atsV.every((n) => key(n).startsWith('ats v')), isTrue);
      expect(ats.where((n) => key(n).startsWith('ats v')), isEmpty);
    });
  });
}
