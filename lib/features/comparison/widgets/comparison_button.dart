import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/car_comparison_store.dart';
import '../../../shared/i18n/comparison_strings.dart';

/// Note: This widget depends on global i18n helper functions that currently live in `lib/main.dart`.
/// As the refactor progresses, those helpers should move into `lib/shared/i18n/...` and be imported here.
class ComparisonButton extends StatelessWidget {
  final Map<String, dynamic> car;
  final bool isCompact;

  const ComparisonButton({
    super.key,
    required this.car,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<CarComparisonStore>(
      builder: (context, comparisonStore, child) {
        final dynamic rawId =
            car['id'] ?? car['car_id'] ?? car['carId'] ?? car['uuid'];
        final int carId = rawId is int
            ? rawId
            : (rawId is String ? (int.tryParse(rawId) ?? rawId.hashCode) : -1);
        final isInComparison = comparisonStore.isCarInComparison(carId);
        final canAddMore = comparisonStore.canAddMore;

        return Container(
          decoration: BoxDecoration(
            color: isInComparison ? Colors.green : Colors.orange,
            borderRadius: BorderRadius.circular(isCompact ? 16 : 20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(isCompact ? 16 : 20),
              onTap: () {
                if (isInComparison) {
                  comparisonStore.removeCarFromComparison(carId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(removedFromComparisonText(context)),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 1),
                    ),
                  );
                } else if (canAddMore && carId != -1) {
                  final normalized = Map<String, dynamic>.from(car);
                  normalized['id'] = carId;
                  comparisonStore.addCarToComparison(normalized);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        addedToComparisonText(
                          context,
                          comparisonStore.comparisonCount,
                        ),
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                  Navigator.pushNamed(context, '/comparison');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(comparisonMaxLimitText(context)),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 8 : 12,
                  vertical: isCompact ? 6 : 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isInComparison ? Icons.check : Icons.compare_arrows,
                      color: Colors.white,
                      size: isCompact ? 16 : 18,
                    ),
                    if (!isCompact) ...[
                      const SizedBox(width: 4),
                      Text(
                        isInComparison
                            ? addedLabel(context)
                            : compareLabel(context),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
