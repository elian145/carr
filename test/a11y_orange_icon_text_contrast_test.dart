// F-24 follow-up: WCAG 2.x contrast for the *remaining* brand-orange uses.
//
// c02e7ba fixed white text on orange fills and normal text in orange. This
// file covers what was left:
//  * orange ICONS / borders / focus rings / spinners need 3:1 (WCAG 1.4.11);
//    the raw brand orange is only 2.86:1 on white (worse on light greys),
//  * white text on the "FEATURED" chip, the price badge, the IQD currency
//    tile and the analytics headers (gradient ends were ~2.4:1),
//  * small orange labels on selected-tile TINTS and on the pending-edits
//    banner (Material orange 700 was ~2.7:1),
//  * the light theme `primary` (focus borders, text buttons, spinners).
import 'dart:io';

import 'package:car_listing_app/features/sell/sell_fancy_selector.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/shared/listings/listing_featured_badge.dart';
import 'package:car_listing_app/shared/listings/pending_edits_banner.dart';
import 'package:car_listing_app/theme/app_colors.dart';
import 'package:car_listing_app/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] at [alpha] painted over opaque [bg].
Color _tint(Color fg, Color bg, double alpha) =>
    Color.alphaBlend(fg.withValues(alpha: alpha), bg);

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light
          ? AppThemes.lightTheme
          : AppThemes.darkTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  const white = Colors.white;
  // Surfaces the app paints icons / borders on (light shell + light greys
  // used for fields and cards, dark cards and the darkest dark surfaces).
  const lightSurfaces = <String, Color>{
    'white shell': Colors.white,
    'listing card F4F4F4': Color(0xFFF4F4F4),
    'field fill F3F3F3': Color(0xFFF3F3F3),
    'iOS grey F2F2F7': Color(0xFFF2F2F7),
    'input fill E0E0E0': Color(0xFFE0E0E0),
  };
  const darkSurfaces = <String, Color>{
    'dark card 1E1E1E': Color(0xFF1E1E1E),
    'dark 121212': Color(0xFF121212),
    'black': Colors.black,
  };

  group('icons / borders / large text (3:1)', () {
    test('documents the violation: raw brand orange < 3:1 on white', () {
      expect(_contrast(AppColors.brandOrange, white), lessThan(3.0));
      expect(
        _contrast(AppColors.brandOrange, const Color(0xFFE0E0E0)),
        lessThan(3.0),
      );
    });

    test('brandOrangeIcon >= 3:1 on every light and dark surface', () {
      for (final e in {...lightSurfaces, ...darkSurfaces}.entries) {
        expect(
          _contrast(AppColors.brandOrangeIcon, e.value),
          greaterThanOrEqualTo(3.0),
          reason: 'brandOrangeIcon on ${e.key}',
        );
      }
    });

    test('brandOrangeIcon stays on the brand hue and is still clearly orange',
        () {
      final h = HSLColor.fromColor(AppColors.brandOrangeIcon);
      final b = HSLColor.fromColor(AppColors.brandOrange);
      expect((h.hue - b.hue).abs(), lessThan(5));
      expect(h.saturation, greaterThan(0.9));
    });

    test('orange icon on its own 10-18% tint (selected tiles) is still >= 3:1',
        () {
      for (final a in [0.08, 0.10, 0.12, 0.14, 0.18]) {
        expect(
          _contrast(
            AppColors.brandOrangeIcon,
            _tint(AppColors.brandOrange, white, a),
          ),
          greaterThanOrEqualTo(3.0),
          reason: 'tint alpha $a over white',
        );
      }
    });

    test('chat composer outline orange meets 3:1 on light and dark', () {
      // was 0xFFFF7A00 (~2.6:1 on white)
      expect(
        _contrast(AppColors.brandOrangeIcon, white),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        _contrast(AppColors.brandOrangeIcon, const Color(0xFF1E1E1E)),
        greaterThanOrEqualTo(3.0),
      );
    });
  });

  group('white text / icons on orange fills (4.5:1)', () {
    test('every stop of the white-text gradient is >= 4.5:1 vs white', () {
      expect(AppColors.brandGradientBehindWhiteText.length, greaterThan(1));
      for (final c in AppColors.brandGradientBehindWhiteText) {
        expect(_contrast(white, c), greaterThanOrEqualTo(4.5), reason: '$c');
      }
    });

    test('the old bright gradients failed (documents the regression)', () {
      expect(_contrast(white, const Color(0xFFFF8A50)), lessThan(3.0));
      expect(_contrast(white, const Color(0xFFFF8C42)), lessThan(3.0));
      expect(_contrast(white, const Color(0xFFFF5A00)), lessThan(4.5));
    });

    testWidgets('FEATURED chip: white label on its fill >= 4.5:1',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (c) {
              ctx = c;
              return buildListingFeaturedBadge(c);
            },
          ),
        ),
      );
      final label = listingFeaturedLabel(ctx);
      final text = tester.widget<Text>(find.text(label));
      final box = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.color != null);
      expect(text.style!.color, white);
      expect(
        _contrast(text.style!.color!, box.color!),
        greaterThanOrEqualTo(4.5),
      );
      // compact variant used on grid cards (10px text) is the same fill
      expect(
        _contrast(white, kFeaturedListingAccent),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('IQD currency tile: 8px white label on its fill >= 4.5:1',
        (tester) async {
      await tester.pumpWidget(_host(buildCurrencyIcon('IQD')));
      final text = tester.widget<Text>(find.text('IQD'));
      final fill = (tester
              .widgetList<Container>(find.byType(Container))
              .map((c) => c.decoration)
              .whereType<BoxDecoration>()
              .firstWhere((d) => d.color != null))
          .color!;
      expect(
        _contrast(text.style!.color!, fill),
        greaterThanOrEqualTo(4.5),
        reason: 'IQD label on $fill',
      );
    });
  });

  group('small orange text (4.5:1)', () {
    test('accentTextOnTint is >= 4.5:1 on the 10-18% tints, light and dark', () {
      const dark = Color(0xFF1E1E1E);
      for (final a in [0.10, 0.12, 0.14, 0.18]) {
        expect(
          _contrast(
            AppColors.brandOrangeDeep,
            _tint(AppColors.brandOrange, white, a),
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'light tint alpha $a',
        );
        expect(
          _contrast(
            AppColors.brandOrangeSoft,
            _tint(AppColors.brandOrange, dark, a),
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'dark tint alpha $a',
        );
      }
      // and strictly better than the Strong shade on the light tint
      expect(
        _contrast(
          AppColors.brandOrangeDeep,
          _tint(AppColors.brandOrange, white, 0.12),
        ),
        greaterThan(
          _contrast(
            AppColors.brandOrangeStrong,
            _tint(AppColors.brandOrange, white, 0.12),
          ),
        ),
      );
    });

    testWidgets('accentTextOnTint resolves per theme', (tester) async {
      late Color onLight;
      late Color onDark;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Theme(
                data: ThemeData(brightness: Brightness.light),
                child: Builder(
                  builder: (c) {
                    onLight = AppColors.accentTextOnTint(c);
                    return const SizedBox();
                  },
                ),
              ),
              Theme(
                data: ThemeData(brightness: Brightness.dark),
                child: Builder(
                  builder: (c) {
                    onDark = AppColors.accentTextOnTint(c);
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );
      expect(onLight, AppColors.brandOrangeDeep);
      expect(onDark, AppColors.brandOrangeSoft);
    });

    for (final status in ['pending', 'editing']) {
      testWidgets('pending-edits banner "$status" title >= 4.5:1 (light)',
          (tester) async {
        await tester.pumpWidget(
          _host(
            PendingEditsBanner(
              listing: {
                'id': 'car_1',
                'status': 'active',
                'pending_revision': {'status': status, 'car': {'id': 'car_1'}},
              },
            ),
          ),
        );
        final banner = find.byKey(const ValueKey('pending_edits_banner'));
        expect(banner, findsOneWidget);
        final deco = (tester.widget<Container>(banner)).decoration!
            as BoxDecoration;
        final bg = Color.alphaBlend(deco.color!, Colors.white);
        final title = tester.widget<Text>(
          find.descendant(of: banner, matching: find.byType(Text)).first,
        );
        final fg = title.style!.color!;
        if (status == 'pending') {
          // the orange variant was Material orange 700 (~2.7:1)
          expect(fg, AppColors.brandOrangeDeep);
        }
        expect(
          _contrast(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: 'banner title $fg on $bg',
        );
      });
    }
  });

  group('theme primary', () {
    test('light primary is >= 4.5:1 on white and >= 3:1 on the input fill', () {
      final scheme = AppThemes.lightTheme.colorScheme;
      expect(scheme.primary, AppColors.brandOrangeStrong);
      expect(_contrast(scheme.primary, white), greaterThanOrEqualTo(4.5));
      // focused input border is drawn in primary over the filled field
      final fill = AppThemes.lightTheme.inputDecorationTheme.fillColor!;
      expect(_contrast(scheme.primary, fill), greaterThanOrEqualTo(3.0));
      final focus =
          (AppThemes.lightTheme.inputDecorationTheme.focusedBorder!
                  as OutlineInputBorder)
              .borderSide
              .color;
      expect(_contrast(focus, fill), greaterThanOrEqualTo(3.0));
    });

    test('dark primary keeps >= 3:1 on dark fields and cards', () {
      final scheme = AppThemes.darkTheme.colorScheme;
      final fill = AppThemes.darkTheme.inputDecorationTheme.fillColor!;
      expect(_contrast(scheme.primary, fill), greaterThanOrEqualTo(3.0));
      expect(
        _contrast(scheme.primary, const Color(0xFF1E1E1E)),
        greaterThanOrEqualTo(3.0),
      );
    });
  });

  group('source guards (lib/)', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    String rel(File f) => f.path.replaceAll('\\', '/');

    test('no raw orange hex literals outside AppColors', () {
      final raw = RegExp(r'0xFF(?:FF6B00|FF5A00|FF7A00|FF8A50|FF8C42)');
      final offenders = [
        for (final f in dartFiles)
          if (!rel(f).endsWith('lib/theme/app_colors.dart') &&
              raw.hasMatch(f.readAsStringSync()))
            rel(f),
      ];
      expect(
        offenders,
        isEmpty,
        reason: 'use an AppColors token (Icon / Strong / Deep) instead',
      );
    });

    test('no solid orange fill carries white text (extended alias list)', () {
      final pair = RegExp(
        r'(?:backgroundColor|selectedColor):\s*(?:AppColors\.brandOrange(?!Strong|Deep|Soft)|AppColors\.brandOrangeIcon|kFilterAccentColor|_searchAccent|_brandOrange|_accent|_editDealerAccent|priceAccent)\s*,\s*foregroundColor:\s*Colors\.white',
      );
      final offenders = [
        for (final f in dartFiles)
          if (pair.hasMatch(f.readAsStringSync())) rel(f),
      ];
      expect(offenders, isEmpty);
    });

    test('bare brand orange only survives where it is audited', () {
      // `AppColors.brandOrange` (2.86:1 on white) is allowed only for: the
      // theme seed, dark-only surfaces, tinted fills, fills carrying BLACK
      // text, disabled controls, and the explicit dark-theme branch of a
      // light/dark ternary. Anything new must pick Icon / Strong / Deep /
      // accentText instead.
      const audited = <String>{
        'lib/theme_provider.dart', // seed + dark primary
        'lib/widgets/in_app_video_screen.dart', // dark video chrome
        'lib/shared/media/pick_cover_image.dart', // cropper toolbar (dark)
        'lib/shared/media/pick_circular_image.dart', // cropper toolbar (dark)
        'lib/app/widgets/home_search_dialog.dart', // always-dark dialog
        'lib/pages/tiktok_scroll_listing_card.dart', // text over dark scrim
        'lib/pages/comparison_page_helpers.dart', // fills with BLACK text
        'lib/features/chat/chat_notifications_page.dart', // tint fill only
        'lib/features/sell/sell_car_page.dart', // alpha-tinted progress bar
        'lib/pages/production_login_page.dart', // tint + disabled bg
        'lib/pages/dealer_profile_page_search.dart', // dark ternary branch
        'lib/features/home/home_more_filters_dialog.dart', // dark ternary
        'lib/shared/ui/filter_card_sections.dart', // dark ternary
        'lib/features/sell/sell_fancy_selector.dart', // dark ternary
      };
      final bare = RegExp(r'AppColors\.brandOrange(?![A-Za-z])');
      final offenders = <String>[];
      for (final f in dartFiles) {
        final p = rel(f);
        if (p.endsWith('lib/theme/app_colors.dart') || audited.contains(p)) {
          continue;
        }
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (l.trimLeft().startsWith('//')) continue;
          if (!bare.hasMatch(l)) continue;
          final next = i + 1 < lines.length ? lines[i + 1] : '';
          // tints: `.withValues(alpha: ...)` on this or the next line
          if (l.contains('.withValues') || next.trimLeft().startsWith('.withValues')) {
            continue;
          }
          offenders.add('$p:${i + 1}: ${l.trim()}');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
