import 'package:flutter/material.dart';

/// CarNet brand color tokens (UI-03).
///
/// Prefer these (or aliases like [kFilterAccentColor]) over raw `0xFFFF6B00`.
abstract final class AppColors {
  /// Primary brand orange — CTAs, selected filters, nav accent.
  ///
  /// NOT for normal-size text on white or as a fill behind white text:
  /// white on this orange is ~2.86:1 (WCAG AA needs 4.5:1 for normal text).
  /// Use [brandOrangeStrong] for those (F-24). Icons, borders and large
  /// decorative accents may keep using this exact brand colour.
  static const Color brandOrange = Color(0xFFFF6B00);

  /// Lighter companion used in gradients / secondary accents.
  static const Color brandOrangeSoft = Color(0xFFFF8C42);

  /// Accessible darker orange (F-24): ~4.8:1 against white, so it can be the
  /// fill behind white normal-size text, or the colour of normal-size orange
  /// text on a light surface. Same hue as [brandOrange].
  static const Color brandOrangeStrong = Color(0xFFC24E00);

  /// Orange for normal-size TEXT that must stay readable on the current
  /// surface: [brandOrangeStrong] on light backgrounds (4.5:1+ on white),
  /// the bright brand orange on dark backgrounds (7:1+ on near-black, where
  /// the darker shade would drop to ~3.6:1).
  static Color accentText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? brandOrangeStrong
      : brandOrange;
}
