part of 'car_details_page.dart';

mixin _CarDetailsPageBuildHero on _CarDetailsPageContact {
  Widget _buildCarDetailsHeroSliver(BuildContext context, bool isLightShell) {
    return                 SliverAppBar(
                  pinned: true,
                  stretch: true,
                  foregroundColor: isLightShell ? Colors.white : null,
                  expandedHeight: 300,
                  leading: Semantics(
                    button: true,
                    label: AppLocalizations.of(context)!.backAction,
                    child: IconButton(
                      icon: Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  actions: [
                    if (_canManageOwnListing) ...[
                      Semantics(
                        button: true,
                        label: _isListingSold
                            ? trLegacyText(
                                context,
                                'Mark as available',
                                ar: 'متاح مجدداً',
                                ku: 'بەردەست بکەرەوە',
                              )
                            : trLegacyText(
                                context,
                                'Mark as sold',
                                ar: 'تحديد كمباع',
                                ku: 'وەک فرۆشراو',
                              ),
                        child: IconButton(
                          tooltip: _isListingSold
                              ? trLegacyText(
                                  context,
                                  'Mark as available',
                                  ar: 'متاح مجدداً',
                                  ku: 'بەردەست بکەرەوە',
                                )
                              : trLegacyText(
                                  context,
                                  'Mark as sold',
                                  ar: 'تحديد كمباع',
                                  ku: 'وەک فرۆشراو',
                                ),
                          onPressed: _toggleListingSoldStatus,
                          icon: Icon(
                            _isListingSold
                                ? Icons.undo_outlined
                                : Icons.sell_outlined,
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: AppLocalizations.of(context)!.editAction,
                        child: IconButton(
                          tooltip: AppLocalizations.of(context)!.editAction,
                          onPressed: _editOwnListing,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: AppLocalizations.of(context)!.deleteAction,
                        child: IconButton(
                          tooltip: AppLocalizations.of(context)!.deleteAction,
                          onPressed: _deleteOwnListing,
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    Semantics(
                      button: true,
                      label: AppLocalizations.of(context)!.shareAction,
                      child: IconButton(
                        tooltip: AppLocalizations.of(context)!.shareAction,
                        onPressed: _shareCar,
                        icon: const Icon(Icons.share_outlined),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: AppLocalizations.of(context)!.favoriteAction,
                      child: IconButton(
                        tooltip: AppLocalizations.of(context)!.favoriteAction,
                        onPressed: _toggleFavoriteOnServer,
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                        ),
                      ),
                    ),
                    if (!_isListingOwner &&
                        ApiService.accessToken != null &&
                        ApiService.accessToken!.isNotEmpty)
                      PopupMenuButton<String>(
                        onSelected: _onCarDetailMenuSelected,
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'report_listing',
                            child: Text(
                              trLegacyText(
                                ctx,
                                'Report listing',
                                ar: 'الإبلاغ عن الإعلان',
                                ku: 'ڕاپۆرتکردنی ڕیکلام',
                              ),
                            ),
                          ),
                          if ((sellerMapFromListing(car)?['id'] ??
                                  sellerMapFromListing(car)?['user_id'] ??
                                  '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            PopupMenuItem(
                              value: 'report_user',
                              child: Text(
                                trLegacyText(
                                  ctx,
                                  'Report seller',
                                  ar: 'الإبلاغ عن البائع',
                                  ku: 'ڕاپۆرتکردنی فرۆشیار',
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.zero,
                          child: GestureDetector(
                            onTap: () {
                              if (_heroMediaCount == 0) return;
                              final idx = _currentImageIndex.clamp(
                                0,
                                _heroMediaCount - 1,
                              );
                              Navigator.of(context).push(
                                AppPageRoute(
                                  builder: (_) => ListingImageGalleryPage(
                                    imageUrls: _imageUrls,
                                    videoUrls: _videoUrls,
                                    initialIndex: idx,
                                  ),
                                ),
                              );
                            },
                            child: (_heroMediaCount > 0)
                                ? PageView.builder(
                                    controller: _imagePageController,
                                    onPageChanged: (idx) => setState(
                                      () => _currentImageIndex = idx,
                                    ),
                                    itemCount: _heroMediaCount,
                                    itemBuilder: (context, index) {
                                      if (index < _imageUrls.length) {
                                        final url = _imageUrls[index];
                                        return listingNetworkImage(
                                          url,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                        );
                                      }
                                      return _buildHeroVideoSlide(
                                        context,
                                        index - _imageUrls.length,
                                      );
                                    },
                                  )
                                : Container(
                                    color: Colors.grey[900],
                                    width: double.infinity,
                                    child: Icon(
                                      Icons.directions_car,
                                      size: 60,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                          ),
                        ),
                        if (_heroMediaCount > 1)
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: true,
                              child: Center(
                                child: () {
                                  const int kMaxVisible = 6;
                                  final int total = _heroMediaCount;
                                  final int visible =
                                      total < kMaxVisible ? total : kMaxVisible;
                                  if (visible <= 1) return const SizedBox.shrink();

                                  int computeDotStart(int index) {
                                    if (total <= visible) return 0;
                                    final int maxStart =
                                        (total - visible).clamp(0, total);
                                    return (index - (visible - 1))
                                        .clamp(0, maxStart);
                                  }

                                  final int start =
                                      computeDotStart(_currentImageIndex);

                                  Widget buildDotRow(int startIndex) {
                                    return Row(
                                      key: ValueKey<int>(startIndex),
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(visible, (j) {
                                        final i = startIndex + j;
                                        final active = i == _currentImageIndex;
                                        return Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                          ),
                                          width: active ? 10 : 6,
                                          height: active ? 10 : 6,
                                          decoration: BoxDecoration(
                                            color: active
                                                ? Colors.white
                                                : Colors.white70,
                                            shape: BoxShape.circle,
                                          ),
                                        );
                                      }),
                                    );
                                  }

                                  return buildDotRow(start);
                                }(),
                              ),
                            ),
                          ),
                        if (_isListingSold)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xCCD32F2F),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white54,
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    listingSoldLabel(context),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 26,
                                      letterSpacing: 2.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
  }
}
