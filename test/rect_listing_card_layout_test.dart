// Rectangular (one-listing-per-row) listing card: title -> specs spacing and
// card height (CarNet iOS TestFlight regression: "large gap between a one-line
// title such as 'Toyota Belta' and the specifications below it").
//
// History (see the investigation notes in the PR description):
//  - ea35bed (F-10) made the list cell `aspectRatio = base / textScale`, i.e.
//    the whole card grew x textScale although the content only grows ~93 dp per
//    +1.0 of scale. The surplus is spread over the flex slots of the text
//    column, so every gap grows.
//  - be8fc19 added an empty `Expanded(flex: 3)` for listings without
//    engine/trim, which pushed the year/mileage row away from the title.
//
// This test renders the REAL `buildGlobalCarCard(listLayout: true)` inside the
// REAL list cell (aspect ratio from `ListingLayoutPrefs`, exactly like
// home_slivers.dart) and MEASURES rendered rects:
//   * title text bottom -> top of the next row (engine/trim chip, or the
//     year/mileage chip when the listing has no engine/trim),
//   * year/mileage chip bottom -> price badge top,
//   * total card height (identical for one-line and two-line titles),
//   * price badge / city position (identical for every variant).
//
// Matrix: iPhone 16 Pro Max (440), iPhone 16 (393), Android 360 / 320 dp;
// text scale 1.0 / 1.3 / 1.5 / 2.0; one-line and two-line titles; with and
// without engine/trim chips; English, Arabic, Kurdish; Bold Text on/off.
//
// `--dart-define=PRINT_LAYOUT_METRICS=true` prints the measured table.
import 'dart:math' as math;

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

/// Largest title -> next-row gap (dp). The pre-regression design was ~20 dp
/// with engine/trim chips; chip-less listings have one chip row (~25 dp) of
/// extra height to place, so they get a slightly larger allowance. The old
/// 32.8 dp (and the regressed 57 dp) must fail.
const double _maxTitleGapChips = 26;
const double _maxTitleGapNoChips = 28;

/// Largest year/mileage -> price gap (dp).
const double _maxSpecsPriceGapChips = 24;
const double _maxSpecsPriceGapNoChips = 38;

/// The card content grows ~93 dp per +1.0 of text scale (title 2 x 15 x 1.28 =
/// 38.4, two chip rows 2 x 13, footer 28 = 92.4). Allow a little headroom.
const double _maxCardGrowthPerScale = 100;

class _Variant {
  const _Variant(this.name, this.model, this.probe);
  final String name;
  final String model;
  final String probe; // text used to find the rendered title
}

const _Variant _oneLine = _Variant('one-line', 'Belta', 'Belta');
const _Variant _twoLine = _Variant(
  'two-line',
  'Camry Hybrid Premium Edition',
  'Camry',
);

Map<String, dynamic> _car(
  _Variant v, {
  required bool chips,
  int price = 48500,
}) => <String, dynamic>{
  'id': 'rect_1',
  'public_id': 'rect_1',
  'brand': 'Toyota',
  'model': v.model,
  if (chips) 'trim': 'XLE',
  if (chips) 'engine_size': '3.5',
  'year': 2021,
  'mileage': 123456,
  'price': price,
  'currency': 'USD',
  'city': 'Erbil',
  'images': <dynamic>[],
  'videos': <dynamic>[],
};

Widget _feed(Map<String, dynamic> car) => Scaffold(
  body: Builder(
    builder: (context) {
      final w = MediaQuery.sizeOf(context).width;
      // Exactly like home_slivers.dart for one column.
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 1,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: ListingLayoutPrefs.gridChildAspectRatioForWidth(
            1,
            w,
            textScale: appTextScaleOf(context),
          ),
        ),
        itemCount: 1,
        itemBuilder: (context, i) =>
            buildGlobalCarCard(context, car, listLayout: true),
      );
    },
  ),
);

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

class _M {
  _M({
    required this.card,
    required this.title,
    required this.next,
    required this.year,
    required this.badge,
    required this.city,
  });

  final Rect card;
  final Rect title;

  /// Top of the row below the title (engine/trim chip, else year chip).
  final double next;
  final Rect year;
  final Rect badge;
  final Rect city;

  double get cardH => card.height;
  double get titleToNext => next - title.bottom;
  double get specsToPrice => badge.top - year.bottom;
  double get titleTop => title.top - card.top;
  double get priceBottomInset => card.bottom - badge.bottom;
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  setUp(() {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    installLogoOverride();
  });
  tearDown(() => debugBrandLogoImageOverride = null);

  Future<_M> measure(
    WidgetTester tester, {
    required Size size,
    required double scale,
    required _Variant variant,
    required bool chips,
    bool bold = false,
    Locale locale = const Locale('en'),
    int price = 48500,
  }) async {
    await f10LoadFonts(tester);
    f10SetWindow(tester, width: size.width, height: size.height);
    await f10Pump(
      tester,
      f10App(
        home: _feed(_car(variant, chips: chips, price: price)),
        textScale: scale,
        boldText: bold,
        locale: locale,
      ),
    );
    expect(
      tester.takeException(),
      isNull,
      reason: '${size.width}dp ${scale}x ${variant.name} chips=$chips',
    );
    expect(find.byType(BrandLogoImage), findsWidgets);
    final card = tester.getRect(find.byType(InkWell).first);
    final title = tester.getRect(
      find.textContaining(variant.probe, findRichText: true).first,
    );
    final year = tester.getRect(_yearChip());
    double next = year.top;
    if (chips) {
      expect(find.text('XLE'), findsWidgets);
      next = tester
          .getRect(
            find
                .ancestor(
                  of: find.text('XLE'),
                  matching: find.byType(Container),
                )
                .first,
          )
          .top;
    } else {
      expect(find.text('XLE'), findsNothing);
    }
    return _M(
      card: card,
      title: title,
      next: next,
      year: year,
      badge: tester.getRect(_priceBadge()),
      city: tester.getRect(find.byIcon(Icons.location_on_outlined).first),
    );
  }

  void expectGaps(_M m, String reason, {required bool chips}) {
    expect(
      m.titleToNext,
      lessThanOrEqualTo(chips ? _maxTitleGapChips : _maxTitleGapNoChips),
      reason:
          '$reason: title -> next row gap '
          '${m.titleToNext.toStringAsFixed(1)} dp (card ${m.cardH.toStringAsFixed(1)} dp)',
    );
    expect(
      m.titleToNext,
      greaterThanOrEqualTo(2),
      reason: '$reason: title touches the next row',
    );
    expect(
      m.specsToPrice,
      lessThanOrEqualTo(
        chips ? _maxSpecsPriceGapChips : _maxSpecsPriceGapNoChips,
      ),
      reason:
          '$reason: year/mileage -> price gap '
          '${m.specsToPrice.toStringAsFixed(1)} dp',
    );
    expect(
      m.specsToPrice,
      greaterThanOrEqualTo(2),
      reason: '$reason: chips collide with the price badge',
    );
    // The gap above the title must not just absorb the removed space.
    expect(
      m.titleTop,
      lessThanOrEqualTo(0.28 * m.cardH),
      reason:
          '$reason: title pushed down ${m.titleTop.toStringAsFixed(1)} dp '
          'from the card top',
    );
    // Everything stays inside the card.
    expect(
      m.badge.bottom,
      lessThanOrEqualTo(m.card.bottom + 0.5),
      reason: '$reason: price badge clipped by the card bottom',
    );
    expect(
      m.badge.right,
      lessThanOrEqualTo(m.card.right + 0.5),
      reason: '$reason: price badge clipped by the card edge',
    );
    expect(m.title.top, greaterThanOrEqualTo(m.card.top - 0.5));
  }

  void log(String tag, String label, _M m) {
    if (!_print) return;
    // ignore: avoid_print
    print(
      'METRIC rect | $tag | $label | cardH=${m.cardH.toStringAsFixed(1)} '
      'titleTop=${m.titleTop.toStringAsFixed(1)} '
      'title->next=${m.titleToNext.toStringAsFixed(1)} '
      'specs->price=${m.specsToPrice.toStringAsFixed(1)} '
      'priceInset=${m.priceBottomInset.toStringAsFixed(1)}',
    );
  }

  group('title -> specs gap is compact (English)', () {
    for (final d in _devices.entries) {
      for (final s in _scales) {
        for (final v in const [_oneLine, _twoLine]) {
          for (final chips in const [true, false]) {
            final label =
                '${d.key} @${s}x ${v.name} '
                '${chips ? 'with engine+trim' : 'no engine/trim'}';
            testWidgets(label, (tester) async {
              final m = await measure(
                tester,
                size: d.value,
                scale: s,
                variant: v,
                chips: chips,
              );
              log('en', label, m);
              expectGaps(m, label, chips: chips);
            });
          }
        }
      }
    }
  });

  group('card height is identical for one-line and two-line titles', () {
    for (final d in _devices.entries) {
      for (final s in _scales) {
        for (final chips in const [true, false]) {
          final label =
              '${d.key} @${s}x '
              '${chips ? 'with engine+trim' : 'no engine/trim'}';
          testWidgets(label, (tester) async {
            final one = await measure(
              tester,
              size: d.value,
              scale: s,
              variant: _oneLine,
              chips: chips,
            );
            final two = await measure(
              tester,
              size: d.value,
              scale: s,
              variant: _twoLine,
              chips: chips,
            );
            expect(one.cardH, closeTo(two.cardH, 0.01), reason: label);
            // Rows below the title do not jump between one-line and two-line
            // cards.
            expect(
              one.year.top - one.card.top,
              closeTo(two.year.top - two.card.top, 1.0),
              reason: '$label: year/mileage row moved with the title',
            );
          });
        }
      }
    }
  });

  group('card height follows the content, not textScale x height', () {
    for (final d in _devices.entries) {
      for (final s in const [1.3, 1.5, 2.0]) {
        testWidgets('${d.key} @${s}x', (tester) async {
          final base = await measure(
            tester,
            size: d.value,
            scale: 1.0,
            variant: _oneLine,
            chips: true,
          );
          final scaled = await measure(
            tester,
            size: d.value,
            scale: s,
            variant: _oneLine,
            chips: true,
          );
          final growth = scaled.cardH - base.cardH;
          expect(
            growth,
            lessThanOrEqualTo(_maxCardGrowthPerScale * (s - 1.0) + 2),
            reason:
                '${d.key} @${s}x: card grew ${growth.toStringAsFixed(1)} dp '
                '(${base.cardH.toStringAsFixed(1)} -> '
                '${scaled.cardH.toStringAsFixed(1)}); content only needs '
                '~93 dp per +1.0 of scale',
          );
          // 1.0x design is untouched: same height the card always had.
          final w = d.value.width;
          expect(
            base.cardH,
            closeTo(
              (w - 8) / ListingLayoutPrefs.gridChildAspectRatioForWidth(1, w),
              0.01,
            ),
          );
        });
      }
    }
  });

  group('price and city sit at the same place on every variant', () {
    for (final d in _devices.entries) {
      for (final s in _scales) {
        testWidgets('${d.key} @${s}x', (tester) async {
          final ms = <String, _M>{};
          for (final v in const [_oneLine, _twoLine]) {
            for (final chips in const [true, false]) {
              ms['${v.name}/${chips ? 'chips' : 'plain'}'] = await measure(
                tester,
                size: d.value,
                scale: s,
                variant: v,
                chips: chips,
              );
            }
          }
          final ref = ms.values.first;
          ms.forEach((name, m) {
            expect(
              m.priceBottomInset,
              closeTo(ref.priceBottomInset, 1.0),
              reason: '${d.key} @${s}x $name: price badge moved',
            );
            expect(
              m.badge.height,
              closeTo(ref.badge.height, 0.5),
              reason: '$name: badge height differs',
            );
            // City icon and badge share a centre line.
            expect(
              m.city.center.dy,
              closeTo(m.badge.center.dy, 2.5),
              reason: '${d.key} @${s}x $name: city not aligned with price',
            );
          });
        });
      }
    }
  });

  group('Arabic and Kurdish keep the same spacing', () {
    for (final locale in const [Locale('ar'), Locale('ku')]) {
      for (final d in const {
        'iPhone 16 Pro Max 440x956': Size(440, 956),
        'Android 360x800': Size(360, 800),
      }.entries) {
        for (final s in _scales) {
          for (final v in const [_oneLine, _twoLine]) {
            for (final chips in const [true, false]) {
              final label =
                  '${locale.languageCode} ${d.key} @${s}x ${v.name} '
                  '${chips ? 'with engine+trim' : 'no engine/trim'}';
              testWidgets(label, (tester) async {
                final m = await measure(
                  tester,
                  size: d.value,
                  scale: s,
                  variant: v,
                  chips: chips,
                  locale: locale,
                );
                log(locale.languageCode, label, m);
                expectGaps(m, label, chips: chips);
              });
            }
          }
        }
      }
    }
  });

  group('iOS Bold Text keeps the spacing', () {
    for (final d in const {
      'iPhone 16 Pro Max 440x956': Size(440, 956),
      'Android 360x800': Size(360, 800),
    }.entries) {
      for (final s in const [1.3, 2.0]) {
        for (final v in const [_oneLine, _twoLine]) {
          for (final chips in const [true, false]) {
            final label =
                'bold ${d.key} @${s}x ${v.name} '
                '${chips ? 'with engine+trim' : 'no engine/trim'}';
            testWidgets(label, (tester) async {
              final m = await measure(
                tester,
                size: d.value,
                scale: s,
                variant: v,
                chips: chips,
                bold: true,
              );
              log('bold', label, m);
              expectGaps(m, label, chips: chips);
            });
          }
        }
      }
    }
  });

  group('worst-case content never overflows', () {
    for (final d in _devices.entries) {
      for (final s in _scales) {
        testWidgets('${d.key} @${s}x 999,999,999 price', (tester) async {
          final m = await measure(
            tester,
            size: d.value,
            scale: s,
            variant: _twoLine,
            chips: true,
            price: 999999999,
          );
          expect(m.badge.right, lessThanOrEqualTo(m.card.right + 0.5));
          expect(m.badge.bottom, lessThanOrEqualTo(m.card.bottom + 0.5));
          expect(math.max(m.specsToPrice, 0), greaterThanOrEqualTo(2));
        });
      }
    }
  });
}
