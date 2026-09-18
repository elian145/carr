import 'package:flutter/material.dart';

/// Locally bundled display fonts (no runtime Google Fonts network fetch).
class AppFonts {
  AppFonts._();

  static const String orbitronFamily = 'Orbitron';
  static const String barlowCondensedFamily = 'BarlowCondensed';

  /// U-04: [orbitronFamily] / [barlowCondensedFamily] are bundled Latin-only
  /// display fonts (Orbitron, Barlow Condensed) with no Arabic/Kurdish
  /// glyphs. Forcing them onto Arabic/Kurdish text leaves glyph selection to
  /// an unpredictable OEM/platform fallback font that varies by device (see
  /// PRODUCTION_AUDIT.md U-04). No Arabic/Kurdish-capable font asset is
  /// bundled with the app yet, so for those locales we deliberately fall
  /// back to the app's normal default text style (no forced `fontFamily`)
  /// instead -- the same, already-working rendering path every other piece
  /// of Arabic/Kurdish text in the app already uses -- rather than the
  /// Latin-only branded font. English keeps the branded font unchanged.
  ///
  /// Use [orbitronForLocale] / [barlowCondensedForLocale] (not [orbitron] /
  /// [barlowCondensed] directly) for any text whose content can be a
  /// translated/localized string. The direct [orbitron] / [barlowCondensed]
  /// helpers remain correct for content that is always Latin/numeric
  /// regardless of locale (e.g. plate codes).
  static bool isLatinBrandFontLocale(Locale locale) =>
      locale.languageCode != 'ar' && locale.languageCode != 'ku';

  static TextStyle _brandStyle({
    required String? fontFamily,
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    TextBaseline? textBaseline,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    return (textStyle ?? const TextStyle()).copyWith(
      fontFamily: fontFamily,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      height: height,
      textBaseline: textBaseline,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }

  /// Drop-in replacement for `GoogleFonts.orbitron`.
  ///
  /// Only use this directly for text that is always Latin/numeric
  /// regardless of locale. For text that can be translated/localized, use
  /// [orbitronForLocale] instead so Arabic/Kurdish don't get the Latin-only
  /// font (see U-04 note on [isLatinBrandFontLocale]).
  static TextStyle orbitron({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    TextBaseline? textBaseline,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    return _brandStyle(
      fontFamily: orbitronFamily,
      textStyle: textStyle,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      height: height,
      textBaseline: textBaseline,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }

  /// Locale-aware variant of [orbitron] for text that can be a
  /// translated/localized string (headings, hints, labels, etc.). Applies
  /// the branded Orbitron font only when [isLatinBrandFontLocale] is true
  /// for [locale]; otherwise returns the same style without forcing a
  /// Latin-only `fontFamily`, letting Arabic/Kurdish render through the
  /// app's normal default text rendering path.
  static TextStyle orbitronForLocale(
    Locale locale, {
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    TextBaseline? textBaseline,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    return _brandStyle(
      fontFamily: isLatinBrandFontLocale(locale) ? orbitronFamily : null,
      textStyle: textStyle,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      height: height,
      textBaseline: textBaseline,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }

  /// Drop-in replacement for `GoogleFonts.barlowCondensed`.
  ///
  /// Only use this directly for text that is always Latin/numeric
  /// regardless of locale. For text that can be translated/localized, use
  /// [barlowCondensedForLocale] instead (see U-04 note on
  /// [isLatinBrandFontLocale]).
  static TextStyle barlowCondensed({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    TextBaseline? textBaseline,
  }) {
    return _brandStyle(
      fontFamily: barlowCondensedFamily,
      textStyle: textStyle,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      height: height,
      textBaseline: textBaseline,
    );
  }

  /// Locale-aware variant of [barlowCondensed] for text that can be a
  /// translated/localized string. See [orbitronForLocale] / U-04 note on
  /// [isLatinBrandFontLocale].
  static TextStyle barlowCondensedForLocale(
    Locale locale, {
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    TextBaseline? textBaseline,
  }) {
    return _brandStyle(
      fontFamily: isLatinBrandFontLocale(locale) ? barlowCondensedFamily : null,
      textStyle: textStyle,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      height: height,
      textBaseline: textBaseline,
    );
  }
}
