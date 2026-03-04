import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/car_comparison_store.dart';

/// Reusable comparison toggle button for non-legacy UI.
///
/// Accepts a raw `car` map (as used across the codebase).
class ComparisonButton extends StatelessWidget {
  final Map<String, dynamic> car;
  final bool isCompact;

  const ComparisonButton({super.key, required this.car, this.isCompact = false});

  String? _carId() {
    final raw = car['id'] ?? car['public_id'] ?? car['car_id'] ?? car['carId'];
    final s = raw?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CarComparisonStore>();
    final id = _carId();
    final inComparison = id != null && store.isCarInComparison(id);

    void toggle() {
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot compare: missing car id')),
        );
        return;
      }
      if (inComparison) {
        store.removeCarFromComparison(id);
        return;
      }
      if (!store.canAddMore) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comparison limit reached (5 cars)')),
        );
        return;
      }
      store.addCarToComparison(Map<String, dynamic>.from(car)..['id'] = id);
    }

    return IconButton(
      onPressed: toggle,
      tooltip: inComparison ? 'Remove from comparison' : 'Add to comparison',
      icon: Icon(
        inComparison ? Icons.compare_arrows : Icons.compare_arrows_outlined,
        size: isCompact ? 18 : 22,
        color: inComparison ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}

