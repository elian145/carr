// Orange price badge at large iOS / Android text sizes.
//
// History: the pill used to be `26 x textScale` tall (52 dp at 2.0x) and was
// stretched by a mis-measured text width; a 1.3x cap was "too large", and a
// fixed 1.0x badge then looked too SMALL next to the (scaled) title, chips and
// city. Contract now:
//   * the price text follows the other card text up to
//     ListingLayoutPrefs.priceBadgeMaxTextScale (1.5x). On the fixed-height
//     rectangular card the card text itself is capped by width
//     (rectCardTextScale: 1.5 / 1.25 / 1.15), the badge follows that;
//   * the pill keeps its 1.0x height (26 dp, 24 on narrow grid tiles) and only
//     grows as far as the text needs: `max(1.0x height, price px + 5)`, i.e.
//     27.5 dp at most - never more than the unchanged 28 dp footer row;
//   * the footer row, the card heights and every other row stay unchanged;
//   * the city (shrunk by a FittedBox to make room) stays readable.
//
// Renders the REAL `buildGlobalCarCard` in the REAL list (1 column) and grid
// (2 columns) cells and MEASURES the pill and the price text.
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

const Map<String, Size> _devices = <String, Size>{
  'iPhone 16 Pro Max 440x956': Size(440, 956),
  'iPhone 16 393x852': Size(393, 852),
  'Android 360x800': Size(360, 800),
  'Android small 320x640': Size(320, 640),
};

const List<double> _scales = <double>[1.0, 1.3, 1.5, 2.0];

/// Badge text scale cap, the largest pill ever (1.5 x 15 sp + 5 dp) and the
/// unchanged footer row (26 + 2 dp) the pill has to stay inside.
const double _cap = 1.5;
const double _maxPillHeight = 27.5;
const double _footerHeight = 28;
const double _minVerticalPadding = 5;

Map<String, dynamic> _car({int price = 48500, String city = 'Erbil'}) =>
    <String, dynamic>{
  'id': 'badge_1',
  'public_id': 'badge_1',
  'brand': 'Toyota',
  'model': 'Camry',
  'trim': 'XLE',
  'engine_size': '3.5',
  'year': 2021,
  'mileage': 123456,
  'price': price,
  'currency': 'USD',
  'city': city,
  'images': <dynamic>[],
  'videos': <dynamic>[],
};

Widget _feed({required bool list, required Map<String, dynamic> car}) =>
    Scaffold(
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

Finder _badge() => find
    .byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color ==
              AppColors.brandOrangeStrong &&
          (w.decoration! as BoxDecoration).gradient == null,
    )
    .first;


class _B {
  _B({
    required this.pill,
    required this.text,
    required this.card,
    required this.fitted,
    required this.city,
    required this.cityNatural,
  });
  final Rect pill;
  final Rect text;
  final Rect card;
  final bool fitted;

  /// City label as painted (after the footer FittedBox) and as laid out.
  final Rect city;
  final Size cityNatural;

  /// Painted size of the city label relative to its laid-out size (1.0 = not
  /// shrunk).
  double get cityShrink => city.height / cityNatural.height;
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  setUp(() {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    installLogoOverride();
  });
  tearDown(() => debugBrandLogoImageOverride = null);

  Future<_B> measure(
    WidgetTester tester, {
    required Size size,
    required double scale,
    required bool list,
    bool bold = false,
    Locale locale = const Locale('en'),
    int price = 48500,
    String city = 'Erbil',
  }) async {
    await f10LoadFonts(tester);
    f10SetWindow(tester, width: size.width, height: size.height);
    await f10Pump(
      tester,
      f10App(
        home: _feed(
          list: list,
          car: _car(price: price, city: city),
        ),
        textScale: scale,
        boldText: bold,
        locale: locale,
      ),
    );
    expect(tester.takeException(), isNull);
    final badge = _badge();
    final text = find.descendant(of: badge, matching: find.byType(Text)).first;
    // The city label is localised (Arabic / Kurdish show another spelling), so
    // only the English runs can find it by its text.
    final cityFinder = find.text(city);
    final hasCity = cityFinder.evaluate().isNotEmpty;
    return _B(
      pill: tester.getRect(badge),
      text: tester.getRect(text),
      card: tester.getRect(find.byType(InkWell).first),
      fitted: find
          .descendant(of: badge, matching: find.byType(FittedBox))
          .evaluate()
          .isNotEmpty,
      city: hasCity ? tester.getRect(cityFinder.first) : Rect.zero,
      cityNatural: hasCity ? tester.getSize(cityFinder.first) : const Size(1, 1),
    );
  }

  /// The text scale the badge is expected to use at system scale [s]: the
  /// scale the card text itself uses (fixed-height rectangular card: capped by
  /// its height; grid: the system scale), never above [_cap].
  double expectedBadgeScale({
    required Size size,
    required double s,
    required bool list,
  }) {
    var card = s;
    if (list) {
      final ratio = ListingLayoutPrefs.gridChildAspectRatioForWidth(
        1,
        size.width,
      );
      card = ListingLayoutPrefs.rectCardTextScale(
        cardHeight: (size.width - 8) / ratio,
        compact: size.width < 360,
        textScale: s,
      );
    }
    return card < _cap ? card : _cap;
  }

  void expectInsideCard(_B b, String reason) {
    expect(
      b.text.left,
      greaterThanOrEqualTo(b.pill.left - 0.5),
      reason: '$reason: text clipped on the left',
    );
    expect(
      b.text.right,
      lessThanOrEqualTo(b.pill.right + 0.5),
      reason: '$reason: text clipped on the right',
    );
    expect(b.text.top, greaterThanOrEqualTo(b.pill.top - 0.5), reason: reason);
    expect(
      b.text.bottom,
      lessThanOrEqualTo(b.pill.bottom + 0.5),
      reason: reason,
    );
    expect(
      b.pill.right,
      lessThanOrEqualTo(b.card.right + 0.5),
      reason: '$reason: pill pushed past the card edge',
    );
    expect(
      b.pill.bottom,
      lessThanOrEqualTo(b.card.bottom + 0.5),
      reason: '$reason: pill pushed past the card bottom',
    );
  }

  for (final list in const [true, false]) {
    final layout = list ? 'list (1 column)' : 'grid (2 columns)';

    group('badge follows the card text up to 1.5x: $layout', () {
      for (final d in _devices.entries) {
        for (final bold in const [false, true]) {
          testWidgets('${d.key} bold=$bold', (tester) async {
            final at10 = await measure(
              tester,
              size: d.value,
              scale: 1.0,
              list: list,
              bold: bold,
            );
            // The 1.0x design: 26 dp pill / 15 sp price (24 dp / 14 sp in grid
            // tiles narrower than 130 dp).
            expect(
              at10.pill.height,
              anyOf(closeTo(26, 0.5), closeTo(24, 0.5)),
              reason: '${d.key}: 1.0x pill',
            );
            final padding1 = at10.pill.width - at10.text.width;
            for (final s in _scales) {
              final b = await measure(
                tester,
                size: d.value,
                scale: s,
                list: list,
                bold: bold,
              );
              // Largest scale the card text allows, and the scale the badge
              // actually has (price width relative to 1.0x, in 0.05 steps).
              final maxScale = expectedBadgeScale(
                size: d.value,
                s: s,
                list: list,
              );
              final sb = (b.text.width / at10.text.width * 20).round() / 20;
              final reason =
                  '$layout ${d.key} bold=$bold @${s}x (badge ${sb}x of $maxScale)';
              if (_print) {
                // ignore: avoid_print
                print(
                  'METRIC badge | $layout | ${d.key} | bold=$bold | ${s}x | '
                  'pill=${b.pill.width.toStringAsFixed(1)}x'
                  '${b.pill.height.toStringAsFixed(1)} '
                  'text=${b.text.width.toStringAsFixed(1)}x'
                  '${b.text.height.toStringAsFixed(1)} fitted=${b.fitted} '
                  'cityShrink=${b.cityShrink.toStringAsFixed(2)} '
                  'cityPx=${b.city.height.toStringAsFixed(1)}',
                );
              }
              // Price text: proportional to the card text. The rectangular
              // card always reaches the card text scale (its city never
              // limits it); a grid tile may stop earlier when the city beside
              // the pill would be squeezed (see the city group), but never
              // below the recorded minimum.
              expect(sb, lessThanOrEqualTo(maxScale + 0.001), reason: reason);
              expect(sb, greaterThanOrEqualTo(1.0), reason: reason);
              final recorded = _gridMinBadgeScale[d.value.width.toInt()]![s]!;
              final minScale = list
                  ? maxScale
                  : (recorded < maxScale ? recorded : maxScale);
              expect(
                sb,
                greaterThanOrEqualTo(minScale - 0.001),
                reason: '$reason: price smaller than the recorded minimum',
              );
              expect(
                b.text.height,
                closeTo(at10.text.height * sb, 0.6),
                reason: '$reason: price text ${b.text.height}',
              );
              // Pill: 1.0x height, grown only as far as the text needs, and
              // never above the 27.5 dp maximum (footer row is 28 dp).
              final needed = at10.text.height * sb + _minVerticalPadding;
              final expectedH = at10.pill.height > needed
                  ? at10.pill.height
                  : needed;
              expect(
                b.pill.height,
                closeTo(expectedH, 0.3),
                reason: '$reason: pill ${b.pill.height} (want $expectedH)',
              );
              expect(
                b.pill.height,
                lessThanOrEqualTo(_maxPillHeight + 0.3),
                reason: '$reason: pill taller than the 27.5 dp maximum',
              );
              expect(b.pill.height, lessThanOrEqualTo(_footerHeight));
              // A normal price hugs its text: same side padding as at 1.0x, no
              // shrink, no empty orange.
              expect(b.fitted, isFalse, reason: '$reason: price text shrunk');
              expect(
                b.pill.width - b.text.width,
                closeTo(padding1, 0.5),
                reason: '$reason: pill padding changed',
              );
              expectInsideCard(b, reason);
            }
          });
        }
      }
    });

    group('card heights do not depend on the badge: $layout', () {
      for (final d in _devices.entries) {
        testWidgets(d.key, (tester) async {
          final at10 = await measure(
            tester,
            size: d.value,
            scale: 1.0,
            list: list,
          );
          for (final s in _scales) {
            final b = await measure(tester, size: d.value, scale: s, list: list);
            if (list) {
              // Fixed height: identical at every text scale.
              expect(
                b.card.height,
                closeTo(at10.card.height, 0.05),
                reason: '${d.key} @${s}x',
              );
            } else {
              // Grid cell: the unchanged cell formula (the footer row, which
              // the cell reserves room for, does not grow).
              final w = d.value.width;
              final cols = 2;
              final cellW = (w - 8.0 * (cols + 1)) / cols;
              final ratio = ListingLayoutPrefs.gridChildAspectRatioForWidth(
                cols,
                w,
                textScale: s,
              );
              expect(
                b.card.height,
                closeTo(cellW / ratio, 0.5),
                reason: '${d.key} @${s}x',
              );
            }
          }
        });
      }
    });

    group('long price never overflows or clips: $layout', () {
      for (final d in _devices.entries) {
        for (final s in _scales) {
          testWidgets('${d.key} @${s}x 999,999,999', (tester) async {
            final b = await measure(
              tester,
              size: d.value,
              scale: s,
              list: list,
              price: 999999999,
            );
            final reason = '$layout ${d.key} @${s}x long price';
            expect(b.pill.height, lessThanOrEqualTo(_maxPillHeight + 0.3));
            expect(b.text.height, lessThanOrEqualTo(15 * _cap + 1.0));
            expectInsideCard(b, reason);
          });
        }
      }
    });

    group('city stays readable beside the larger badge: $layout', () {
      for (final d in _devices.entries) {
        for (final s in const [1.0, 1.3, 2.0]) {
          for (final city in const ['Erbil', 'Sulaymaniyah']) {
            for (final price in const [48500, 1250000]) {
              testWidgets('${d.key} @${s}x $city \$$price', (tester) async {
                final b = await measure(
                  tester,
                  size: d.value,
                  scale: s,
                  list: list,
                  city: city,
                  price: price,
                );
                if (_print) {
                  // ignore: avoid_print
                  print(
                    'METRIC city | $layout | ${d.key} | ${s}x | $city | '
                    '\$$price | cityShrink=${b.cityShrink.toStringAsFixed(2)} '
                    'cityPx=${b.city.height.toStringAsFixed(1)} '
                    'pillW=${b.pill.width.toStringAsFixed(1)} '
                    'fitted=${b.fitted}',
                  );
                }
                final reason = '$layout ${d.key} @${s}x $city \$$price';
                // The label is painted at least this fraction of its laid-out
                // size: the badge may not squeeze the city.
                final floor = _cityShrinkFloor(
                  list,
                  d.value.width,
                  s,
                  city,
                  price,
                );
                expect(
                  b.cityShrink,
                  greaterThanOrEqualTo(floor),
                  reason:
                      '$reason: city shrunk to ${b.cityShrink.toStringAsFixed(2)}',
                );

                expectInsideCard(b, reason);
              });
            }
          }
        }
      }
    });
  }

  group('Arabic, Kurdish and Bold Text', () {
    for (final locale in const [Locale('ar'), Locale('ku')]) {
      for (final list in const [true, false]) {
        for (final s in const [1.0, 1.3, 2.0]) {
          testWidgets(
            '${locale.languageCode} ${list ? 'list' : 'grid'} 440dp @${s}x',
            (tester) async {
              final b = await measure(
                tester,
                size: const Size(440, 956),
                scale: s,
                list: list,
                locale: locale,
              );
              expect(b.pill.height, lessThanOrEqualTo(_maxPillHeight + 0.3));
              expectInsideCard(b, '${locale.languageCode} @${s}x');
            },
          );
        }
      }
    }
    for (final list in const [true, false]) {
      for (final s in const [1.3, 2.0]) {
        testWidgets('bold ${list ? 'list' : 'grid'} 360dp @${s}x', (
          tester,
        ) async {
          final b = await measure(
            tester,
            size: const Size(360, 800),
            scale: s,
            list: list,
            bold: true,
          );
          expect(b.pill.height, lessThanOrEqualTo(_maxPillHeight + 0.3));
          expectInsideCard(b, 'bold @${s}x');
        });
      }
    }
  });
}

/// Smallest badge text scale the GRID tile reaches with the default city and
/// price (`Erbil`, `48,500`): by device width, then system scale. Narrow
/// tiles stop earlier on purpose: the city beside the pill keeps its size.
final Map<int, Map<double, double>> _gridMinBadgeScale =
    <int, Map<double, double>>{
      440: {1.0: 1.0, 1.3: 1.3, 1.5: 1.5, 2.0: 1.5},
      393: {1.0: 1.0, 1.3: 1.3, 1.5: 1.5, 2.0: 1.4},
      360: {1.0: 1.0, 1.3: 1.3, 1.5: 1.3, 2.0: 1.1},
      320: {1.0: 1.0, 1.3: 1.15, 1.5: 1.1, 2.0: 1.05},
    };

/// City label painted/laid-out ratio beside the 1.0x badge (the layout before
/// the badge was allowed to grow), recorded per case:
/// 'L|G' (list|grid), device width, system scale, city, price.
const Map<String, double> _cityShrinkBefore = <String, double>{
  'L|440|1.0|Erbil|48500': 1.00,
  'L|440|1.0|Erbil|1250000': 1.00,
  'L|440|1.0|Sulaymaniyah|48500': 1.00,
  'L|440|1.0|Sulaymaniyah|1250000': 1.00,
  'L|440|1.3|Erbil|48500': 1.00,
  'L|440|1.3|Erbil|1250000': 1.00,
  'L|440|1.3|Sulaymaniyah|48500': 1.00,
  'L|440|1.3|Sulaymaniyah|1250000': 1.00,
  'L|440|2.0|Erbil|48500': 1.00,
  'L|440|2.0|Erbil|1250000': 1.00,
  'L|440|2.0|Sulaymaniyah|48500': 1.00,
  'L|440|2.0|Sulaymaniyah|1250000': 0.90,
  'L|393|1.0|Erbil|48500': 1.00,
  'L|393|1.0|Erbil|1250000': 1.00,
  'L|393|1.0|Sulaymaniyah|48500': 1.00,
  'L|393|1.0|Sulaymaniyah|1250000': 0.99,
  'L|393|1.3|Erbil|48500': 1.00,
  'L|393|1.3|Erbil|1250000': 1.00,
  'L|393|1.3|Sulaymaniyah|48500': 1.00,
  'L|393|1.3|Sulaymaniyah|1250000': 0.82,
  'L|393|2.0|Erbil|48500': 1.00,
  'L|393|2.0|Erbil|1250000': 1.00,
  'L|393|2.0|Sulaymaniyah|48500': 1.00,
  'L|393|2.0|Sulaymaniyah|1250000': 0.82,
  'L|360|1.0|Erbil|48500': 1.00,
  'L|360|1.0|Erbil|1250000': 1.00,
  'L|360|1.0|Sulaymaniyah|48500': 1.00,
  'L|360|1.0|Sulaymaniyah|1250000': 0.80,
  'L|360|1.3|Erbil|48500': 1.00,
  'L|360|1.3|Erbil|1250000': 1.00,
  'L|360|1.3|Sulaymaniyah|48500': 0.91,
  'L|360|1.3|Sulaymaniyah|1250000': 0.71,
  'L|360|2.0|Erbil|48500': 1.00,
  'L|360|2.0|Erbil|1250000': 1.00,
  'L|360|2.0|Sulaymaniyah|48500': 0.91,
  'L|360|2.0|Sulaymaniyah|1250000': 0.71,
  'L|320|1.0|Erbil|48500': 1.00,
  'L|320|1.0|Erbil|1250000': 1.00,
  'L|320|1.0|Sulaymaniyah|48500': 0.86,
  'L|320|1.0|Sulaymaniyah|1250000': 0.63,
  'L|320|1.3|Erbil|48500': 1.00,
  'L|320|1.3|Erbil|1250000': 1.00,
  'L|320|1.3|Sulaymaniyah|48500': 0.76,
  'L|320|1.3|Sulaymaniyah|1250000': 0.56,
  'L|320|2.0|Erbil|48500': 1.00,
  'L|320|2.0|Erbil|1250000': 1.00,
  'L|320|2.0|Sulaymaniyah|48500': 0.76,
  'L|320|2.0|Sulaymaniyah|1250000': 0.56,
  'G|440|1.0|Erbil|48500': 1.00,
  'G|440|1.0|Erbil|1250000': 1.00,
  'G|440|1.0|Sulaymaniyah|48500': 1.00,
  'G|440|1.0|Sulaymaniyah|1250000': 0.92,
  'G|440|1.3|Erbil|48500': 1.00,
  'G|440|1.3|Erbil|1250000': 1.00,
  'G|440|1.3|Sulaymaniyah|48500': 0.93,
  'G|440|1.3|Sulaymaniyah|1250000': 0.74,
  'G|440|2.0|Erbil|48500': 0.97,
  'G|440|2.0|Erbil|1250000': 0.97,
  'G|440|2.0|Sulaymaniyah|48500': 0.64,
  'G|440|2.0|Sulaymaniyah|1250000': 0.51,
  'G|393|1.0|Erbil|48500': 1.00,
  'G|393|1.0|Erbil|1250000': 1.00,
  'G|393|1.0|Sulaymaniyah|48500': 0.90,
  'G|393|1.0|Sulaymaniyah|1250000': 0.67,
  'G|393|1.3|Erbil|48500': 1.00,
  'G|393|1.3|Erbil|1250000': 1.00,
  'G|393|1.3|Sulaymaniyah|48500': 0.72,
  'G|393|1.3|Sulaymaniyah|1250000': 0.54,
  'G|393|2.0|Erbil|48500': 0.97,
  'G|393|2.0|Erbil|1250000': 0.95,
  'G|393|2.0|Sulaymaniyah|48500': 0.50,
  'G|393|2.0|Sulaymaniyah|1250000': 0.37,
  'G|360|1.0|Erbil|48500': 1.00,
  'G|360|1.0|Erbil|1250000': 1.00,
  'G|360|1.0|Sulaymaniyah|48500': 0.72,
  'G|360|1.0|Sulaymaniyah|1250000': 0.49,
  'G|360|1.3|Erbil|48500': 1.00,
  'G|360|1.3|Erbil|1250000': 0.93,
  'G|360|1.3|Sulaymaniyah|48500': 0.58,
  'G|360|1.3|Sulaymaniyah|1250000': 0.40,
  'G|360|2.0|Erbil|48500': 0.97,
  'G|360|2.0|Erbil|1250000': 0.70,
  'G|360|2.0|Sulaymaniyah|48500': 0.40,
  'G|360|2.0|Sulaymaniyah|1250000': 0.27,
  'G|320|1.0|Erbil|48500': 1.00,
  'G|320|1.0|Erbil|1250000': 0.83,
  'G|320|1.0|Sulaymaniyah|48500': 0.59,
  'G|320|1.0|Sulaymaniyah|1250000': 0.38,
  'G|320|1.3|Erbil|48500': 1.00,
  'G|320|1.3|Erbil|1250000': 0.71,
  'G|320|1.3|Sulaymaniyah|48500': 0.47,
  'G|320|1.3|Sulaymaniyah|1250000': 0.30,
  'G|320|2.0|Erbil|48500': 0.83,
  'G|320|2.0|Erbil|1250000': 0.53,
  'G|320|2.0|Sulaymaniyah|48500': 0.32,
  'G|320|2.0|Sulaymaniyah|1250000': 0.21,
};

/// Smallest acceptable painted/laid-out ratio of the city label beside the
/// larger badge: it may lose at most 10% of what it had, is never pushed below
/// 75% of its size by the badge, and a city that was already squeezed below
/// that keeps exactly what it had (the badge then stays at 1.0x).
double _cityShrinkFloor(
  bool list,
  double width,
  double s,
  String city,
  int price,
) {
  final key = '${list ? 'L' : 'G'}|${width.toInt()}|$s|$city|$price';
  final before = _cityShrinkBefore[key];
  if (before == null) throw StateError('no baseline for $key');
  final tenPercent = before * 0.9;
  final floor = tenPercent > 0.75 ? tenPercent : 0.75;
  // 0.02: the baseline is recorded to two decimals.
  return (before < floor ? before : floor) - 0.02;
}
