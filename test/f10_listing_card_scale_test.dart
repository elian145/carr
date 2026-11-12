// F-10: the REAL listing card (buildGlobalCarCard) at system text scale
// 1.0 / 1.5 / 2.0 in the real grid / list cells (cell aspect comes from
// ListingLayoutPrefs.gridChildAspectRatioForWidth(textScale:), exactly as the
// feed pages call it).
//
// Per scale: no RenderFlex overflow / framework exception, the title and the
// price footer stay inside the card, the price badge stays tappable-sized, and
// the text really grows (rendered title height at 2.0 > at 1.0).
import 'package:car_listing_app/app/widgets/global_listing_card.dart';
import 'package:car_listing_app/shared/prefs/listing_layout_prefs.dart';
import 'package:car_listing_app/shared/ui/app_text_scale.dart';
import 'package:car_listing_app/shared/ui/brand_logo_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/brand_picker_harness.dart' show installLogoOverride;
import 'support/f10_scale_harness.dart';

Map<String, dynamic> _car({String city = 'Erbil'}) => <String, dynamic>{
      'id': 'f10_card_1',
      'public_id': 'f10_card_1',
      'brand': 'Toyota',
      'model': 'Camry Hybrid Premium Edition',
      'trim': 'XLE Premium',
      'engine_size': '3.5',
      'year': 2021,
      'mileage': 123456,
      'price': 48500,
      'currency': 'USD',
      'city': city,
      'images': <dynamic>[],
      'videos': <dynamic>[],
    };

/// Mirrors home_slivers.dart: padding 8, spacing 8, aspect from the prefs.
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

  Future<void> pump(
    WidgetTester tester, {
    required double scale,
    required bool list,
    double width = kF10RegularWidth,
    Locale locale = const Locale('en'),
    String city = 'Erbil',
  }) async {
    await f10LoadFonts(tester);
    f10SetWindow(tester, width: width, height: 900);
    await f10Pump(
      tester,
      f10App(
        home: _feed(list: list, car: _car(city: city)),
        textScale: scale,
        locale: locale,
      ),
    );
  }

  Finder title() => find.textContaining('Camry').first;

  double titleHeight(WidgetTester tester) =>
      tester.getSize(title()).height;

  for (final list in const [false, true]) {
    final layoutName = list ? 'list (1 column)' : 'grid (2 columns)';

    for (final scale in kF10Scales) {
      testWidgets('$layoutName card at ${scale}x: no overflow, content inside',
          (tester) async {
        await pump(tester, scale: scale, list: list);
        expect(tester.takeException(), isNull);

        final card = find.byType(Semantics).evaluate().isEmpty
            ? find.byType(Card)
            : find.byType(RepaintBoundary);
        expect(card, findsWidgets);

        // Title and the price footer are laid out inside the first card.
        final cardRect = tester.getRect(
          find.byType(InkWell).first,
        );
        final t = tester.getRect(title());
        expect(t.top, greaterThanOrEqualTo(cardRect.top - 0.5));
        expect(t.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5));

        final price = find.textContaining('48,500').first;
        final p = tester.getRect(price);
        expect(p.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5),
            reason: 'price must not be pushed out of the card');
        expect(p.top, greaterThanOrEqualTo(cardRect.top - 0.5));
        // Badge is a usable, non-degenerate target.
        expect(p.height, greaterThan(8));
        expect(p.width, greaterThan(20));
        // Whole price is inside the horizontal bounds of the card.
        expect(p.left, greaterThanOrEqualTo(cardRect.left - 0.5));
        expect(p.right, lessThanOrEqualTo(cardRect.right + 0.5));
      });
    }

    testWidgets('$layoutName: title text really scales (2.0x taller than 1.0x)',
        (tester) async {
      await pump(tester, scale: 1.0, list: list);
      expect(tester.takeException(), isNull);
      final h1 = titleHeight(tester);

      await pump(tester, scale: 2.0, list: list);
      expect(tester.takeException(), isNull);
      final h2 = titleHeight(tester);

      // The grid card follows the system size fully. The rectangular card has
      // a FIXED height, so its text grows only as far as that height can hold
      // (ListingLayoutPrefs.rectCardTextScale: 1.15x at this 360 dp width).
      expect(h2, greaterThan(h1 * (list ? 1.1 : 1.3)),
          reason: 'title rendered at 2.0x must be taller ($h1 -> $h2)');
    });

    testWidgets('$layoutName: 2.0x on a 320 dp phone has no overflow',
        (tester) async {
      await pump(
        tester,
        scale: 2.0,
        list: list,
        width: kF10NarrowWidth,
      );
      expect(tester.takeException(), isNull);
      final cardRect = tester.getRect(find.byType(InkWell).first);
      final p = tester.getRect(find.textContaining('48,500').first);
      expect(p.right, lessThanOrEqualTo(cardRect.right + 0.5));
      expect(p.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5));
    });

    testWidgets('$layoutName: Arabic / RTL at 2.0x has no overflow',
        (tester) async {
      await pump(
        tester,
        scale: 2.0,
        list: list,
        locale: const Locale('ar'),
        city: 'أربيل',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('aspect ratio is unchanged at 1.0x; the grid cell gets taller when '
      'text grows, the list cell never does', (tester) async {
    for (final cols in const [1, 2, 3]) {
      for (final w in const [320.0, 360.0, 411.0, 800.0]) {
        final base = ListingLayoutPrefs.gridChildAspectRatioForWidth(cols, w);
        expect(
          ListingLayoutPrefs.gridChildAspectRatioForWidth(
            cols,
            w,
            textScale: 1.0,
          ),
          base,
        );
        final a15 = ListingLayoutPrefs.gridChildAspectRatioForWidth(
          cols,
          w,
          textScale: 1.5,
        );
        final a20 = ListingLayoutPrefs.gridChildAspectRatioForWidth(
          cols,
          w,
          textScale: 2.0,
        );
        if (cols == 1) {
          // Rectangular card: FIXED height, whatever the text size.
          expect(a15, base, reason: 'cols=$cols w=$w');
          expect(a20, base, reason: 'cols=$cols w=$w');
        } else {
          expect(a15, lessThan(base), reason: 'cols=$cols w=$w');
          expect(a20, lessThan(a15), reason: 'cols=$cols w=$w');
        }
        // Clamped like the lock: nothing beyond 2.0 changes the cell.
        expect(
          ListingLayoutPrefs.gridChildAspectRatioForWidth(
            cols,
            w,
            textScale: 5.0,
          ),
          a20,
        );
      }
    }
  });
}
