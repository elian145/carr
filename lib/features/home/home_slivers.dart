part of 'home_flow.dart';

mixin _HomePageSlivers on _HomePageSliversFilterCard {
  List<Widget> _buildHomeFeedSlivers(BuildContext context) {
    return [
      if (isLoading)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color(0xFFFF6B00),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  selectedSortBy != null
                      ? homeFeedSortingListingsText(context)
                      : homeFeedLoadingListingsText(context),
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        )
      else if (loadErrorMessage != null && cars.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: HomeFeedErrorState(
            message: formatHomeFeedErrorMessage(
              context,
              loadErrorMessage,
            ),
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
            padding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                PopupMenuButton<String>(
                  tooltip: AppLocalizations.of(context)!.sortBy,
                  icon: Icon(Icons.sort, size: 20),
                  onSelected: (value) {
                    setState(
                      () => selectedSortBy = value == ''
                          ? null
                          : value,
                    );
                    _persistFilters();
                    onSortChanged();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: '',
                      child: Text(
                        AppLocalizations.of(context)!.defaultSort,
                      ),
                    ),
                    ...getLocalizedSortOptions(context)
                        .skip(1)
                        .map(
                          (s) => PopupMenuItem(
                            value: s,
                            child: Text(s),
                          ),
                        ),
                  ],
                ),
                ToggleButtons(
                  isSelected: [
                    listingColumns == 1,
                    listingColumns == 2,
                    listingColumns == 3,
                  ],
                  onPressed: (index) {
                    setState(() {
                      listingColumns = index == 0 ? 1 : (index == 1 ? 2 : 3);
                    });
                    ListingLayoutPrefs.setColumns(listingColumns);
                  },
                  children: const [
                    Icon(Icons.view_agenda),
                    Icon(Icons.grid_view),
                    Icon(Icons.swipe_vertical),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (loadErrorMessage != null && cars.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              margin: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
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
                  Icon(
                    Icons.offline_bolt,
                    color: Colors.orange,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      homeFeedCachedResultsBannerText(context),
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: fetchCars,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size(0, 0),
                    ),
                    child: Text(
                      homeFeedRefreshText(context),
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            listingColumns == 1 ? 4 : 8,
            8,
            listingColumns == 1 ? 4 : 8,
            8 + MediaQuery.of(context).padding.bottom + 92,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: listingColumns == 1 ? 1 : 2,
              // Slightly taller cells than 0.65 so listing cards (image + content) don’t overflow
              // One column: horizontal row — wider vs tall to match strip layout.
              // One column: horizontal card. Larger ratio => shorter cell height
              // so the text column is not left with a tall empty band under the last row.
              childAspectRatio: listingColumns == 1
                  ? 2.78
                  : (Platform.isIOS ? 0.66 : 0.61),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index >= cars.length) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                );
              }
              final car = cars[index];
              if (listingColumns == 3) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      '/tiktok_scroll',
                      arguments: {
                        'cars': cars,
                        'initialIndex': index,
                      },
                    );
                  },
                  child: AbsorbPointer(
                    child: buildGlobalCarCard(
                      context,
                      car,
                      listLayout: false,
                      carouselResetSeed: _homeCarouselResetSeed,
                    ),
                  ),
                );
              }
              return buildGlobalCarCard(
                context,
                car,
                listLayout: listingColumns == 1,
                carouselResetSeed: _homeCarouselResetSeed,
              );
            }, childCount: cars.length + (_hasNext ? 1 : 0)),
          ),
        ),
      ],
    ];
  }
}
