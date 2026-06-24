part of 'car_details_page.dart';

mixin _CarDetailsPageBuild on _CarDetailsPageContact {
  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final stickyButtons = (!loading && car != null && !_isListingSold && _hasDialableSellerPhone && _showStickyButtons);

    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      body: Stack(
        children: [
          loading
          ? Center(child: CircularProgressIndicator())
          : car == null
          ? Center(child: Text(AppLocalizations.of(context)!.carNotFound))
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
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
                    if (_isListingOwner) ...[
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
                                MaterialPageRoute(
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
                ),
                SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isLightShell
                          ? AppThemes.lightAppBackground
                          : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    child: Theme(
                      data: isLightShell
                          ? Theme.of(context)
                          : AppThemes.darkTheme,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Quick Sell Banner
                          if (car!['is_quick_sell'] == true ||
                              car!['is_quick_sell'] == 'true')
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              margin: EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.orange, Colors.deepOrange],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.flash_on,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    AppLocalizations.of(context)!.quickSell,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Brand full width; price aligns with model line (same row as model)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _displayBrandName(context),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isLightShell
                                            ? AppThemes.darkHomeShellBackground
                                            : Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (car!['price'] != null &&
                                      _displayModelName(context).isEmpty) ...[
                                    SizedBox(width: 12),
                                    Text(
                                      formatCurrency(
                                        context,
                                        car!['price'],
                                      ),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFFF6B00),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (_displayModelName(context).isNotEmpty) ...[
                                SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _displayModelName(context),
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: isLightShell
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant
                                              : Colors.white70,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (car!['price'] != null) ...[
                                      SizedBox(width: 12),
                                      Text(
                                        formatCurrency(
                                          context,
                                          car!['price'],
                                        ),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFFF6B00),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                          // City + listing age under model/price
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
                              final uploadedDetail = listingUploadedAgo(
                                context,
                                car!,
                              );
                              if (cityDetail.isEmpty &&
                                  uploadedDetail.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
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
                                                        ? const Color(
                                                            0xFF757575,
                                                          )
                                                        : Colors.white70,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      '${AppLocalizations.of(context)!.cityLabel}: '
                                                      '${translateListingValue(context, listingFirstNonEmpty(car!, ['city', 'location'])) ?? listingFirstNonEmpty(car!, ['city', 'location'])}',
                                                      style: cityLabelStyle,
                                                      // Allow long cities like "Sulaymaniyah" to show fully.
                                                      maxLines: 2,
                                                      overflow: TextOverflow.clip,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                      if (uploadedDetail.isNotEmpty) ...[
                                        if (cityDetail.isNotEmpty)
                                          const SizedBox(width: 8),
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
                          const SizedBox(height: 16),

                          Divider(
                            height: 1,
                            thickness: 1,
                            color: isLightShell
                                ? const Color(0xFFE0E0E0)
                                : Colors.white24,
                          ),
                          SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context)!.specificationsLabel,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6B00),
                            ),
                          ),
                          SizedBox(height: 20),
                          _buildSpecsGrid(),
                          SizedBox(height: 24),

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
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: ComparisonButton(car: car!),
                              ),
                              if (!_isListingSold) ...[
                              SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Color(0xFFFF6B00),
                                    side: BorderSide(color: Color(0xFFFF6B00)),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size(0, 46),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
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
                          SizedBox(height: 28),
                          if (similarCars.isNotEmpty) ...[
                            Text(
                              AppLocalizations.of(context)!.similarListings,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                            ),
                            SizedBox(height: 12),
                            CarDetailsHorizontalList(
                              items: similarCars,
                              listingColumnsPref: _listingColumnsPref,
                              snapController: _similarSnapController,
                            ),
                            SizedBox(height: 28),
                          ] else if (loadingSimilar) ...[
                            Text(
                              AppLocalizations.of(context)!.similarListings,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            SizedBox(height: 28),
                          ],
                          if (relatedCars.isNotEmpty) ...[
                            Text(
                              AppLocalizations.of(context)!.relatedListings,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                            ),
                            SizedBox(height: 12),
                            CarDetailsHorizontalList(
                              items: relatedCars,
                              listingColumnsPref: _listingColumnsPref,
                              snapController: _relatedSnapController,
                            ),
                          ] else if (loadingRelated) ...[
                            Text(
                              AppLocalizations.of(context)!.relatedListings,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (stickyButtons)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: _buildContactButtonsRow(),
            ),
        ],
      ),
    );
  }

  Widget _buildSpecsGrid() => buildCarListingSpecsGrid(context, car!);
}
