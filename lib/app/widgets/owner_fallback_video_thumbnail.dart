import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../widgets/network_video_thumbnail.dart';

/// Test-only interception point for [_OwnerFallbackVideoThumbnailState]'s
/// remote-thumbnail probe -- same contract/rationale as
/// `debugOwnerFallbackHeroRemoteProbeOverride`
/// (`owner_fallback_hero_image.dart`), just returning fake thumbnail bytes
/// (or `null` for "treat as failed/still pending") instead of a bool, so a
/// test can also assert on exactly what gets painted. Always `null` in
/// production; tests MUST reset to `null` in `tearDown`.
@visibleForTesting
Future<Uint8List?> Function(String url)?
    debugOwnerFallbackVideoRemoteProbeOverride;

/// Optimistic-local-media fix: video equivalent of
/// `OwnerFallbackHeroImage` -- shows the owner's own local video's
/// thumbnail immediately, and swaps to the remote video's thumbnail only
/// once that remote thumbnail has genuinely finished generating
/// successfully. Deliberately fetches the remote thumbnail bytes directly
/// (via [VideoThumbnail.thumbnailData]) rather than simply handing a new
/// `videoUrl` to [NetworkVideoThumbnailPreview] and letting it show its
/// own loading spinner -- the whole point is that the visible tile must
/// never regress from "a real, playable-looking local thumbnail" to "a
/// spinner", even briefly, just because a remote URL appeared.
class OwnerFallbackVideoThumbnail extends StatefulWidget {
  const OwnerFallbackVideoThumbnail({
    super.key,
    required this.localUrl,
    required this.remoteUrl,
    this.maxWidth = 720,
    this.timeMs = 800,
    this.fillParent = false,
    this.onRemoteDisplayReady,
  });

  final String localUrl;
  final String? remoteUrl;
  final int maxWidth;
  final int timeMs;
  final bool fillParent;
  final VoidCallback? onRemoteDisplayReady;

  @override
  State<OwnerFallbackVideoThumbnail> createState() =>
      _OwnerFallbackVideoThumbnailState();
}

class _OwnerFallbackVideoThumbnailState
    extends State<OwnerFallbackVideoThumbnail> {
  String? _probingUrl;
  String? _confirmedRemoteUrl;
  Uint8List? _confirmedRemoteBytes;

  bool get _hasLocal => widget.localUrl.trim().isNotEmpty;
  bool get _hasRemote => (widget.remoteUrl ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _maybeStartProbe();
  }

  @override
  void didUpdateWidget(covariant OwnerFallbackVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteUrl != widget.remoteUrl) {
      _confirmedRemoteUrl = null;
      _confirmedRemoteBytes = null;
      _maybeStartProbe();
    }
  }

  void _maybeStartProbe() {
    final url = widget.remoteUrl;
    if (url == null || url.trim().isEmpty) {
      _probingUrl = null;
      return;
    }
    if (_probingUrl == url || _confirmedRemoteUrl == url) return;
    _probingUrl = url;
    if (!_hasLocal) {
      // Nothing local to protect (requirement 9's "local file
      // unexpectedly missing" fallback) -- just let the normal
      // (loading-spinner-while-fetching) preview widget handle it. Plain
      // assignment (no `setState`) for the same reason as
      // `OwnerFallbackHeroImage`'s identical branch -- see its comment.
      _confirmedRemoteUrl = url;
      return;
    }
    unawaited(_probe(url));
  }

  Future<void> _probe(String url) async {
    try {
      final override = debugOwnerFallbackVideoRemoteProbeOverride;
      final data = override != null
          ? await override(url)
          : await VideoThumbnail.thumbnailData(
              video: url,
              imageFormat: ImageFormat.JPEG,
              maxWidth: widget.maxWidth,
              quality: 80,
              timeMs: widget.timeMs,
            );
      if (!mounted || _probingUrl != url) return;
      if (data == null || data.isEmpty) {
        return; // keep local (STATE E) -- a later rebuild may retry.
      }
      setState(() {
        _confirmedRemoteUrl = url;
        _confirmedRemoteBytes = data;
      });
      widget.onRemoteDisplayReady?.call();
    } catch (e) {
      if (!mounted) return;
      // keep local (STATE E).
    }
  }

  Widget _fromBytes(Uint8List bytes) {
    final child = Image.memory(
      bytes,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );
    if (widget.fillParent) return SizedBox.expand(child: child);
    return AspectRatio(aspectRatio: 16 / 9, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final showRemote =
        _hasRemote && _confirmedRemoteUrl == widget.remoteUrl;
    if (showRemote && _confirmedRemoteBytes != null) {
      return _fromBytes(_confirmedRemoteBytes!);
    }
    final effectiveUrl = showRemote
        ? widget.remoteUrl!
        : (_hasLocal ? widget.localUrl : (widget.remoteUrl ?? ''));
    return NetworkVideoThumbnailPreview(
      key: ValueKey('owner_fallback_video|$effectiveUrl'),
      videoUrl: effectiveUrl,
      maxWidth: widget.maxWidth,
      timeMs: widget.timeMs,
      fillParent: widget.fillParent,
    );
  }
}
