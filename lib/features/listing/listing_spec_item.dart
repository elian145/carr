import 'package:flutter/material.dart';

/// One row in the listing specs summary grid (detail + sell preview).
class ListingSpecItem {
  const ListingSpecItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String? value;
}
