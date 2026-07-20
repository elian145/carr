part of 'home_flow.dart';

mixin _HomePageSlivers on _HomePageSliversFeatured {
  List<Widget> _buildHomeFeedSlivers(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final feedColumns = ListingLayoutPrefs.effectiveColumnsForWidth(
      listingColumns == 1 ? 1 : 2,
      screenWidth,
    );
    return [
      if (isLoading)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
                ),
                SizedBox(height: 16),
                Text(
                  selectedSortBy != null
                      ? homeFeedSortingListingsText(context)
                      : homeFeedLoadingListingsText(context),
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
        )
      else if (loadErrorMessage != null && cars.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: HomeFeedErrorState(
            message: formatHomeFeedErrorMessage(context, loadErrorMessage),
            onRetry: () {
              _fetchRetryCount = 0;
              fetchCars(bypassCache: true);
            },
            onClearFilters: () => onFilterChanged(),
          ),
        )
      else if (cars.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: HomeEmptyListMessage(
            selectedSortBy: selectedSortBy,
            onAutoFetch: () {
              if (!_autoFetchedForEmptyWithSort &&
                  selectedSortBy != null &&
                  selectedSortBy!.isNotEmpty) {
                _autoFetchedForEmptyWithSort = true;
                onFilterChanged();
              }
            },
          ),
        )
      else ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ListingSortButton(
                  tooltip: AppLocalizations.of(context)!.sortBy,
                  active:
                      selectedSortBy != null && selectedSortBy!.isNotEmpty,
                  onSelected: (value) {
                    setState(() => selectedSortBy = value == '' ? null : value);
                    _persistFilters();
                    onSortChanged();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: '',
                      child: Text(AppLocalizations.of(context)!.defaultSort),
                    ),
                    ...getLocalizedSortOptions(context)
                        .skip(1)
                        .map((s) => PopupMenuItem(value: s, child: Text(s))),
                  ],
                ),
                ListingLayoutToggle(
                  columns: listingColumns,
                  onChanged: (cols) {
                    setState(() => listingColumns = cols);
                    ListingLayoutPrefs.setColumns(cols);
                  },
                ),
              ],
            ),
          ),
        ),
        if (loadErrorMessage != null && cars.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.offline_bolt, color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      homeFeedCachedResultsBannerText(context),
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: fetchCars,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size(0, 0),
                    ),
                    child: Text(
                      homeFeedRefreshText(context),
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (servingCachedFeed && cars.isNotEmpty)
          SliverToBoxAdapter(
            child: Semantics(
              liveRegion: true,
              label: homeFeedOfflineBannerText(context),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ConnectivityService.instance.isOnline.value
                            ? homeFeedCachedResultsBannerText(context)
                            : homeFeedOfflineBannerText(context),
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => fetchCars(bypassCache: true),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size(0, 0),
                      ),
                      child: Text(
                        homeFeedRefreshText(context),
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Builder(
          builder: (context) {
            final feedCars = mixFeaturedIntoListingFeed(
              feed: cars,
              featured: featuredCars,
            );
            return SliverPadding(
              padding: EdgeInsets.fromLTRB(
                feedColumns == 1 ? 4 : 8,
                8,
                feedColumns == 1 ? 4 : 8,
                8 + MediaQuery.of(context).padding.bottom + 92,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: feedColumns,
                  // Slightly taller cells than 0.65 so listing cards (image + content) don’t overflow
                  // One column: horizontal row — wider vs tall to match strip layout.
                  // One column: horizontal card. Larger ratio => shorter cell height
                  // so the text column is not left with a tall empty band under the last row.
                  childAspectRatio:
                      ListingLayoutPrefs.gridChildAspectRatioForWidth(
                    feedColumns,
                    screenWidth,
                  ),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index >= feedCars.length) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final car = feedCars[index];
                  return buildGlobalCarCard(
                    context,
                    car,
                    listLayout: feedColumns == 1,
                    carouselResetSeed: _homeCarouselResetSeed,
                  );
                }, childCount: feedCars.length + (_hasNext ? 1 : 0)),
              ),
            );
          },
        ),
      ],
    ];
  }
}
