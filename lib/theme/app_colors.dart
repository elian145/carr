import 'package:flutter/material.dart';

/// CarNet brand color tokens (UI-03).
///
/// Prefer these (or aliases like [kFilterAccentColor]) over raw `0xFFFF6B00`.
abstract final class AppColors {
  /// Primary brand orange — CTAs, selected filters, nav accent.
  static const Color brandOrange = Color(0xFFFF6B00);

  /// Lighter companion used in gradients / secondary accents.
  static const Color brandOrangeSoft = Color(0xFFFF8C42);
}
