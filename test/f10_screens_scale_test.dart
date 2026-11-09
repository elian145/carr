// F-10: the REAL detail-page building blocks, brand picker, bottom navigation
// and sell review preview at system text scale 1.0 / 1.5 / 2.0 (plus 2.0 on a
// 320 dp phone and in Arabic/RTL).
//
// Every case asserts: no RenderFlex overflow / framework exception, primary
// controls remain on screen and hit-testable (tap really fires the callback),
// and where it is measurable that the text really grows (2.0x taller than
// 1.0x).
import 'package:car_listing_app/app/widgets/main_shell_navigation.dart';
import 'package:car_listing_app/features/listing/car_listing_specs_grid.dart';
import 'package:car_listing_app/features/listing/widgets/car_details_contact_bar.dart';
import 'package:car_listing_app/features/sell/sell_flow.dart'
    show SellReviewCarDetailScrollView;
import 'package:car_listing_app/shared/ui/brand_logo_image.dart';
import 'package:car_listing_app/shared/ui/brand_tile_label.dart';
import 'package:car_listing_app/shared/ui/filter_make_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/brand_picker_harness.dart' show installLogoOverride;
import 'support/f10_scale_harness.dart';

const _specsCar = <String, dynamic>{
  'mileage': 42355,
  'cylinders': 6,
  'engine_size': 3.5,
  'region_specs': 'us',
  'transmission': 'automatic',
  'fuel_type': 'gasoline',
  'trim': 'XLE Premium Plus Package',
  'condition': 'new',
  'drive_type': 'fwd',
  'body_type': 'sedan',
  'color': 'brown',
  'seating': 5,
};

/// The caption Text inside the picker tile (the header summary also shows
/// the selected brand name, so match through [BrandTileLabel]).
Finder _brandLabel(String name) => find.descendant(
      of: find.widgetWithText(BrandTileLabel, name),
      matching: find.byType(Text),
    );

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    installLogoOverride();
  });

  tearDown(() {
    debugBrandLogoImageOverride = null;
  });

  group('listing detail specs grid', () {
    Future<void> pump(
      WidgetTester tester, {
      required double scale,
      double width = kF10RegularWidth,
      Locale locale = const Locale('en'),
    }) async {
      await f10LoadFonts(tester);
      f10SetWindow(tester, width: width);
      await f10Pump(
        tester,
        f10App(
          textScale: scale,
          locale: locale,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Builder(
                  builder: (context) =>
                      buildCarListingSpecsGrid(context, _specsCar),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final scale in kF10Scales) {
      testWidgets('at ${scale}x: no overflow, tiles + detail rows visible',
          (tester) async {
        await pump(tester, scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('Mileage'), findsOneWidget);
        expect(find.text('Automatic'), findsOneWidget);
        expect(find.text('Trim'), findsOneWidget);
        expect(find.textContaining('XLE'), findsOneWidget);
      });
    }

    testWidgets('value text really scales (tile value taller at 2.0x)',
        (tester) async {
      await pump(tester, scale: 1.0);
      final h1 = tester.getSize(find.text('Automatic')).height;
      final detail1 = tester.getSize(find.text('Trim')).height;
      await pump(tester, scale: 2.0);
      expect(tester.takeException(), isNull);
      final h2 = tester.getSize(find.text('Automatic')).height;
      final detail2 = tester.getSize(find.text('Trim')).height;
      expect(h2, greaterThan(h1 * 1.2), reason: 'tile value $h1 -> $h2');
      expect(detail2, greaterThan(detail1 * 1.6),
          reason: 'detail row label $detail1 -> $detail2');
    });

    testWidgets('2.0x on a 320 dp phone: no overflow', (tester) async {
      await pump(tester, scale: 2.0, width: kF10NarrowWidth);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic / RTL at 2.0x: no overflow', (tester) async {
      await pump(tester, scale: 2.0, locale: const Locale('ar'));
      expect(tester.takeException(), isNull);
    });
  });

  group('brand tile label / brand picker', () {
    const longNames = <String>[
      'Toyota',
      'Mercedes-Benz',
      'Zyle Daewoo Commercial Vehicle',
      'Rolls-Royce',
      'Land Rover',
    ];

    Future<void> pump(
      WidgetTester tester, {
      required double scale,
      double width = kF10RegularWidth,
      Locale locale = const Locale('en'),
    }) async {
      await f10LoadFonts(tester);
      f10SetWindow(tester, width: width, height: 1000);
      await f10Pump(
        tester,
        f10App(
          textScale: scale,
          locale: locale,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FilterMakeSection(
                brands: longNames,
                selectedBrand: 'Toyota',
                onBrandSelected: (_) {},
                brandsExpanded: true,
                onToggleBrandsExpanded: () {},
                models: const {},
                requiredFields: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    for (final scale in kF10Scales) {
      testWidgets('picker at ${scale}x: no overflow, tiles tappable',
          (tester) async {
        await pump(tester, scale: scale);
        expect(tester.takeException(), isNull);
        // Every tile label is laid out inside its own tile.
        for (final name in longNames) {
          final f = _brandLabel(name);
          expect(f, findsOneWidget, reason: name);
          final r = tester.getRect(f);
          final tile = tester.getRect(find.ancestor(of: f, matching: find.byType(InkWell)).first);
          expect(r.left, greaterThanOrEqualTo(tile.left - 0.5), reason: '$name at $scale');
          expect(r.right, lessThanOrEqualTo(tile.right + 0.5), reason: '$name at $scale');
          expect(r.bottom, lessThanOrEqualTo(tile.bottom + 0.5), reason: '$name at $scale');
          expect(f10IsOnScreen(tester, f), isTrue, reason: '$name at $scale');
        }
      });
    }

    testWidgets('label text really scales: a 2.0x label is taller than at 1.0x',
        (tester) async {
      await pump(tester, scale: 1.0);
      final h1 = tester.getSize(_brandLabel('Toyota')).height;
      await pump(tester, scale: 2.0);
      expect(tester.takeException(), isNull);
      final h2 = tester.getSize(_brandLabel('Toyota')).height;
      expect(h2, greaterThan(h1 * 1.6), reason: '$h1 -> $h2');
    });

    testWidgets('brand tile is tappable at 2.0x on 320 dp', (tester) async {
      String? tapped;
      await f10LoadFonts(tester);
      f10SetWindow(tester, width: kF10NarrowWidth, height: 1000);
      await f10Pump(
        tester,
        f10App(
          textScale: 2.0,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FilterMakeSection(
                brands: longNames,
                selectedBrand: null,
                onBrandSelected: (b) => tapped = b,
                brandsExpanded: true,
                onToggleBrandsExpanded: () {},
                models: const {},
                requiredFields: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      await tester.tap(_brandLabel('Mercedes-Benz'));
      expect(tapped, 'Mercedes-Benz');
    });

    test('plan at 1.0x is the same as before (default argument)', () {
      const style = TextStyle(fontSize: 12, fontFamily: 'Roboto');
      for (final n in longNames) {
        final a = BrandTileLabel.plan(text: n, style: style, maxWidth: 70);
        final b = BrandTileLabel.plan(
          text: n,
          style: style,
          maxWidth: 70,
          textScale: 1.0,
        );
        expect(a.toString(), b.toString());
        expect(a.maxLines, b.maxLines);
      }
      expect(BrandTileLabel.rowHeightFor(1.0), 92);
      expect(BrandTileLabel.maxHeightFor(1.0), 30);
      expect(BrandTileLabel.rowHeightFor(2.0), 122);
    });
  });

  group('bottom navigation', () {
    Future<void> pump(
      WidgetTester tester, {
      required double scale,
      required ValueChanged<int> onTap,
      double width = kF10RegularWidth,
      Locale locale = const Locale('en'),
    }) async {
      await f10LoadFonts(tester);
      f10SetWindow(tester, width: width);
      await f10Pump(
        tester,
        f10App(
          textScale: scale,
          locale: locale,
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: Builder(
              builder: (context) => buildFloatingBottomNav(
                context,
                currentIndex: 0,
                onTap: onTap,
                solidBackground: true,
              ),
            ),
          ),
        ),
      );
    }

    for (final scale in kF10Scales) {
      testWidgets('at ${scale}x: no overflow and every tab is tappable',
          (tester) async {
        final taps = <int>[];
        await pump(tester, scale: scale, onTap: taps.add);
        expect(tester.takeException(), isNull);
        final bar = find.byType(BottomNavigationBar);
        expect(bar, findsOneWidget);
        expect(f10IsOnScreen(tester, bar), isTrue);

        final icons = <IconData>[
          Icons.home,
          Icons.add,
          Icons.storefront_outlined,
          Icons.person,
        ];
        for (var i = 0; i < icons.length; i++) {
          final f = find.byIcon(icons[i]);
          expect(f, findsOneWidget);
          expect(f10IsOnScreen(tester, f), isTrue, reason: 'tab $i at $scale');
          await tester.tap(f);
          await tester.pump();
        }
        expect(taps, [0, 1, 2, 3]);
      });
    }

    testWidgets('2.0x on 320 dp and in Arabic: no overflow', (tester) async {
      await pump(
        tester,
        scale: 2.0,
        onTap: (_) {},
        width: kF10NarrowWidth,
        locale: const Locale('ar'),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('listing detail contact bar (WhatsApp / call CTAs)', () {
    Future<void> pump(
      WidgetTester tester, {
      required double scale,
      required VoidCallback onWhatsApp,
      required VoidCallback onCall,
      double width = kF10RegularWidth,
      Locale locale = const Locale('en'),
    }) async {
      await f10LoadFonts(tester);
      f10SetWindow(tester, width: width);
      await f10Pump(
        tester,
        f10App(
          textScale: scale,
          locale: locale,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: CarDetailsContactBar(
                  onWhatsApp: onWhatsApp,
                  onCall: onCall,
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (final scale in kF10Scales) {
      for (final width in const [kF10RegularWidth, kF10NarrowWidth]) {
        testWidgets('${scale}x @ ${width.toInt()}dp: both CTAs on screen and '
            'tappable', (tester) async {
          var wa = 0;
          var call = 0;
          await pump(
            tester,
            scale: scale,
            width: width,
            onWhatsApp: () => wa++,
            onCall: () => call++,
          );
          expect(tester.takeException(), isNull);
          final buttons = find.byType(ElevatedButton);
          expect(buttons, findsNWidgets(2));
          for (var i = 0; i < 2; i++) {
            expect(f10IsOnScreen(tester, buttons.at(i)), isTrue,
                reason: 'button $i');
            // Large touch target: at least 44 dp high and wide.
            final s = tester.getSize(buttons.at(i));
            expect(s.height, greaterThanOrEqualTo(44));
            expect(s.width, greaterThanOrEqualTo(44));
          }
          await tester.tap(buttons.at(0));
          await tester.tap(buttons.at(1));
          expect([wa, call], [1, 1]);
        });
      }
    }

    testWidgets('large text stacks the CTAs; label text is taller at 2.0x',
        (tester) async {
      await pump(tester, scale: 1.0, onWhatsApp: () {}, onCall: () {});
      final row = tester.getTopLeft(find.byType(ElevatedButton).at(0));
      final row2 = tester.getTopLeft(find.byType(ElevatedButton).at(1));
      expect(row.dy, row2.dy, reason: 'side by side at 1.0x');

      await pump(tester, scale: 2.0, onWhatsApp: () {}, onCall: () {});
      expect(tester.takeException(), isNull);
      final a = tester.getTopLeft(find.byType(ElevatedButton).at(0));
      final b = tester.getTopLeft(find.byType(ElevatedButton).at(1));
      expect(b.dy, greaterThan(a.dy), reason: 'stacked at 2.0x');
      final h = tester.getSize(find.byType(ElevatedButton).at(0)).height;
      expect(h, greaterThan(46), reason: 'button grows with the text');
    });

    testWidgets('Arabic / RTL at 2.0x on 320 dp: no overflow', (tester) async {
      await pump(
        tester,
        scale: 2.0,
        width: kF10NarrowWidth,
        locale: const Locale('ar'),
        onWhatsApp: () {},
        onCall: () {},
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('sell wizard review preview (SellReviewCarDetailScrollView)', () {
    final car = <String, dynamic>{
      'brand': 'Toyota',
      'model': 'Camry Hybrid Premium Edition',
      'year': 2021,
      'price': 48500,
      'city': 'Erbil',
      'mileage': 123456,
      'trim': 'XLE Premium',
      'transmission': 'automatic',
      'fuel_type': 'gasoline',
      'images': <dynamic>[],
      'videos': <dynamic>[],
    };

    Future<void> pump(
      WidgetTester tester, {
      required double scale,
      double width = kF10RegularWidth,
      Locale locale = const Locale('en'),
    }) async {
      await f10LoadFonts(tester);
      f10SetWindow(tester, width: width, height: 800);
      await f10Pump(
        tester,
        f10App(
          textScale: scale,
          locale: locale,
          home: Scaffold(body: SellReviewCarDetailScrollView(carData: car)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    for (final scale in kF10Scales) {
      testWidgets('at ${scale}x: no overflow, model + price visible',
          (tester) async {
        await pump(tester, scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Camry'), findsWidgets);
        expect(find.textContaining('48,500'), findsWidgets);
      });
    }

    testWidgets('model text really scales (taller at 2.0x)', (tester) async {
      await pump(tester, scale: 1.0);
      final h1 = tester.getSize(find.textContaining('Camry').first).height;
      await pump(tester, scale: 2.0);
      expect(tester.takeException(), isNull);
      final h2 = tester.getSize(find.textContaining('Camry').first).height;
      expect(h2, greaterThan(h1 * 1.5), reason: '$h1 -> $h2');
    });

    testWidgets('2.0x on 320 dp: no overflow', (tester) async {
      await pump(tester, scale: 2.0, width: kF10NarrowWidth);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic / RTL at 2.0x: no overflow', (tester) async {
      await pump(tester, scale: 2.0, locale: const Locale('ar'));
      expect(tester.takeException(), isNull);
    });
  });
}
