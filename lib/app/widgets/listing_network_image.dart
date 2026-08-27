import 'dart:async';
import '../../theme/app_colors.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../shared/debug/app_log.dart';
import '../../shared/debug/expected_client_noise.dart';

/// Cached [ImageProvider] for remote listing / media URLs (avatars, covers, precache).
ImageProvider listingCachedNetworkImageProvider(String url) =>
    CachedNetworkImageProvider(url);

/// Cached network image for listing / media URLs.
///
/// Uses [CachedNetworkImage] with a small auto-retry to reduce transient
/// "connection closed" failures, plus a path-fallback for misplaced uploads.
Widget listingNetworkImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  Alignment alignment = Alignment.center,
  double? width,
  double? height,
  FilterQuality filterQuality = FilterQuality.low,
  Widget? errorWidget,
  Widget? placeholder,
}) {
  if (url.isEmpty) {
    return errorWidget ??
        Container(
          color: Colors.grey[900],
          child: Center(
            child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
          ),
        );
  }
  return _RetryingListingNetworkImage(
    url: url,
    fit: fit,
    alignment: alignment,
    width: width,
    height: height,
    filterQuality: filterQuality,
    errorWidget: errorWidget,
    placeholder: placeholder,
  );
}

class _RetryingListingNetworkImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;
  final Widget? errorWidget;
  final Widget? placeholder;

  const _RetryingListingNetworkImage({
    required this.url,
    required this.fit,
    required this.alignment,
    this.width,
    this.height,
    required this.filterQuality,
    this.errorWidget,
    this.placeholder,
  });

  @override
  State<_RetryingListingNetworkImage> createState() =>
      _RetryingListingNetworkImageState();
}

class _RetryingListingNetworkImageState
    extends State<_RetryingListingNetworkImage> {
  int _attempt = 0;
  bool _retryScheduled = false;
  Timer? _retryTimer;
  static const int _maxRetries = 5;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _RetryingListingNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _retryTimer?.cancel();
      _attempt = 0;
      _retryScheduled = false;
    }
  }

  String _fallbackUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      // Bare filenames under /static/uploads/ often live in /static/uploads/car_photos/.
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
    if (_attempt >= _maxRetries) return;
    if (_retryScheduled) return;
    _retryScheduled = true;
    final delayMs = 700 * (1 << _attempt).clamp(1, 8);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      setState(() {
        _attempt += 1;
        _retryScheduled = false;
      });
    });
  }

  Widget _defaultError() {
    return widget.errorWidget ??
        Container(
          color: Colors.grey[900],
          child: Center(
            child: Icon(
              Icons.directions_car,
              size: 60,
              color: Colors.grey[400],
            ),
          ),
        );
  }

  Widget _defaultPlaceholder() {
    return widget.placeholder ??
        Container(
          color: Colors.white10,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandOrange),
              ),
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final url = _effectiveUrl;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Decode at the display size (in physical pixels) instead of full
        // resolution. This dramatically cuts memory for grid thumbnails while
        // keeping full-screen images crisp (capped to avoid pathological sizes).
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final double logicalWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : (widget.width ?? double.infinity);
        int? memCacheWidth;
        if (logicalWidth.isFinite && logicalWidth > 0) {
          memCacheWidth = (logicalWidth * dpr).round().clamp(1, 2048).toInt();
        }
        return CachedNetworkImage(
          key: ValueKey('$url#$_attempt'),
          imageUrl: url,
          fit: widget.fit,
          alignment: widget.alignment,
          width: widget.width,
          height: widget.height,
          memCacheWidth: memCacheWidth,
          filterQuality: widget.filterQuality,
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: const Duration(milliseconds: 80),
          placeholder: (context, _) => _defaultPlaceholder(),
          errorListener: (_) {},
          errorWidget: (context, _, error) {
            try {
              appLog('Listing image failed (attempt=$_attempt)');
            } catch (e, st) {
              logNonFatal(e, st, 'ListingNetworkImage.error');
            }
            if (!isPermanentHttpImageError(error)) {
              _scheduleRetry();
            }
            return _defaultError();
          },
        );
      },
    );
  }
}
