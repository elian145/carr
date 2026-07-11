import 'package:flutter/material.dart';

/// One row in the listing specs summary grid (detail + sell preview).
class ListingSpecItem {
  const ListingSpecItem({
    required this.icon,
    required this.label,
    required this.value,
    this.imageAsset,
  });

  final IconData icon;
  /// Accessibility / tooltip label (not shown in the orange grid cards).
  final String label;
  final String? value;
  /// Custom artwork shown instead of [icon] when set.
  final String? imageAsset;
}
