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

  /// Accessible darker orange (F-24): ~5.1:1 against white (and >= 4.5:1 on the
  /// #F4F4F4 / #F3F3F3 / #F2F2F7 light greys the app paints text on), so it can
  /// be the fill behind white normal-size text, or the colour of normal-size
  /// orange text on a light surface. Same hue as [brandOrange].
  static const Color brandOrangeStrong = Color(0xFFBC4B00);

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

  /// Text / icon colour ON a filled bright [brandOrange] surface in the DARK
  /// theme (`ColorScheme.onPrimary`): white on [brandOrange] is only ~2.86:1,
  /// near-black is ~6.1:1. The light theme keeps white on [brandOrangeStrong].
  static const Color onBrandOrange = Color(0xFF1A1A1A);

  /// Muted / secondary grey text on LIGHT surfaces (replaces the old
  /// `0xFF8E8E93`, ~3.3:1 on white): >= 4.5:1 on white, #FFF7F0, the
  /// #F4F4F4 / #F3F3F3 / #F2F2F7 greys and #E0E0E0.
  static const Color mutedText = Color(0xFF636366);

  /// Muted grey text on DARK surfaces (#1E1E1E, #2A211C, #121212): the iOS
  /// system grey, >= 4.5:1 there (but NOT on light surfaces: use [mutedText]).
  static const Color mutedTextOnDark = Color(0xFF8E8E93);

  /// Muted grey for the given theme brightness ([mutedText] on light,
  /// [mutedTextOnDark] on dark).
  static Color mutedTextFor(Brightness brightness) =>
      brightness == Brightness.light ? mutedText : mutedTextOnDark;

  /// Background of "warning" SnackBars (replaces `Colors.orange`, which is
  /// only ~2:1 against any text): [brandOrangeStrong] with
  /// [warningSnackBarTextStyle] (white) is >= 4.5:1. Use both together.
  static const Color warningSnackBarBackground = brandOrangeStrong;

  /// Foreground of [warningSnackBarBackground].
  static const Color onWarningSnackBar = Color(0xFFFFFFFF);

  /// Text style for content painted on [warningSnackBarBackground] (a
  /// SnackBar's default text colour follows the theme's inverse surface, not
  /// its `backgroundColor`; see [WarningSnackBarText]).
  static const TextStyle warningSnackBarTextStyle = TextStyle(
    color: onWarningSnackBar,
  );

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

/// SnackBar text for a SnackBar whose ackgroundColor is
/// [AppColors.warningSnackBarBackground]: white (>= 4.5:1) in both themes.
class WarningSnackBarText extends StatelessWidget {
  const WarningSnackBarText(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) =>
      Text(data, style: AppColors.warningSnackBarTextStyle);
}