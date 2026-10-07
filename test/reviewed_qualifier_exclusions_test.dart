import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

/// Reviewed qualifier exclusions: ONLY the 18 audited name-prefix rules (572
/// dataset rows, 13 catalog models) are applied on top of the strict sibling
/// matcher. The audit artifact is the source of truth for which rules and rows
/// are approved; everything else (SAFE trims/engine designations and the 557
/// AMBIGUOUS rows) keeps matching exactly as before. Real bundled assets.
void main() {
  const auditPath =
      'tools/catalog_enrichment/iqcars/generated/iqcars_qualifier_quarantine_audit.json';
  const searchCylinderDefaults = [
    'Any', '1', '2', '3', '4', '5', '6', '8', '10', '12', '16', //
  ];
  const sellCylinderDefaults = ['3', '4', '5', '6', '8', '10', '12'];

  late Map<String, dynamic> audit;
  late List<Map<String, dynamic>> auditRows;
  late List<Map<String, dynamic>> entries;
  late Map<String, Map<String, dynamic>> auditModels;
  late Map<String, Map<String, dynamic>> selectiveChanged;
  late Map<String, dynamic> catalogJson;
  late Map<String, dynamic> spec;
  late String specRaw;
  late IqCarsOverlay overlay;
  late CarSpecIndex plainIdx;
  late CarSpecIndex iqIdx;

  const excludedClasses = {'OTHER_MODEL_OR_SIBLING', 'MALFORMED_OR_NOISY'};

  String k(String brand, String model) => '$brand|$model';

  setUpAll(() {
    audit = jsonDecode(File(auditPath).readAsStringSync()) as Map<String, dynamic>;
    auditRows = (audit['rows'] as List).cast<Map<String, dynamic>>();
    entries = ((audit['recommendation'] as Map)['exclusion_entries'] as List)
        .cast<Map<String, dynamic>>();
    auditModels = {
      for (final m in (audit['models'] as List).cast<Map<String, dynamic>>())
        k(m['brand'] as String, m['model'] as String): m,
    };
    selectiveChanged = {
      for (final m in ((audit['proposed_selective_exclusion'] as Map)['changed_models']
              as List)
          .cast<Map<String, dynamic>>())
        k(m['brand'] as String, m['model'] as String): m,
    };
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

  Set<String> rows(String b, String m) =>
      plainIdx.debugFamilyDatasetModelNames(b, m).toSet();

  HomeVehicleFieldDefaults defaults() => const HomeVehicleFieldDefaults(
        bodyTypes: ['Any', 'SUV'],
        transmissions: ['Any', 'Automatic', 'Manual'],
        fuelTypes: ['Any', 'Gasoline', 'Diesel'],
        driveTypes: ['Any', 'FWD', 'RWD', 'AWD', '4WD'],
        cylinderCounts: searchCylinderDefaults,
        seatings: ['Any', '5'],
        engineSizes: ['Any', 'generic-engine-ladder'],
      );

  HomeVehicleFieldOptions search(CarSpecIndex idx, String b, String m) {
    final ctx = HomeVehicleContext(brand: b, model: m);
    return HomeVehicleFieldOptions.resolve(
      catalog: resolveHomeVehicleCatalogOptions(idx, ctx),
      engineCatalog: resolveHomeVehicleEngineCatalogOptions(idx, ctx),
      defaults: defaults(),
      vehicleResolved: true,
    );
  }

  ({List<String> engines, List<String> cylinders}) sell(
      CarSpecIndex idx, String b, String m, int year) {
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

  /// Baseline (CarNet only) options of a model in the audit's field names.
  Map<String, List<String>> baseline(String b, String m) {
    final o = plainIdx.homeFilterFieldOptions(b, m, '');
    List<String> s(Set<String>? v) => (v ?? const <String>{}).toList()..sort();
    return {
      'engines': sortCatalogEngineSizeLabels(o?.engineSizes ?? const <String>{}),
      'cylinders': (o?.cylinderCounts ?? const <String>{}).toList()
        ..sort((a, c) => int.parse(a).compareTo(int.parse(c))),
      'body': s(o?.bodyTypes),
      'fuel': s(o?.fuelTypes),
      'drive': s(o?.driveTypes),
      'transmission': s(o?.transmissions),
      'seating': s(o?.seatings),
    };
  }

  group('the exclusion table is exactly the audited, approved list', () {
    test('18 rules / 13 models / 572 rows, identical to the audit artifact', () {
      final expected = <String, Set<String>>{};
      for (final e in entries) {
        final key =
            '${carSpecSpacedNameKey(e['brand'] as String)}|${carSpecSpacedNameKey(e['model'] as String)}';
        expected.putIfAbsent(key, () => <String>{}).add(e['exclude_prefix'] as String);
      }
      expect(entries.length, 18);
      expect(entries.fold<int>(0, (a, e) => a + (e['rows'] as int)), 572);
      expect(carSpecReviewedFamilyExclusions.keys.toSet(), expected.keys.toSet());
      expect(carSpecReviewedFamilyExclusions.length, 13);
      for (final e in expected.entries) {
        expect(carSpecReviewedFamilyExclusions[e.key]!.toSet(), e.value, reason: e.key);
      }
      expect(
        carSpecReviewedFamilyExclusions.values.fold<int>(0, (a, v) => a + v.length),
        18,
      );
    });

    test('each rule matches exactly the number of dataset rows the audit counted', () {
      final brands = {
        for (final b in (spec['brands'] as List)) (b as Map)['id'] as int: b['name'] as String,
      };
      final datasetModels = (spec['models'] as List).cast<Map<String, dynamic>>();
      var total = 0;
      for (final e in entries) {
        final brand = e['brand'] as String;
        final prefix = e['exclude_prefix'] as String;
        var n = 0;
        for (final m in datasetModels) {
          if (brands[m['brand_id']] != brand) continue;
          final dn = carSpecSpacedNameKey(m['name'] as String);
          if (dn == prefix || dn.startsWith('$prefix ')) n++;
        }
        expect(n, e['rows'], reason: '$brand $prefix');
        total += n;
      }
      expect(total, 572);
    });

    test('ONLY approved rules fire, and each fires only for its own brand+model', () {
      // every rule's sample dataset name is excluded for its model and for NO other catalog model
      final catalogModels = (catalogJson['models'] as Map<String, dynamic>);
      for (final e in entries) {
        final brand = e['brand'] as String;
        final model = e['model'] as String;
        final sample = '${e['exclude_prefix']} 1 6 (100 Hp)';
        for (final be in catalogModels.entries) {
          for (final m in (be.value as List).cast<String>()) {
            final fires = carSpecDatasetNameIsReviewedExclusion(be.key, m, sample);
            if (be.key == brand && m == model) {
              expect(fires, isTrue, reason: '$brand $model must exclude $sample');
            } else {
              // the other model of the SAME rule family, or any other brand/model, never fires
              final ownRule = (carSpecReviewedFamilyExclusions[
                          '${carSpecSpacedNameKey(be.key)}|${carSpecSpacedNameKey(m)}'] ??
                      const <String>[])
                  .any((p) => carSpecSpacedNameKey(sample) == p ||
                      carSpecSpacedNameKey(sample).startsWith('$p '));
              expect(fires, ownRule, reason: '${be.key} $m vs $sample');
            }
          }
        }
      }
    });

    test('whole-phrase prefix only: lookalikes and other spellings are not excluded', () {
      expect(carSpecDatasetNameIsReviewedExclusion('Toyota', 'Corolla', 'Corolla Verso 1 8 (110 Hp)'), isTrue);
      expect(carSpecDatasetNameIsReviewedExclusion('Toyota', 'Corolla', 'Corolla Versos 1 8'), isFalse);
      expect(carSpecDatasetNameIsReviewedExclusion('Toyota', 'Corolla', 'Corolla 1 8 (136 Hp)'), isFalse);
      expect(carSpecDatasetNameIsReviewedExclusion('Toyota', 'Corolla Cross', 'Corolla Cross 2 0'), isFalse);
      expect(carSpecDatasetNameIsReviewedExclusion('Toyota', 'Camry', 'Corolla Verso 1 8'), isFalse);
      expect(carSpecDatasetNameIsReviewedExclusion('Lexus', 'Corolla', 'Corolla Verso 1 8'), isFalse);
      expect(carSpecDatasetNameIsReviewedExclusion('Chery', 'Tiggo 2', 'Tiggo 2 0 (125 Hp)'), isTrue);
      expect(carSpecDatasetNameIsReviewedExclusion('Chery', 'Tiggo 2', 'Tiggo 2 Pro 1 5'), isFalse);
      expect(carSpecDatasetNameIsReviewedExclusion('Chery', 'Tiggo 2', 'Tiggo 2 1 5 (106 Hp)'), isFalse);
      // brand spelling folds like everywhere else
      expect(carSpecDatasetNameIsReviewedExclusion('Mercedes-Benz', 'EQS', 'EQS SUV EQS 450 120 kWh'), isTrue);
      expect(carSpecDatasetNameIsReviewedExclusion('Mercedes-Benz', 'EQS', 'EQS 450+ 107 8 kWh'), isFalse);
    });
  });

  group('audit rows: excluded classes leave the family, SAFE and AMBIGUOUS stay', () {
    test('every one of the 2,265 audited rows lands exactly where its class says', () {
      final byModel = <String, List<Map<String, dynamic>>>{};
      for (final r in auditRows) {
        byModel
            .putIfAbsent(k(r['flutter_brand'] as String, r['flutter_model'] as String), () => [])
            .add(r);
      }
      var removed = 0, kept = 0, ambiguousKept = 0, safeKept = 0;
      for (final e in byModel.entries) {
        final parts = e.key.split('|');
        final fam = rows(parts[0], parts[1]);
        for (final r in e.value) {
          final name = r['raw_name'] as String;
          final cls = r['class'] as String;
          if (excludedClasses.contains(cls)) {
            expect(fam.contains(name), isFalse, reason: '$name ($cls) must be excluded from ${e.key}');
            removed++;
          } else {
            expect(fam.contains(name), isTrue, reason: '$name ($cls) must stay in ${e.key}');
            kept++;
            if (cls == 'AMBIGUOUS') ambiguousKept++;
            if (cls == 'SAFE_TRIM_OR_VARIANT') safeKept++;
          }
        }
      }
      expect(auditRows.length, 2265);
      expect(removed, auditRows.where((r) => excludedClasses.contains(r['class'])).length);
      expect(ambiguousKept, 557);
      expect(safeKept, 1136);
      expect(kept, 557 + 1136);
    });

    test('the removed rows are counted by dataset row: 570 OTHER + 2 MALFORMED = 572', () {
      expect(auditRows.where((r) => r['class'] == 'OTHER_MODEL_OR_SIBLING').length, 570);
      expect(auditRows.where((r) => r['class'] == 'MALFORMED_OR_NOISY').length, 2);
      // the exclusion keys of those rows are exactly the 18 approved prefixes
      final keys = {
        for (final r in auditRows)
          if (excludedClasses.contains(r['class']))
            '${carSpecSpacedNameKey(r['flutter_model'] as String)} ${r['exclusion_key']}'.trim(),
      };
      final approved = {for (final e in entries) e['exclude_prefix'] as String};
      // audit keys carry the model name + exclusion key; every one of them is an approved prefix
      expect(keys.difference(approved), isEmpty);
      expect(approved.difference(keys), isEmpty);
    });

    test('named AMBIGUOUS / SAFE examples are untouched', () {
      bool has(String b, String m, String starts) =>
          rows(b, m).any((n) => carSpecSpacedNameKey(n).startsWith(starts));
      expect(has('Ford', 'F-250', 'f 250 super duty'), isTrue); // SAFE series name
      expect(has('Ford', 'F-350', 'f 350 super duty'), isTrue);
      expect(has('Dodge', 'Ram', 'ram drw'), isTrue); // AMBIGUOUS DRW
      expect(has('Mercedes-Benz', 'E-Class', 'e class e 200 t'), isTrue); // AMBIGUOUS
      expect(has('Renault', 'Megane', 'megane conquest'), isTrue); // AMBIGUOUS
      expect(has('Volkswagen', 'Polo', 'polo gti'), isTrue); // SAFE
      expect(has('Volkswagen', 'Golf', 'golf gtd'), isTrue); // SAFE
      expect(has('Porsche', '911', '911 carrera gts'), isTrue); // SAFE
    });
  });

  group('runtime options after the exclusion = audit "current" minus the audit\'s selective loss', () {
    test('baseline engines/cylinders/body/fuel/drive/transmission/seats of all 13 models', () {
      var checked = 0;
      for (final key in carSpecReviewedFamilyExclusions.keys) {
        // find the catalog model behind the spaced key
        String? brand, model;
        for (final be in (catalogJson['models'] as Map<String, dynamic>).entries) {
          if (carSpecSpacedNameKey(be.key) != key.split('|').first) continue;
          for (final m in (be.value as List).cast<String>()) {
            if (carSpecSpacedNameKey(m) == key.split('|').last) {
              brand = be.key;
              model = m;
            }
          }
        }
        expect(brand, isNotNull, reason: key);
        final before = auditModels[k(brand!, model!)]!['current'] as Map<String, dynamic>;
        final lost = (selectiveChanged[k(brand, model)]?['lost'] as Map<String, dynamic>?) ?? const {};
        final now = baseline(brand, model);
        // body / drive are deliberately NOT compared: the audit's "current" values were
        // produced by the old Sedan / FWD defaults. Their new evidence-only semantics are
        // covered by test/body_drivetrain_normalization_test.dart.
        for (final f in ['engines', 'cylinders', 'fuel', 'transmission', 'seating']) {
          final exp = (before[f] as List).cast<String>().toSet()
            ..removeAll(((lost[f] as List?) ?? const []).cast<String>());
          expect(now[f]!.toSet(), exp, reason: '$brand $model $f');
        }
        checked++;
      }
      expect(checked, 13);
    });

    test('models with a selective change in the audit are exactly the ones whose options change', () {
      expect(selectiveChanged.length, 11);
      var engineModels = 0, cylModels = 0, otherModels = 0;
      for (final m in selectiveChanged.values) {
        final lost = m['lost'] as Map<String, dynamic>;
        if ((lost['engines'] as List).isNotEmpty) engineModels++;
        if ((lost['cylinders'] as List).isNotEmpty) cylModels++;
        if (['body', 'fuel', 'drive', 'transmission', 'seating']
            .any((f) => (lost[f] as List).isNotEmpty)) {
          otherModels++;
        }
      }
      expect((engineModels, cylModels, otherModels), (7, 4, 8));
    });
  });

  group('Toyota Corolla acceptance', () {
    test('Corolla no longer receives Verso / Spacio / Rumion rows', () {
      final corolla = rows('Toyota', 'Corolla');
      for (final n in corolla) {
        final key = carSpecSpacedNameKey(n);
        expect(key.startsWith('corolla verso'), isFalse, reason: n);
        expect(key.startsWith('corolla spacio'), isFalse, reason: n);
        expect(key.startsWith('corolla rumion'), isFalse, reason: n);
        expect(key.startsWith('corolla cross'), isFalse, reason: n);
      }
      // 258 rows before (strict sibling matcher) - 27 reviewed rows (20 + 5 + 2) = 231
      expect(plainIdx.debugFamilyDatasetModelNames('Toyota', 'Corolla').length, 231);
    });

    test('contaminated 2.2 TD and the 7-seat option are gone; legitimate options stay', () {
      final o = baseline('Toyota', 'Corolla');
      final before = auditModels[k('Toyota', 'Corolla')]!['current'] as Map<String, dynamic>;
      expect(before['engines'], contains('2.2 TD'));
      expect(before['seating'], contains('7'));
      expect(o['engines'], isNot(contains('2.2 TD')));
      expect(o['seating'], isNot(contains('7')));
      expect(o['cylinders'], before['cylinders']);
      expect(o['engines']!.toSet(), (before['engines'] as List).cast<String>().toSet()..remove('2.2 TD'));
      expect(o['seating']!.toSet(), (before['seating'] as List).cast<String>().toSet()..remove('7'));
      // legitimate Corolla trims remain (SAFE rows such as 'Corolla SL 1100')
      expect(rows('Toyota', 'Corolla').any((n) => n.toLowerCase().startsWith('corolla sl ')), isTrue);
    });

    test('Corolla Cross is untouched and still isolated from Corolla', () {
      final cross = rows('Toyota', 'Corolla Cross');
      expect(cross, isNotEmpty);
      expect(cross.every((n) => carSpecSpacedNameKey(n).startsWith('corolla cross')), isTrue);
      expect(auditModels.containsKey(k('Toyota', 'Corolla Cross')), isFalse);
      expect(rows('Toyota', 'Corolla').intersection(cross), isEmpty);
    });

    test('effective Search engines for Corolla follow the corrected baseline + IQ', () {
      final s = search(iqIdx, 'Toyota', 'Corolla');
      expect(s.engineSizes, isNot(contains('2.2 TD')));
      expect(s.cylinderCounts, containsAll(['Any', '4']));
    });
  });

  group('Ford Transit and Suzuki SX4: every legacy row belonged to another line', () {
    test('baseline has no rows left (hasCoverage false) - accepted', () {
      for (final (b, m) in [('Ford', 'Transit'), ('Suzuki', 'SX4')]) {
        expect(rows(b, m), isEmpty, reason: '$b $m');
        expect(plainIdx.hasCoverage(b, m), isFalse, reason: '$b $m');
        expect(plainIdx.homeFilterFieldOptions(b, m, ''), isNull, reason: '$b $m');
      }
    });

    test('trusted IQ model-level data is used when it exists (Search and Sell)', () {
      final t = search(iqIdx, 'Ford', 'Transit');
      expect(t.engineSizes.first, 'Any');
      expect(t.engineSizes, containsAll(['2.0 TD', '2.2 TD', '2.4 TD', '3.2', '3.5', '3.7']));
      expect(t.engineSizes, isNot(contains('1.5 D'))); // Transit Connect engines are gone
      expect(t.engineSizes, isNot(contains('1.0 T')));
      expect(t.cylinderCounts, ['Any', '4', '5', '6']);
      final ts = sell(iqIdx, 'Ford', 'Transit', 2020);
      expect(ts.cylinders, ['4', '5', '6']);
      expect(ts.engines, containsAll(['2.0 TD', '3.7']));

      final x = search(iqIdx, 'Suzuki', 'SX4');
      expect(x.engineSizes, ['Any', '1.5', '1.6', '2.0']);
      expect(x.cylinderCounts, ['Any', '4']);
      final xs = sell(iqIdx, 'Suzuki', 'SX4', 2012);
      expect(xs.cylinders, ['4']);
      expect(xs.engines, ['Any', '1.5', '1.6', '2.0']);
    });

    test('without any trusted data: Search -> Any only, Sell -> existing manual fallback', () {
      final raw = jsonDecode(File('assets/car_iqcars_overlay.json').readAsStringSync())
          as Map<String, dynamic>;
      (raw['Ford'] as Map).remove('Transit');
      (raw['Suzuki'] as Map).remove('SX4');
      final bare = parseCarSpecDatasetJsonString(specRaw).index!
        ..attachIqCarsOverlay(IqCarsOverlay.parse(jsonEncode(raw)));
      for (final (b, m) in [('Ford', 'Transit'), ('Suzuki', 'SX4')]) {
        final s = search(bare, b, m);
        expect(s.engineSizes, ['Any'], reason: '$b $m');
        expect(s.cylinderCounts, ['Any'], reason: '$b $m');
        final sl = sell(bare, b, m, 2018);
        expect(sl.engines, ['<full default ladder>'], reason: '$b $m');
        expect(sl.cylinders, sellCylinderDefaults, reason: '$b $m');
      }
    });
  });

  group('other reviewed high-risk models', () {
    bool none(String b, String m, List<String> startsWith) => rows(b, m).every((n) {
          final key = carSpecSpacedNameKey(n);
          return !startsWith.any(key.startsWith);
        });

    test('GMC Sierra vs Sierra 2500HD / 3500HD', () {
      expect(none('GMC', 'Sierra', ['sierra 2500hd', 'sierra 3500hd']), isTrue);
      expect(rows('GMC', 'Sierra'), isNotEmpty);
      final o = baseline('GMC', 'Sierra');
      expect(o['engines'], isNot(contains('6.6')));
      expect(o['engines'], isNot(contains('6.6 D')));
      // the light-duty Sierra keeps its own rows
      expect(rows('GMC', 'Sierra').any((n) => carSpecSpacedNameKey(n).startsWith('sierra 1500')), isTrue);
    });

    test('Toyota Crown vs Crown Majesta', () {
      expect(none('Toyota', 'Crown', ['crown majesta']), isTrue);
      final o = baseline('Toyota', 'Crown');
      expect(o['cylinders'], isNot(contains('8')));
      expect(o['engines']!.toSet().intersection({'4.0', '4.3', '4.6'}), isEmpty);
      // IQ still carries its own approved Crown cylinders/engines (effective option sets are unioned)
      expect(search(iqIdx, 'Toyota', 'Crown').cylinderCounts, contains('8'));
    });

    test('Volkswagen Polo vs Polo Vivo (SAFE Polo GTI / BlueGT stay)', () {
      expect(none('Volkswagen', 'Polo', ['polo vivo']), isTrue);
      expect(rows('Volkswagen', 'Polo').any((n) => n.toLowerCase().startsWith('polo gti')), isTrue);
      expect(rows('Volkswagen', 'Polo').any((n) => n.toLowerCase().startsWith('polo bluegt')), isTrue);
    });

    test('Mercedes EQS vs EQS SUV', () {
      expect(none('Mercedes-Benz', 'EQS', ['eqs suv']), isTrue);
      expect(rows('Mercedes-Benz', 'EQS'), isNotEmpty);
      expect(baseline('Mercedes-Benz', 'EQS')['body'], isNot(contains('SUV')));
    });

    test('Renault Megane vs Megane GrandCoupe (AMBIGUOUS Megane Conquest stays)', () {
      expect(none('Renault', 'Megane', ['megane grandcoupe']), isTrue);
      expect(rows('Renault', 'Megane').any((n) => n.toLowerCase().startsWith('megane conquest')), isTrue);
    });

    test('Hyundai Ioniq vs Ioniq 9 (Ioniq 5 / 6 stay isolated)', () {
      expect(none('Hyundai', 'Ioniq', ['ioniq 9']), isTrue);
      expect(rows('Hyundai', 'Ioniq').intersection(rows('Hyundai', 'Ioniq 5')), isEmpty);
      expect(rows('Hyundai', 'Ioniq').intersection(rows('Hyundai', 'Ioniq 6')), isEmpty);
      expect(rows('Hyundai', 'Ioniq 5'), isNotEmpty);
    });

    test('Toyota Urban Cruiser vs Hyryder; Avensis vs Verso; Suzuki Vitara vs Brezza / e Vitara', () {
      expect(none('Toyota', 'Urban Cruiser', ['urban cruiser hyryder']), isTrue);
      expect(baseline('Toyota', 'Urban Cruiser')['cylinders'], isNot(contains('3')));
      expect(none('Toyota', 'Avensis', ['avensis verso']), isTrue);
      expect(baseline('Toyota', 'Avensis')['seating'], isNot(contains('7')));
      expect(none('Suzuki', 'Vitara', ['vitara brezza', 'vitara e vitara']), isTrue);
      expect(baseline('Suzuki', 'Vitara')['fuel'], isNot(contains('Electric')));
    });

    test('Chery Tiggo malformed "2 0" / "2 4" rows no longer attach to Tiggo 2', () {
      expect(none('Chery', 'Tiggo 2', ['tiggo 2 0 ', 'tiggo 2 4 ']), isTrue);
      final o = baseline('Chery', 'Tiggo 2');
      expect(o['engines']!.toSet().intersection({'2.0', '2.4'}), isEmpty);
    });
  });

  group('previous fixes are intact', () {
    test('strict sibling isolation: Land Cruiser 74 / Prado 77, disjoint', () {
      final lc = rows('Toyota', 'Land Cruiser');
      final pr = rows('Toyota', 'Land Cruiser Prado');
      expect(plainIdx.debugFamilyDatasetModelNames('Toyota', 'Land Cruiser').length, 74);
      expect(plainIdx.debugFamilyDatasetModelNames('Toyota', 'Land Cruiser Prado').length, 77);
      expect(lc.intersection(pr), isEmpty);
      expect(lc.any((n) => n.toLowerCase().startsWith('land cruiser prado')), isFalse);
      expect(baseline('Toyota', 'Land Cruiser Prado')['engines'], containsAll(['2.4 D']));
      expect(iqIdx.iqOnlyFieldOptions('Toyota', 'Land Cruiser Prado', CarSpecIndex.catalogAutofillModelOnly), isNotNull);
    });

    test('other sibling pairs stay isolated in both directions', () {
      for (final p in [
        ('Volkswagen', 'Golf', 'Golf R'),
        ('Ford', 'Bronco', 'Bronco Sport'),
        ('Mitsubishi', 'Pajero', 'Pajero Sport'),
        ('Land Rover', 'Discovery', 'Discovery Sport'),
        ('Volkswagen', 'Passat', 'Passat CC'),
      ]) {
        final a = rows(p.$1, p.$2), b = rows(p.$1, p.$3);
        expect(a.intersection(b), isEmpty, reason: '${p.$2} / ${p.$3}');
        expect(a, isNotEmpty);
        expect(b, isNotEmpty);
      }
    });

    test('BMW series naming, Rolls Royce, Ram 2500 and "/" families still behave', () {
      for (var i = 1; i <= 8; i++) {
        expect(plainIdx.hasCoverage('BMW', '$i-Series'), isTrue, reason: '$i-Series');
      }
      expect(plainIdx.hasCoverage('Rolls Royce', 'Ghost'), isTrue);
      expect(plainIdx.hasCoverage('Ram', '2500'), isTrue);
      expect(carSpecDatasetNameMatchesFamily('Ram', '2500', '2500/3500 2500 6 7'), isTrue);
      // slash families remain unresolved (not folded)
      expect(carSpecDatasetNameMatchesFamily('Audi', 'S6', 'S6/S7 4 0 TFSI'), isFalse);
      expect(carSpecSpacedNameKey('S6/S7'), 's6/s7');
    });

    test('Geely Cityray cylinder-3 quarantine and full IQ cylinder sets are intact', () {
      final cityray = iqIdx.iqOnlyFieldOptions('Geely', 'Cityray', CarSpecIndex.catalogAutofillModelOnly);
      expect(cityray?.cylinderCounts ?? const <String>{}, isNot(contains('3')));
      expect(overlay.hasCylinderCounts('Toyota', 'Hilux'), isTrue);
    });
  });
}
