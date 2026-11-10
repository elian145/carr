import 'package:flutter/foundation.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Result of [RemoteVideoThumbnail.generate]. Never carries an exception:
/// every platform failure is folded into "no bytes".
class RemoteVideoThumbnailResult {
  const RemoteVideoThumbnailResult._({
    this.bytes,
    this.timeMsUsed,
    this.throttled = false,
    this.fromCache = false,
  });

  const RemoteVideoThumbnailResult.success(
    Uint8List bytes,
    int timeMsUsed, {
    bool fromCache = false,
  }) : this._(bytes: bytes, timeMsUsed: timeMsUsed, fromCache: fromCache);

  /// [throttled] = true when this failure was served from the failure
  /// cache without touching the platform plugin at all.
  const RemoteVideoThumbnailResult.failure({bool throttled = false})
      : this._(throttled: throttled);

  final Uint8List? bytes;

  /// Which timestamp finally produced [bytes] (null on failure).
  final int? timeMsUsed;
  final bool throttled;
  final bool fromCache;

  bool get ok => bytes != null && bytes!.isNotEmpty;
}

typedef RemoteVideoThumbnailFetcher = Future<Uint8List?> Function(
  String video,
  Map<String, String>? headers,
  int timeMs,
  int maxWidth,
);

/// Single entry point for generating a video thumbnail frame, shared by the
/// Listing Details "Processing media" readiness probe, the hero video
/// preview and the owner-fallback video tile.
///
/// Why it exists (real-device diagnosis, Samsung A17, 1080x1920 H.26x clip
/// served over HTTPS): `VideoThumbnail.thumbnailData(timeMs: 800)` fails
/// while `timeMs: 0` succeeds with identical arguments otherwise. The
/// plugin's Android code (`VideoThumbnailPlugin.java`) calls
/// `MediaMetadataRetriever.getFrameAtTime(timeMs*1000, OPTION_CLOSEST)`;
/// when that returns null it throws an internal `NullPointerException`
/// that it catches but never reports (`handled` stays false), so Dart sees
/// `MissingPluginException` -- i.e. "no frame decodable at that exact
/// timestamp", NOT "plugin missing". The first frame (0 ms) needs no seek
/// and decodes fine, so we fall back to it.
///
/// Behaviour:
///  * tries [preferredTimeMs] first (nicer than a black first frame), then
///    falls back to 0 ms;
///  * every platform exception is swallowed into a failed result;
///  * REMOTE (http/https) videos only: concurrent callers for one URL share
///    one in-flight attempt chain, a success is cached (small LRU), and a
///    total failure is remembered with exponential backoff so a genuinely
///    unavailable video is NOT re-attempted (and does not throw) on every
///    2-second badge poll tick. Local paths are never cached/throttled (the
///    file may legitimately appear/change under the same path).
abstract final class RemoteVideoThumbnail {
  RemoteVideoThumbnail._();

  static const int fallbackTimeMs = 0;
  static const int maxCachedThumbnails = 8;

  /// Delay before a remote URL that failed [failures] times in a row (all
  /// attempts each time) may be tried again: 15s, 30s, 60s, 2m, then 5m.
  static Duration backoffFor(int failures) {
    if (failures <= 0) return Duration.zero;
    final exp = failures - 1 > 5 ? 5 : failures - 1;
    final seconds = 15 * (1 << exp);
    return Duration(seconds: seconds > 300 ? 300 : seconds);
  }

  static final Map<String, Future<RemoteVideoThumbnailResult>> _inFlight =
      <String, Future<RemoteVideoThumbnailResult>>{};
  // Insertion-ordered => oldest first for LRU eviction.
  static final Map<String, ({Uint8List bytes, int timeMs})> _cache =
      <String, ({Uint8List bytes, int timeMs})>{};
  static final Map<String, ({int failures, DateTime retryAt})> _failures =
      <String, ({int failures, DateTime retryAt})>{};

  @visibleForTesting
  static RemoteVideoThumbnailFetcher? debugFetcherOverride;

  @visibleForTesting
  static DateTime Function()? debugNow;

  @visibleForTesting
  static void debugReset() {
    debugFetcherOverride = null;
    debugNow = null;
    _inFlight.clear();
    _cache.clear();
    _failures.clear();
  }

  /// Consecutive total failures currently remembered for [video] (tests).
  @visibleForTesting
  static int debugFailureCount(String video) => _failures[video]?.failures ?? 0;

  static DateTime _now() => (debugNow ?? DateTime.now)();

  static bool _isRemote(String video) {
    final v = video.trimLeft().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  static Future<Uint8List?> _fetch(
    String video,
    Map<String, String>? headers,
    int timeMs,
    int maxWidth,
  ) {
    final override = debugFetcherOverride;
    if (override != null) return override(video, headers, timeMs, maxWidth);
    return VideoThumbnail.thumbnailData(
      video: video,
      headers: headers,
      imageFormat: ImageFormat.JPEG,
      maxWidth: maxWidth,
      quality: 80,
      timeMs: timeMs,
    );
  }

  static Future<RemoteVideoThumbnailResult> generate(
    String video, {
    Map<String, String>? headers,
    int preferredTimeMs = 800,
    int maxWidth = 720,
  }) {
    final url = video.trim();
    if (url.isEmpty) {
      return Future.value(const RemoteVideoThumbnailResult.failure());
    }
    if (!_isRemote(url)) {
      return _attempt(url, headers, preferredTimeMs, maxWidth);
    }

    final cached = _cache.remove(url);
    if (cached != null) {
      _cache[url] = cached; // refresh LRU position
      return Future.value(
        RemoteVideoThumbnailResult.success(
          cached.bytes,
          cached.timeMs,
          fromCache: true,
        ),
      );
    }
    final failed = _failures[url];
    if (failed != null && _now().isBefore(failed.retryAt)) {
      return Future.value(
        const RemoteVideoThumbnailResult.failure(throttled: true),
      );
    }
    final running = _inFlight[url];
    if (running != null) return running;

    final future = _attempt(url, headers, preferredTimeMs, maxWidth).then((r) {
      _inFlight.remove(url);
      if (r.ok) {
        _failures.remove(url);
        _cache[url] = (bytes: r.bytes!, timeMs: r.timeMsUsed ?? 0);
        while (_cache.length > maxCachedThumbnails) {
          _cache.remove(_cache.keys.first);
        }
      } else {
        final n = (_failures[url]?.failures ?? 0) + 1;
        _failures[url] = (failures: n, retryAt: _now().add(backoffFor(n)));
      }
      return r;
    });
    _inFlight[url] = future;
    return future;
  }

  static Future<RemoteVideoThumbnailResult> _attempt(
    String url,
    Map<String, String>? headers,
    int preferredTimeMs,
    int maxWidth,
  ) async {
    final times = preferredTimeMs <= 0
        ? const <int>[fallbackTimeMs]
        : <int>[preferredTimeMs, fallbackTimeMs];
    for (final t in times) {
      try {
        final data = await _fetch(url, headers, t, maxWidth);
        if (data != null && data.isNotEmpty) {
          return RemoteVideoThumbnailResult.success(data, t);
        }
      } catch (_) {
        // MissingPluginException (frame not decodable at this timestamp),
        // PlatformException, ... -> try the next time.
      }
    }
    return const RemoteVideoThumbnailResult.failure();
  }
}
