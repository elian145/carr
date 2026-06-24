part of 'listing_image_gallery_page.dart';

class ListingImageGalleryPage extends StatefulWidget {
  const ListingImageGalleryPage({
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
  State<ListingImageGalleryPage> createState() => _ListingImageGalleryPageState();
}

class _ListingImageGalleryPageState extends State<ListingImageGalleryPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _targetTileKey = GlobalKey();

  int get _totalCount => widget.imageUrls.length + widget.videoUrls.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollInitialTargetIntoView());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Matches [SliverGridDelegateWithFixedCrossAxisCount] (crossAxisCount 2,
  /// spacing 8, aspect 1) + same padding as the grid.
  double _estimatedOffsetForIndex(int index, double viewportWidth) {
    const pad = 8.0;
    const cols = 2;
    const crossGap = 8.0;
    const mainGap = 8.0;
    const aspect = 1.0;
    final innerCross = viewportWidth - pad * 2;
    final childCross = (innerCross - crossGap * (cols - 1)) / cols;
    final childMain = childCross / aspect;
    final mainStride = childMain + mainGap;
    final row = index ~/ cols;
    return pad + row * mainStride;
  }

  void _scrollInitialTargetIntoView() {
    if (!mounted || _totalCount == 0) return;
    final highlight = widget.initialIndex.clamp(0, _totalCount - 1);
    if (highlight == 0) {
      _fineTuneVisible();
      return;
    }
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final rough = _estimatedOffsetForIndex(highlight, w);
    final biased = (rough - h * 0.12).clamp(0.0, double.infinity);

    void jumpIfReady() {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(biased.clamp(0.0, max));
    }

    jumpIfReady();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      jumpIfReady();
      _fineTuneVisible();
    });
  }

  void _fineTuneVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _targetTileKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.12,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = loc?.photosVideosTitle ?? 'Photos';

    if (_totalCount == 0) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: Icon(Icons.image_not_supported_outlined, size: 48)),
      );
    }

    final highlightIndex = widget.initialIndex.clamp(0, _totalCount - 1);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _totalCount,
        itemBuilder: (context, index) {
          final selected = index == highlightIndex;
          if (index < widget.imageUrls.length) {
            final url = widget.imageUrls[index];
            final tile = _GalleryTile(
              selected: selected,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(child: Icon(Icons.broken_image));
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
              onTap: () => _openListingMediaViewer(
                context,
                imageUrls: widget.imageUrls,
                videoUrls: widget.videoUrls,
                initialIndex: index,
              ),
            );
            if (index == highlightIndex) {
              return KeyedSubtree(key: _targetTileKey, child: tile);
            }
            return tile;
          }
          final videoUrl = widget.videoUrls[index - widget.imageUrls.length];
          final tile = _GalleryTile(
            selected: selected,
            onTap: () {
              if (videoUrl.trim().isEmpty) return;
              _openListingMediaViewer(
                context,
                imageUrls: widget.imageUrls,
                videoUrls: widget.videoUrls,
                initialIndex: index,
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetworkVideoThumbnailPreview(
                  videoUrl: videoUrl,
                  maxWidth: 720,
                  timeMs: 800,
                  fillParent: true,
                ),
                Container(
                  alignment: Alignment.center,
                  color: Colors.black26,
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 56,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'VIDEO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
          if (index == highlightIndex) {
            return KeyedSubtree(key: _targetTileKey, child: tile);
          }
          return tile;
        },
      ),
    );
  }
}

/// Sell-flow media grid that supports both local [XFile] and URL strings.
/// Opens [ListingPreviewMediaViewerPage] when a tile is tapped.
