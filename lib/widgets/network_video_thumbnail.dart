import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Loads a preview frame from a local path or **network video URL** using the
/// platform thumbnail generator (same plugin as local file previews).
class NetworkVideoThumbnailPreview extends StatefulWidget {
  const NetworkVideoThumbnailPreview({
    super.key,
    required this.videoUrl,
    this.maxWidth = 720,
    this.timeMs = 800,
    this.httpHeaders,
  });

  final String videoUrl;
  final int maxWidth;
  /// Offset into the video to avoid an all-black first frame.
  final int timeMs;
  final Map<String, String>? httpHeaders;

  @override
  State<NetworkVideoThumbnailPreview> createState() =>
      _NetworkVideoThumbnailPreviewState();
}

class _NetworkVideoThumbnailPreviewState
    extends State<NetworkVideoThumbnailPreview> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NetworkVideoThumbnailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.maxWidth != widget.maxWidth ||
        oldWidget.timeMs != widget.timeMs) {
      _bytes = null;
      _loading = true;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.videoUrl.trim();
    if (url.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: url,
        headers: widget.httpHeaders,
        imageFormat: ImageFormat.JPEG,
        maxWidth: widget.maxWidth,
        quality: 80,
        timeMs: widget.timeMs,
      );
      if (!mounted) return;
      final ok = data != null && data.isNotEmpty;
      setState(() {
        _loading = false;
        _failed = !ok;
        _bytes = ok ? data : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
        _bytes = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: Colors.grey[900],
        alignment: Alignment.center,
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey[500],
          ),
        ),
      );
    }
    if (_failed || _bytes == null) {
      return Container(
        color: Colors.grey[800],
        alignment: Alignment.center,
        child: Icon(
          Icons.videocam,
          size: 48,
          color: Colors.grey[500],
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey[800],
        alignment: Alignment.center,
        child: Icon(
          Icons.videocam,
          size: 48,
          color: Colors.grey[500],
        ),
      ),
    );
  }
}
