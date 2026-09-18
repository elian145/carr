import 'package:flutter/material.dart';

/// Locally bundled display fonts (no runtime Google Fonts network fetch).
class AppFonts {
  AppFonts._();

  static const String orbitronFamily = 'Orbitron';
  static const String barlowCondensedFamily = 'BarlowCondensed';

  /// Bundled Arabic-script display font (Noto Sans Arabic, variable `wght`
  /// 100-900) used for `ar`/`ku` text instead of the Latin-only branded
  /// fonts. Covers standard Arabic glyphs plus the extended Sorani Kurdish
  /// letters this app's `ku` content uses (e.g. `ڕ ڵ ھ ێ ۆ`). See
  /// `assets/fonts/README.md` for source/license (OFL, google/fonts).
  static const String notoSansArabicFamily = 'NotoSansArabic';

  /// U-04: [orbitronFamily] / [barlowCondensedFamily] are bundled Latin-only
  /// display fonts (Orbitron, Barlow Condensed) with no Arabic/Kurdish
  /// glyphs. Forcing them onto Arabic/Kurdish text leaves glyph selection to
  /// an unpredictable OEM/platform fallback font that varies by device (see
  /// PRODUCTION_AUDIT.md U-04). [notoSansArabicFamily] is now bundled with
  /// the app specifically to give `ar`/`ku` a deterministic, glyph-complete
  /// font instead of relying on OEM/platform fallback. English keeps the
  /// branded font unchanged.
  ///
  /// Use [orbitronForLocale] / [barlowCondensedForLocale] (not [orbitron] /
  /// [barlowCondensed] directly) for any text whose content can be a
  /// translated/localized string. The direct [orbitron] / [barlowCondensed]
  /// helpers remain correct for content that is always Latin/numeric
  /// regardless of locale (e.g. plate codes).
  static bool isLatinBrandFontLocale(Locale locale) =>
      locale.languageCode != 'ar' && locale.languageCode != 'ku';

  /// Returns the deterministic bundled font family for [locale]: the
  /// branded Latin font is never appropriate for `ar`/`ku` (see
  /// [isLatinBrandFontLocale]), so those locales resolve to
  /// [notoSansArabicFamily] instead of an unpredictable OEM/platform
  /// fallback. Centralizing this here means callers never need their own
  /// `languageCode == 'ar' || ...` branching.
  static String fontFamilyForLocale(
    Locale locale, {
    required String latinFamily,
  }) =>
      isLatinBrandFontLocale(locale) ? latinFamily : notoSansArabicFamily;

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
  /// for [locale]; otherwise deterministically resolves to the bundled
  /// [notoSansArabicFamily] font for Arabic/Kurdish (see
  /// [fontFamilyForLocale]) instead of an unpredictable OEM/platform
  /// fallback.
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
      fontFamily: fontFamilyForLocale(locale, latinFamily: orbitronFamily),
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
  /// [isLatinBrandFontLocale] / [fontFamilyForLocale].
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
      fontFamily:
          fontFamilyForLocale(locale, latinFamily: barlowCondensedFamily),
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
