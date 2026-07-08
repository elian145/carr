part of 'comparison_page.dart';

extension _CarComparisonPageBodyFilledTable on CarComparisonPage {
  Widget _buildComparisonFilledTable(
    BuildContext context,
    CarComparisonStore comparisonStore,
    List<Map<String, dynamic>> cars,
  ) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: _buildComparisonRows(context, cars),
    );
  }

  Widget _buildCarSummarySection(
    BuildContext context,
    CarComparisonStore comparisonStore,
    List<Map<String, dynamic>> cars,
  ) {
    if (cars.length == 2) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildComparisonCarCard(
              context,
              comparisonStore,
              cars[0],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildComparisonCarCard(
              context,
              comparisonStore,
              cars[1],
            ),
          ),
        ],
      );
    }

    if (cars.length == 3) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < cars.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _buildComparisonCarCard(
                context,
                comparisonStore,
                cars[i],
              ),
            ),
          ],
        ],
      );
    }

    return SizedBox(
      height: 188,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: cars.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 168,
            child: _buildComparisonCarCard(
              context,
              comparisonStore,
              cars[index],
              width: 168,
            ),
          );
        },
      ),
    );
  }
}
