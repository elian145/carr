part of 'car_details_page.dart';

mixin _CarDetailsPageBuildBody on _CarDetailsPageBuildHero {
  Widget _buildCarDetailsBodySliver(BuildContext context, bool isLightShell) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final feedColumns = ListingLayoutPrefs.effectiveColumnsForWidth(
      _listingColumnsPref == 1 ? 1 : 2,
      screenWidth,
    );
    // Match Home feed horizontal inset so similar cards share Home dimensions.
    final feedHorizontalPadding = feedColumns == 1 ? 4.0 : 8.0;

    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        color: isLightShell
            ? AppThemes.lightAppBackground
            : AppThemes.darkHomeShellBackground,
        padding: const EdgeInsets.only(bottom: 24),
        child: Theme(
          data: isLightShell ? Theme.of(context) : AppThemes.darkTheme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSpecsGrid(),
                    const SizedBox(height: 24),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_isListingSold && _hasDialableSellerPhone) ...[
                          Container(
                            key: _contactButtonsKey,
                            child: _buildContactButtonsRow(),
                          ),
                          SizedBox(height: 6),
                        ],
                        ComparisonButton(car: car!),
                        if (!_isListingSold) ...[
                          SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.brandOrange,
                                side: BorderSide(color: AppColors.brandOrange),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                minimumSize: Size(0, 46),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(17),
                                ),
                              ),
                              onPressed: _openCarzoChat,
                              icon: Icon(Icons.forum_outlined, size: 19),
                              label: Text(
                                AppLocalizations.of(context)!.chatOnCarzo,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                        CarDetailsSellerSection(car: car!),
                      ],
                    ),
                  ],
                ),
              ),
              if (similarCars.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                  child: Text(
                    AppLocalizations.of(context)!.similarListings,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isLightShell
                          ? AppThemes.darkHomeShellBackground
                          : Colors.white,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    feedHorizontalPadding,
                    12,
                    feedHorizontalPadding,
                    28,
                  ),
                  child: CarDetailsHorizontalList(
                    items: similarCars,
                    listingColumnsPref: _listingColumnsPref,
                  ),
                ),
              ] else if (loadingSimilar) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                  child: Text(
                    AppLocalizations.of(context)!.similarListings,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isLightShell
                          ? AppThemes.darkHomeShellBackground
                          : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpecsGrid() => buildCarListingSpecsGrid(context, car!);
}
