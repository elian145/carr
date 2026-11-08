// F-24: WCAG 2.x AA contrast for the CarNet brand orange.
//
// White on #FF6B00 is ~2.86:1 (fails 4.5:1 for normal text). The brand colour
// itself is unchanged; fills that carry white text use [AppColors.brandOrangeStrong]
// and normal-size orange text uses [AppColors.accentText].
import 'dart:io';

import 'package:car_listing_app/theme/app_colors.dart';
import 'package:car_listing_app/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const white = Colors.white;

  test('documents the original violation: white on brand orange < 4.5:1', () {
    expect(contrast(white, AppColors.brandOrange), lessThan(4.5));
  });

  test('brandOrangeStrong gives white normal text >= 4.5:1', () {
    expect(contrast(white, AppColors.brandOrangeStrong),
        greaterThanOrEqualTo(4.5));
  });

  test('brandOrangeStrong is the same hue family (orange), not a new brand',
      () {
    final h = HSLColor.fromColor(AppColors.brandOrangeStrong).hue;
    final b = HSLColor.fromColor(AppColors.brandOrange).hue;
    expect((h - b).abs(), lessThan(8));
  });

  testWidgets('accentText is >= 4.5:1 on light and dark surfaces',
      (tester) async {
    late Color onLight;
    late Color onDark;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Theme(
              data: ThemeData(brightness: Brightness.light),
              child: Builder(builder: (c) {
                onLight = AppColors.accentText(c);
                return const SizedBox();
              }),
            ),
            Theme(
              data: ThemeData(brightness: Brightness.dark),
              child: Builder(builder: (c) {
                onDark = AppColors.accentText(c);
                return const SizedBox();
              }),
            ),
          ],
        ),
      ),
    );
    expect(contrast(onLight, white), greaterThanOrEqualTo(4.5));
    // darkest card/surface colours used by the app
    expect(contrast(onDark, const Color(0xFF1E1E1E)), greaterThanOrEqualTo(4.5));
    expect(contrast(onDark, Colors.black), greaterThanOrEqualTo(4.5));
  });

  test('themed buttons and orange app bars meet 4.5:1', () {
    for (final theme in [AppThemes.lightTheme, AppThemes.darkTheme]) {
      final style = theme.elevatedButtonTheme.style!;
      final bg = style.backgroundColor!.resolve(<WidgetState>{})!;
      final fg = style.foregroundColor!.resolve(<WidgetState>{})!;
      expect(contrast(bg, fg), greaterThanOrEqualTo(4.5),
          reason: '${theme.brightness} elevated button');
    }
    final bar = AppThemes.lightTheme.appBarTheme;
    expect(contrast(bar.backgroundColor!, bar.foregroundColor!),
        greaterThanOrEqualTo(4.5));
  });

  test('layout-toggle / preview label greys are readable on their surfaces',
      () {
    // selected list/grid segment: white icon on the strong orange
    expect(contrast(white, AppColors.brandOrangeStrong),
        greaterThanOrEqualTo(4.5));
    // preview label grey on the white / dark cards
    expect(contrast(const Color(0xFF636366), white), greaterThanOrEqualTo(4.5));
    expect(contrast(const Color(0xFF8E8E93), const Color(0xFF1E1E1E)),
        greaterThanOrEqualTo(4.5));
  });

  test('no solid brand-orange fill carries white text anywhere in lib/', () {
    final pair = RegExp(
      r'(?:backgroundColor|selectedColor):\s*(?:AppColors\.brandOrange|kFilterAccentColor|_brandOrange|_accent|_editDealerAccent|kFeaturedListingAccent)\s*,\s*foregroundColor:\s*Colors\.white',
    );
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (pair.hasMatch(f.readAsStringSync())) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: 'use AppColors.brandOrangeStrong behind white text');
  });
}
