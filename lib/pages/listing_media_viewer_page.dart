part of 'listing_image_gallery_page.dart';

class ListingMediaViewerPage extends StatefulWidget {
  const ListingMediaViewerPage({
    super.key,
    required this.imageUrls,
    this.videoUrls = const <String>[],
    this.initialIndex = 0,
  });

  final List<String> imageUrls;
  final List<String> videoUrls;
  /// Index in combined list: all images first, then all videos.
  final int initialIndex;

  @override
  State<ListingMediaViewerPage> createState() => _ListingMediaViewerPageState();
}

class _ListingMediaViewerPageState extends State<ListingMediaViewerPage> {
  late final PageController _pageController;
  late int _index;

  int get _mediaCount => widget.imageUrls.length + widget.videoUrls.length;

  bool _isVideoSlide(int i) => i >= widget.imageUrls.length;

  @override
  void initState() {
    super.initState();
    final n = _mediaCount;
    _index = n == 0 ? 0 : widget.initialIndex.clamp(0, n - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_mediaCount == 0) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Icon(Icons.broken_image, color: Colors.white38, size: 48),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${_index + 1}/$_mediaCount',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: _mediaCount,
            itemBuilder: (context, i) {
              if (_isVideoSlide(i)) {
                final vIdx = i - widget.imageUrls.length;
                final videoUrl = widget.videoUrls[vIdx];
                return GalleryEmbeddedVideoPlayer(
                  videoUrl: videoUrl,
                  isActive: i == _index,
                );
              }
              return _ZoomableNetworkImage(url: widget.imageUrls[i]);
            },
          ),
          if (_mediaCount > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_mediaCount, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 10 : 6,
                      height: active ? 10 : 6,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white54,
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomableNetworkImage extends StatefulWidget {
  const _ZoomableNetworkImage({required this.url});

  final String url;

  @override
  State<_ZoomableNetworkImage> createState() => _ZoomableNetworkImageState();
}

class _ZoomableNetworkImageState extends State<_ZoomableNetworkImage> {
  final TransformationController _tc = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_syncZoom);
  }

  void _syncZoom() {
    if (!mounted) return;
    final s = _tc.value.storage;
    final scale = math.sqrt(s[0] * s[0] + s[4] * s[4] + s[8] * s[8]);
    final z = scale > 1.02;
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  @override
  void dispose() {
    _tc.removeListener(_syncZoom);
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    return InteractiveViewer(
      transformationController: _tc,
      minScale: 0.8,
      maxScale: 4,
      panEnabled: _zoomed,
      scaleEnabled: true,
      child: SizedBox(
        width: s.width,
        height: s.height,
        child: Center(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            width: s.width,
            height: s.height,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.broken_image, color: Colors.white38, size: 48);
            },
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
              );
            },
          ),
        ),
      ),
    );
  }
}

void _openListingMediaViewer(
  BuildContext context, {
  required List<String> imageUrls,
  required List<String> videoUrls,
  required int initialIndex,
}) {
  Navigator.of(context).push<void>(
    AppPageRoute<void>(
      builder: (context) => ListingMediaViewerPage(
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        initialIndex: initialIndex,
      ),
    ),
  );
}

/// Images then videos in a grid (same order as listing hero). Any tile opens
/// [ListingMediaViewerPage] so photos and videos are on one swipeable screen.
