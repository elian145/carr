import 'package:flutter/material.dart';

import '../../shared/debug/app_log.dart';

/// Listing image widget using Image.network (avoids CachedNetworkImage HTTP issues on Android).
/// Includes a small auto-retry to reduce transient "connection closed" failures.
Widget listingNetworkImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) {
  if (url.isEmpty) {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
      ),
    );
  }
  return _RetryingListingNetworkImage(
    url: url,
    fit: fit,
    width: width,
    height: height,
  );
}

class _RetryingListingNetworkImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  const _RetryingListingNetworkImage({
    required this.url,
    required this.fit,
    this.width,
    this.height,
  });

  @override
  State<_RetryingListingNetworkImage> createState() =>
      _RetryingListingNetworkImageState();
}

class _RetryingListingNetworkImageState
    extends State<_RetryingListingNetworkImage> {
  int _attempt = 0;
  bool _retryScheduled = false;
  // Connection drops can happen when serving many large images; retry a bit more with backoff.
  static const int _maxRetries = 5;

  String _fallbackUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      // If we got a bare filename under /static/uploads/, it often actually lives in /static/uploads/car_photos/.
      // Example wrong:  /static/uploads/processed_x.jpg
      // Example right:   /static/uploads/car_photos/processed_x.jpg
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
    } catch (e, st) { logNonFatal(e, st); }
    return url;
  }

  String get _effectiveUrl {
    // Attempt 0: original
    // Attempt 1: fallback path variant (fixes some backend path variants)
    if (_attempt == 1) return _fallbackUrl(widget.url);
    return widget.url;
  }

  void _scheduleRetry() {
    if (_attempt >= _maxRetries) return;
    if (_retryScheduled) return;
    _retryScheduled = true;
    final delayMs =
        700 * (1 << _attempt).clamp(1, 8); // 700ms, 1.4s, 2.8s... capped
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      setState(() {
        _attempt += 1;
        _retryScheduled = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _effectiveUrl;
    return Image.network(
      url,
      key: ValueKey('$url#$_attempt'),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.white10,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          (loadingProgress.expectedTotalBytes ?? 1)
                    : null,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        try {
          appLog('Listing image failed (attempt=$_attempt)');
        } catch (e, st) {
          logNonFatal(e, st, 'ListingNetworkImage.error');
        }
        _scheduleRetry();
        return Container(
          color: Colors.grey[900],
          child: Center(
            child: Icon(
              Icons.directions_car,
              size: 60,
              color: Colors.grey[400],
            ),
          ),
        );
      },
    );
  }
}
