part of 'home_flow.dart';

mixin _HomePageSliversFeatured on _HomePageSliversSearchBar {
  Widget _buildFeaturedListingsSliver(BuildContext context) {
    if (featuredCars.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
            SizedBox(
              height: AppResponsive.featuredCarouselHeight(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: featuredCars.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = Map<String, dynamic>.from(featuredCars[index]);
                  final normalized =
                      mapListingToGlobalCarCardData(context, item);
                  return SizedBox(
                    width: AppResponsive.featuredCardWidth(context),
                    child: buildGlobalCarCard(
                      context,
                      normalized,
                      carouselResetSeed: _homeCarouselResetSeed,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
