part of 'comparison_page.dart';

extension _CarComparisonPageBody on CarComparisonPage {
  Widget _buildComparisonBody(
    BuildContext context,
    CarComparisonStore comparisonStore,
  ) {
    final cars = comparisonStore.comparisonCars;
    if (cars.isEmpty) {
      return _buildComparisonEmptyState(context);
    }
    return _buildComparisonFilledState(context, comparisonStore, cars);
  }
}
