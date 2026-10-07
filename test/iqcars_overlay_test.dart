import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/iqcars_overlay.dart';

/// Unit tests of the runtime IQ Cars overlay: parsing, additive merge helpers,
/// keyed lookup, and the load-once / fail-safe loading contract.
const String _doc = '''
{
  "_meta": {"format": 1},
  "Ford": {
    "Everest": {
      "trims_add": ["Titanium", "Trend", "Ambiente"],
      "engine_sizes_add": ["2.7L", "2.2L", "2.5L", "2.3L"],
      "cylinders_add": [6, 4]
    },
    "Ranger": {"trims_add": ["Wildtrak"]}
  },
  "Toyota": {
    "Land Cruiser": {"trims_add": ["GR HEV", "VX Limited"]},
    "Land Cruiser Prado": {"trims_add": ["TXS", "A4 Adventure"]}
  }
}
''';

List<double> sortedLiters(Iterable<String> labels) =>
    labels.map((l) => double.parse(l.split(' ').first)).toList()..sort();

void main() {
  tearDown(IqCarsOverlay.debugResetForTest);

  group('parsing', () {
    test('reads the three independent lists and ignores _meta', () {
      final o = IqCarsOverlay.parse(_doc);
      expect(o.modelCount, 4);
      final e = o.additionsFor('Ford', 'Everest')!;
      expect(e.trims, ['Titanium', 'Trend', 'Ambiente']); // exported order
      expect(e.engineLiters, [2.2, 2.3, 2.5, 2.7]); // ascending numeric
      expect(e.cylinders, [4, 6]); // ascending numeric
      expect(o.additionsFor('Ford', 'Ranger')!.engineLiters, isEmpty);
      expect(o.additionsFor('_meta', 'format'), isNull);
    });

    test('garbage never throws and yields the empty overlay', () {
      for (final raw in <String>[
        '',
        'not json',
        '[]',
        '42',
        'null',
        '{"Ford": 3}',
        '{"Ford": {"Everest": 7}}',
        '{"Ford": {"Everest": {}}}',
      ]) {
        final o = IqCarsOverlay.parse(raw);
        expect(o.isEmpty, isTrue, reason: raw);
        expect(o.additionsFor('Ford', 'Everest'), isNull, reason: raw);
      }
    });

    test('malformed entries are skipped, valid siblings survive', () {
      final o = IqCarsOverlay.parse('''
      {"Ford": {
        "Everest": {"trims_add": [1, null, "  Titanium  ", "titanium", ""],
                    "engine_sizes_add": ["2.7L", "TD", "4.5TD", 2.7, "0.0L", "139"],
                    "cylinders_add": [6, "8", "x", -1, 0, 2.5]},
        "Broken": {"trims_add": "nope"}
      }}''');
      final e = o.additionsFor('Ford', 'Everest')!;
      expect(e.trims, ['Titanium']); // trimmed + case-insensitive dedupe
      expect(e.engineLiters, [2.7]); // displacement only, never qualifiers/raw
      expect(e.cylinders, [6, 8]);
      expect(o.additionsFor('Ford', 'Broken'), isNull);
    });
  });

  group('lookup', () {
    test('Land Cruiser and Land Cruiser Prado are separate keys', () {
      final o = IqCarsOverlay.parse(_doc);
      final lc = o.additionsFor('Toyota', 'Land Cruiser')!;
      final prado = o.additionsFor('Toyota', 'Land Cruiser Prado')!;
      expect(lc.trims, ['GR HEV', 'VX Limited']);
      expect(prado.trims, ['TXS', 'A4 Adventure']);
      expect(o.additionsFor('Toyota', 'Land Cruiser FJ'), isNull);
      expect(o.additionsFor('Toyota', 'Land'), isNull);
    });

    test('unknown / null keys answer null and the answer is memoised', () {
      final o = IqCarsOverlay.parse(_doc);
      expect(o.additionsFor(null, 'Everest'), isNull);
      expect(o.additionsFor('Ford', null), isNull);
      expect(o.additionsFor('Ford', 'Mustang'), isNull);
      expect(o.additionsFor('Nope', 'Everest'), isNull);
      final a = o.additionsFor('Ford', 'Everest');
      expect(identical(a, o.additionsFor('Ford', 'Everest')), isTrue);
      // same canonical names, different case / spacing
      expect(identical(a, o.additionsFor(' ford ', 'EVEREST')), isTrue);
    });

    test('lookup stays cheap: 200k keyed lookups', () {
      final o = IqCarsOverlay.parse(_doc);
      final sw = Stopwatch()..start();
      var hits = 0;
      for (var i = 0; i < 200000; i++) {
        if (o.additionsFor('Ford', 'Everest') != null) hits++;
      }
      sw.stop();
      expect(hits, 200000);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });
  });

  group('additive merges', () {
    final o = IqCarsOverlay.parse(_doc);

    test('trims: catalog order first, new ones appended, nothing removed', () {
      const base = ['Limited', 'XLT', 'Mid Range', 'XLS'];
      final merged = o.mergeTrims(base, 'Ford', 'Everest');
      expect(merged, [...base, 'Titanium', 'Trend', 'Ambiente']);
    });

    test('trims: a trailing Other placeholder stays last', () {
      final merged = o.mergeTrims(
        ['Limited', 'XLT', 'Other'],
        'Ford',
        'Everest',
      );
      expect(merged, ['Limited', 'XLT', 'Titanium', 'Trend', 'Ambiente', 'Other']);
    });

    test('trims: deduplicated case-insensitively against the catalog', () {
      final merged = o.mergeTrims(
        ['titanium', 'XLT'],
        'Ford',
        'Everest',
      );
      expect(merged, ['titanium', 'XLT', 'Trend', 'Ambiente']);
    });

    test('trims: nothing new returns the very same baseline list', () {
      const base = ['Titanium', 'Trend', 'Ambiente'];
      expect(identical(o.mergeTrims(base, 'Ford', 'Everest'), base), isTrue);
      expect(identical(o.mergeTrims(base, 'Ford', 'Mustang'), base), isTrue);
    });

    test('trims never merge lookalikes: only exact additions are added', () {
      final lc = IqCarsOverlay.parse(
        '{"Toyota": {"Land Cruiser": {"trims_add": ["VX.E"]}}}',
      );
      // EX.R / EXR style lookalikes are held upstream and never reach the asset.
      final merged = lc.mergeTrims(['EXR', 'VXR'], 'Toyota', 'Land Cruiser');
      expect(merged, ['EXR', 'VXR', 'VX.E']);
      expect(merged.contains('EX.R'), isFalse);
    });

    test('engine sizes: added as plain litres, ascending after catalog sort', () {
      final labels = <String>{'2.0', '3.5 T'};
      o.addEngineSizes(labels, 'Ford', 'Everest');
      expect(labels, {'2.0', '3.5 T', '2.2', '2.3', '2.5', '2.7'});
      expect(labels.any((l) => l.contains('L') || l.contains('TD')), isFalse);
    });

    test('legacy plain sizes are a different engine from a qualified label', () {
      // Identity is displacement + qualifier: plain 2.2 is NOT '2.2 D'.
      final labels = <String>{'2.2 D', '2.5 T'};
      o.addEngineSizes(labels, 'Ford', 'Everest');
      expect(labels, {'2.2 D', '2.5 T', '2.2', '2.3', '2.5', '2.7'});
    });

    group('engine identity = displacement + normalised qualifier', () {
      IqCarsOverlay variants(String list) => IqCarsOverlay.parse(
            '{"Acme": {"Zeta": {"engine_variants_add": $list}}}',
          );

      Set<String> merged(Iterable<String> baseline, String list) {
        final s = <String>{...baseline};
        variants(list).addEngineSizes(s, 'Acme', 'Zeta');
        return s;
      }

      test('1. Prado: baseline 2.4 D + IQ 2.4T -> both survive', () {
        expect(merged({'2.4 D'}, '["2.4T"]'), {'2.4 D', '2.4 T'});
      });

      test('2. 4.5 vs 4.5TD (and 3.5 vs 3.5T): both survive', () {
        expect(merged({'4.5'}, '["4.5TD"]'), {'4.5', '4.5 TD'});
        expect(merged({'4.5 TD'}, '["4.5"]'), {'4.5 TD', '4.5'});
        expect(merged({'3.5'}, '["3.5T"]'), {'3.5', '3.5 T'});
      });

      test('3. 2.4T vs "2.4 T" / "2.4 Turbo" / unit text: one option', () {
        expect(merged({'2.4 T'}, '["2.4T"]'), {'2.4 T'});
        expect(merged({'2.4T'}, '["2.4T"]'), {'2.4T'},
            reason: 'an existing label is never rewritten');
        expect(merged({'2.4 Turbo'}, '["2.4T"]'), {'2.4 Turbo'});
        expect(merged({'2.4L T'}, '["2.4T"]').length, 1);
      });

      test('4. 2.4 vs 2.4: one option (also with unit text)', () {
        expect(merged({'2.4'}, '["2.4"]'), {'2.4'});
        expect(merged({'2.4L'}, '["2.4"]'), {'2.4L'});
      });

      test('D / TD / T / plain are four distinct engines', () {
        expect(
          merged({'2.4'}, '["2.4D","2.4TD","2.4T"]'),
          {'2.4', '2.4 D', '2.4 TD', '2.4 T'},
        );
        expect(merged({'2.4 D'}, '["2.4TD"]'), {'2.4 D', '2.4 TD'});
      });

      test('an unknown qualifier is kept verbatim, never collapsed', () {
        final e = variants('["2.4TC"]').additionsFor('Acme', 'Zeta')!;
        expect(e.engineVariants.single.label, '2.4 TC');
        expect(merged({'2.4'}, '["2.4TC"]'), {'2.4', '2.4 TC'});
      });

      test('label style follows the app: litres with one decimal + qualifier',
          () {
        final e = variants('["2.4T","3.0TD","2.7"]').additionsFor('Acme', 'Zeta')!;
        expect(e.engineVariants.map((v) => v.label).toList(),
            ['2.4 T', '2.7', '3.0 TD']);
      });

      test('existing values are never removed', () {
        final s = merged({'2.4 D', '9.9 X', '1.0'}, '["2.4T"]');
        expect(s.containsAll({'2.4 D', '9.9 X', '1.0'}), isTrue);
      });

      test('normalizeEngineQualifier and parseEngineIdentity', () {
        expect(normalizeEngineQualifier(' turbo '), 'T');
        expect(normalizeEngineQualifier('Diesel'), 'D');
        expect(normalizeEngineQualifier('TurboDiesel'), 'TD');
        expect(normalizeEngineQualifier(''), '');
        final id = parseEngineIdentity('2.4 Turbo')!;
        expect((id.tenths, id.qualifier), (24, 'T'));
        final id2 = parseEngineIdentity('2.0L')!;
        expect((id2.tenths, id2.qualifier), (20, ''));
        expect(parseEngineIdentity('Electric'), isNull);
      });

      test('format-2 asset: variants parse, dedupe and sort', () {
        final e = variants('["2.7","2.4T","2.4 T","2.4TD","bad","2.4T"]')
            .additionsFor('Acme', 'Zeta')!;
        expect(e.engineVariants.map((v) => v.identity).toList(),
            ['24|T', '24|TD', '27|']);
        expect(e.engineLiters, [2.4, 2.7]);
      });
    });

    test('an EMPTY CarNet set is filled by the approved IQ values', () {
      final engines = <String>{};
      final cyls = <String>{};
      o.addEngineSizes(engines, 'Ford', 'Everest');
      o.addCylinderCounts(cyls, 'Ford', 'Everest');
      expect(engines, {'2.2', '2.3', '2.5', '2.7'});
      expect(cyls, {'4', '6'}, reason: 'the fixture supplies cylinders 4 and 6');
    });

    group('empty / populated baseline union (explicit semantics)', () {
      final m = IqCarsOverlay.parse(
        '{"Acme": {"Zeta": {"engine_sizes_add": ["2.0L","2.5L"], '
        '"cylinders_add": [4,6]}}}',
      );

      test('baseline engines [] + IQ [2.0L, 2.5L] -> [2.0, 2.5]', () {
        final engines = <String>{};
        m.addEngineSizes(engines, 'Acme', 'Zeta');
        expect(engines, {'2.0', '2.5'});
        expect(engines.length, 2);
      });

      test('baseline cylinders [] + IQ [4, 6] -> [4, 6]', () {
        final cyls = <String>{};
        m.addCylinderCounts(cyls, 'Acme', 'Zeta');
        expect(cyls, {'4', '6'});
      });

      test('baseline engines [2.0L] + IQ [2.0L, 2.5L] -> [2.0L, 2.5], no duplicate',
          () {
        final engines = <String>{'2.0L'};
        m.addEngineSizes(engines, 'Acme', 'Zeta');
        expect(engines, {'2.0L', '2.5'});
        // Same displacement in the catalog's own label form: still just one.
        final catalogForm = <String>{'2.0'};
        m.addEngineSizes(catalogForm, 'Acme', 'Zeta');
        expect(catalogForm, {'2.0', '2.5'});
        expect(sortedLiters(catalogForm), [2.0, 2.5]);
      });

      test('baseline cylinders [4] + IQ [4, 6] -> [4, 6], no duplicate', () {
        final cyls = <String>{'4'};
        m.addCylinderCounts(cyls, 'Acme', 'Zeta');
        expect(cyls, {'4', '6'});
      });

      test('a model without an entry stays empty (nothing invented)', () {
        final engines = <String>{};
        final cyls = <String>{};
        m.addEngineSizes(engines, 'Acme', 'Other Model');
        m.addCylinderCounts(cyls, 'Acme', 'Other Model');
        expect(engines, isEmpty);
        expect(cyls, isEmpty);
      });

      test('the empty overlay never fills anything', () {
        final engines = <String>{};
        IqCarsOverlay.empty.addEngineSizes(engines, 'Acme', 'Zeta');
        expect(engines, isEmpty);
      });
    });

    test('cylinders: only explicitly supplied counts, union with the catalog',
        () {
      final cyls = <String>{'4', '8'};
      o.addCylinderCounts(cyls, 'Ford', 'Everest');
      expect(cyls, {'4', '6', '8'});
      final none = <String>{'4'};
      o.addCylinderCounts(none, 'Ford', 'Ranger');
      expect(none, {'4'}, reason: 'Ranger has no cylinder additions');
    });

    test('models without an entry change nothing', () {
      final engines = <String>{'1.6'};
      final cyls = <String>{'4'};
      o.addEngineSizes(engines, 'Volkswagen', 'Golf R');
      o.addCylinderCounts(cyls, 'Volkswagen', 'Golf R');
      expect(engines, {'1.6'});
      expect(cyls, {'4'});
    });

    test('the empty overlay is a strict no-op', () {
      final engines = <String>{'1.6'};
      IqCarsOverlay.empty.addEngineSizes(engines, 'Ford', 'Everest');
      expect(engines, {'1.6'});
      const base = ['A'];
      expect(
        identical(IqCarsOverlay.empty.mergeTrims(base, 'Ford', 'Everest'), base),
        isTrue,
      );
    });
  });

  group('loading', () {
    test('loads once, parses once, then serves the same instance', () async {
      var reads = 0;
      IqCarsOverlay.debugAssetLoader = (path) async {
        reads++;
        expect(path, IqCarsOverlay.assetPath);
        return _doc;
      };
      final a = await IqCarsOverlay.ensureLoaded();
      final b = await IqCarsOverlay.ensureLoaded();
      final futures = await Future.wait([
        IqCarsOverlay.ensureLoaded(),
        IqCarsOverlay.ensureLoaded(),
      ]);
      expect(reads, 1);
      expect(IqCarsOverlay.loadCount, 1);
      expect(identical(a, b), isTrue);
      expect(futures.every((f) => identical(f, a)), isTrue);
      expect(identical(IqCarsOverlay.current, a), isTrue);
      expect(a.modelCount, 4);
    });

    test('a missing asset falls back to the empty overlay', () async {
      IqCarsOverlay.debugAssetLoader =
          (path) async => throw StateError('Unable to load asset: $path');
      final o = await IqCarsOverlay.ensureLoaded();
      expect(o.isEmpty, isTrue);
      expect(identical(o, IqCarsOverlay.empty), isTrue);
      expect(IqCarsOverlay.current.isEmpty, isTrue);
    });

    test('a malformed asset falls back to the empty overlay', () async {
      IqCarsOverlay.debugAssetLoader = (path) async => '{"Ford": ';
      final o = await IqCarsOverlay.ensureLoaded();
      expect(o.isEmpty, isTrue);
    });

    test('a failure is also remembered: no reload loop', () async {
      var reads = 0;
      IqCarsOverlay.debugAssetLoader = (path) async {
        reads++;
        throw StateError('missing');
      };
      await IqCarsOverlay.ensureLoaded();
      await IqCarsOverlay.ensureLoaded();
      expect(reads, 1);
    });
  });
}
