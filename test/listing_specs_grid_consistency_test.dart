// Six-item specification grid on the listing details page (CarNet iOS
// TestFlight report: with iOS Bold Text on, "some numbers and letters look
// disproportionately large").
//
// Root cause under test: every tile used to size its own value with a
// FittedBox(scaleDown). Short values ("4", "2.0L") stay at full size while long
// ones ("123,456 km", "Automatic") are shrunk to the tile width, so the six
// values end up at visibly different type sizes as soon as the text scale or
// glyph width (Bold Text) grows.
//
// This test renders the REAL `buildCarListingSpecsGrid` (padding 16 like the
// details page) and reads back the RENDERED size of every label and value
// (font size x text scale x FittedBox scale) at iPhone 16 Pro Max and smaller
// Android sizes, text scales 1.0 / 1.3 / 1.5 / 2.0, Bold Text on/off, English /
// Arabic / Kurdish.
//
// Set `--dart-define=PRINT_LAYOUT_METRICS=true` to print the measured table.
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

/// Typical listing: short numbers (4, 2.0L) next to long text/number values.
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

/// The two longest real (enumerated) values the grid can show next to short
/// ones: "Semi-Automatic" and "Plug-in Hybrid" (and their Arabic / Kurdish
/// translations).
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

class _Zone {
  _Zone({
    required this.text,
    required this.renderedPx,
    required this.fontSize,
    required this.visual,
    required this.tile,
  });

  final String text;

  /// font size x text scale x FittedBox scale = what the user actually sees.
  final double renderedPx;
  final double fontSize;
  final Rect visual;
  final Rect tile;
}

class _Grid {
  _Grid(this.labels, this.values);
  final List<_Zone> labels;
  final List<_Zone> values;

  double get valueMin => values.map((z) => z.renderedPx).reduce(math.min);
  double get valueMax => values.map((z) => z.renderedPx).reduce(math.max);
  double get labelMin => labels.map((z) => z.renderedPx).reduce(math.min);
  double get labelMax => labels.map((z) => z.renderedPx).reduce(math.max);
}

Widget _page(Map<String, dynamic> car) {
  return Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Builder(builder: (context) => buildCarListingSpecsGrid(context, car)),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_Grid> pumpGrid(
    WidgetTester tester, {
    required Size size,
    required double scale,
    Map<String, dynamic> car = _typicalCar,
    bool bold = false,
    Locale locale = const Locale('en'),
    TargetPlatform? platform,
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
        platform: platform,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final fitted = find.descendant(
      of: find.byType(GridView).first,
      matching: find.byType(FittedBox),
    );
    // 6 tiles x (label + value).
    expect(fitted.evaluate().length, 12);

    final labels = <_Zone>[];
    final values = <_Zone>[];
    for (var i = 0; i < 12; i++) {
      final box = fitted.at(i);
      final textFinder = find.descendant(of: box, matching: find.byType(Text));
      final text = tester.widget<Text>(textFinder);
      final boxSize = tester.getSize(box);
      final textSize = tester.getSize(textFinder);
      final k = math.min(
        1.0,
        math.min(boxSize.width / textSize.width, boxSize.height / textSize.height),
      );
      final fontSize = text.style!.fontSize!;
      final zone = _Zone(
        text: text.data ?? '',
        fontSize: fontSize,
        renderedPx: fontSize * scale * k,
        visual: tester.getRect(textFinder),
        tile: tester.getRect(
          find.ancestor(of: box, matching: find.byType(ClipRRect)).first,
        ),
      );
      (i.isEven ? labels : values).add(zone);
    }
    return _Grid(labels, values);
  }

  void expectConsistent(_Grid g, String label, {double maxSpread = 1.08}) {
    final spread = g.valueMax / g.valueMin;
    expect(
      spread,
      lessThanOrEqualTo(maxSpread),
      reason: '$label: value sizes differ too much '
          '(${g.values.map((z) => '${z.text}=${z.renderedPx.toStringAsFixed(1)}').join(', ')})',
    );
    final labelSpread = g.labelMax / g.labelMin;
    expect(
      labelSpread,
      lessThanOrEqualTo(maxSpread),
      reason: '$label: label sizes differ too much '
          '(${g.labels.map((z) => '${z.text}=${z.renderedPx.toStringAsFixed(1)}').join(', ')})',
    );
  }

  void expectInsideTiles(_Grid g, String label) {
    for (final z in [...g.values, ...g.labels]) {
      expect(z.visual.left, greaterThanOrEqualTo(z.tile.left - 0.6),
          reason: '$label: "${z.text}" clipped on the left');
      expect(z.visual.right, lessThanOrEqualTo(z.tile.right + 0.6),
          reason: '$label: "${z.text}" clipped on the right');
      expect(z.visual.top, greaterThanOrEqualTo(z.tile.top - 0.6),
          reason: '$label: "${z.text}" clipped on the top');
      expect(z.visual.bottom, lessThanOrEqualTo(z.tile.bottom + 0.6),
          reason: '$label: "${z.text}" clipped on the bottom');
    }
  }

  group('six values render at one consistent size', () {
    for (final entry in _devices.entries) {
      for (final bold in const [false, true]) {
        for (final scale in _scales) {
          final label = '${entry.key} bold=$bold @${scale}x';
          testWidgets(label, (tester) async {
            final g = await pumpGrid(
              tester,
              size: entry.value,
              scale: scale,
              bold: bold,
            );
            if (_print) {
              // ignore: avoid_print
              print('METRIC specs | $label | values '
                  '${g.values.map((z) => z.renderedPx.toStringAsFixed(1)).join('/')} '
                  '| labels '
                  '${g.labels.map((z) => z.renderedPx.toStringAsFixed(1)).join('/')}');
            }
            expectConsistent(g, label);
            expectInsideTiles(g, label);
          });
        }
      }
    }
  });

  group('labels stay distinguishable from values', () {
    for (final entry in _devices.entries) {
      for (final bold in const [false, true]) {
        for (final scale in _scales) {
          final label = '${entry.key} bold=$bold @${scale}x';
          testWidgets(label, (tester) async {
            final g = await pumpGrid(
              tester,
              size: entry.value,
              scale: scale,
              bold: bold,
            );
            // Value is clearly bigger than its label ...
            expect(g.valueMin, greaterThanOrEqualTo(g.labelMax * 1.1),
                reason: '$label: values must stay larger than labels');
            // ... and the colours differ (muted label vs. strong value).
            final texts = find
                .descendant(
                  of: find.byType(GridView).first,
                  matching: find.byType(Text),
                )
                .evaluate()
                .map((e) => e.widget as Text)
                .toList();
            final labelColor = texts[0].style!.color;
            final valueColor = texts[1].style!.color;
            expect(labelColor, isNot(valueColor), reason: label);
          });
        }
      }
    }
  });

  group('readable at accessibility scales', () {
    for (final entry in _devices.entries) {
      testWidgets(entry.key, (tester) async {
        final base = await pumpGrid(tester, size: entry.value, scale: 1.0);
        for (final scale in const [1.3, 1.5, 2.0]) {
          for (final bold in const [false, true]) {
            final g = await pumpGrid(
              tester,
              size: entry.value,
              scale: scale,
              bold: bold,
            );
            expect(g.valueMin, greaterThanOrEqualTo(base.valueMin - 0.6),
                reason: '${entry.key} @${scale}x bold=$bold: values rendered '
                    'smaller (${g.valueMin.toStringAsFixed(1)}) than at 1.0x '
                    '(${base.valueMin.toStringAsFixed(1)})');
            expect(g.labelMin, greaterThanOrEqualTo(base.labelMin - 0.6),
                reason: '${entry.key} @${scale}x bold=$bold: labels smaller '
                    'than at 1.0x');
            expect(g.valueMin, greaterThanOrEqualTo(10.0),
                reason: '${entry.key} @${scale}x bold=$bold: value too small');
          }
        }
      });
    }
  });

  group('long real values do not drag the short ones down', () {
    for (final locale in const [Locale('en'), Locale('ar'), Locale('ku')]) {
      for (final entry in const <String, Size>{
        'iPhone 16 Pro Max 440x956': Size(440, 956),
        'Android 360x800': Size(360, 800),
      }.entries) {
        for (final scale in _scales) {
          for (final bold in const [false, true]) {
            final label = '${locale.languageCode} ${entry.key} bold=$bold '
                '@${scale}x';
            testWidgets(label, (tester) async {
              final g = await pumpGrid(
                tester,
                size: entry.value,
                scale: scale,
                bold: bold,
                locale: locale,
                car: _outlierCar,
              );
              expectInsideTiles(g, label);
              // Tiles 4 (transmission) and 5 (fuel) carry the long values.
              // The four others share one size; the long ones may be a bit
              // smaller (shrunk inside their own tile) but stay readable.
              final shortOnes = <double>[
                for (var i = 0; i < 4; i++) g.values[i].renderedPx,
              ];
              final spread =
                  shortOnes.reduce(math.max) / shortOnes.reduce(math.min);
              expect(spread, lessThanOrEqualTo(1.08),
                  reason: '$label: short values must match ($shortOnes)');
              for (final i in const [4, 5]) {
                expect(
                  g.values[i].renderedPx,
                  greaterThanOrEqualTo(shortOnes.first * 0.6),
                  reason: '$label: "${g.values[i].text}" is dramatically '
                      'smaller (${g.values[i].renderedPx}) than the short '
                      'values (${shortOnes.first})',
                );
                expect(g.values[i].renderedPx, greaterThanOrEqualTo(7.0),
                    reason: '$label: "${g.values[i].text}" unreadable');
              }
            });
          }
        }
      }
    }
  });

  group('Bold Text, Arabic and Kurdish', () {
    for (final locale in const [Locale('en'), Locale('ar'), Locale('ku')]) {
      for (final bold in const [false, true]) {
        for (final scale in _scales) {
          for (final size in const [Size(440, 956), Size(320, 640)]) {
            final label = '${locale.languageCode} bold=$bold '
                '${size.width.toInt()}dp @${scale}x';
            testWidgets(label, (tester) async {
              final g = await pumpGrid(
                tester,
                size: size,
                scale: scale,
                bold: bold,
                locale: locale,
              );
              expectConsistent(g, label);
              expectInsideTiles(g, label);
            });
          }
        }
      }
    }
  });

  group('3x2 layout is preserved', () {
    for (final entry in _devices.entries) {
      for (final bold in const [false, true]) {
        testWidgets('${entry.key} bold=$bold @1.0x', (tester) async {
          final g = await pumpGrid(
            tester,
            size: entry.value,
            scale: 1.0,
            bold: bold,
          );
          final lefts = g.values.map((z) => z.tile.left.round()).toSet();
          final tops = g.values.map((z) => z.tile.top.round()).toSet();
          expect(lefts.length, 3, reason: 'three columns');
          expect(tops.length, 2, reason: 'two rows');
        });
      }
    }
  });

  group('iOS and Android platform themes behave the same', () {
    for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
      for (final scale in _scales) {
        testWidgets('$platform bold=true @${scale}x', (tester) async {
          final g = await pumpGrid(
            tester,
            size: const Size(440, 956),
            scale: scale,
            bold: true,
            platform: platform,
          );
          expectConsistent(g, '$platform @${scale}x');
          expectInsideTiles(g, '$platform @${scale}x');
        });
      }
    }
  });
}
