part of 'listing_image_gallery_page.dart';

class ListingPreviewMediaGridPage extends StatefulWidget {
  const ListingPreviewMediaGridPage({
    super.key,
    required this.imageFilesOrUrls,
    this.videoFilesOrUrls = const <dynamic>[],
    this.initialIndex = 0,
    this.appBarTitle,
  });

  final List<dynamic> imageFilesOrUrls;
  final List<dynamic> videoFilesOrUrls;
  /// Index in combined list: all images first, then all videos.
  final int initialIndex;

  /// When set, used as the scaffold app bar title (e.g. damage-only gallery).
  final String? appBarTitle;

  @override
  State<ListingPreviewMediaGridPage> createState() =>
      _ListingPreviewMediaGridPageState();
}

class _ListingPreviewMediaGridPageState extends State<ListingPreviewMediaGridPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _targetTileKey = GlobalKey();

  int get _totalCount =>
      widget.imageFilesOrUrls.length + widget.videoFilesOrUrls.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollInitialTargetIntoView(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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

  bool _looksLikeLocalPath(String s) {
    final v = s.trim();
    if (v.isEmpty) return false;
    if (v.startsWith('http://') || v.startsWith('https://')) return false;
    if (v.startsWith('/')) return true;
    if (v.contains(r':\')) return true;
    return File(v).existsSync();
  }

  Widget _buildImageTile(dynamic item) {
    if (item is XFile) {
      return Image.file(
        File(item.path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Center(child: Icon(Icons.broken_image)),
      );
    }
    final raw = item.toString().trim();
    if (raw.isEmpty) return const Center(child: Icon(Icons.broken_image));
    if (_looksLikeLocalPath(raw)) {
      return Image.file(
        File(raw),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Center(child: Icon(Icons.broken_image)),
      );
    }
    return Image.network(
      raw,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) =>
          const Center(child: Icon(Icons.broken_image)),
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
    );
  }

  Widget _buildVideoTile(dynamic item) {
    final raw = item is XFile ? item.path : item.toString().trim();
    final isNetwork =
        raw.startsWith('http://') || raw.startsWith('https://');
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isNetwork)
          NetworkVideoThumbnailPreview(
            videoUrl: raw,
            maxWidth: 720,
            timeMs: 800,
            fillParent: true,
          )
        else
          Container(
            color: Colors.grey[850],
            alignment: Alignment.center,
            child: const Icon(Icons.videocam, color: Colors.white70, size: 42),
          ),
        Container(color: Colors.black26),
        Center(
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
    );
  }

  void _openViewer(BuildContext context, int index) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListingPreviewMediaViewerPage(
          imageFilesOrUrls: widget.imageFilesOrUrls,
          videoFilesOrUrls: widget.videoFilesOrUrls,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = (widget.appBarTitle != null &&
            widget.appBarTitle!.trim().isNotEmpty)
        ? widget.appBarTitle!.trim()
        : (loc?.photosVideosTitle ?? 'Photos & Videos');
    if (_totalCount == 0) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(
          child: Icon(Icons.image_not_supported_outlined, size: 48),
        ),
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
          final Widget tile = index < widget.imageFilesOrUrls.length
              ? _GalleryTile(
                  selected: selected,
                  onTap: () => _openViewer(context, index),
                  child: _buildImageTile(widget.imageFilesOrUrls[index]),
                )
              : _GalleryTile(
                  selected: selected,
                  onTap: () => _openViewer(context, index),
                  child: _buildVideoTile(
                    widget.videoFilesOrUrls[index - widget.imageFilesOrUrls.length],
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

/// Full-screen media viewer for sell-preview drafts (supports local files).
