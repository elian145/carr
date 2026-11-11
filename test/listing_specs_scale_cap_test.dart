// Six specification boxes on the listing-details page: text growth is capped
// at ~1.3x and the boxes must not keep growing taller.
//
// Before the fix the tile height was `design x textScale / 1.5` above 1.5x:
// on the iPhone 16 Pro Max the boxes went from 112.8 dp (1.0x-1.5x) to 150.4 dp
// at 2.0x (+33%) while the type itself was already limited by the tile width
// (~18.9 px), so the six boxes looked oversized and mostly empty.
//
// Renders the REAL `buildCarListingSpecsGrid` (padding 16 like the details
// page) and reads back the rendered tile rects and the RENDERED size of every
// label and value (font size x text scale x FittedBox scale).
import 'dart:math' as math;

import 'package:car_listing_app/features/listing/car_listing_specs_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/f10_scale_harness.dart';

const bool _print = bool.fromEnvironment('PRINT_LAYOUT_METRICS');

const Map<String, Size> _devices = <String, Size>{
  'iPhone 16 Pro Max 440x956': Size(440, 956),
  'iPhone 16 393x852': Size(393, 852),
  'Android 360x800': Size(360, 800),
  'Android small 320x640': Size(320, 640),
};

const List<double> _scales = <double>[1.0, 1.3, 1.5, 2.0];
const double _cap = 1.3;

const Map<String, dynamic> _typicalCar = <String, dynamic>{
  'mileage': 123456,
  'cylinders': 4,
  'engine_size': 2.0,
  'region_specs': 'us',
  'transmission': 'automatic',
  'fuel_type': 'gasoline',
  'trim': 'XLE',
  'condition': 'new',
  'color': 'brown',
  'seating': 5,
};

/// The longest real (enumerated) values next to short ones.
const Map<String, dynamic> _outlierCar = <String, dynamic>{
  'mileage': 8,
  'cylinders': 4,
  'engine_size': 2.0,
  'region_specs': 'us',
  'transmission': 'semi_automatic',
  'fuel_type': 'plug_in_hybrid',
  'trim': 'XLE',
  'condition': 'new',
  'color': 'brown',
  'seating': 5,
};

class _G {
  _G({
    required this.tiles,
    required this.valuePx,
    required this.labelPx,
    required this.valueRects,
    required this.labelRects,
  });
  final List<Rect> tiles;
  final List<double> valuePx;
  final List<double> labelPx;
  final List<Rect> valueRects;
  final List<Rect> labelRects;

  double get tileH => tiles.first.height;
  double get valueMin => valuePx.reduce(math.min);
  double get valueMax => valuePx.reduce(math.max);
  double get labelMin => labelPx.reduce(math.min);
  double get labelMax => labelPx.reduce(math.max);
}

Widget _page(Map<String, dynamic> car) => Scaffold(
  body: SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Builder(
        builder: (context) => buildCarListingSpecsGrid(context, car),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_G> pumpGrid(
    WidgetTester tester, {
    required Size size,
    required double scale,
    Map<String, dynamic> car = _typicalCar,
    bool bold = false,
    Locale locale = const Locale('en'),
  }) async {
    await f10LoadFonts(tester);
    f10SetWindow(tester, width: size.width, height: size.height);
    await f10Pump(
      tester,
      f10App(
        home: _page(car),
        textScale: scale,
        locale: locale,
        boldText: bold,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final fitted = find.descendant(
      of: find.byType(GridView).first,
      matching: find.byType(FittedBox),
    );
    expect(fitted.evaluate().length, 12, reason: '6 tiles x (label + value)');

    final tiles = <Rect>[];
    final valuePx = <double>[];
    final labelPx = <double>[];
    final valueRects = <Rect>[];
    final labelRects = <Rect>[];
    for (var i = 0; i < 12; i++) {
      final box = fitted.at(i);
      final textFinder = find.descendant(of: box, matching: find.byType(Text));
      final text = tester.widget<Text>(textFinder);
      final boxSize = tester.getSize(box);
      final textSize = tester.getSize(textFinder);
      final k = math.min(
        1.0,
        math.min(
          boxSize.width / textSize.width,
          boxSize.height / textSize.height,
        ),
      );
      // font size x system scale x FittedBox scale = what the user sees. The
      // scale actually applied to the Text comes from the inherited
      // MediaQuery (the grid may cap it), not from the harness value.
      final ctx = tester.element(textFinder);
      final applied = MediaQuery.textScalerOf(ctx).scale(1.0);
      final px = text.style!.fontSize! * applied * k;
      final tile = tester.getRect(
        find.ancestor(of: box, matching: find.byType(ClipRRect)).first,
      );
      if (i.isEven) {
        labelPx.add(px);
        labelRects.add(tester.getRect(textFinder));
      } else {
        valuePx.add(px);
        valueRects.add(tester.getRect(textFinder));
        tiles.add(tile);
      }
    }
    return _G(
      tiles: tiles,
      valuePx: valuePx,
      labelPx: labelPx,
      valueRects: valueRects,
      labelRects: labelRects,
    );
  }

  void expectCapped(_G at, _G base, double s, String label) {
    // Boxes do not grow taller than their 1.0x size: the type is capped, so
    // the extra height would only be empty space.
    expect(
      at.tileH,
      lessThanOrEqualTo(base.tileH + 0.5),
      reason:
          '$label: tile ${at.tileH.toStringAsFixed(1)} dp tall vs '
          '${base.tileH.toStringAsFixed(1)} dp at 1.0x',
    );
    // Value text never exceeds 1.3x of its 1.0x size ...
    expect(
      at.valueMax,
      lessThanOrEqualTo(base.valueMax * _cap + 0.3),
      reason:
          '$label: value text ${at.valueMax.toStringAsFixed(1)} px vs '
          '${base.valueMax.toStringAsFixed(1)} px at 1.0x (cap ${_cap}x)',
    );
    expect(
      at.labelMax,
      lessThanOrEqualTo(base.labelMax * _cap + 0.3),
      reason: '$label: label text ${at.labelMax.toStringAsFixed(1)} px',
    );
    // ... and never shrinks below readable.
    expect(
      at.valueMin,
      greaterThanOrEqualTo(base.valueMin * 0.85),
      reason:
          '$label: value text shrank to ${at.valueMin.toStringAsFixed(1)} px',
    );
  }

  void expectConsistent(_G g, String label) {
    expect(
      g.valueMax / g.valueMin,
      lessThanOrEqualTo(1.08),
      reason:
          '$label: six values differ in size '
          '(${g.valuePx.map((p) => p.toStringAsFixed(1)).join('/')})',
    );
    expect(
      g.labelMax / g.labelMin,
      lessThanOrEqualTo(1.08),
      reason:
          '$label: six labels differ in size '
          '(${g.labelPx.map((p) => p.toStringAsFixed(1)).join('/')})',
    );
    // Labels stay visibly smaller than values.
    expect(
      g.labelMax,
      lessThan(g.valueMin * 0.92),
      reason: '$label: labels are not distinguishable from values',
    );
    // Nothing clipped by its tile.
    for (var i = 0; i < 6; i++) {
      final t = g.tiles[i];
      for (final r in [g.valueRects[i], g.labelRects[i]]) {
        expect(r.left, greaterThanOrEqualTo(t.left - 0.6), reason: label);
        expect(r.right, lessThanOrEqualTo(t.right + 0.6), reason: label);
        expect(r.top, greaterThanOrEqualTo(t.top - 0.6), reason: label);
        expect(r.bottom, lessThanOrEqualTo(t.bottom + 0.6), reason: label);
      }
    }
  }

  void expectThreeByTwo(_G g, String label) {
    final lefts = g.tiles.map((t) => t.left.round()).toSet();
    final tops = g.tiles.map((t) => t.top.round()).toSet();
    expect(lefts.length, 3, reason: '$label: expected 3 columns');
    expect(tops.length, 2, reason: '$label: expected 2 rows');
  }

  group('boxes and type are capped at 1.3x (English, Bold Text on/off)', () {
    for (final d in _devices.entries) {
      for (final bold in const [false, true]) {
        for (final s in const [1.3, 1.5, 2.0]) {
          testWidgets('${d.key} bold=$bold @${s}x', (tester) async {
            final base = await pumpGrid(
              tester,
              size: d.value,
              scale: 1.0,
              bold: bold,
            );
            final at = await pumpGrid(
              tester,
              size: d.value,
              scale: s,
              bold: bold,
            );
            final label = '${d.key} bold=$bold @${s}x';
            if (_print) {
              // ignore: avoid_print
              print(
                'METRIC specs-cap | $label | tileH=${at.tileH.toStringAsFixed(1)} '
                '(1.0x ${base.tileH.toStringAsFixed(1)}) '
                'value=${at.valueMax.toStringAsFixed(1)}px '
                '(1.0x ${base.valueMax.toStringAsFixed(1)}px) '
                'label=${at.labelMax.toStringAsFixed(1)}px',
              );
            }
            expectCapped(at, base, s, label);
            expectConsistent(at, label);
            expectThreeByTwo(at, label);
          });
        }
      }
    }
  });

  group('identical above the cap', () {
    for (final d in _devices.entries) {
      testWidgets(d.key, (tester) async {
        final at13 = await pumpGrid(tester, size: d.value, scale: 1.3);
        for (final s in const [1.5, 2.0]) {
          final at = await pumpGrid(tester, size: d.value, scale: s);
          expect(
            at.tileH,
            closeTo(at13.tileH, 0.5),
            reason: '${d.key} @${s}x tile height differs from 1.3x',
          );
          expect(
            at.valueMax,
            closeTo(at13.valueMax, 0.3),
            reason: '${d.key} @${s}x value size differs from 1.3x',
          );
        }
      });
    }
  });

  group('longest real values (semi_automatic / plug_in_hybrid)', () {
    for (final d in _devices.entries) {
      for (final s in _scales) {
        testWidgets('${d.key} @${s}x', (tester) async {
          final base = await pumpGrid(
            tester,
            size: d.value,
            scale: 1.0,
            car: _outlierCar,
          );
          final at = await pumpGrid(
            tester,
            size: d.value,
            scale: s,
            car: _outlierCar,
          );
          final label = '${d.key} @${s}x outliers';
          expectCapped(at, base, s, label);
          expectConsistent(at, label);
          expectThreeByTwo(at, label);
        });
      }
    }
  });

  group('Arabic and Kurdish', () {
    for (final locale in const [Locale('ar'), Locale('ku')]) {
      for (final d in const {
        'iPhone 16 Pro Max 440x956': Size(440, 956),
        'Android 360x800': Size(360, 800),
      }.entries) {
        for (final s in const [1.3, 2.0]) {
          testWidgets('${locale.languageCode} ${d.key} @${s}x', (tester) async {
            final base = await pumpGrid(
              tester,
              size: d.value,
              scale: 1.0,
              locale: locale,
              car: _outlierCar,
            );
            final at = await pumpGrid(
              tester,
              size: d.value,
              scale: s,
              locale: locale,
              car: _outlierCar,
            );
            final label = '${locale.languageCode} ${d.key} @${s}x';
            expectCapped(at, base, s, label);
            expectConsistent(at, label);
            expectThreeByTwo(at, label);
          });
        }
      }
    }
  });
}
