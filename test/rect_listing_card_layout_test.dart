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

class _Variant {
  const _Variant(this.name, this.model, this.probe, {this.brand = 'Toyota'});
  final String name;
  final String model;
  final String probe; // text used to find the rendered title
  final String brand;
}

const _Variant _oneLine = _Variant('one-line', 'Belta', 'Belta');
const _Variant _twoLine = _Variant(
  'two-line',
  'Camry Hybrid Premium Edition',
  'Camry',
);

/// A title that is ONE line in every width, including for the title-line probe
/// inside the card (which measures with the default test font, 1 em per glyph:
/// "Toyota Belta" measured as two lines in tests but one line on a real
/// iPhone, which is why the one-line gap was not reproduced by the tests).
const _Variant _shortOneLine = _Variant(
  'short one-line',
  'Rio',
  'Rio',
  brand: 'Kia',
);

Map<String, dynamic> _car(
  _Variant v, {
  required bool chips,
  int price = 48500,
}) => <String, dynamic>{
  'id': 'rect_1',
  'public_id': 'rect_1',
  'brand': v.brand,
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
    // At the text-scale cap the fixed card is full: the rows then keep ~2 dp
    // between them (never touching).
    expect(
      m.titleToNext,
      greaterThanOrEqualTo(1.5),
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
      'y[title ${(m.title.top - m.card.top).toStringAsFixed(1)}-'
      '${(m.title.bottom - m.card.top).toStringAsFixed(1)} '
      'next ${(m.next - m.card.top).toStringAsFixed(1)} '
      'year ${(m.year.top - m.card.top).toStringAsFixed(1)}-'
      '${(m.year.bottom - m.card.top).toStringAsFixed(1)} '
      'badge ${(m.badge.top - m.card.top).toStringAsFixed(1)}-'
      '${(m.badge.bottom - m.card.top).toStringAsFixed(1)}] '
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

  group('card height is FIXED: identical at every text scale', () {
    for (final d in _devices.entries) {
      for (final chips in const [true, false]) {
        for (final v in const [_oneLine, _twoLine, _shortOneLine]) {
          testWidgets(
            '${d.key} ${v.name} ${chips ? 'chips' : 'plain'}',
            (tester) async {
              final base = await measure(
                tester,
                size: d.value,
                scale: 1.0,
                variant: v,
                chips: chips,
              );
              // 1.0x design: the height a card always had at this width.
              final w = d.value.width;
              expect(
                base.cardH,
                closeTo(
                  (w - 8) /
                      ListingLayoutPrefs.gridChildAspectRatioForWidth(1, w),
                  0.01,
                ),
              );
              for (final s in const [1.15, 1.3, 1.5, 2.0]) {
                final scaled = await measure(
                  tester,
                  size: d.value,
                  scale: s,
                  variant: v,
                  chips: chips,
                );
                expect(
                  scaled.cardH,
                  closeTo(base.cardH, 0.01),
                  reason:
                      '${d.key} @${s}x ${v.name}: card height '
                      '${scaled.cardH.toStringAsFixed(1)} dp vs '
                      '${base.cardH.toStringAsFixed(1)} dp at 1.0x',
                );
              }
            },
          );
        }
      }
    }
  });

  group('card height is identical for every title and every scale', () {
    for (final d in _devices.entries) {
      for (final s in _scales) {
        testWidgets('${d.key} @${s}x', (tester) async {
          final heights = <double>[];
          for (final v in const [_oneLine, _twoLine, _shortOneLine]) {
            for (final chips in const [true, false]) {
              heights.add(
                (await measure(
                  tester,
                  size: d.value,
                  scale: s,
                  variant: v,
                  chips: chips,
                )).cardH,
              );
            }
          }
          for (final h in heights) {
            expect(h, closeTo(heights.first, 0.01), reason: '${d.key} @${s}x');
          }
        });
      }
    }
  });

  group('one-line title is centred in the two-line title area', () {
    for (final d in _devices.entries) {
      for (final s in _scales) {
        for (final chips in const [true, false]) {
          testWidgets(
            '${d.key} @${s}x ${chips ? 'with engine+trim' : 'no engine/trim'}',
            (tester) async {
              final one = await measure(
                tester,
                size: d.value,
                scale: s,
                variant: _shortOneLine,
                chips: chips,
              );
              final two = await measure(
                tester,
                size: d.value,
                scale: s,
                variant: _twoLine,
                chips: chips,
              );
              // Same centre line: the one-line title sits in the middle of the
              // area a two-line title uses, instead of hugging the top and
              // leaving a hole above the chips.
              expect(
                one.title.center.dy,
                closeTo(two.title.center.dy, 1.0),
                reason:
                    '${d.key} @${s}x: one-line title centre '
                    '${(one.title.center.dy - one.card.top).toStringAsFixed(1)}'
                    ' dp vs two-line '
                    '${(two.title.center.dy - two.card.top).toStringAsFixed(1)}'
                    ' dp',
              );
              // The rows below do not move between the two cards.
              expect(one.next, closeTo(two.next, 0.5), reason: 'next row');
              expect(one.year.top, closeTo(two.year.top, 0.5));
              expect(one.badge.top, closeTo(two.badge.top, 0.5));
              expect(one.city.top, closeTo(two.city.top, 0.5));
              // Exactly centred: the gap under the one-line title is the
              // two-line gap plus half the missing line - no extra hole.
              expect(
                one.titleToNext - two.titleToNext,
                closeTo((two.title.height - one.title.height) / 2, 1.0),
                reason: '${d.key} @${s}x: hole under the one-line title',
              );
            },
          );
        }
      }
    }
  });

  // The card text follows the system size only up to what the FIXED card
  // height can hold (ListingLayoutPrefs.rectCardTextScale): ~1.5x on a Pro Max,
  // ~1.3x at 393 dp, ~1.15-1.2x at 360 dp and below.
  const Map<int, ({double min, double max})> capByWidth = {
    440: (min: 1.45, max: 1.5),
    393: (min: 1.25, max: 1.3),
    360: (min: 1.1, max: 1.2),
    320: (min: 1.1, max: 1.2),
  };

  double appliedScale(WidgetTester tester, Finder f) =>
      MediaQuery.textScalerOf(tester.element(f.first)).scale(14) / 14;

  group('painted text scale is capped by the fixed card height', () {
    for (final d in _devices.entries) {
      final cap = capByWidth[d.value.width.toInt()]!;
      for (final s in _scales) {
        testWidgets('${d.key} @${s}x', (tester) async {
          await measure(
            tester,
            size: d.value,
            scale: s,
            variant: _twoLine,
            chips: true,
          );
          final title = appliedScale(
            tester,
            find.textContaining('Camry', findRichText: true),
          );
          final year = appliedScale(tester, find.text('2021'));
          final engine = appliedScale(tester, find.text('XLE'));
          final city = appliedScale(tester, find.text('Erbil'));
          for (final a in [title, year, engine, city]) {
            expect(a, closeTo(title, 0.001), reason: 'rows use different sizes');
          }
          expect(title, greaterThanOrEqualTo(1.0 - 1e-9));
          expect(
            title,
            lessThanOrEqualTo(math.min(s, cap.max) + 1e-9),
            reason: '${d.key} @${s}x: text scale $title exceeds the cap',
          );
          if (s >= cap.max) {
            expect(
              title,
              greaterThanOrEqualTo(cap.min),
              reason: '${d.key} @${s}x: text capped too low ($title)',
            );
          } else {
            // Below the cap the user's size is honoured.
            expect(title, closeTo(s, 0.001));
          }
          // The price badge never follows the system size.
          expect(
            tester.getSize(_priceBadge()).height,
            closeTo(26, 0.5),
            reason: 'price badge grew',
          );
        });
      }
    }
  });

  group('full text stays reachable', () {
    testWidgets('accessible description carries every detail', (tester) async {
      final handle = tester.ensureSemantics();
      await measure(
        tester,
        size: const Size(440, 956),
        scale: 2.0,
        variant: _twoLine,
        chips: true,
      );
      final label = tester.getSemantics(find.byType(InkWell).first).label;
      for (final part in [
        'Toyota Camry Hybrid Premium Edition',
        '3.5',
        'XLE',
        '2021',
        '123,456',
        'Erbil',
        '48,500',
      ]) {
        expect(label, contains(part), reason: 'missing "$part" in "$label"');
      }
      handle.dispose();
    });

    Future<void> pumpNavigable(WidgetTester tester) async {
      await f10LoadFonts(tester);
      f10SetWindow(tester, width: 440, height: 956);
      await f10Pump(
        tester,
        f10App(
          textScale: 2.0,
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => settings.name == '/car_detail'
                  ? const Scaffold(body: Text('DETAIL PAGE'))
                  : _feed(_car(_twoLine, chips: true)),
            ),
          ),
        ),
      );
    }

    const fullTitle = 'Toyota Camry Hybrid Premium Edition';

    testWidgets('a normal tap still opens the details page, no tooltip', (
      tester,
    ) async {
      await pumpNavigable(tester);
      final before = find.text(fullTitle, findRichText: true).evaluate().length;
      await tester.tapAt(tester.getRect(find.byType(InkWell).first).center);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('DETAIL PAGE'), findsOneWidget);
      expect(
        find.text(fullTitle, findRichText: true).evaluate().length,
        lessThanOrEqualTo(before),
      );
    });

    testWidgets('a long press shows the full title and does not navigate', (
      tester,
    ) async {
      await pumpNavigable(tester);
      final before = find.text(fullTitle, findRichText: true).evaluate().length;
      await tester.longPress(find.byType(InkWell).first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('DETAIL PAGE'), findsNothing);
      expect(
        find.text(fullTitle, findRichText: true).evaluate().length,
        greaterThan(before),
        reason: 'long press did not show the full-title tooltip',
      );
      await tester.pump(const Duration(seconds: 3)); // tooltip auto-dismiss
    });

    testWidgets('scrolling the list is not blocked by the tooltip', (
      tester,
    ) async {
      await f10LoadFonts(tester);
      f10SetWindow(tester, width: 440, height: 600);
      await f10Pump(
        tester,
        f10App(
          textScale: 1.0,
          home: Scaffold(
            body: Builder(
              builder: (context) => ListView.builder(
                itemCount: 8,
                itemBuilder: (context, i) => SizedBox(
                  height: 169,
                  child: buildGlobalCarCard(
                    context,
                    _car(_twoLine, chips: true),
                    listLayout: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final first = tester.getTopLeft(find.byType(InkWell).first).dy;
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.getTopLeft(find.byType(InkWell).first).dy,
        lessThan(first - 100),
        reason: 'ListView did not scroll over the cards',
      );
    });
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
      for (final d in _devices.entries) {
        for (final s in _scales) {
          for (final v in const [_oneLine, _twoLine, _shortOneLine]) {
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
    for (final d in _devices.entries) {
      for (final s in _scales) {
        for (final v in const [_oneLine, _twoLine, _shortOneLine]) {
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
