part of 'tiktok_scroll_page.dart';

class _TikTokListingCard extends StatefulWidget {
  final Map<String, dynamic> car;

  const _TikTokListingCard({required this.car});

  @override
  State<_TikTokListingCard> createState() => _TikTokListingCardState();
}

class _TikTokListingCardState extends State<_TikTokListingCard> {
  int _imageIndex = 0;
  late final List<String> _imageUrls;

  @override
  void initState() {
    super.initState();
    _imageUrls = _extractImageUrls(widget.car);
  }

  List<String> _extractImageUrls(Map<String, dynamic> car) {
    final List<String> urls = [];
    final String primary = (car['image_url'] ?? '').toString();
    final List<dynamic> imgs =
        (car['images'] is List) ? (car['images'] as List) : const [];

    if (primary.isNotEmpty) {
      urls.add(buildMediaUrl(primary));
    }
    for (final dynamic it in imgs) {
      if (it is Map && (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
        continue;
      }
      String s;
      if (it is Map) {
        s = (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
            .toString();
      } else {
        s = it.toString();
      }
      if (s.isNotEmpty) {
        final full = buildMediaUrl(s);
        if (!urls.contains(full)) urls.add(full);
      }
    }
    return urls;
  }

  String _formatCurrency(dynamic raw) {
    final symbol = globalSymbol;
    num? value;
    if (raw is num) {
      value = raw;
    } else {
      value = num.tryParse(
        raw?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '',
      );
    }
    if (value == null) return symbol;
    return symbol + NumberFormat.decimalPattern().format(value);
  }

  String _normalizeBrandId(String brand) {
    return brand
        .trim()
        .toLowerCase()
        .replaceAll(' ', '-')
        .replaceAll(RegExp(r'[^a-z0-9\\-]'), '');
  }

  @override
  Widget build(BuildContext context) {
    final car = widget.car;
    final carId = listingPrimaryId(car);
    final title = CarNameTranslations.getLocalizedCarTitleNoYear(context, car);
    final year = (car['year'] ?? '').toString().trim();
    final brand = (car['brand'] ?? '').toString();
    final brandId = _normalizeBrandId(brand);
    final price = _formatCurrency(car['price']);
    final mileageRaw = (car['mileage'] ?? '').toString().trim();
    final loc = AppLocalizations.of(context)!;
    final num? mileageNum = mileageRaw.isEmpty
        ? null
        : num.tryParse(mileageRaw.replaceAll(RegExp(r'[^0-9.]'), ''));
    final String mileageDisplay = mileageRaw.isEmpty
        ? ''
        : '${mileageNum == null ? mileageRaw : NumberFormat.decimalPattern().format(mileageNum)} ${loc.unit_km}';
    String? cityRaw;
    for (final key in const ['city', 'location', 'city_name']) {
      final v = car[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) {
        cityRaw = s;
        break;
      }
    }
    final cityLine = cityRaw ?? '';

    final displayTitle = prettyTitleCase([
      if (title.isNotEmpty) title else (car['title']?.toString() ?? '').trim(),
      if (year.isNotEmpty) year,
    ].join(' ').trim());

    return GestureDetector(
      onTap: () {
        if (carId.isEmpty) return;
        Navigator.pushNamed(
          context,
          '/car_detail',
          arguments: {'carId': carId},
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen image with swipe
          if (_imageUrls.isNotEmpty)
            PageView.builder(
              itemCount: _imageUrls.length,
              onPageChanged: (i) => setState(() => _imageIndex = i),
              itemBuilder: (context, i) {
                return Image.network(
                  _imageUrls[i],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[900],
                      child: Center(
                        child: Icon(
                          Icons.directions_car,
                          size: 80,
                          color: Colors.grey[600],
                        ),
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Colors.black,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
                        ),
                      ),
                    );
                  },
                );
              },
            )
          else
            Container(
              color: Colors.grey[900],
              child: Center(
                child: Icon(
                  Icons.directions_car,
                  size: 80,
                  color: Colors.grey[600],
                ),
              ),
            ),

          // Gradient overlay at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 280,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Image counter
          if (_imageUrls.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_imageIndex + 1} / ${_imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

          // Car info overlay at bottom
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Brand logo + title
                Row(
                  children: [
                    if (brandId.isNotEmpty)
                      Container(
                        width: 32,
                        height: 32,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: CachedNetworkImage(
                          imageUrl:
                              '${effectiveApiBase()}/static/images/brands/$brandId.png',
                          fit: BoxFit.contain,
                          errorWidget: (context, url, error) => const Icon(
                            Icons.directions_car,
                            size: 18,
                            color: Color(0xFFFF6B00),
                          ),
                        ),
                      ),
                    if (brandId.isNotEmpty) const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        displayTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Price
                Text(
                  price,
                  style: const TextStyle(
                    color: Color(0xFFFF6B00),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                // Mileage + City row
                if (mileageDisplay.isNotEmpty || cityLine.isNotEmpty)
                  Row(
                    children: [
                      if (mileageDisplay.isNotEmpty) ...[
                        const Icon(Icons.speed, color: Colors.white70, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          mileageDisplay,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (mileageDisplay.isNotEmpty && cityLine.isNotEmpty)
                        const SizedBox(width: 16),
                      if (cityLine.isNotEmpty) ...[
                        const Icon(Icons.location_on,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            cityLine,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 16),
                // Tap to view details hint
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B00).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.touch_app,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'View Details',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scroll hint arrows
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.45,
            child: Column(
              children: [
                Icon(
                  Icons.keyboard_arrow_up,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 28,
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 28,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
