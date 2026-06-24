part of 'comparison_page.dart';

extension _CarComparisonPageBodyFilled on CarComparisonPage {
  Widget _buildComparisonFilledState(
    BuildContext context,
    CarComparisonStore comparisonStore,
    List<Map<String, dynamic>> cars,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildComparisonFilledHeader(context, comparisonStore, cars),
        const SizedBox(height: 20),
        _buildComparisonFilledTable(context, comparisonStore, cars),
      ],
    );
  }
}
