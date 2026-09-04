import 'package:flutter/material.dart';

/// Locally bundled display fonts (no runtime Google Fonts network fetch).
class AppFonts {
  AppFonts._();

  static const String orbitronFamily = 'Orbitron';
  static const String barlowCondensedFamily = 'BarlowCondensed';

  /// Drop-in replacement for `GoogleFonts.orbitron`.
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
    return (textStyle ?? const TextStyle()).copyWith(
      fontFamily: orbitronFamily,
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

  /// Drop-in replacement for `GoogleFonts.barlowCondensed`.
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
    return (textStyle ?? const TextStyle()).copyWith(
      fontFamily: barlowCondensedFamily,
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
