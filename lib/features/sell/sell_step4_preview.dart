part of 'sell_flow.dart';

class _PreviewMediaEntry {
  const _PreviewMediaEntry({required this.isVideo, required this.item});
  final bool isVideo;
  final dynamic item;
}

// Preview of how the listing will look after submission (used in SellStep5).
class ListingPreviewWidget extends StatefulWidget {
  final Map<String, dynamic> carData;
  final List<dynamic> imageFilesOrUrls;

  /// When true, renders edge-to-edge like the real listing page (no rounded corners/border).
  final bool fullPage;

  const ListingPreviewWidget({
    super.key,
    required this.carData,
    required this.imageFilesOrUrls,
    this.fullPage = false,
  });

  @override
  State<ListingPreviewWidget> createState() => _ListingPreviewWidgetState();
}

class _ListingPreviewWidgetState extends State<ListingPreviewWidget> {
  final PageController _imagePageController = PageController();
  int _currentMediaIndex = 0;

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
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
      MaterialPageRoute(
        builder: (_) => ListingPreviewMediaGridPage(
          imageFilesOrUrls: images,
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

  static String? _getFirstNonEmpty(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      final String stringValue = value.toString().trim();
      if (stringValue.isNotEmpty) return stringValue;
    }
    return null;
  }

  String _formatPrice(BuildContext context, String raw) {
    try {
      final num? value = num.tryParse(raw.replaceAll(RegExp(r'[^0-9\.-]'), ''));
      if (value == null) return raw;
      final formatter = _decimalFormatterGlobal(context);
      return formatter.format(value);
    } catch (e, st) { logNonFatal(e, st); 
      return raw;
    }
  }

  Widget _buildSpecCard(_SpecItem item) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      constraints: BoxConstraints(minHeight: 84),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(item.icon, size: 16, color: Colors.black87),
              SizedBox(width: 6),
              Flexible(
                child: AutoSizeText(
                  item.label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  textScaleFactor: 1.0,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    height: 1.1,
                  ),
                  minFontSize: 7,
                  stepGranularity: 0.5,
                  overflow: TextOverflow.clip,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.black.withValues(alpha: 0.22),
            ),
          ),
          AutoSizeText(
            item.value!,
            maxLines: 2,
            textAlign: TextAlign.center,
            textScaleFactor: 1.0,
            style: TextStyle(
              fontSize: 15,
              height: 1.15,
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ),
            minFontSize: 10,
            stepGranularity: 0.5,
            overflow: TextOverflow.clip,
          ),
        ],
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String? value,
  }) {
    if (value == null || value.isEmpty) return SizedBox.shrink();
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFF3F3F3)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLight ? const Color(0xFFE0E0E0) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.black),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isLight ? const Color(0xFF3A3A3A) : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecsFromData(Map<String, dynamic> data) {
    final loc = AppLocalizations.of(context)!;
    final String? engineSize = _getFirstNonEmpty(data, [
      'engine_size',
      'engineSize',
      'engine',
    ]);
    final List<_SpecItem> primary = [
      _SpecItem(
        icon: Icons.speed,
        label: loc.mileageLabel,
        value: data['mileage'] != null
            ? '${_localizeDigitsGlobal(context, _formatPrice(context, data['mileage'].toString()))} ${loc.unit_km}'
            : null,
      ),
      _SpecItem(
        icon: Icons.settings_input_component,
        label: loc.detail_cylinders,
        value: () {
          final raw = _getFirstNonEmpty(data, [
            'cylinder_count',
            'cylinders',
            'cylinderCount',
          ]);
          if (raw == null) return null;
          return _localizeDigitsGlobal(context, raw);
        }(),
      ),
      _SpecItem(
        icon: Icons.straighten,
        label: loc.detail_engine,
        value: engineSize != null
            ? '${_localizeDigitsGlobal(context, engineSize.toString())}${loc.unit_liter_suffix}'
            : null,
      ),
      _SpecItem(
        icon: Icons.layers,
        label: loc.trimLabel,
        value:
            _translateValueGlobal(context, _getFirstNonEmpty(data, ['trim'])) ??
            _getFirstNonEmpty(data, ['trim']),
      ),
      _SpecItem(
        icon: Icons.settings,
        label: loc.transmissionLabel,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['transmission']),
        ),
      ),
      _SpecItem(
        icon: Icons.local_gas_station,
        label: loc.detail_fuel,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['fuel_type']),
        ),
      ),
    ];
    final List<Widget> details = [
      _detailRow(
        icon: Icons.layers,
        label: loc.trimLabel,
        value:
            _translateValueGlobal(context, _getFirstNonEmpty(data, ['trim'])) ??
            _getFirstNonEmpty(data, ['trim']),
      ),
      _detailRow(
        icon: Icons.check_circle,
        label: loc.detail_condition,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['condition']),
        ),
      ),
      _detailRow(
        icon: Icons.assignment_turned_in,
        label: loc.titleStatus,
        value: data['title_status'] != null
            ? (data['title_status'].toString().toLowerCase() == 'damaged'
                  ? (data['damaged_parts'] != null
                        ? loc.titleStatusDamagedWithParts(
                            _localizeDigitsGlobal(
                              context,
                              data['damaged_parts'].toString(),
                            ),
                          )
                        : loc.value_title_damaged)
                  : loc.value_title_clean)
            : null,
      ),
      _detailRow(
        icon: Icons.drive_eta,
        label: loc.detail_drive,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, [
            'drive_type',
            'driveType',
            'drivetrain',
            'drive',
          ]),
        ),
      ),
      _detailRow(
        icon: Icons.directions_car_filled,
        label: loc.detail_body,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['body_type', 'bodyType', 'body']),
        ),
      ),
      _detailRow(
        icon: Icons.color_lens,
        label: loc.detail_color,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['color']),
        ),
      ),
      _detailRow(
        icon: Icons.airline_seat_recline_normal,
        label: loc.detail_seating,
        value: _localizeDigitsGlobal(
          context,
          _getFirstNonEmpty(data, ['seating', 'seats', 'seatCount']) ?? '',
        ),
      ),
      _detailRow(
        icon: Icons.phone,
        label: loc.phoneLabel,
        value: _getFirstNonEmpty(data, ['contact_phone']),
      ),
      _detailRow(
        icon: Icons.pin_outlined,
        label: 'VIN',
        value: _getFirstNonEmpty(data, ['vin']),
      ),
    ];
    final primItems = primary
        .where((i) => i.value != null && i.value!.isNotEmpty)
        .toList();
    final primGrid = GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: primItems.length,
      itemBuilder: (context, index) => _buildSpecCard(primItems[index]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [primGrid, SizedBox(height: 12), ...details],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.carData;
    final images = widget.imageFilesOrUrls;
    final dynamic rawVideos = data['videos'];
    final List<dynamic> videos = rawVideos is List ? rawVideos : const [];
    final List<_PreviewMediaEntry> media = [
      ...images.map((e) => _PreviewMediaEntry(isVideo: false, item: e)),
      ...videos.map((e) => _PreviewMediaEntry(isVideo: true, item: e)),
    ];
    final hasMedia = media.isNotEmpty;

    final String title = (data['title']?.toString() ?? '').trim().isNotEmpty
        ? data['title'].toString().trim()
        : '${data['brand'] ?? ''} ${data['model'] ?? ''} ${data['trim'] ?? ''}'
              .trim();
    final String yearStr = data['year'] != null ? data['year'].toString() : '';
    final String titleWithYear = yearStr.isNotEmpty
        ? '$title ($yearStr)'
        : (title.isEmpty ? 'Your listing' : title);

    final bool fullPage = widget.fullPage;
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: fullPage ? BorderRadius.zero : BorderRadius.circular(16),
        border: fullPage ? null : Border.all(color: Colors.grey[700]!),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photo + video carousel — tap: images open gallery, videos open preview/player
          SizedBox(
            height: fullPage ? 300 : 260,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasMedia)
                  GestureDetector(
                    onTap: () => _openCarouselDetail(context, media, images),
                    child: PageView.builder(
                      controller: _imagePageController,
                      onPageChanged: (idx) =>
                          setState(() => _currentMediaIndex = idx),
                      itemCount: media.length,
                      itemBuilder: (context, index) {
                        final slot = media[index];
                        if (slot.isVideo) {
                          return _buildVideoCarouselSlide(slot.item);
                        }
                        final item = slot.item;
                        if (item is XFile) {
                          return Image.file(
                            File(item.path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          );
                        }
                        final url = item.toString().trim();
                        final fullUrl = url.startsWith('http')
                            ? url
                            : _buildFullImageUrl(url);
                        return _listingNetworkImage(
                          fullUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        );
                      },
                    ),
                  )
                else
                  Container(
                    color: Colors.grey[800],
                    child: Icon(
                      Icons.directions_car,
                      size: 64,
                      color: Colors.grey[500],
                    ),
                  ),
                if (hasMedia && media.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(media.length, (i) {
                          final active = i == _currentMediaIndex;
                          return AnimatedContainer(
                            duration: Duration(milliseconds: 200),
                            margin: EdgeInsets.symmetric(horizontal: 4),
                            width: active ? 10 : 6,
                            height: active ? 10 : 6,
                            decoration: BoxDecoration(
                              color: active ? Colors.white : Colors.white70,
                              shape: BoxShape.circle,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Content (title, price, specs)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data['is_quick_sell'] == true ||
                    data['is_quick_sell'] == 'true')
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                        Icon(Icons.flash_on, color: Colors.white, size: 20),
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
                Text(
                  titleWithYear,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 8),
                if (data['price'] != null &&
                    data['price'].toString().trim().isNotEmpty)
                  Text(
                    _formatCurrencyGlobal(context, data['price']),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF6B00),
                    ),
                  ),
                SizedBox(height: 16),
                Divider(height: 1, thickness: 1, color: Colors.white24),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.specificationsLabel,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF6B00),
                  ),
                ),
                SizedBox(height: 12),
                _buildSpecsFromData(data),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _sellReviewListingBrand(BuildContext context, Map<String, dynamic> car) {
  final brand = (car['brand'] ?? '').toString().trim();
  final locBrand = CarNameTranslations.getLocalizedBrand(
    context,
    brand.isEmpty ? null : brand,
  );
  if (locBrand.isNotEmpty) return locBrand;
  return (car['title'] ?? '').toString().trim();
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
  if (displayModel.isEmpty) return year;
  if (year.isEmpty) return displayModel;
  return '$displayModel $year';
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
      MaterialPageRoute(
        builder: (_) => ListingPreviewMediaGridPage(
          imageFilesOrUrls: images,
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
            height: 300,
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
                          if (item is XFile) {
                            return Image.file(
                              File(item.path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey[900],
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                              ),
                            );
                          }
                          final url = item.toString().trim();
                          final fullUrl = url.startsWith('http')
                              ? url
                              : _buildFullImageUrl(url);
                          return _listingNetworkImage(
                            fullUrl,
                            fit: BoxFit.cover,
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              brandStr,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_sellReviewHasPrice(car) && modelStr.isEmpty) ...[
                            const SizedBox(width: 12),
                            Text(
                              _formatCurrencyGlobal(context, car['price']),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFF6B00),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (modelStr.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                modelStr,
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
                            if (_sellReviewHasPrice(car)) ...[
                              const SizedBox(width: 12),
                              Text(
                                _formatCurrencyGlobal(context, car['price']),
                                style: const TextStyle(
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
                  // Match Home listing card: city / uploaded info goes below title + price.
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
                        color: isLightShell
                            ? const Color(0xFF757575)
                            : Colors.white70,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
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
                  const SizedBox(height: 16),
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
