import 'package:flutter/material.dart';

/// Shared colors/spacing for the home More Filters dialog sections.
class MoreFiltersDialogStyle {
  const MoreFiltersDialogStyle({
    required this.onSurface,
    required this.muted,
    required this.anyOrange,
    required this.fieldFill,
    required this.menuFill,
    this.fieldGap = 18,
  });

  final Color onSurface;
  final Color muted;
  final Color anyOrange;
  /// Closed field / chip fill (may be translucent in dark mode).
  final Color fieldFill;
  /// Open dropdown menu surface — must stay opaque for readability.
  final Color menuFill;
  final double fieldGap;
}
