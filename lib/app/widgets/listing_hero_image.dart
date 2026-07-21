import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../shared/debug/app_log.dart';
import '../../shared/listings/listing_image_media.dart';
import 'listing_hero_focus.dart';

/// Hero listing photo: cover + vehicle bias, optional detection crop, fade-in.
class ListingHeroImage extends StatefulWidget {
  const ListingHeroImage({
    super.key,
    required this.url,
    this.detectionSource,
    this.fadeDuration = const Duration(milliseconds: 280),
  });

  final String url;
  final dynamic detectionSource;
  final Duration fadeDuration;

  @override
  State<ListingHeroImage> createState() => _ListingHeroImageState();
}

class _ListingHeroImageState extends State<ListingHeroImage> {
  ui.Image? _decoded;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _failed = false;
  bool _shown = false;
  int _attempt = 0;
  bool _retryScheduled = false;
  Timer? _retryTimer;
  static const int _maxRetries = 5;

  ListingHeroCarBBox? get _bbox =>
      ListingImageMedia.focusY(widget.detectionSource) != null
      ? null
      : parseListingHeroCarBBox(widget.detectionSource);

  Alignment get _alignment =>
      listingHeroAlignmentFor(widget.detectionSource ?? const {});

  String _fallbackUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      if (path.contains('/static/uploads/') &&
          !path.contains('/static/uploads/car_photos/')) {
        final idx = path.indexOf('/static/uploads/');
        final after = path.substring(idx + '/static/uploads/'.length);
        if (after.isNotEmpty && !after.contains('/')) {
          final newPath =
              '${path.substring(0, idx)}/static/uploads/car_photos/$after';
          return uri.replace(path: newPath).toString();
        }
      }
    } catch (e, st) {
      logNonFatal(e, st);
    }
    return url;
  }

  String get _effectiveUrl {
    if (_attempt == 1) return _fallbackUrl(widget.url);
    return widget.url;
  }

  void _scheduleRetry() {
    if (_attempt >= _maxRetries || _retryScheduled) return;
    _retryScheduled = true;
    final delayMs = 700 * (1 << _attempt).clamp(1, 8);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      setState(() {
        _attempt += 1;
        _retryScheduled = false;
        _failed = false;
        _shown = false;
        _decoded = null;
      });
      _resolveImage();
    });
  }

  void _resolveImage() {
    _clearStream();
    if (widget.url.isEmpty) {
      _failed = true;
      return;
    }
    final provider = NetworkImage(_effectiveUrl);
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _decoded = info.image;
          _failed = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _shown = true);
        });
      },
      onError: (error, stack) {
        try {
          appLog('Hero listing image failed (attempt=$_attempt)');
        } catch (e, st) {
          logNonFatal(e, st, 'ListingHeroImage.error');
        }
        if (!mounted) return;
        setState(() => _failed = true);
        _scheduleRetry();
      },
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _clearStream() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant ListingHeroImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.detectionSource != widget.detectionSource) {
      _attempt = 0;
      _failed = false;
      _shown = false;
      _decoded = null;
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _clearStream();
    super.dispose();
  }

  Widget _placeholder() {
    return const ColoredBox(
      color: Color(0xFF1A1A1A),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
          ),
        ),
      ),
    );
  }

  Widget _error() {
    return ColoredBox(
      color: Colors.grey[900]!,
      child: Center(
        child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
      ),
    );
  }

  Widget _buildDecoded(ui.Image decoded) {
    final bbox = _bbox;
    if (bbox == null) {
      return RawImage(
        image: decoded,
        fit: BoxFit.cover,
        alignment: _alignment,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final vh = constraints.maxHeight;
        if (!vw.isFinite || !vh.isFinite || vw <= 0 || vh <= 0) {
          return const SizedBox.expand();
        }
        final srcNorm = resolveHeroCoverSourceRect(
          viewportAspect: vw / vh,
          carBBox: bbox,
        );
        final src = Rect.fromLTWH(
          srcNorm.left * decoded.width,
          srcNorm.top * decoded.height,
          srcNorm.width * decoded.width,
          srcNorm.height * decoded.height,
        );
        return CustomPaint(
          painter: _HeroCropPainter(image: decoded, src: src),
          size: Size(vw, vh),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) return _error();
    if (_failed && _attempt >= _maxRetries && _decoded == null) {
      return _error();
    }

    final decoded = _decoded;
    return Stack(
      fit: StackFit.expand,
      children: [
        _placeholder(),
        if (decoded != null)
          AnimatedOpacity(
            opacity: _shown ? 1 : 0,
            duration: widget.fadeDuration,
            curve: Curves.easeOut,
            child: _buildDecoded(decoded),
          ),
      ],
    );
  }
}

class _HeroCropPainter extends CustomPainter {
  _HeroCropPainter({required this.image, required this.src});

  final ui.Image image;
  final Rect src;

  @override
  void paint(Canvas canvas, Size size) {
    if (src.width <= 0 || src.height <= 0) return;
    final dst = Offset.zero & size;
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant _HeroCropPainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.src != src;
  }
}
