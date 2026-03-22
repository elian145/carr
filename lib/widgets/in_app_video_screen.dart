import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'network_video_thumbnail.dart';

String _formatVideoTime(Duration d) {
  if (d.inMilliseconds < 0) return '0:00';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Inline video for [FullScreenGalleryPage] so users can swipe to other media
/// while the video is playing (no pushed route on top).
class GalleryEmbeddedVideoPlayer extends StatefulWidget {
  const GalleryEmbeddedVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.isActive,
  });

  final String videoUrl;
  final bool isActive;

  @override
  State<GalleryEmbeddedVideoPlayer> createState() =>
      _GalleryEmbeddedVideoPlayerState();
}

class _GalleryEmbeddedVideoPlayerState extends State<GalleryEmbeddedVideoPlayer> {
  VideoPlayerController? _controller;
  bool _loading = false;
  String? _error;
  /// While dragging the seek slider, holds the thumb position in ms.
  double? _seekDragMs;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _init();
    }
  }

  @override
  void didUpdateWidget(GalleryEmbeddedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoUrl != oldWidget.videoUrl) {
      _disposeController();
      if (widget.isActive) {
        _init();
      }
      return;
    }
    if (widget.isActive && !oldWidget.isActive) {
      if (_controller == null) {
        _init();
      } else {
        _controller!.play();
      }
    }
    if (!widget.isActive && oldWidget.isActive) {
      _controller?.pause();
    }
  }

  Future<void> _init() async {
    final url = widget.videoUrl.trim();
    if (url.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Empty URL';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(url);
      final c = VideoPlayerController.networkUrl(uri);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.setLooping(false);
      await c.play();
      setState(() {
        _controller = c;
        _loading = false;
      });
      c.addListener(_onTick);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _disposeController() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    _controller = null;
    _seekDragMs = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  Widget _buildSeekBar(BuildContext context, VideoPlayerController c) {
    final v = c.value;
    if (!v.isInitialized) return const SizedBox.shrink();
    final totalMs = v.duration.inMilliseconds;
    if (totalMs <= 0) return const SizedBox.shrink();

    final posMs = v.position.inMilliseconds.clamp(0, totalMs);
    final maxD = totalMs.toDouble();
    final thumbMs = (_seekDragMs ?? posMs.toDouble()).clamp(0.0, maxD);

    final timeStyle = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    _formatVideoTime(
                      Duration(milliseconds: thumbMs.round()),
                    ),
                    style: timeStyle,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 10,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 13,
                        elevation: 3,
                        pressedElevation: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 24,
                      ),
                      activeTrackColor: const Color(0xFFFF6B00),
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: const Color(0x66FF6B00),
                    ),
                    child: Slider(
                      value: thumbMs,
                      max: maxD,
                      onChangeStart: (_) {
                        setState(() => _seekDragMs = posMs.toDouble());
                      },
                      onChanged: (nv) {
                        final t = nv.clamp(0.0, maxD);
                        setState(() => _seekDragMs = t);
                        c.seekTo(Duration(milliseconds: t.round()));
                      },
                      onChangeEnd: (_) {
                        setState(() => _seekDragMs = null);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    _formatVideoTime(v.duration),
                    textAlign: TextAlign.right,
                    style: timeStyle.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Drag the bar to jump in the video',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.videoUrl.trim();
    if (url.isEmpty) {
      return const Center(
        child: Icon(Icons.videocam_off, color: Colors.white38, size: 48),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_loading || _controller == null || !_controller!.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail while loading (same as tap-to-open flow)
          NetworkVideoThumbnailPreview(
            videoUrl: url,
            maxWidth: 1280,
            timeMs: 800,
            fillParent: true,
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      );
    }

    final c = _controller!;
    final ar = c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio;

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: ar,
            child: GestureDetector(
              onTap: _togglePlay,
              child: VideoPlayer(c),
            ),
          ),
        ),
        Positioned(
          top: 14,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'VIDEO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        if (!c.value.isPlaying)
          Center(
            child: IgnorePointer(
              child: Icon(
                Icons.play_circle_filled,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: _buildSeekBar(context, c),
          ),
        ),
      ],
    );
  }
}

/// Plays a network video inside the app (no external browser / launcher).
class InAppVideoScreen extends StatefulWidget {
  const InAppVideoScreen({super.key, required this.videoUrl});

  final String videoUrl;

  @override
  State<InAppVideoScreen> createState() => _InAppVideoScreenState();
}

class _InAppVideoScreenState extends State<InAppVideoScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final uri = Uri.parse(widget.videoUrl);
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final ar = controller.value.aspectRatio;
      _videoController = controller;
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        aspectRatio: ar == 0 ? 16 / 9 : ar,
      );
      setState(() {
        _loading = false;
      });
    } catch (e) {
      await _videoController?.dispose();
      _videoController = null;
      _chewieController?.dispose();
      _chewieController = null;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Video'),
      ),
      body: SafeArea(
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(color: Colors.white)
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _chewieController != null
                      ? Chewie(controller: _chewieController!)
                      : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
