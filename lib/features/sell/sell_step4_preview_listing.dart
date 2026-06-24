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
