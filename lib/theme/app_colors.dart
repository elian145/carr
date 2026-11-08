import 'package:flutter/material.dart';

/// CarNet brand color tokens (UI-03).
///
/// Prefer these (or aliases like [kFilterAccentColor]) over raw `0xFFFF6B00`.
abstract final class AppColors {
  /// Primary brand orange — CTAs, selected filters, nav accent.
  ///
  /// NOT for normal-size text on white or as a fill behind white text:
  /// white on this orange is ~2.86:1 (WCAG AA needs 4.5:1 for normal text).
  /// Use [brandOrangeStrong] for those (F-24). It also misses the 3:1
  /// non-text contrast bar (WCAG 1.4.11) for icons / borders / focus rings on
  /// white (~2.86:1, worse on light greys): use [brandOrangeIcon] for those.
  /// Keep this exact colour for fills, tints, gradients and dark surfaces.
  static const Color brandOrange = Color(0xFFFF6B00);

  /// Lighter companion used in gradients / secondary accents.
  static const Color brandOrangeSoft = Color(0xFFFF8C42);

  /// Accessible darker orange (F-24): ~4.8:1 against white, so it can be the
  /// fill behind white normal-size text, or the colour of normal-size orange
  /// text on a light surface. Same hue as [brandOrange].
  static const Color brandOrangeStrong = Color(0xFFC24E00);

  /// Orange for ICONS, borders, focus rings, spinners and large / bold text
  /// (WCAG 3:1) that works on light AND dark surfaces without needing a
  /// [BuildContext] (so it stays const-friendly): >= 3.1:1 on white, the light
  /// greys the app uses (down to the #E0E0E0 input fill) and the 10-18% orange
  /// tints, and >= 4.1:1 on the dark surfaces (#1E1E1E and darker). Same hue as
  /// [brandOrange]. Normal-size text still needs [accentText] /
  /// [brandOrangeStrong] (4.5:1).
  static const Color brandOrangeIcon = Color(0xFFD65300);

  /// Darker still (>= 5:1 on white AND on the 10-18% orange tints / light greys
  /// the app paints behind orange text) for small text on those tinted pills,
  /// and the end stop of [brandGradientBehindWhiteText]. Same hue.
  static const Color brandOrangeDeep = Color(0xFFA84300);

  /// Gradient for headers / pills that carry WHITE text: every stop is >= 4.5:1
  /// against white (the bright [brandOrange] -> [brandOrangeSoft] gradient is
  /// only ~2.9:1 to ~2.4:1).
  static const List<Color> brandGradientBehindWhiteText = <Color>[
    brandOrangeStrong,
    brandOrangeDeep,
  ];

  /// Orange for normal-size TEXT that must stay readable on the current
  /// surface: [brandOrangeStrong] on light backgrounds (4.5:1+ on white),
  /// the bright brand orange on dark backgrounds (7:1+ on near-black, where
  /// the darker shade would drop to ~3.6:1).
  static Color accentText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? brandOrangeStrong
      : brandOrange;

  /// Like [accentText] but for small text painted on a light orange TINT (the
  /// 10-18% orange fills behind selected tiles / pills), where [brandOrangeStrong]
  /// drops to ~4.2:1: uses [brandOrangeDeep] (>= 5:1) on light surfaces and the
  /// lighter [brandOrangeSoft] on dark ones (the bright brand orange is only
  /// ~4.4:1 on a dark surface with an 18% orange tint).
  static Color accentTextOnTint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? brandOrangeDeep
      : brandOrangeSoft;
}
