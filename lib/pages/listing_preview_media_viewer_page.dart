part of 'listing_image_gallery_page.dart';

class ListingPreviewMediaViewerPage extends StatefulWidget {
  const ListingPreviewMediaViewerPage({
    super.key,
    required this.imageFilesOrUrls,
    this.videoFilesOrUrls = const <dynamic>[],
    this.initialIndex = 0,
  });

  final List<dynamic> imageFilesOrUrls;
  final List<dynamic> videoFilesOrUrls;
  final int initialIndex;

  @override
  State<ListingPreviewMediaViewerPage> createState() =>
      _ListingPreviewMediaViewerPageState();
}

class _ListingPreviewMediaViewerPageState
    extends State<ListingPreviewMediaViewerPage> {
  late final PageController _controller;
  late int _index;
  late final int _mediaCount;

  bool _isVideoSlide(int index) => index >= widget.imageFilesOrUrls.length;

  @override
  void initState() {
    super.initState();
    _mediaCount =
        widget.imageFilesOrUrls.length + widget.videoFilesOrUrls.length;
    _index = widget.initialIndex.clamp(0, _mediaCount > 0 ? _mediaCount - 1 : 0);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _asPathOrUrl(dynamic item) {
    if (item is XFile) return item.path;
    return item.toString().trim();
  }

  bool _looksLikeLocalPath(String s) {
    final v = s.trim();
    if (v.isEmpty) return false;
    if (v.startsWith('http://') || v.startsWith('https://')) return false;
    if (v.startsWith('/')) return true;
    if (v.contains(r':\')) return true;
    return File(v).existsSync();
  }

  Widget _buildImage(dynamic item) {
    if (item is XFile) {
      return _ZoomableFileImage(path: item.path);
    }
    final raw = item.toString().trim();
    if (raw.isEmpty) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.white38, size: 48),
      );
    }
    if (_looksLikeLocalPath(raw)) return _ZoomableFileImage(path: raw);
    return _ZoomableNetworkImage(url: raw);
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
        title: Text(
          '${_index + 1}/$_mediaCount',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _mediaCount,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, index) {
              if (_isVideoSlide(index)) {
                final v = widget.videoFilesOrUrls[index - widget.imageFilesOrUrls.length];
                final src = _asPathOrUrl(v);
                return GalleryEmbeddedVideoPlayer(
                  videoUrl: src,
                  isActive: index == _index,
                );
              }
              return _buildImage(widget.imageFilesOrUrls[index]);
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

class _ZoomableFileImage extends StatefulWidget {
  const _ZoomableFileImage({required this.path});

  final String path;

  @override
  State<_ZoomableFileImage> createState() => _ZoomableFileImageState();
}

class _ZoomableFileImageState extends State<_ZoomableFileImage> {
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
          child: Image.file(
            File(widget.path),
            fit: BoxFit.contain,
            width: s.width,
            height: s.height,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.broken_image, color: Colors.white38, size: 48);
            },
          ),
        ),
      ),
    );
  }
}
