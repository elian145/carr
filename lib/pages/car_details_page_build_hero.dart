part of 'car_details_page.dart';

mixin _CarDetailsPageBuildHero on _CarDetailsPageContact {
  static const double _sheetTopRadius = 24;

  double _carDetailsTitleHeaderHeight(BuildContext context) {
    final bool hasQuickSell =
        car!['is_quick_sell'] == true || car!['is_quick_sell'] == 'true';
    final bool hasModelOrPrice = _displayModelName(context).isNotEmpty ||
        tryParseCurrencyValue(car!['price']) != null;
    final cityDetail =
        (listingFirstNonEmpty(car!, ['city', 'location']) ?? '').trim();
    final uploadedDetail = listingUploadedAgo(context, car!);
    final bool hasMeta = cityDetail.isNotEmpty || uploadedDetail.isNotEmpty;

    // Top pad + brand + optional model/price + meta + bottom pad.
    // Extra slack avoids PreferredSize clipping/overflow.
    double height = 14 + 26;
    if (hasModelOrPrice) height += 4 + 32;
    if (hasMeta) height += 10 + 24;
    height += 6;
    if (hasQuickSell) height += 44 + 16;
    return height;
  }

  Widget _buildCarDetailsTitleHeader(BuildContext context, bool isLightShell) {
    final bool hasPrice = tryParseCurrencyValue(car!['price']) != null;
    final bg = isLightShell
        ? AppThemes.lightAppBackground
        : AppThemes.darkHomeShellBackground;

    return Material(
      color: bg,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(_sheetTopRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: isLightShell ? Theme.of(context) : AppThemes.darkTheme,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
            if (car!['is_quick_sell'] == true ||
                car!['is_quick_sell'] == 'true')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.deepOrange],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.flash_on,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.quickSell,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: AutoSizeText(
                    _displayBrandName(context),
                    textScaleFactor: 1.0,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isLightShell
                          ? AppThemes.darkHomeShellBackground
                          : Colors.white,
                    ),
                    maxLines: 1,
                    minFontSize: 11,
                    stepGranularity: 0.5,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ],
            ),
            if (_displayModelName(context).isNotEmpty || hasPrice) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _displayModelName(context).isEmpty
                        ? const SizedBox.shrink()
                        : AutoSizeText(
                            _displayModelName(context),
                            textScaleFactor: 1.0,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isLightShell
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                  : Colors.white70,
                            ),
                            maxLines: 1,
                            minFontSize: 14,
                            stepGranularity: 0.5,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  if (hasPrice) ...[
                    const SizedBox(width: 12),
                    Text(
                      formatCurrency(context, car!['price']),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF6B00),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            Builder(
              builder: (context) {
                final cityDetail =
                    (listingFirstNonEmpty(car!, [
                              'city',
                              'location',
                            ]) ??
                            '')
                        .trim();
                final cityLabelStyle = TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isLightShell
                      ? const Color(0xFF757575)
                      : Colors.white70,
                );
                final uploadedDetail = listingUploadedAgo(context, car!);
                if (cityDetail.isEmpty && uploadedDetail.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: cityDetail.isEmpty
                              ? const SizedBox.shrink()
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.location_city,
                                      size: 14,
                                      color: isLightShell
                                          ? const Color(0xFF757575)
                                          : Colors.white70,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        '${AppLocalizations.of(context)!.cityLabel}: '
                                        '${translateListingValue(context, listingFirstNonEmpty(car!, ['city', 'location'])) ?? listingFirstNonEmpty(car!, ['city', 'location'])}',
                                        style: cityLabelStyle,
                                        maxLines: 2,
                                        overflow: TextOverflow.clip,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        if (uploadedDetail.isNotEmpty) ...[
                          if (cityDetail.isNotEmpty) const SizedBox(width: 8),
                          Text(
                            uploadedDetail,
                            style: cityLabelStyle.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildCarDetailsHeroSliver(BuildContext context, bool isLightShell) {
    final titleHeaderHeight = _carDetailsTitleHeaderHeight(context);
    // Keep a similar photo area as before (~296px above the sheet).
    final expandedHeight = 296 + titleHeaderHeight;
    return                 SliverAppBar(
                  pinned: true,
                  stretch: true,
                  foregroundColor: isLightShell ? Colors.white : null,
                  expandedHeight: expandedHeight,
                  bottom: PreferredSize(
                    preferredSize: Size.fromHeight(titleHeaderHeight),
                    child: SizedBox(
                      height: titleHeaderHeight,
                      width: double.infinity,
                      child: _buildCarDetailsTitleHeader(context, isLightShell),
                    ),
                  ),
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
                            bottom: 36,
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
