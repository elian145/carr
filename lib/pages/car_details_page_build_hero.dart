part of 'car_details_page.dart';

mixin _CarDetailsPageBuildHero on _CarDetailsPageContact {
  static const double _sheetTopRadius = 24;

  /// Fixed gap between city / uploaded-ago and the divider (all screens).
  static const double _metaToDividerGap = 10;

  /// Visible photo height: ~35% of screen (clamped into the 32–38% band).
  double _heroPhotoHeight(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    return (screenH * 0.35).clamp(screenH * 0.32, screenH * 0.38);
  }

  Color _carDetailsSheetColor(bool isLightShell) => isLightShell
      ? AppThemes.lightAppBackground
      : AppThemes.darkHomeShellBackground;

  /// Model/price row height at fixed fontSize 22 (model may wrap).
  double _modelPriceRowHeight(BuildContext context) {
    const fontSize = 22.0;
    const lineHeight = 1.15;
    const singleLine = fontSize * lineHeight;

    final modelName = _displayModelName(context);
    final hasPrice = tryParseCurrencyValue(car!['price']) != null;
    if (modelName.isEmpty) return singleLine;

    final textDir = Directionality.of(context);
    var maxWidth = MediaQuery.sizeOf(context).width - 32; // L/R padding
    if (hasPrice) {
      final pricePainter = TextPainter(
        text: TextSpan(
          text: formatCurrency(context, car!['price']),
          style: const TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            height: lineHeight,
          ),
        ),
        textDirection: textDir,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      )..layout();
      maxWidth -= 12 + pricePainter.width;
    }

    final modelPainter = TextPainter(
      text: TextSpan(
        text: modelName,
        style: const TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: lineHeight,
        ),
      ),
      textDirection: textDir,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: maxWidth.clamp(1.0, double.infinity));

    return hasPrice
        ? (modelPainter.height > singleLine ? modelPainter.height : singleLine)
        : modelPainter.height;
  }

  double _carDetailsTitleContentHeight(BuildContext context) {
    final bool hasQuickSell =
        car!['is_quick_sell'] == true || car!['is_quick_sell'] == 'true';
    final bool hasModelOrPrice = _displayModelName(context).isNotEmpty ||
        tryParseCurrencyValue(car!['price']) != null;
    final cityDetail =
        (listingFirstNonEmpty(car!, ['city', 'location']) ?? '').trim();
    final uploadedDetail = listingUploadedAgo(context, car!);
    final bool hasMeta = cityDetail.isNotEmpty || uploadedDetail.isNotEmpty;

    // Sheet content from top padding through Specifications.
    double height = 12 + 22;
    if (hasModelOrPrice) height += 4 + _modelPriceRowHeight(context);
    if (hasMeta) height += 16 + 18;
    height += _metaToDividerGap + 1;
    height += 10 + 26; // gap + Specifications
    if (hasQuickSell) height += 44 + 16;
    return height;
  }

  Widget _buildCarDetailsTitleHeader(BuildContext context, bool isLightShell) {
    final bool hasPrice = tryParseCurrencyValue(car!['price']) != null;
    final bg = _carDetailsSheetColor(isLightShell);

    return Material(
      color: bg,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(_sheetTopRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: isLightShell ? Theme.of(context) : AppThemes.darkTheme,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
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
                      height: 1.15,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _displayModelName(context).isEmpty
                        ? const SizedBox.shrink()
                        : Text(
                            _displayModelName(context),
                            textScaler: const TextScaler.linear(1.0),
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              color: isLightShell
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                  : Colors.white70,
                            ),
                          ),
                  ),
                  if (hasPrice) ...[
                    const SizedBox(width: 12),
                    Text(
                      formatCurrency(context, car!['price']),
                      textScaler: const TextScaler.linear(1.0),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF6B00),
                        height: 1.15,
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
                  height: 1.2,
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
                    const SizedBox(height: 16),
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
                                        textScaler: const TextScaler.linear(1.0),
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
                            textScaler: const TextScaler.linear(1.0),
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
            // Keep this gap in the same column as the meta row so it cannot
            // vary with PreferredSize height slack across platforms.
            const SizedBox(height: _metaToDividerGap),
            Divider(
              height: 1,
              thickness: 1,
              color: isLightShell
                  ? const Color(0xFFE0E0E0)
                  : Colors.white24,
            ),
            // Push Specs to the bottom of the sheet so PreferredSize slack can't
            // open a gap between Specs and the grid below.
            const Spacer(),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.specificationsLabel,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6B00),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildCarDetailsHeroSliver(BuildContext context, bool isLightShell) {
    final titleContentHeight = _carDetailsTitleContentHeight(context);
    final heroPhotoHeight = _heroPhotoHeight(context);
    // Photo band + title sheet. Title lives in flexibleSpace (not `bottom`) so
    // SliverAppBar's collapsing bottomOpacity cannot fade a white sheet over
    // the photo while scrolling.
    final expandedHeight = heroPhotoHeight + titleContentHeight;
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    // Keep the photo tucked under the sheet radius so stretch overscroll still
    // reveals the image through the rounded corners (not the scaffold).
    final sheetOverlap = titleContentHeight > _sheetTopRadius
        ? titleContentHeight - _sheetTopRadius
        : 0.0;
    final heroEntries = _heroImageEntries;
    return                 SliverAppBar(
                  pinned: false,
                  stretch: true,
                  forceMaterialTransparency: true,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  clipBehavior: Clip.none,
                  foregroundColor: isLightShell ? Colors.white : null,
                  expandedHeight: expandedHeight,
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
                  flexibleSpace: Stack(
                    fit: StackFit.expand,
                    children: [
                        // Photo fills down under the sheet radius so stretch
                        // overscroll keeps rounded corners over the image.
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          bottom: sheetOverlap,
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
                                      if (index < heroEntries.length) {
                                        final entry = heroEntries[index];
                                        return ListingHeroImage(
                                          url: entry.url,
                                          detectionSource: entry.meta,
                                        );
                                      }
                                      return _buildHeroVideoSlide(
                                        context,
                                        index - heroEntries.length,
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
                            // Dots sit just above the title sheet.
                            left: 0,
                            right: 0,
                            bottom: titleContentHeight + 12,
                            child: IgnorePointer(
                              ignoring: true,
                              child: Center(
                                child: () {
                                  const int kMaxVisible = 6;
                                  final int total = _heroMediaCount;
                                  final int visible =
                                      total < kMaxVisible ? total : kMaxVisible;
                                  if (visible <= 1) {
                                    return const SizedBox.shrink();
                                  }

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
                          Positioned(
                            top: statusBarHeight,
                            left: 0,
                            right: 0,
                            bottom: titleContentHeight,
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
                        // Title sheet over the photo — same stack as the image so
                        // it never gets SliverAppBar bottomOpacity fade.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: titleContentHeight,
                          child: _buildCarDetailsTitleHeader(
                            context,
                            isLightShell,
                          ),
                        ),
                    ],
                  ),
                );
  }
}
