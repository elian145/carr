import 'package:flutter/material.dart';

/// Shared colors/spacing for the home More Filters dialog sections.
class MoreFiltersDialogStyle {
  const MoreFiltersDialogStyle({
    required this.onSurface,
    required this.muted,
    required this.anyOrange,
    required this.fieldFill,
    this.fieldGap = 18,
  });

  final Color onSurface;
  final Color muted;
  final Color anyOrange;
  final Color fieldFill;
  final double fieldGap;
}
