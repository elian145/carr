import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/media/media_url.dart';
import '../../widgets/in_app_video_screen.dart';
import 'listing_network_image.dart';

/// [InteractiveViewer] that only enables **pan** after pinch-zoom so horizontal
/// swipes are handled by the parent [PageView] (e.g. to reach video slides).
class FullscreenZoomableSlide extends StatefulWidget {
  const FullscreenZoomableSlide({super.key, required this.child});

  final Widget child;

  @override
  State<FullscreenZoomableSlide> createState() =>
      FullscreenZoomableSlideState();
}

class FullscreenZoomableSlideState extends State<FullscreenZoomableSlide> {
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
    return InteractiveViewer(
      transformationController: _tc,
      minScale: 0.8,
      maxScale: 4.0,
      panEnabled: _zoomed,
      scaleEnabled: true,
      child: Center(child: widget.child),
    );
  }
}

class FullScreenGalleryPage extends StatefulWidget {
  final List<String> imageUrls;
  final List<String> videoUrls;
  final int initialIndex;
  const FullScreenGalleryPage({
    super.key,
    required this.imageUrls,
    this.videoUrls = const [],
    this.initialIndex = 0,
  });
  @override
  State<FullScreenGalleryPage> createState() => _FullScreenGalleryPageState();
}

class _FullScreenGalleryPageState extends State<FullScreenGalleryPage> {
  late final PageController _controller;
  late int _index;
  late final int _mediaCount;

  bool _isVideoSlide(int index) => index >= widget.imageUrls.length;

  @override
  void initState() {
    super.initState();
    _mediaCount = widget.imageUrls.length + widget.videoUrls.length;
    _index = widget.initialIndex.clamp(
      0,
      _mediaCount > 0 ? _mediaCount - 1 : 0,
    );
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        title: _mediaCount > 0
            ? Text(
                '${_index + 1}/$_mediaCount',
                style: TextStyle(color: Colors.white),
              )
            : null,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: _mediaCount,
            itemBuilder: (context, i) {
              if (_isVideoSlide(i)) {
                final videoIndex = i - widget.imageUrls.length;
                final videoUrl = widget.videoUrls[videoIndex];
                return GalleryEmbeddedVideoPlayer(
                  videoUrl: videoUrl,
                  isActive: i == _index,
                );
              }

              final url = widget.imageUrls[i];
              return FullscreenZoomableSlide(
                child: url.isEmpty
                    ? Icon(
                        Icons.directions_car,
                        size: 48,
                        color: Colors.white38,
                      )
                    : listingNetworkImage(url, fit: BoxFit.contain),
              );
            },
          ),
          if (_mediaCount > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: BouncingScrollPhysics(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_mediaCount, (i) {
                    final active = i == _index;
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
    );
  }
}

/// Full-screen gallery for listing preview: supports both local XFile and URL strings.
class ListingPreviewGalleryPage extends StatefulWidget {
  final List<dynamic> imageFilesOrUrls;
  final List<dynamic> videoFilesOrUrls;
  final int initialIndex;

  const ListingPreviewGalleryPage({
    super.key,
    required this.imageFilesOrUrls,
    this.videoFilesOrUrls = const [],
    this.initialIndex = 0,
  });

  @override
  State<ListingPreviewGalleryPage> createState() =>
      _ListingPreviewGalleryPageState();
}

class _ListingPreviewGalleryPageState extends State<ListingPreviewGalleryPage> {
  late final PageController _controller;
  late int _index;
  late final int _mediaCount;

  bool _isVideoSlide(int index) => index >= widget.imageFilesOrUrls.length;

  @override
  void initState() {
    super.initState();
    _mediaCount =
        widget.imageFilesOrUrls.length + widget.videoFilesOrUrls.length;
    _index = widget.initialIndex.clamp(
      0,
      _mediaCount > 0 ? _mediaCount - 1 : 0,
    );
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildImage(BuildContext context, dynamic item) {
    if (item is XFile) {
      return Image.file(File(item.path), fit: BoxFit.contain);
    }
    final url = item.toString().trim();
    final fullUrl = url.startsWith('http') ? url : buildLegacyFullImageUrl(url);
    return listingNetworkImage(fullUrl, fit: BoxFit.contain);
  }

  Widget _buildVideo(BuildContext context, dynamic item, bool isActive) {
    final String raw = item is XFile ? item.path : item.toString().trim();
    if (raw.isEmpty) {
      return const Center(
        child: Icon(Icons.videocam_off, color: Colors.white38, size: 48),
      );
    }
    final String source =
        (raw.startsWith('http://') || raw.startsWith('https://'))
        ? (raw.startsWith('http') ? raw : buildLegacyFullImageUrl(raw))
        : raw;
    return GalleryEmbeddedVideoPlayer(videoUrl: source, isActive: isActive);
  }

  @override
  Widget build(BuildContext context) {
    if (_mediaCount == 0) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Icon(Icons.directions_car, size: 64, color: Colors.white38),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        title: Text('${_index + 1}/$_mediaCount'),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: _mediaCount,
            itemBuilder: (context, i) {
              if (_isVideoSlide(i)) {
                final videoIndex = i - widget.imageFilesOrUrls.length;
                final videoItem = widget.videoFilesOrUrls[videoIndex];
                return _buildVideo(context, videoItem, i == _index);
              }
              return FullscreenZoomableSlide(
                child: _buildImage(context, widget.imageFilesOrUrls[i]),
              );
            },
          ),
          if (_mediaCount > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_mediaCount, (i) {
                    final active = i == _index;
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
    );
  }
}
