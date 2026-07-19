import 'package:flutter/material.dart';

import '../../../app/widgets/global_listing_card.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;
import '../../../shared/prefs/listing_layout_prefs.dart';

/// Similar listings grid on the detail page (scrolls with the page).
class CarDetailsHorizontalList extends StatelessWidget {
  const CarDetailsHorizontalList({
    super.key,
    required this.items,
    required this.listingColumnsPref,
  });

  final List<Map<String, dynamic>> items;
  final int listingColumnsPref;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final listingColumns = ListingLayoutPrefs.effectiveColumnsForWidth(
      listingColumnsPref == 1 ? 1 : 2,
      screenWidth,
    );
    // The details body has 16 px side padding, while the Home feed uses
    // 4 px for list cards and 8 px for grid cards. Let only this section
    // extend into that padding so its cards have the exact Home dimensions.
    final homeFeedWidth = screenWidth - (listingColumns == 1 ? 8.0 : 16.0);

    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: homeFeedWidth,
      maxWidth: homeFeedWidth,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: listingColumns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: ListingLayoutPrefs.gridChildAspectRatioForWidth(
            listingColumns,
            screenWidth,
          ),
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = Map<String, dynamic>.from(items[index]);
          final normalized = mapListingToGlobalCarCardData(context, item);
          return buildGlobalCarCard(
            context,
            normalized,
            listLayout: listingColumns == 1,
          );
        },
      ),
    );
  }
}
