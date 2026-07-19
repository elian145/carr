import 'package:flutter/material.dart';

import '../../../app/widgets/global_listing_card.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;
import '../../../shared/prefs/listing_layout_prefs.dart';

/// Similar listings grid on the detail page (scrolls with the page).
///
/// Parent should use the same horizontal padding as the Home feed
/// (8 px) so card widths match without overflowing layout constraints.
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

    return GridView.builder(
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
    );
  }
}
