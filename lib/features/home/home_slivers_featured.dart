part of 'home_flow.dart';

mixin _HomePageSliversFeatured on _HomePageSliversSearchBar {
  Widget _buildFeaturedListingsSliver(BuildContext context) {
    if (featuredCars.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    const inset = AppResponsive.featuredSectionHorizontalInset;
    const glowPad = 10.0;
    final cardW = AppResponsive.featuredCardWidth(context);
    final cardH = AppResponsive.featuredCarouselHeight(context);
    final normalizedCars = [
      for (final raw in featuredCars)
        mapListingToGlobalCarCardData(
          context,
          Map<String, dynamic>.from(raw),
        ),
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: inset,
                vertical: 4,
              ),
              child: Text(
                _trLegacyText(
                  context,
                  'Featured Listings',
                  ar: 'إعلانات مميزة',
                  ku: 'ڕیکلامە تایبەتەکان',
                ),
                style: GoogleFonts.orbitron(
                  color: const Color(0xFFFF6B00),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 8),
            FeaturedListingsAutoScroll(
              cars: normalizedCars,
              height: cardH,
              cardWidth: cardW,
              horizontalPadding: inset,
              verticalPadding: glowPad,
            ),
          ],
        ),
      ),
    );
  }
}
