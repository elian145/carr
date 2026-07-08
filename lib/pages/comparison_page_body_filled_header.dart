part of 'comparison_page.dart';

extension _CarComparisonPageBodyFilledHeader on CarComparisonPage {
  Widget _buildComparisonFilledHeader(
    BuildContext context,
    CarComparisonStore comparisonStore,
    List<Map<String, dynamic>> cars,
  ) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            loc.addedToComparison(cars.length, 5),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF6B00),
            side: const BorderSide(color: Color(0xFFFF6B00)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.pushReplacementNamed(context, '/'),
          icon: const Icon(Icons.add, size: 18),
          label: Text(loc.addMoreListings),
        ),
      ],
    );
  }
}
