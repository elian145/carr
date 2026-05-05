import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/in_app_video_screen.dart';
import '../widgets/network_video_thumbnail.dart';

/// Full-screen: swipe through **images** (pinch zoom) and **videos** (inline
/// player) on one page — same order as the gallery grid (images, then videos).
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
    MaterialPageRoute<void>(
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
                    color: Colors.white.withOpacity(0.92),
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

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black12,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: selected
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox.expand(child: child),
      ),
    );
  }
}
