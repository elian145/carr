part of 'comparison_page.dart';

extension _CarComparisonPageBodyFilled on CarComparisonPage {
  Widget _buildComparisonFilledState(
    BuildContext context,
    CarComparisonStore comparisonStore,
    List<Map<String, dynamic>> cars,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          _buildComparisonFilledHeader(context, comparisonStore, cars),
          const SizedBox(height: 16),
          _buildCarSummarySection(context, comparisonStore, cars),
          const SizedBox(height: 20),
          Expanded(
            child: _buildComparisonFilledTable(context, comparisonStore, cars),
          ),
        ],
      ),
    );
  }
}
