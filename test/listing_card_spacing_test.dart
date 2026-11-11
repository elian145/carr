// Listing card vertical rhythm (CarNet iOS TestFlight report: "excessively
// large vertical gap between year/mileage and city/price").
//
// Renders the REAL `buildGlobalCarCard` inside the REAL feed grid cell (aspect
// ratio from `ListingLayoutPrefs.gridChildAspectRatioForWidth`, exactly like
// home_slivers.dart) and MEASURES the gap between the bottom of the
// year/mileage chips and the top of the orange price badge.
//
// Covered matrix: iPhone 16 Pro Max (440x956), iPhone 16 (393), Android
// 360 / 320 dp, text scales 1.0 / 1.3 / 1.5 / 2.0, Bold Text on/off, English /
// Arabic / Kurdish, listings with and without engine+trim chips.
//
// Set `--dart-define=PRINT_LAYOUT_METRICS=true` to print the measured table.
import 'package:car_listing_app/app/widgets/global_listing_card.dart';
import 'package:car_listing_app/shared/prefs/listing_layout_prefs.dart';
import 'package:car_listing_app/shared/ui/app_text_scale.dart';
import 'package:car_listing_app/shared/ui/brand_logo_image.dart';
import 'package:car_listing_app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/brand_picker_harness.dart' show installLogoOverride;
import 'support/f10_scale_harness.dart';

const bool _print = bool.fromEnvironment('PRINT_LAYOUT_METRICS');

/// Logical sizes (dp). Pro Max / iPhone 16 are iOS; 360 / 320 are Android.
const Map<String, Size> _devices = <String, Size>{
  'iPhone 16 Pro Max 440x956': Size(440, 956),
  'iPhone 16 393x852': Size(393, 852),
  'Android 360x800': Size(360, 800),
  'Android small 320x640': Size(320, 640),
};

const List<double> _scales = <double>[1.0, 1.3, 1.5, 2.0];

/// Largest acceptable year/mileage -> price gap. The design (4 dp section gap +
/// a little slack) is ~10-14 dp at 1.0x; 24 dp is the hard ceiling that still
/// reads as "one compact block" even at 2.0x accessibility text.
const double _maxGap = 24;

Map<String, dynamic> _car({required bool detail}) => <String, dynamic>{
      'id': 'spacing_1',
      'public_id': 'spacing_1',
      'brand': 'Toyota',
      'model': 'Camry Hybrid Premium Edition',
      if (detail) 'trim': 'XLE Premium',
      if (detail) 'engine_size': '3.5',
      'year': 2021,
      'mileage': 123456,
      'price': 48500,
      'currency': 'USD',
      'city': 'Erbil',
      'images': <dynamic>[],
      'videos': <dynamic>[],
    };

Widget _feed({required bool list, required Map<String, dynamic> car}) {
  return Scaffold(
    body: Builder(
      builder: (context) {
        final w = MediaQuery.sizeOf(context).width;
        final cols = list ? 1 : 2;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(list ? 4 : 8, 8, list ? 4 : 8, 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: ListingLayoutPrefs.gridChildAspectRatioForWidth(
              cols,
              w,
              textScale: appTextScaleOf(context),
            ),
          ),
          itemCount: 2,
          itemBuilder: (context, i) =>
              buildGlobalCarCard(context, car, listLayout: list),
        );
      },
    ),
  );
}

class _Metrics {
  _Metrics({
    required this.cellH,
    required this.gap,
    required this.yearTop,
    required this.yearBottom,
    required this.badgeBottom,
    required this.cardTop,
    required this.cardBottom,
  });

  final double cellH;
  final double gap;
  final double yearTop;
  final double yearBottom;
  final double badgeBottom;
  final double cardTop;
  final double cardBottom;
}

Finder _yearChip() => find
    .ancestor(
      of: find.byIcon(Icons.calendar_today_rounded),
      matching: find.byType(Container),
    )
    .first;

Finder _priceBadge() => find
    .byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color ==
              AppColors.brandOrangeStrong &&
          (w.decoration! as BoxDecoration).gradient == null,
    )
    .first;

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    installLogoOverride();
  });

  tearDown(() {
    debugBrandLogoImageOverride = null;
  });

  Future<_Metrics> measure(
    WidgetTester tester, {
    required Size size,
    required double scale,
    required bool detail,
    bool list = false,
    bool bold = false,
    Locale locale = const Locale('en'),
    TargetPlatform? platform,
  }) async {
    await f10LoadFonts(tester);
    f10SetWindow(tester, width: size.width, height: size.height);
    await f10Pump(
      tester,
      f10App(
        home: _feed(list: list, car: _car(detail: detail)),
        textScale: scale,
        locale: locale,
        boldText: bold,
        platform: platform,
      ),
    );
    expect(tester.takeException(), isNull);
    if (detail) {
      expect(find.text('XLE Premium'), findsWidgets);
    } else {
      expect(find.text('XLE Premium'), findsNothing);
    }
    final card = tester.getRect(find.byType(InkWell).first);
    final year = tester.getRect(_yearChip());
    final badge = tester.getRect(_priceBadge());
    return _Metrics(
      cellH: card.height,
      gap: badge.top - year.bottom,
      yearTop: year.top - card.top,
      yearBottom: year.bottom,
      badgeBottom: badge.bottom,
      cardTop: card.top,
      cardBottom: card.bottom,
    );
  }

  void expectCompact(_Metrics m, String reason) {
    expect(
      m.gap,
      lessThanOrEqualTo(_maxGap),
      reason: '$reason: year/mileage -> price gap ${m.gap.toStringAsFixed(1)} '
          'dp (cell ${m.cellH.toStringAsFixed(1)} dp) must be <= $_maxGap',
    );
    expect(m.gap, greaterThanOrEqualTo(2), reason: '$reason: chips collide');
    expect(m.yearBottom, lessThan(m.badgeBottom));
    expect(m.badgeBottom, lessThanOrEqualTo(m.cardBottom + 0.5),
        reason: '$reason: price pushed out of the card');
  }

  group('grid card: year/mileage -> city/price gap is compact', () {
    for (final entry in _devices.entries) {
      for (final scale in _scales) {
        for (final detail in const [true, false]) {
          final label = '${entry.key} @${scale}x '
              '${detail ? 'with engine+trim' : 'without engine/trim'}';
          testWidgets(label, (tester) async {
            final m = await measure(
              tester,
              size: entry.value,
              scale: scale,
              detail: detail,
            );
            if (_print) {
              // ignore: avoid_print
              print('METRIC grid | ${entry.key} | ${scale}x | '
                  '${detail ? 'chips' : 'no-chips'} | '
                  'cell=${m.cellH.toStringAsFixed(1)} '
                  'yearTop=${m.yearTop.toStringAsFixed(1)} '
                  'gap=${m.gap.toStringAsFixed(1)}');
            }
            expectCompact(m, label);
          });
        }
      }
    }
  });

  group('grid card: listings with and without chips stay aligned', () {
    for (final entry in _devices.entries) {
      for (final scale in _scales) {
        testWidgets('${entry.key} @${scale}x', (tester) async {
          final withChips = await measure(
            tester,
            size: entry.value,
            scale: scale,
            detail: true,
          );
          final without = await measure(
            tester,
            size: entry.value,
            scale: scale,
            detail: false,
          );
          expect(
            (withChips.gap - without.gap).abs(),
            lessThanOrEqualTo(1.0),
            reason: 'gap must not depend on whether chips exist '
                '(${withChips.gap} vs ${without.gap})',
          );
          // Same row position in neighbouring cards of one grid row.
          expect(
            (withChips.yearTop - without.yearTop).abs(),
            lessThanOrEqualTo(1.0),
            reason: 'year/mileage row must sit at the same y with or without '
                'engine/trim chips',
          );
        });
      }
    }
  });

  group('grid card: gap does not balloon as text scale grows', () {
    for (final entry in _devices.entries) {
      testWidgets(entry.key, (tester) async {
        final base = await measure(
          tester,
          size: entry.value,
          scale: 1.0,
          detail: true,
        );
        for (final scale in const [1.3, 1.5, 2.0]) {
          final m = await measure(
            tester,
            size: entry.value,
            scale: scale,
            detail: true,
          );
          expect(
            m.gap - base.gap,
            lessThanOrEqualTo(12),
            reason: '${entry.key}: gap ${base.gap.toStringAsFixed(1)} @1.0x '
                'grew to ${m.gap.toStringAsFixed(1)} @${scale}x',
          );
        }
      });
    }
  });

  group('grid card: Bold Text and locales', () {
    for (final locale in const [Locale('en'), Locale('ar'), Locale('ku')]) {
      for (final bold in const [false, true]) {
        for (final scale in _scales) {
          for (final size in const [Size(440, 956), Size(320, 640)]) {
            for (final detail in const [true, false]) {
              final label = '${locale.languageCode} bold=$bold '
                  '${size.width.toInt()}dp @${scale}x '
                  '${detail ? 'chips' : 'no-chips'}';
              testWidgets(label, (tester) async {
                final m = await measure(
                  tester,
                  size: size,
                  scale: scale,
                  detail: detail,
                  bold: bold,
                  locale: locale,
                );
                if (_print) {
                  // ignore: avoid_print
                  print('METRIC loc | $label | gap=${m.gap.toStringAsFixed(1)}');
                }
                expectCompact(m, label);
              });
            }
          }
        }
      }
    }
  });

  group('grid card: same layout on iOS and Android platform themes', () {
    for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
      for (final scale in _scales) {
        testWidgets('$platform @${scale}x', (tester) async {
          final m = await measure(
            tester,
            size: const Size(440, 956),
            scale: scale,
            detail: true,
            bold: true,
            platform: platform,
          );
          expectCompact(m, '$platform @${scale}x');
        });
      }
    }
  });

  group('list (1 column) card keeps a compact year/mileage -> price gap', () {
    for (final entry in _devices.entries) {
      for (final scale in _scales) {
        for (final detail in const [true, false]) {
          final label = 'list ${entry.key} @${scale}x '
              '${detail ? 'chips' : 'no-chips'}';
          testWidgets(label, (tester) async {
            final m = await measure(
              tester,
              size: entry.value,
              scale: scale,
              detail: detail,
              list: true,
            );
            if (_print) {
              // ignore: avoid_print
              print('METRIC list | ${entry.key} | ${scale}x | '
                  '${detail ? 'chips' : 'no-chips'} | '
                  'cell=${m.cellH.toStringAsFixed(1)} '
                  'gap=${m.gap.toStringAsFixed(1)}');
            }
            expect(m.gap, greaterThanOrEqualTo(0), reason: label);
            // The horizontal card is sized by flex rows (its height grows
            // linearly with the text scale), so allow a little more than the
            // grid at 2.0x, but never the old 45-57 dp hole for chip-less
            // listings.
            expect(m.gap, lessThanOrEqualTo(36), reason: label);
            expect(m.badgeBottom, lessThanOrEqualTo(m.cardBottom + 0.5),
                reason: label);
          });
        }
      }
    }
    for (final entry in _devices.entries) {
      for (final scale in _scales) {
        testWidgets('list ${entry.key} @${scale}x: chip-less == chips',
            (tester) async {
          final withChips = await measure(tester,
              size: entry.value, scale: scale, detail: true, list: true);
          final without = await measure(tester,
              size: entry.value, scale: scale, detail: false, list: true);
          expect((withChips.gap - without.gap).abs(), lessThanOrEqualTo(1.0));
        });
      }
    }
  });
}
