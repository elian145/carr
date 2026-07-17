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
  final p = car['price'];
  if (p == null) return false;
  return p.toString().trim().isNotEmpty;
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
  final PageController _pageController = PageController();
  int _currentMediaIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<_PreviewMediaEntry> _buildMediaList() {
    final imgs = widget.carData['images'];
    final vids = widget.carData['videos'];
    final il = imgs is List
        ? SellDraftMediaPersistence.resolveDynamicMediaList(
            List<dynamic>.from(imgs),
          )
        : const <dynamic>[];
    final vl = vids is List
        ? SellDraftMediaPersistence.resolveDynamicMediaList(
            List<dynamic>.from(vids),
          )
        : const <dynamic>[];
    return [
      ...il.map((e) => _PreviewMediaEntry(isVideo: false, item: e)),
      ...vl.map((e) => _PreviewMediaEntry(isVideo: true, item: e)),
    ];
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
    final String path = item is XFile ? item.path : item.toString().trim();
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

  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final car = widget.carData;
    final media = _buildMediaList();
    final brandStr = _sellReviewListingBrand(context, car);
    final modelStr = _sellReviewListingModel(context, car);
    final rawImages = car['images'] is List ? (car['images'] as List) : [];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: AppResponsive.previewHeroHeight(context),
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (media.isEmpty)
                    Container(
                      color: Colors.grey[900],
                      child: Icon(
                        Icons.directions_car,
                        size: 60,
                        color: Colors.grey[400],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () =>
                          _openCarouselDetail(context, media, rawImages),
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (idx) =>
                            setState(() => _currentMediaIndex = idx),
                        itemCount: media.length,
                        itemBuilder: (context, index) {
                          final slot = media[index];
                          if (slot.isVideo) {
                            return _buildVideoCarouselSlide(slot.item);
                          }
                          final item = slot.item;
                          final local = ListingImageMedia.localFile(item);
                          final alignment = ListingImageMedia.coverAlignment(
                            item,
                          );
                          if (local != null) {
                            return Image.file(
                              File(local.path),
                              fit: BoxFit.cover,
                              alignment: alignment,
                              width: double.infinity,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: Colors.grey[900],
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      size: 48,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                            );
                          }
                          final url = ListingImageMedia.source(item);
                          final fullUrl = url.startsWith('http')
                              ? url
                              : _buildFullImageUrl(url);
                          return _listingNetworkImage(
                            fullUrl,
                            fit: BoxFit.cover,
                            alignment: alignment,
                            width: double.infinity,
                          );
                        },
                      ),
                    ),
                  if (media.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: true,
                        child: Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(media.length, (i) {
                                final active = i == _currentMediaIndex;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
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
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Theme(
              data: isLightShell ? Theme.of(context) : AppThemes.darkTheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (car['is_quick_sell'] == true ||
                      car['is_quick_sell'] == 'true')
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
                          brandStr,
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
                  if (modelStr.isNotEmpty || _sellReviewHasPrice(car)) ...[
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
                        if (_sellReviewHasPrice(car)) ...[
                          const SizedBox(width: 12),
                          Text(
                            _formatCurrencyGlobal(context, car['price']),
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
                  // Match listing details: city / uploaded info below title + price.
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
                                              textScaler:
                                                  const TextScaler.linear(1.0),
                                              style: cityLabelStyle,
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
                  const SizedBox(height: 10),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isLightShell
                        ? const Color(0xFFE0E0E0)
                        : Colors.white24,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.specificationsLabel,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6B00),
                    ),
                  ),
                  const SizedBox(height: 20),
                  buildCarListingSpecsGrid(context, car),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Step 5: Review & Submit
