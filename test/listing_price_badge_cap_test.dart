// Orange price badge at large iOS / Android text sizes (CarNet TestFlight:
// "oversized orange price badge").
//
// Before the fix the pill was `26 x textScale` tall (52 dp at 2.0x, double the
// 1.0x design) and, because its width was measured with a TextPainter that did
// not inherit the app text style, it was frequently stretched to the maximum
// width with the text shrunk inside (empty orange padding). A 1.3x cap was
// still too large on device, so the badge now keeps its NORMAL 1.0x size
// (26 dp pill, 15 sp price) whatever the system text size is, in both the
// list and the grid card.
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

/// Badge scale cap and the 1.0x design (list card: (24 + 2) dp tall, 15 sp).
const double _cap = 1.0;
const double _designHeight = 26;
const double _designFont = 15;

Map<String, dynamic> _car({int price = 48500}) => <String, dynamic>{
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
  'city': 'Erbil',
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
  });
  final Rect pill;
  final Rect text;
  final Rect card;
  final bool fitted;
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
  }) async {
    await f10LoadFonts(tester);
    f10SetWindow(tester, width: size.width, height: size.height);
    await f10Pump(
      tester,
      f10App(
        home: _feed(
          list: list,
          car: _car(price: price),
        ),
        textScale: scale,
        boldText: bold,
        locale: locale,
      ),
    );
    expect(tester.takeException(), isNull);
    final badge = _badge();
    final text = find.descendant(of: badge, matching: find.byType(Text)).first;
    return _B(
      pill: tester.getRect(badge),
      text: tester.getRect(text),
      card: tester.getRect(find.byType(InkWell).first),
      fitted: find
          .descendant(of: badge, matching: find.byType(FittedBox))
          .evaluate()
          .isNotEmpty,
    );
  }

  void expectCompactBadge(_B b, String reason, {required bool longPrice}) {
    // Height stops growing at the cap (grid 1.0x design is the same 26 dp).
    expect(
      b.pill.height,
      lessThanOrEqualTo(_designHeight * _cap + 0.5),
      reason:
          '$reason: pill ${b.pill.height.toStringAsFixed(1)} dp tall '
          '(cap ${(_designHeight * _cap).toStringAsFixed(1)})',
    );
    // Text stops growing at the cap too (strut height 1 => height = font px).
    expect(
      b.text.height,
      lessThanOrEqualTo(_designFont * _cap + 1.0),
      reason: '$reason: price text ${b.text.height.toStringAsFixed(1)} px',
    );
    // Text lies inside the pill with room to spare: no clipping.
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
    expect(b.text.top, greaterThanOrEqualTo(b.pill.top - 0.5));
    expect(b.text.bottom, lessThanOrEqualTo(b.pill.bottom + 0.5));
    // The pill stays inside the card.
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
    if (!longPrice) {
      // A normal price hugs its text: no empty orange padding, no shrink.
      expect(b.fitted, isFalse, reason: '$reason: price text was shrunk');
      expect(
        b.pill.width - b.text.width,
        lessThanOrEqualTo(20),
        reason:
            '$reason: pill ${b.pill.width.toStringAsFixed(1)} dp wide for '
            '${b.text.width.toStringAsFixed(1)} dp of text (empty padding)',
      );
    }
  }

  for (final list in const [true, false]) {
    final layout = list ? 'list (1 column)' : 'grid (2 columns)';
    group('badge stays compact: $layout', () {
      for (final d in _devices.entries) {
        for (final s in _scales) {
          testWidgets('${d.key} @${s}x', (tester) async {
            final b = await measure(
              tester,
              size: d.value,
              scale: s,
              list: list,
            );
            if (_print) {
              // ignore: avoid_print
              print(
                'METRIC badge | $layout | ${d.key} | ${s}x | '
                'pill=${b.pill.width.toStringAsFixed(1)}x'
                '${b.pill.height.toStringAsFixed(1)} '
                'text=${b.text.width.toStringAsFixed(1)}x'
                '${b.text.height.toStringAsFixed(1)} fitted=${b.fitted}',
              );
            }
            expectCompactBadge(b, '$layout ${d.key} @${s}x', longPrice: false);
          });
        }
      }
    });

    group('badge keeps its 1.0x size at every text scale: $layout', () {
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
            // The 1.0x design itself: 26 dp pill, 15 sp price (24 dp / 14 sp
            // in grid tiles narrower than 130 dp).
            expect(
              at10.pill.height,
              anyOf(closeTo(_designHeight, 0.5), closeTo(_designHeight - 2, 0.5)),
            );
            for (final s in const [1.15, 1.3, 1.5, 2.0]) {
              final b = await measure(
                tester,
                size: d.value,
                scale: s,
                list: list,
                bold: bold,
              );
              expect(
                b.pill.height,
                closeTo(at10.pill.height, 0.05),
                reason: '${d.key} @${s}x: pill height changed',
              );
              expect(
                b.pill.width,
                closeTo(at10.pill.width, 0.05),
                reason: '${d.key} @${s}x: pill width changed',
              );
              expect(
                b.text.height,
                closeTo(at10.text.height, 0.05),
                reason: '${d.key} @${s}x: price text size changed',
              );
              expect(
                b.text.width,
                closeTo(at10.text.width, 0.05),
                reason: '${d.key} @${s}x: price text width changed',
              );
            }
          });
        }
      }
    });

    group('long price never overflows: $layout', () {
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
            expectCompactBadge(
              b,
              '$layout ${d.key} @${s}x long price',
              longPrice: true,
            );
          });
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
              expectCompactBadge(
                b,
                '${locale.languageCode} @${s}x',
                longPrice: false,
              );
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
          expectCompactBadge(b, 'bold @${s}x', longPrice: false);
        });
      }
    }
  });
}
