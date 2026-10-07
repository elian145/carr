import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/data/car_catalog_loader.dart';
import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

/// Search + Sell integration of the approved IQ Cars additions, against the REAL
/// bundled assets: catalog, spec dataset and the runtime overlay.
///
/// Contract under test: effective options = existing CarNet values UNION approved
/// IQ additions. Nothing is removed, nothing is inferred, held / ambiguous /
/// unmatched / default-list values never appear.
void main() {
  late String specRaw;
  late Map<String, dynamic> catalogJson;
  late String overlayRaw;
  late IqCarsOverlay overlay;
  late Map<String, dynamic> exclusions;

  const searchCylinderDefaults = [
    'Any', '1', '2', '3', '4', '5', '6', '8', '10', '12', '16', //
  ];
  const sellCylinderDefaults = ['3', '4', '5', '6', '8', '10', '12'];

  setUpAll(() {
    specRaw = File('assets/car_spec_dataset.json').readAsStringSync();
    catalogJson = jsonDecode(File('assets/car_catalog.json').readAsStringSync())
        as Map<String, dynamic>;
    overlayRaw = File('assets/car_iqcars_overlay.json').readAsStringSync();
    overlay = IqCarsOverlay.parse(overlayRaw);
    exclusions = jsonDecode(
      File(
        'tools/catalog_enrichment/iqcars/generated/carnet_iqcars_overlay_exclusions.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  setUp(() {
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalog.applyCatalogFromAsset(catalogJson);
    CarCatalogLoader.debugResetForTest();
    IqCarsOverlay.debugResetForTest();
  });

  tearDown(() {
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalogLoader.debugResetForTest();
    IqCarsOverlay.debugResetForTest();
  });

  CarSpecIndex plain() => parseCarSpecDatasetJsonString(specRaw).index!;
  CarSpecIndex withIq() => plain()..attachIqCarsOverlay(overlay);

  List<String> trimsBefore(String b, String m) {
    CarCatalog.applyIqCarsOverlay(IqCarsOverlay.empty);
    return List<String>.of(CarCatalog.trimsFor(b, m));
  }

  List<String> trimsAfter(String b, String m) {
    CarCatalog.applyIqCarsOverlay(overlay);
    return List<String>.of(CarCatalog.trimsFor(b, m));
  }

  Set<String> ivLabels(String b, String m) => {
        for (final v in overlay.additionsFor(b, m)!.engineVariants) v.label,
      };

  Set<double> litres(Set<String>? labels) => {
        for (final l in labels ?? const <String>{})
          double.parse(l.split(' ').first),
      };

  group('the runtime asset', () {
    test('is compact and matches the reviewed candidate totals', () {
      expect(File('assets/car_iqcars_overlay.json').lengthSync(), lessThan(150 * 1024));
      expect(overlay.modelCount, 1558);
      var trims = 0, engines = 0, cyls = 0;
      for (final b in overlay.entries) {
        for (final m in b.value.values) {
          trims += m.trims.length;
          engines += m.engineVariants.length;
          cyls += m.cylinders.length;
        }
      }
      expect((trims, engines, cyls), (1791, 3468, 2121));
    });

    test('carries only the three lists: no research metadata leaks in', () {
      final doc = jsonDecode(overlayRaw) as Map<String, dynamic>;
      for (final b in doc.entries) {
        if (b.key == '_meta') continue;
        for (final m in (b.value as Map<String, dynamic>).values) {
          expect((m as Map).keys.toSet().difference({'trims_add', 'engine_variants_add', 'cylinders'}), isEmpty);
        }
      }
      for (final banned in ['http', 'iq_', 'raw_values', '"qualifier"', 'held', 'warnings', 'relationships']) {
        expect(overlayRaw.contains(banned), isFalse, reason: banned);
      }
    });
  });

  group('exclusions stay excluded', () {
    test('ambiguous / unmatched / explicitly excluded models are absent', () {
      for (final key in ['ambiguous_iq_models', 'unmatched_iq_models', 'explicitly_excluded_models']) {
        for (final e in exclusions[key] as List) {
          final brand = e['iq_brand'] as String;
          final model = e['iq_model'] as String;
          // Land Cruiser FJ has no entry of its own; the unmatched models are
          // not CarNet models at all.
          final a = overlay.additionsFor(brand, model);
          expect(a, isNull, reason: '$brand $model must stay excluded');
        }
      }
      expect(overlay.additionsFor('Toyota', 'Land Cruiser FJ'), isNull);
    });

    test('held duplicate trims never appear in the overlay or the merged lists', () {
      var checked = 0;
      for (final e in exclusions['trims_held_for_review'] as List) {
        final brand = e['brand'] as String;
        final model = e['model'] as String;
        final held = e['iq_trim'] as String;
        final adds = overlay.additionsFor(brand, model)?.trims ?? const <String>[];
        expect(adds.contains(held), isFalse, reason: '$brand $model "$held"');
        final merged = trimsAfter(brand, model);
        final base = trimsBefore(brand, model);
        if (!base.contains(held)) {
          expect(merged.contains(held), isFalse, reason: '$brand $model "$held"');
        }
        checked++;
      }
      expect(checked, 98);
    });

    test('the shared 139-engine / 10-cylinder defaults never reach any model', () {
      for (final e in exclusions['unrestricted_default_engine_lists'] as List) {
        final a = overlay.additionsFor(e['brand'] as String, e['model'] as String);
        expect(a?.engineLiters ?? const <double>[], isEmpty, reason: '${e['brand']} ${e['model']}');
      }
      for (final e in exclusions['unrestricted_default_cylinder_lists'] as List) {
        final a = overlay.additionsFor(e['brand'] as String, e['model'] as String);
        expect(a?.cylinders ?? const <int>[], isEmpty, reason: '${e['brand']} ${e['model']}');
      }
      for (final b in overlay.entries) {
        for (final m in b.value.entries) {
          expect(m.value.engineLiters.length, lessThan(20), reason: '${b.key} ${m.key}');
          expect(m.value.cylinders.length, lessThan(7), reason: '${b.key} ${m.key}');
        }
      }
    });

    test('an EV with IQ default lists gains no combustion engine or cylinder', () {
      // Audi Q4 e-tron: IQ returned the shared defaults; only trims are approved.
      final plainIdx = plain();
      final iqIdx = withIq();
      final a = plainIdx.homeFilterFieldOptions('Audi', 'Q4 e-tron', '');
      final b = iqIdx.homeFilterFieldOptions('Audi', 'Q4 e-tron', '');
      expect(b?.engineSizes ?? const <String>{}, a?.engineSizes ?? const <String>{});
      expect(b?.cylinderCounts ?? const <String>{}, a?.cylinderCounts ?? const <String>{});
      expect(overlay.additionsFor('Audi', 'Q4 e-tron')?.engineLiters ?? const <double>[], isEmpty);
      expect(overlay.additionsFor('Audi', 'Q4 e-tron')?.cylinders ?? const <int>[], isEmpty);
    });
  });

  group('Ford Everest', () {
    test('trims: existing kept in order, Titanium / Trend / Ambiente added, Other last', () {
      final before = trimsBefore('Ford', 'Everest');
      final after = trimsAfter('Ford', 'Everest');
      expect(before, ['Limited', 'XLT', 'Mid Range', 'XLS', 'Other']);
      expect(after, [
        'Limited', 'XLT', 'Mid Range', 'XLS', //
        'Titanium', 'Trend', 'Ambiente', 'Other',
      ]);
    });

    test('engine variants gain 2.2 TD / 2.3 T / 2.5 / 2.7 T / 3.2 TD and keep every existing size', () {
      final a = plain().homeFilterFieldOptions('Ford', 'Everest', '')!;
      final b = withIq().homeFilterFieldOptions('Ford', 'Everest', '')!;
      expect(a.engineSizes, {'2.0 D', '2.0 TD', '3.0 TD', '3.2 D'});
      expect(b.engineSizes.containsAll(a.engineSizes), isTrue);
      expect(b.engineSizes.difference(a.engineSizes),
          {'2.2 TD', '2.3 T', '2.5', '2.7 T', '3.2 TD'});
      // CarNet's '3.2 D' and IQ's 3.2TD are different engines: both listed.
      expect(b.engineSizes, containsAll(['3.2 D', '3.2 TD']));
      // Raw unit text never becomes a picker value.
      expect(b.engineSizes.any((s) => s.contains('L')), isFalse);
      expect(b.cylinderCounts, a.cylinderCounts, reason: 'no cylinder additions for Everest');
    });
  });

  group('Toyota Land Cruiser vs Land Cruiser Prado', () {
    test('Land Cruiser gets its safe trims and none of the held / Prado ones', () {
      final before = trimsBefore('Toyota', 'Land Cruiser');
      final after = trimsAfter('Toyota', 'Land Cruiser');
      expect(after.where(before.contains).toList(), before,
          reason: 'existing trims keep their order');
      expect(after.last, 'Other', reason: 'the Other placeholder stays last');
      expect(after.length, before.length + 18);
      for (final t in ['G', 'GR', 'GX.R.i', 'GR HEV', 'VX HEV', 'VX Limited', 'VX.E']) {
        expect(after, contains(t));
      }
      // held lookalikes (EX.R/EXR, VX.S/VXS, VX.R/VXR, GX.R/GXR ...)
      for (final t in ['EX.R', 'VX.S', 'VX.R', 'GX.R', 'GX.R Grand Touring', 'VX.R.i', 'VX 3.5L Twin-Turbo', 'VX 3.5L Twin Turbo', 'VX.R Grand Touring']) {
        expect(after, isNot(contains(t)), reason: t);
      }
      // Prado-only additions
      for (final t in ['VXE', 'TXS', 'A4 Adventure', 'All Rounder', 'R2', 'R3']) {
        expect(after, isNot(contains(t)), reason: t);
      }
    });

    test('Prado stays separate: its own additions, none of the Land Cruiser ones', () {
      final after = trimsAfter('Toyota', 'Land Cruiser Prado');
      for (final t in ['VXE', 'TXS', 'A4 Adventure', 'All Rounder', 'R2', 'R3']) {
        expect(after, contains(t));
      }
      for (final t in ['GR HEV', 'VX HEV', 'GX.R.i', 'VX Limited', 'VX.E']) {
        expect(after, isNot(contains(t)), reason: t);
      }
      expect(trimsAfter('Toyota', 'Land Cruiser Prado').length,
          trimsBefore('Toyota', 'Land Cruiser Prado').length + 10);
    });

    test('no contaminated engines or cylinders are added to either', () {
      // Engines: only the model's own approved IQ variants may be added, never
      // from the sibling model and never from the shared default list.
      for (final m in ['Land Cruiser', 'Land Cruiser Prado']) {
        final a = plain().homeFilterFieldOptions('Toyota', m, '')!;
        final b = withIq().homeFilterFieldOptions('Toyota', m, '')!;
        final own = {
          for (final v in overlay.additionsFor('Toyota', m)!.engineVariants)
            v.label,
        };
        expect(b.engineSizes.containsAll(a.engineSizes), isTrue, reason: m);
        expect(own.containsAll(b.engineSizes.difference(a.engineSizes)), isTrue,
            reason: m);
        expect(b.engineSizes.length, lessThan(40), reason: m);
        expect(b.cylinderCounts, a.cylinderCounts, reason: m);
      }
    });

    test('Land Cruiser keeps its sizes and adds only the missing variants', () {
      final a = plain().homeFilterFieldOptions('Toyota', 'Land Cruiser', '')!;
      final b = withIq().homeFilterFieldOptions('Toyota', 'Land Cruiser', '')!;
      expect(b.engineSizes.difference(a.engineSizes), {'3.3 TD', '4.2 TD'});
      // 4.5 / 4.5 D / 4.5 TD were all CarNet's already: no duplicates.
      expect(b.engineSizes.where((s) => s.startsWith('4.5')).length, 3);
    });

    test('a selected trim never changes the options: model-level IQ variants are kept (Prado, Everest, LX, X5, Land Cruiser)', () {
      final base = plain();
      final iq = withIq();
      var checked = 0;
      for (final (b, m) in [
        ('Toyota', 'Land Cruiser Prado'),
        ('Toyota', 'Land Cruiser'),
        ('Ford', 'Everest'),
        ('Lexus', 'LX'),
        ('BMW', 'X5'),
      ]) {
        for (final trim in trimsAfter(b, m)) {
          final x = base.homeFilterFieldOptions(b, m, trim);
          final y = iq.homeFilterFieldOptions(b, m, trim);
          final x0 = base.homeFilterFieldOptions(b, m, '');
          final y0 = iq.homeFilterFieldOptions(b, m, '');
          expect(y == null, y0 == null, reason: '$b $m $trim');
          if (x == null || y == null || x0 == null || y0 == null) continue;
          // The trim changes neither the CarNet nor the IQ-widened sets.
          expect(x.engineSizes, x0.engineSizes, reason: '$b $m $trim');
          expect(y.engineSizes, y0.engineSizes, reason: '$b $m $trim');
          expect(y.cylinderCounts, y0.cylinderCounts, reason: '$b $m $trim');
          expect(y.engineSizes.containsAll(x.engineSizes), isTrue);
          checked++;
        }
      }
      expect(checked, greaterThan(0));
    });

    test('Prado: CarNet 2.4 D and IQ 2.4 T are both offered (real data)', () {
      final a = plain().homeFilterFieldOptions('Toyota', 'Land Cruiser Prado', '')!;
      final b = withIq().homeFilterFieldOptions('Toyota', 'Land Cruiser Prado', '')!;
      expect(a.engineSizes, contains('2.4 D'));
      expect(a.engineSizes, isNot(contains('2.4 T')));
      expect(b.engineSizes, containsAll(['2.4 D', '2.4 T']));
      expect(b.engineSizes.difference(a.engineSizes), {'2.4 T'});
      // Sell step 2 (model-level, per-year) offers it too.
      final iq = withIq();
      final years = iq.yearsForCatalogStep('Toyota', 'Land Cruiser Prado', '');
      final s = iq.sellFieldOptionsUnion('Toyota', 'Land Cruiser Prado',
          CarSpecIndex.catalogAutofillModelOnly, years.first)!;
      expect(s.engineSizes, contains('2.4 T'));
    });
  });

  group('empty CarNet baseline is filled by the approved IQ values (model level)', () {
    // Covered models whose CarNet spec rows carry NO engine size / NO cylinder
    // count at all, but which have approved IQ additions.
    List<(String, String)> emptyBaseline({required bool engines}) {
      final base = plain();
      final out = <(String, String)>[];
      for (final b in overlay.entries) {
        for (final m in b.value.entries) {
          final x = base.homeFilterFieldOptions(b.key, m.key, '');
          if (x == null) continue;
          if (engines && x.engineSizes.isEmpty && m.value.engineLiters.isNotEmpty) {
            out.add((b.key, m.key));
          }
          if (!engines && x.cylinderCounts.isEmpty && m.value.cylinders.isNotEmpty) {
            out.add((b.key, m.key));
          }
        }
      }
      return out;
    }

    test('such models exist in the real data (so the rule is exercised)', () {
      expect(emptyBaseline(engines: true), isNotEmpty);
      expect(emptyBaseline(engines: false), isNotEmpty);
    });

    test('engines: baseline [] -> exactly the IQ displacements (Search union)', () {
      final base = plain();
      final iq = withIq();
      for (final (b, m) in emptyBaseline(engines: true)) {
        final x = base.homeFilterFieldOptions(b, m, '')!;
        final y = iq.homeFilterFieldOptions(b, m, '')!;
        expect(x.engineSizes, isEmpty, reason: '$b $m');
        expect(y.engineSizes, ivLabels(b, m), reason: '$b $m');
        // app label style, no "L" and no invented qualifier
        expect(y.engineSizes.every((e) => RegExp(r'^\d{1,2}\.\d( (TD|TC|T|D))?$').hasMatch(e)), isTrue, reason: '$b $m');
      }
    });

    test('cylinders: baseline [] -> exactly the IQ counts (Search union)', () {
      final base = plain();
      final iq = withIq();
      for (final (b, m) in emptyBaseline(engines: false)) {
        final x = base.homeFilterFieldOptions(b, m, '')!;
        final y = iq.homeFilterFieldOptions(b, m, '')!;
        expect(x.cylinderCounts, isEmpty, reason: '$b $m');
        expect(y.cylinderCounts, overlay.additionsFor(b, m)!.cylinders.map((c) => '$c').toSet(), reason: '$b $m');
      }
    });

    test('Sell step 2 (per-year, model-only) fills the same way', () {
      final base = plain();
      final iq = withIq();
      for (final (b, m) in emptyBaseline(engines: true)) {
        final years = base.yearsForCatalogStep(b, m, '');
        if (years.isEmpty) continue;
        final x = base.sellFieldOptionsUnion(b, m, CarSpecIndex.catalogAutofillModelOnly, years.first);
        final y = iq.sellFieldOptionsUnion(b, m, CarSpecIndex.catalogAutofillModelOnly, years.first);
        expect(x, isNotNull);
        expect(x!.engineSizes, isEmpty, reason: '$b $m');
        expect(y!.engineSizes, ivLabels(b, m), reason: '$b $m');
      }
    });

    test('a selected trim receives the same additive model-level list as no trim', () {
      final iq = withIq();
      var checked = 0;
      for (final (b, m) in [...emptyBaseline(engines: true), ...emptyBaseline(engines: false)]) {
        for (final trim in CarCatalog.trimsFor(b, m)) {
          if (trim.trim().isEmpty) continue;
          final y = iq.homeFilterFieldOptions(b, m, trim);
          final y0 = iq.homeFilterFieldOptions(b, m, '');
          expect(y == null, y0 == null, reason: '$b $m $trim');
          if (y == null || y0 == null) continue;
          expect(y.engineSizes, y0.engineSizes, reason: '$b $m $trim');
          expect(y.cylinderCounts, y0.cylinderCounts, reason: '$b $m $trim');
          checked++;
        }
      }
      expect(checked, greaterThan(0));
    });
  });

  group('Lexus LX / BMW X5 / Golf R', () {
    test('Lexus LX gains its IQ variants (3.3 TD / 3.4 T / 3.5 T) and its approved trims', () {
      final a = plain().homeFilterFieldOptions('Lexus', 'LX', '')!;
      final b = withIq().homeFilterFieldOptions('Lexus', 'LX', '')!;
      expect(litres(a.engineSizes), isNot(contains(3.5)));
      expect(b.engineSizes.difference(a.engineSizes), {'3.3 TD', '3.4 T', '3.5 T'});
      expect(b.engineSizes.containsAll(a.engineSizes), isTrue);
      final after = trimsAfter('Lexus', 'LX');
      final before = trimsBefore('Lexus', 'LX');
      expect(after.take(before.length), before);
      for (final t in ['570', '450d', '600 Prestige', '700h']) {
        expect(after, contains(t));
      }
    });

    test('BMW X5 keeps its sizes and gains 3.0 T / 3.0 TD / 4.4 T', () {
      final a = plain().homeFilterFieldOptions('BMW', 'X5', '')!;
      final b = withIq().homeFilterFieldOptions('BMW', 'X5', '')!;
      expect(b.engineSizes.containsAll(a.engineSizes), isTrue);
      expect(b.engineSizes.difference(a.engineSizes), {'3.0 T', '3.0 TD', '4.4 T'});
    });

    test('BMW X5 gains approved trims; held lookalikes stay out', () {
      final before = trimsBefore('BMW', 'X5');
      final after = trimsAfter('BMW', 'X5');
      expect(after.take(before.length - 1), before.take(before.length - 1));
      expect(after.last, 'Other');
      for (final t in ['40i', '35i', 'xDrive30d', 'M Competition', 'xDrive40d', 'xDrive48i']) {
        expect(after, contains(t));
      }
      // xDrive30i ('xDrive 30i' exists), xDrive50i ('Xdrive50i' exists), 30i ('3.0i' exists)
      for (final t in ['xDrive30i', '30i']) {
        expect(after, isNot(contains(t)), reason: t);
      }
      expect(after.where((t) => t.toLowerCase() == 'xdrive50i').length, 1);
    });

    test('Volkswagen Golf R carries only its cylinder set: nothing visibly changes', () {
      final adds = overlay.additionsFor('Volkswagen', 'Golf R')!;
      expect(adds.cylinders, [4]);
      expect(adds.trims, isEmpty);
      expect(adds.engineVariants, isEmpty);
      expect(trimsAfter('Volkswagen', 'Golf R'), trimsBefore('Volkswagen', 'Golf R'));
      final a = plain().homeFilterFieldOptions('Volkswagen', 'Golf R', '')!;
      final b = withIq().homeFilterFieldOptions('Volkswagen', 'Golf R', '')!;
      expect(b.engineSizes, a.engineSizes);
      expect(b.cylinderCounts, a.cylinderCounts);
    });
  });

  group('purely additive over the whole overlay', () {
    test('every model: trims / engines / cylinders are supersets, other fields identical', () {
      final base = plain();
      final iq = withIq();
      var modelsWithEngineGain = 0, modelsWithCylGain = 0, covered = 0;
      for (final b in overlay.entries) {
        for (final m in b.value.entries) {
          final x = base.homeFilterFieldOptions(b.key, m.key, '');
          final y = iq.homeFilterFieldOptions(b.key, m.key, '');
          if (x == null) {
            // Legacy gate says "no coverage": the overlay may answer, but only
            // for the engine / cylinder fields it supplies -- nothing else.
            if (y != null) {
              expect(base.hasCoverage(b.key, m.key), isFalse, reason: '${b.key} ${m.key}');
              expect(y.bodyTypes, isEmpty);
              expect(y.fuelTypes, isEmpty);
              expect(y.driveTypes, isEmpty);
              expect(y.transmissions, isEmpty);
              expect(y.seatings, isEmpty);
              expect(y.engineSizes.isNotEmpty, m.value.engineLiters.isNotEmpty);
              expect(y.cylinderCounts.isNotEmpty, m.value.cylinders.isNotEmpty);
            } else {
              expect(m.value.engineLiters.isEmpty && m.value.cylinders.isEmpty, isTrue,
                  reason: '${b.key} ${m.key}: IQ data must not be dropped');
            }
            continue;
          }
          expect(y, isNotNull, reason: '${b.key} ${m.key}: covered stays covered');
          if (y == null) continue;
          covered++;
          expect(y.engineSizes.containsAll(x.engineSizes), isTrue, reason: '${b.key} ${m.key}');
          expect(y.cylinderCounts.containsAll(x.cylinderCounts), isTrue, reason: '${b.key} ${m.key}');
          expect(y.bodyTypes, x.bodyTypes);
          expect(y.fuelTypes, x.fuelTypes);
          expect(y.driveTypes, x.driveTypes);
          expect(y.transmissions, x.transmissions);
          expect(y.seatings, x.seatings);
          // Added values are only ever approved ones.
          final addedEngines = litres(y.engineSizes.difference(x.engineSizes));
          expect(m.value.engineLiters.toSet().containsAll(addedEngines), isTrue, reason: '${b.key} ${m.key}');
          expect(ivLabels(b.key, m.key).containsAll(y.engineSizes.difference(x.engineSizes)), isTrue, reason: '${b.key} ${m.key}: added labels are IQ variants');
          final addedCyls = y.cylinderCounts.difference(x.cylinderCounts);
          expect(m.value.cylinders.map((c) => '$c').toSet().containsAll(addedCyls), isTrue, reason: '${b.key} ${m.key}');
          // An EMPTY catalog field is filled by exactly the approved IQ values.
          if (x.engineSizes.isEmpty) {
            expect(litres(y.engineSizes), m.value.engineLiters.toSet(), reason: '${b.key} ${m.key}');
          }
          if (x.cylinderCounts.isEmpty) {
            expect(y.cylinderCounts, m.value.cylinders.map((c) => '$c').toSet(), reason: '${b.key} ${m.key}');
          }
          if (y.engineSizes.length > x.engineSizes.length) modelsWithEngineGain++;
          if (y.cylinderCounts.length > x.cylinderCounts.length) modelsWithCylGain++;
        }
      }
      expect(covered, greaterThan(400));
      expect(modelsWithEngineGain, greaterThan(100));
      expect(modelsWithCylGain, greaterThan(20));
    });

    test('every catalog trim list keeps all existing trims in the same relative order', () {
      CarCatalog.applyIqCarsOverlay(IqCarsOverlay.empty);
      final baseline = {
        for (final b in CarCatalog.trimsByBrandModel.entries)
          b.key: {for (final m in b.value.entries) m.key: List<String>.of(m.value)},
      };
      CarCatalog.applyIqCarsOverlay(overlay);
      var grown = 0;
      for (final b in baseline.entries) {
        for (final m in b.value.entries) {
          final now = CarCatalog.trimsByBrandModel[b.key]?[m.key];
          expect(now, isNotNull, reason: '${b.key} ${m.key} disappeared');
          expect(now!.where(m.value.contains).toList(), m.value, reason: '${b.key} ${m.key}');
          if (now.length > m.value.length) grown++;
        }
      }
      expect(grown, greaterThan(200));
    });

    test('a trim-scoped resolution equals the model-level one (trim never changes options)', () {
      for (final (br, mo, tr) in [
        ('Toyota', 'Camry', 'SE'),
        ('Ford', 'Everest', 'Limited'),
      ]) {
        final withTrim = withIq().homeFilterFieldOptions(br, mo, tr);
        final modelLevel = withIq().homeFilterFieldOptions(br, mo, '');
        expect(withTrim?.engineSizes, modelLevel?.engineSizes, reason: mo);
        expect(withTrim?.cylinderCounts, modelLevel?.cylinderCounts, reason: mo);
        expect(withTrim?.fuelTypes, modelLevel?.fuelTypes, reason: mo);
      }
    });
  });

  group('Search integration', () {
    HomeVehicleFieldDefaults defaults() => const HomeVehicleFieldDefaults(
          bodyTypes: ['Any', 'SUV'],
          transmissions: ['Any', 'Automatic', 'Manual'],
          fuelTypes: ['Any', 'Gasoline', 'Diesel'],
          driveTypes: ['Any', 'FWD', 'RWD', 'AWD', '4WD'],
          cylinderCounts: searchCylinderDefaults,
          seatings: ['Any', '5'],
          engineSizes: ['Any', 'default'],
        );

    HomeVehicleFieldOptions resolve(CarSpecIndex idx, String b, String m) {
      final ctx = HomeVehicleContext(brand: b, model: m);
      return HomeVehicleFieldOptions.resolve(
        catalog: resolveHomeVehicleCatalogOptions(idx, ctx),
        engineCatalog: resolveHomeVehicleEngineCatalogOptions(idx, ctx),
        defaults: defaults(),
      );
    }

    test('Everest: the engine picker lists the new sizes, ascending, after Any', () {
      final o = resolve(withIq(), 'Ford', 'Everest');
      expect(o.engineSizes.first, 'Any');
      expect(o.engineSizes, ['Any', '2.0 D', '2.0 TD', '2.2 TD', '2.3 T', '2.5', '2.7 T', '3.0 TD', '3.2 D', '3.2 TD']);
      expect(o.narrowedFields, contains(HomeVehicleField.engineSize));
    });

    test('cylinders: added counts join the narrowed list in default-list order', () {
      final base = plain();
      final iq = withIq();
      String? found;
      for (final b in overlay.entries) {
        for (final m in b.value.entries) {
          final x = base.homeFilterFieldOptions(b.key, m.key, '');
          final y = iq.homeFilterFieldOptions(b.key, m.key, '');
          if (x == null || y == null || x.cylinderCounts.isEmpty) continue;
          final gained = y.cylinderCounts.difference(x.cylinderCounts);
          if (gained.isEmpty || !gained.every(searchCylinderDefaults.contains)) continue;
          final before = resolve(base, b.key, m.key).cylinderCounts;
          final after = resolve(iq, b.key, m.key).cylinderCounts;
          expect(after.where(before.contains).toList(), before, reason: 'existing options keep their order');
          expect(after.toSet().difference(before.toSet()), gained);
          // order follows the default list, 'Any' retained
          final order = after.map(searchCylinderDefaults.indexOf).toList();
          expect(order, [...order]..sort());
          expect(after.first, 'Any');
          found = '${b.key} ${m.key}';
          break;
        }
        if (found != null) break;
      }
      expect(found, isNotNull, reason: 'at least one model gains a cylinder count');
    });

    test('Search picker for an empty-baseline model narrows to the IQ values', () {
      final base = plain();
      String? b, m;
      for (final be in overlay.entries) {
        for (final me in be.value.entries) {
          final x = base.homeFilterFieldOptions(be.key, me.key, '');
          if (x != null && x.engineSizes.isEmpty && me.value.engineLiters.isNotEmpty) {
            b = be.key;
            m = me.key;
          }
        }
      }
      expect(b, isNotNull);
      final o = resolve(withIq(), b!, m!);
      expect(o.engineSizes.first, 'Any');
      expect(o.engineSizes.skip(1).toSet(), ivLabels(b, m));
      final ls = o.engineSizes.skip(1).map((e) => double.parse(e.split(' ').first)).toList();
      expect(ls, [...ls]..sort(), reason: 'ascending litres');
      expect(o.narrowedFields, contains(HomeVehicleField.engineSize));
      // without the overlay the same model keeps the full default ladder
      expect(resolve(plain(), b, m).engineSizes, ['Any', 'default']);
    });

    test('a field the catalog has no data for still shows the full defaults', () {
      final o = resolve(withIq(), 'Not A Brand', 'Not A Model');
      expect(o.cylinderCounts, searchCylinderDefaults);
      expect(o.narrowedFields, isEmpty);
    });

    test('memoised resolution survives attach: same instance until the overlay changes', () {
      final idx = plain();
      final a = idx.homeFilterFieldOptions('Ford', 'Everest', '');
      expect(identical(a, idx.homeFilterFieldOptions('Ford', 'Everest', '')), isTrue);
      idx.attachIqCarsOverlay(overlay);
      final b = idx.homeFilterFieldOptions('Ford', 'Everest', '');
      expect(identical(a, b), isFalse, reason: 'stale pre-overlay answer was dropped');
      expect(b!.engineSizes, contains('2.7 T'));
      expect(identical(b, idx.homeFilterFieldOptions('Ford', 'Everest', '')), isTrue);
      idx.attachIqCarsOverlay(overlay); // idempotent: cache kept
      expect(identical(b, idx.homeFilterFieldOptions('Ford', 'Everest', '')), isTrue);
      idx.attachIqCarsOverlay(null); // detach -> pure catalog again
      expect(idx.homeFilterFieldOptions('Ford', 'Everest', '')!.engineSizes, isNot(contains('2.7 T')));
    });

    test('repeated model switching stays on cached answers (no repeated overlay scans)', () {
      final idx = withIq();
      final models = [
        ['Ford', 'Everest'], ['Toyota', 'Camry'], ['Lexus', 'LX'], ['BMW', 'X5'], //
      ];
      for (final m in models) {
        idx.homeFilterFieldOptions(m[0], m[1], '');
      }
      final sw = Stopwatch()..start();
      for (var i = 0; i < 2000; i++) {
        final m = models[i % models.length];
        idx.homeFilterFieldOptions(m[0], m[1], '');
      }
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('Sell integration', () {
    test('trim picker: catalog trims + approved additions (Base kept where it was the only entry)', () {
      expect(trimsAfter('Ford', 'Everest'), contains('Titanium'));
      // A model with no catalog trims: Sell keeps its 'Base' entry and adds the IQ ones.
      String? model;
      String? brand;
      for (final b in overlay.entries) {
        for (final m in b.value.entries) {
          if (m.value.trims.isEmpty) continue;
          if (trimsBefore(b.key, m.key).length == 1 && trimsBefore(b.key, m.key).first == 'Base' && CarCatalog.baselineTrimsByBrandModel[b.key]?[m.key] == null) {
            brand = b.key;
            model = m.key;
            break;
          }
        }
        if (model != null) break;
      }
      expect(model, isNotNull);
      final after = trimsAfter(brand!, model!);
      expect(after.first, 'Base');
      expect(after.skip(1).toList(), overlay.additionsFor(brand, model)!.trims);
      // Search reads the map: no phantom 'Base' there, just the additions.
      expect(CarCatalog.trimsByBrandModel[brand]![model], overlay.additionsFor(brand, model)!.trims);
    });

    test('step 2 option sets: per-year union gains the IQ sizes and keeps every existing one', () {
      final base = plain();
      final iq = withIq();
      for (final year in [2012, 2018, 2022]) {
        final a = base.sellFieldOptionsUnion('Ford', 'Everest', CarSpecIndex.catalogAutofillModelOnly, year);
        final b = iq.sellFieldOptionsUnion('Ford', 'Everest', CarSpecIndex.catalogAutofillModelOnly, year);
        if (a == null) {
          expect(b, isNull);
          continue;
        }
        expect(b!.engineSizes.containsAll(a.engineSizes), isTrue);
        expect(b.engineSizes, containsAll(['2.2 TD', '2.3 T', '2.5', '2.7 T']));
        // cylinders: baseline UNION the full approved IQ set (Everest 4/5/6)
        expect(b.cylinderCounts,
            {...a.cylinderCounts, ...overlay.additionsFor('Ford', 'Everest')!.cylinders.map((c) => '$c')});
        expect(b.fuelTypes, a.fuelTypes);
        expect(b.transmissions, a.transmissions);
      }
    });

    test('Sell cylinder picker narrows to defaults ∩ (catalog ∪ IQ) and never loses an option', () {
      final base = plain();
      final iq = withIq();
      for (final b in overlay.entries) {
        for (final m in b.value.entries) {
          final a = base.sellFieldOptionsUnion(b.key, m.key, '', 2020);
          final c = iq.sellFieldOptionsUnion(b.key, m.key, '', 2020);
          if (a == null || c == null) continue;
          final before = narrowOptionsToCatalog(sellCylinderDefaults, a.cylinderCounts);
          final after = narrowOptionsToCatalog(sellCylinderDefaults, c.cylinderCounts);
          if (a.cylinderCounts.isEmpty) {
            // CarNet knew nothing: the full default ladder used to show. The
            // approved IQ counts now fill the empty baseline (UNION), so the
            // picker narrows to them -- or stays on the defaults if none of
            // them is a Sell default (e.g. only 1/2/16).
            expect(c.cylinderCounts, m.value.cylinders.map((x) => '$x').toSet(),
                reason: '${b.key} ${m.key}');
          } else {
            expect(after.toSet().containsAll(before), isTrue, reason: '${b.key} ${m.key}');
          }
        }
      }
    });

    test('catalog load applies the real overlay once; a missing asset leaves the catalog untouched', () async {
      IqCarsOverlay.debugAssetLoader = (_) async => overlayRaw;
      await CarCatalogLoader.ensureLoaded();
      await CarCatalogLoader.ensureLoaded();
      expect(IqCarsOverlay.loadCount, 1);
      expect(CarCatalog.trimsFor('Ford', 'Everest'), contains('Titanium'));

      CarCatalog.resetCatalogOverrideForTest();
      CarCatalogLoader.debugResetForTest();
      IqCarsOverlay.debugResetForTest();
      IqCarsOverlay.debugAssetLoader = (p) async => throw StateError('missing $p');
      await CarCatalogLoader.ensureLoaded();
      expect(CarCatalog.trimsFor('Ford', 'Everest'), ['Limited', 'XLT', 'Mid Range', 'XLS', 'Other']);
      expect(CarCatalog.brands, isNotEmpty);
    });

    test('a malformed overlay asset leaves the catalog untouched', () async {
      IqCarsOverlay.debugAssetLoader = (_) async => '{"Ford": {"Everest": ';
      await CarCatalogLoader.ensureLoaded();
      expect(CarCatalog.trimsFor('Ford', 'Everest'), ['Limited', 'XLT', 'Mid Range', 'XLS', 'Other']);
    });

    test('a catalog re-apply (remote overlay path) re-merges instead of serving a stale cache', () {
      CarCatalog.applyIqCarsOverlay(overlay);
      final a = CarCatalog.trimsByBrandModel;
      expect(identical(a, CarCatalog.trimsByBrandModel), isTrue, reason: 'merged once, then cached');
      CarCatalog.applyCatalogFromAsset(catalogJson);
      expect(CarCatalog.trimsFor('Ford', 'Everest'), contains('Titanium'));
      expect(CarCatalog.baselineTrimsFor('Ford', 'Everest'), isNot(contains('Titanium')));
    });
  });

  group('runtime asset vs generator', () {
    test('every approved trim in the asset is also in the reviewed candidate', () {
      final cand = jsonDecode(File('tools/catalog_enrichment/iqcars/generated/carnet_iqcars_overlay_candidate.json').readAsStringSync()) as Map<String, dynamic>;
      final byKey = {
        for (final m in cand['models'] as List) '${m['brand']}\x1e${m['model']}': m as Map<String, dynamic>,
      };
      for (final b in overlay.entries) {
        for (final m in b.value.entries) {
          final c = byKey['${b.key}\x1e${m.key}'];
          expect(c, isNotNull, reason: '${b.key} ${m.key}');
          expect((c!['trims_add'] as List).cast<String>(), m.value.trims);
          expect((c['cylinders'] as List).cast<int>().toSet(), m.value.cylinders.toSet());
        }
      }
    });
  });
}
