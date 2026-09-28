part of 'car_details_page.dart';

mixin _CarDetailsPageMedia on _CarDetailsPageOwner {
  /// Optimistic-submission fix (task item #14): true for a raw media
  /// reference that is a local device file (from this device's own
  /// still-in-flight Sell submission -- see `owner_pending_media_merge
  /// .dart`), as opposed to a genuine server URL/relative path. Local
  /// references must never be passed through [buildLegacyFullImageUrl]
  /// (which assumes every input is server-relative and would mangle an
  /// absolute device path into a broken URL) -- they are used AS-IS, since
  /// every renderer that ends up consuming them
  /// (`listingCachedNetworkImageProvider` / `listingNetworkImage` /
  /// `NetworkVideoThumbnailPreview` / `GalleryEmbeddedVideoPlayer`)
  /// already auto-detects and renders a local path directly.
  bool _isLocalMediaPath(String raw) => ListingImageMedia.localFile(raw) != null;

  String _resolveHeroMediaUrl(String raw) =>
      _isLocalMediaPath(raw) ? raw : buildLegacyFullImageUrl(raw);

  List<String> get _imageUrls {
    return _heroImageEntries.map((e) => e.url).toList(growable: false);
  }

  /// Listing (non-damage) images with optional car-detection metadata for hero crop.
  List<({String url, Map<String, dynamic>? meta})> get _heroImageEntries {
    final List<({String url, Map<String, dynamic>? meta})> entries = [];
    if (car == null) return entries;

    final List<dynamic> imgs =
        (car!['images'] is List) ? (car!['images'] as List) : const [];

    void addUrl(String raw, Map<String, dynamic>? meta) {
      if (raw.isEmpty) return;
      final full = _resolveHeroMediaUrl(raw);
      if (full.isEmpty) return;
      if (entries.any((e) => e.url == full)) return;
      entries.add((url: full, meta: meta));
    }

    Map<String, dynamic>? metaFrom(dynamic it) {
      if (it is! Map) return null;
      return Map<String, dynamic>.from(it);
    }

    bool isDamage(dynamic it) =>
        it is Map &&
        (it['kind'] ?? '').toString().toLowerCase() == 'damage';

    final String primary = (car!['image_url'] ?? '').toString();
    if (primary.isNotEmpty) {
      Map<String, dynamic>? primaryMeta;
      for (final dynamic it in imgs) {
        if (isDamage(it)) continue;
        final s = ListingImageMedia.source(it);
        if (s.isNotEmpty &&
            (buildLegacyFullImageUrl(s) == buildLegacyFullImageUrl(primary) ||
                s == primary)) {
          primaryMeta = metaFrom(it);
          break;
        }
      }
      // Listing-level detection metadata (rare) as fallback for primary.
      primaryMeta ??= () {
        final det = car!['car_detection'] ??
            car!['primary_car_bbox'] ??
            car!['hero_detection'];
        if (det == null) return null;
        return <String, dynamic>{'car_detection': det};
      }();
      addUrl(primary, primaryMeta);
    }

    for (final dynamic it in imgs) {
      if (isDamage(it)) continue;
      final s = ListingImageMedia.source(it);
      addUrl(s, metaFrom(it));
    }

    // If no explicit primary but images exist, first listing image is hero.
    if (entries.isEmpty && imgs.isNotEmpty) {
      for (final dynamic it in imgs) {
        if (isDamage(it)) continue;
        final s = ListingImageMedia.source(it);
        if (s.isNotEmpty) {
          addUrl(s, metaFrom(it));
          break;
        }
      }
    }

    return entries;
  }

  /// Normalizes API `videos` (strings and/or `{video_url: ...}` maps) to relative paths.
  static List<String> _normalizeVideoPaths(dynamic raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    final List<String> out = [];
    for (final dynamic it in raw) {
      String s = '';
      if (it is String) {
        s = it.trim();
      } else if (it is Map) {
        final map = Map<String, dynamic>.from(it);
        s = (map['video_url'] ?? map['url'] ?? map['path'] ?? map['source'] ?? '')
            .toString()
            .trim();
      } else {
        s = it.toString().trim();
      }
      if (s.isNotEmpty && !s.startsWith('{') && s != 'null') {
        out.add(s);
      }
    }
    return out;
  }

  Map<String, dynamic> _normalizeCarDetailMap(Map<String, dynamic> src) {
    final m = Map<String, dynamic>.from(src);
    m['videos'] = _normalizeVideoPaths(m['videos']);
    return m;
  }

  List<String> get _videoUrls {
    final List<String> urls = [];
    if (car == null) return urls;
    final paths = _normalizeVideoPaths(car!['videos']);
    for (final String s in paths) {
      final full = _resolveHeroMediaUrl(s);
      if (full.isNotEmpty && !urls.contains(full)) urls.add(full);
    }
    return urls;
  }

  int get _heroMediaCount => _imageUrls.length + _videoUrls.length;

  Widget _buildHeroVideoSlide(BuildContext context, int videoIndex) {
    final videoUrl = _videoUrls[videoIndex];
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        NetworkVideoThumbnailPreview(
          videoUrl: videoUrl,
          maxWidth: 720,
          timeMs: 800,
          fillParent: true,
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'VIDEO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            padding: EdgeInsets.all(14),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
          ),
        ),
      ],
    );
  }
}
