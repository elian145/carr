import 'package:flutter/material.dart';

import '../../../app/widgets/global_listing_card.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;
import '../../../shared/ui/responsive.dart';

/// Similar / related listings carousel on the detail page.
class CarDetailsHorizontalList extends StatelessWidget {
  const CarDetailsHorizontalList({
    super.key,
    required this.items,
    required this.listingColumnsPref,
    required this.snapController,
  });

  final List<Map<String, dynamic>> items;
  final int listingColumnsPref;
  final PageController snapController;

  @override
  Widget build(BuildContext context) {
    const verticalChrome = 12.0;
    const cardViewportPadding = EdgeInsets.fromLTRB(0, 2, 0, 10);

    if (listingColumnsPref == 1) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final double viewportW = constraints.maxWidth;
          final double itemW = (viewportW.isFinite && viewportW > 0)
              ? viewportW
              : MediaQuery.of(context).size.width;
          final double h = (itemW.isFinite && itemW > 0) ? (itemW / 2.78) : 140;

          return SizedBox(
            height: h + verticalChrome,
            child: PageView.builder(
              controller: snapController,
              physics: const PageScrollPhysics(),
              pageSnapping: true,
              clipBehavior: Clip.none,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = Map<String, dynamic>.from(items[index]);
                final normalized = mapListingToGlobalCarCardData(context, item);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                  ).add(cardViewportPadding),
                  child: SizedBox(
                    width: itemW,
                    height: h,
                    child: buildGlobalCarCard(
                      context,
                      normalized,
                      listLayout: true,
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    }

    final cardW = AppResponsive.homeGridListingCardWidth(context);
    final cardH = AppResponsive.homeGridListingCardHeight(context);

    return SizedBox(
      height: cardH + verticalChrome,
      child: ListView.separated(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
        ).add(cardViewportPadding),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = Map<String, dynamic>.from(items[index]);
          final normalized = mapListingToGlobalCarCardData(context, item);
          return SizedBox(
            width: cardW,
            height: cardH,
            child: buildGlobalCarCard(context, normalized),
          );
        },
      ),
    );
  }
}
