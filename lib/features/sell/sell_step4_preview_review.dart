part of 'sell_flow.dart';

String _sellReviewListingBrand(BuildContext context, Map<String, dynamic> car) {
  final brand = (car['brand'] ?? '').toString().trim();
  final locBrand = CarNameTranslations.getLocalizedBrand(
    context,
    brand.isEmpty ? null : brand,
  );
  if (locBrand.isNotEmpty) return prettyTitleCase(locBrand);
  return prettyTitleCase(
    brand.isNotEmpty ? brand : (car['title'] ?? '').toString().trim(),
  );
}

String _sellReviewListingModel(BuildContext context, Map<String, dynamic> car) {
  final brand = (car['brand'] ?? '').toString().trim();
  final model = (car['model'] ?? '').toString().trim();
  final localizedModel = CarNameTranslations.getLocalizedModel(
    context,
    brand.isEmpty ? null : brand,
    model.isEmpty ? null : model,
  );
  final displayModel = localizedModel.isNotEmpty ? localizedModel : model;
  final year = (car['year'] ?? '').toString().trim();
  final raw = [
    if (displayModel.isNotEmpty) displayModel,
    if (year.isNotEmpty) year,
  ].join(' ').trim();
  return prettyTitleCase(raw);
}

bool _sellReviewHasPrice(Map<String, dynamic> car) {
  return tryParseCurrencyValue(car['price']) != null;
}

/// Sell step 5 preview: matches [CarDetailsPage] layout and light/dark theming.
class SellReviewCarDetailScrollView extends StatefulWidget {
  const SellReviewCarDetailScrollView({super.key, required this.carData});

  final Map<String, dynamic> carData;

  @override
  State<SellReviewCarDetailScrollView> createState() =>
      _SellReviewCarDetailScrollViewState();
}

class _SellReviewCarDetailScrollViewState
    extends State<SellReviewCarDetailScrollView> {
  static const double _sheetTopRadius = 24;
  static const double _metaToDividerGap = 10;

  final PageController _pageController = PageController();
  int _currentMediaIndex = 0;
  Map<String, dynamic>? _lastNonEmptyCar;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Live wizard data, so edits on earlier steps show up here.
  ///
  /// Submitting clears the parent's draft data while this page is still on
  /// screen; fall back to the data this page was built with so the review never
  /// blanks out into a placeholder car.
  /// Live wizard data, so edits on earlier steps show up here.
  ///
  /// Mid-submit draft clearing must not blank this preview: prefer live parent
  /// data when present, otherwise keep the last non-empty snapshot.
  Map<String, dynamic> _reviewCar(BuildContext context) {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final live = parent?.carData;
    if (live != null && live.isNotEmpty) {
      _lastNonEmptyCar = Map<String, dynamic>.from(live);
      return live;
    }
    if (widget.carData.isNotEmpty) {
      _lastNonEmptyCar = Map<String, dynamic>.from(widget.carData);
      return widget.carData;
    }
    return _lastNonEmptyCar ?? widget.carData;
  }

  List<_PreviewMediaEntry> _buildMediaList(Map<String, dynamic> car) {
    final imgs = car['images'];
    final vids = car['videos'];
    final il = imgs is List
        ? sellImagesWithPrimaryFirst(
            List<dynamic>.from(imgs),
            primaryIndex: sellPrimaryImageIndex(car, length: imgs.length),
          )
        : const <dynamic>[];
    final vl = vids is List ? List<dynamic>.from(vids) : const <dynamic>[];
    return [
      ...il
          .where((e) => ListingImageMedia.source(e).isNotEmpty)
          .map((e) => _PreviewMediaEntry(isVideo: false, item: e)),
      ...vl
          .where((e) => ListingImageMedia.source(e).isNotEmpty)
          .map((e) => _PreviewMediaEntry(isVideo: true, item: e)),
    ];
  }

  /// Same band as [CarDetailsPage] hero photo (~35% of screen, 32–38% clamp).
  double _heroPhotoHeight(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    return (screenH * 0.35).clamp(screenH * 0.32, screenH * 0.38);
  }

  Color _sheetColor(bool isLightShell) => isLightShell
      ? AppThemes.lightAppBackground
      : AppThemes.darkHomeShellBackground;

  double _modelPriceRowHeight(BuildContext context) {
    const fontSize = 22.0;
    const lineHeight = 1.15;
    const singleLine = fontSize * lineHeight;

    final modelName = _sellReviewListingModel(context, _reviewCar(context));
    final hasPrice = _sellReviewHasPrice(_reviewCar(context));
    if (modelName.isEmpty) return singleLine;

    final textDir = Directionality.of(context);
    var maxWidth = MediaQuery.sizeOf(context).width - 32;
    if (hasPrice) {
      final pricePainter = TextPainter(
        text: TextSpan(
          text: formatCurrency(context, _reviewCar(context)['price']),
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

  double _titleContentHeight(BuildContext context) {
    final car = _reviewCar(context);
    final bool hasQuickSell =
        car['is_quick_sell'] == true || car['is_quick_sell'] == 'true';
    final bool hasModelOrPrice =
        _sellReviewListingModel(context, car).isNotEmpty ||
        _sellReviewHasPrice(car);

    String? pickCity(List<String> keys) {
      for (final k in keys) {
        final v = car[k]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final cityDetail = (pickCity(['city', 'location']) ?? '').trim();
    final uploadedDetail = _listingUploadedAgo(context, car);
    final bool hasMeta = cityDetail.isNotEmpty || uploadedDetail.isNotEmpty;

    double height = 12 + 22;
    if (hasModelOrPrice) height += 4 + _modelPriceRowHeight(context);
    if (hasMeta) height += 16 + 18;
    height += _metaToDividerGap + 1;
    // Specs title needs extra descent for Arabic/Kurdish underdots + bottom pad.
    height += 8 + 32 + 6;
    if (hasQuickSell) height += 44 + 16;
    return height;
  }

  void _openCarouselDetail(
    BuildContext context,
    List<_PreviewMediaEntry> media,
    List<dynamic> images,
  ) {
    if (media.isEmpty) return;
    final i = _currentMediaIndex.clamp(0, media.length - 1);
    final videos = media.where((m) => m.isVideo).map((m) => m.item).toList();
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ListingPreviewMediaGridPage(
          imageFilesOrUrls: images.map((item) {
            final local = ListingImageMedia.localFile(item);
            return local ?? ListingImageMedia.source(item);
          }).toList(),
          videoFilesOrUrls: videos,
          initialIndex: i,
        ),
      ),
    );
  }

  Widget _buildVideoCarouselSlide(dynamic item) {
    final String path = ListingImageMedia.source(item);
    final bool isLocalFile =
        path.isNotEmpty &&
        !path.startsWith('http://') &&
        !path.startsWith('https://');
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isLocalFile)
          FutureBuilder<String?>(
            future: generateVideoThumbnail(path),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                );
              }
              return Container(
                color: Colors.grey[850],
                child: Center(
                  child: Icon(Icons.videocam, color: Colors.white70, size: 48),
                ),
              );
            },
          )
        else
          Container(
            color: Colors.grey[850],
            child: Center(
              child: Icon(Icons.videocam, color: Colors.white70, size: 56),
            ),
          ),
        Center(
          child: Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 40),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaSlide(_PreviewMediaEntry slot) {
    if (slot.isVideo) return _buildVideoCarouselSlide(slot.item);
    final item = slot.item;
    return _listingNetworkImage(
      ListingImageMedia.source(item),
      fit: BoxFit.cover,
      alignment: ListingImageMedia.coverAlignment(item),
      width: double.infinity,
    );
  }

  Widget _buildCarouselDots(int total) {
    const int kMaxVisible = 6;
    final int visible = total < kMaxVisible ? total : kMaxVisible;
    if (visible <= 1) return const SizedBox.shrink();

    int computeDotStart(int index) {
      if (total <= visible) return 0;
      final int maxStart = (total - visible).clamp(0, total);
      return (index - (visible - 1)).clamp(0, maxStart);
    }

    final int start = computeDotStart(_currentMediaIndex);
    return Row(
      key: ValueKey<int>(start),
      mainAxisSize: MainAxisSize.min,
      children: List.generate(visible, (j) {
        final i = start + j;
        final active = i == _currentMediaIndex;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 10 : 6,
          height: active ? 10 : 6,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white70,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }

  Widget _buildTitleHeader(BuildContext context, bool isLightShell) {
    final car = _reviewCar(context);
    final brandStr = _sellReviewListingBrand(context, car);
    final modelStr = _sellReviewListingModel(context, car);
    final hasPrice = _sellReviewHasPrice(car);
    final bg = _sheetColor(isLightShell);

    return Material(
      color: bg,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(_sheetTopRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: isLightShell ? Theme.of(context) : AppThemes.darkTheme,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              if (car['is_quick_sell'] == true || car['is_quick_sell'] == 'true')
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
                      const Icon(Icons.flash_on, color: Colors.white, size: 20),
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
                      brandStr,
                      textScaleFactor: 1.0,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.15,
                        color: isLightShell
                            ? const Color(0xFF858585)
                            : Colors.white60,
                      ),
                      maxLines: 1,
                      minFontSize: 11,
                      stepGranularity: 0.5,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ],
              ),
              if (modelStr.isNotEmpty || hasPrice) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: modelStr.isEmpty
                          ? const SizedBox.shrink()
                          : Text(
                              modelStr,
                              textScaler: const TextScaler.linear(1.0),
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                                color: isLightShell
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant
                                    : Colors.white70,
                              ),
                            ),
                    ),
                    if (hasPrice) ...[
                      const SizedBox(width: 12),
                      Text(
                        formatCurrency(context, car['price']),
                        textScaler: const TextScaler.linear(1.0),
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandOrange,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              Builder(
                builder: (context) {
                  String? pickCity(List<String> keys) {
                    for (final k in keys) {
                      final v = car[k]?.toString().trim();
                      if (v != null && v.isNotEmpty) return v;
                    }
                    return null;
                  }

                  final cityDetail = (pickCity(['city', 'location']) ?? '')
                      .trim();
                  final uploadedDetail = _listingUploadedAgo(context, car);
                  if (cityDetail.isEmpty && uploadedDetail.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final cityLabelStyle = TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: isLightShell
                        ? const Color(0xFF757575)
                        : Colors.white70,
                  );
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
                                          '${AppLocalizations.of(context)!.cityLabel}: ${_translateValueGlobal(context, pickCity(['city', 'location'])) ?? pickCity(['city', 'location'])}',
                                          textScaler: const TextScaler.linear(
                                            1.0,
                                          ),
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
              const SizedBox(height: _metaToDividerGap),
              Divider(
                height: 1,
                thickness: 1,
                color: isLightShell
                    ? const Color(0xFFE0E0E0)
                    : Colors.white24,
              ),
              const Spacer(),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.specificationsLabel,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                  leadingDistribution: TextLeadingDistribution.even,
                  color: AppColors.brandOrange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final car = _reviewCar(context);
    final media = _buildMediaList(car);
    final rawImages = car['images'] is List ? (car['images'] as List) : [];
    final titleContentHeight = _titleContentHeight(context);
    final heroPhotoHeight = _heroPhotoHeight(context);
    // Match [CarDetailsPage]: collapsing SliverAppBar so the white sheet
    // scrolls up over the photo (fixed SliverToBoxAdapter cannot collapse).
    final expandedHeight = heroPhotoHeight + titleContentHeight;
    final sheetOverlap = titleContentHeight > _sheetTopRadius
        ? titleContentHeight - _sheetTopRadius
        : 0.0;
    final sheetBg = _sheetColor(isLightShell);

    return CustomScrollView(
      clipBehavior: Clip.none,
      slivers: [
        // Same collapse primitive as car details hero — no toolbar chrome
        // inside the sell wizard.
        // Title lives in flexibleSpace (not `bottom`) so SliverAppBar's
        // collapsing bottomOpacity cannot fade the white sheet over the photo.
        SliverAppBar(
          pinned: false,
          stretch: true,
          forceMaterialTransparency: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          clipBehavior: Clip.none,
          automaticallyImplyLeading: false,
          toolbarHeight: 0,
          expandedHeight: expandedHeight,
          flexibleSpace: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: sheetOverlap,
                child: media.isEmpty
                    ? Container(
                        color: Colors.grey[900],
                        child: Icon(
                          Icons.directions_car,
                          size: 60,
                          color: Colors.grey[400],
                        ),
                      )
                    : GestureDetector(
                        onTap: () =>
                            _openCarouselDetail(context, media, rawImages),
                        child: PageView.builder(
                          controller: _pageController,
                          onPageChanged: (idx) =>
                              setState(() => _currentMediaIndex = idx),
                          itemCount: media.length,
                          itemBuilder: (context, index) =>
                              _buildMediaSlide(media[index]),
                        ),
                      ),
              ),
              if (media.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: titleContentHeight + 12,
                  child: IgnorePointer(
                    ignoring: true,
                    child: Center(child: _buildCarouselDots(media.length)),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: titleContentHeight,
                child: _buildTitleHeader(context, isLightShell),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            color: sheetBg,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Theme(
              data: isLightShell ? Theme.of(context) : AppThemes.darkTheme,
              child: buildCarListingSpecsGrid(context, car),
            ),
          ),
        ),
      ],
    );
  }
}

// Step 5: Review & Submit
