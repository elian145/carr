part of 'car_details_page.dart';

mixin _CarDetailsPageMedia on _CarDetailsPageOwner {
  List<String> get _imageUrls {
    final List<String> urls = [];
    if (car != null) {
      final String primary = (car!['image_url'] ?? '').toString();
      final List<dynamic> imgs = (car!['images'] is List)
          ? (car!['images'] as List)
          : const [];
      if (primary.isNotEmpty) {
        urls.add(buildLegacyFullImageUrl(primary));
      }
      for (final dynamic it in imgs) {
        if (it is Map &&
            (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
          continue;
        }
        String s;
        if (it is Map) {
          s = (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
              .toString();
        } else {
          s = it.toString();
        }
        if (s.isNotEmpty) {
          final full = buildLegacyFullImageUrl(s);
          if (!urls.contains(full)) urls.add(full);
        }
      }
      // If no explicit primary but images exist, treat first as primary
      if (urls.isEmpty && imgs.isNotEmpty) {
        final dynamic first = imgs.first;
        if (first is Map &&
            (first['kind'] ?? '').toString().toLowerCase() == 'damage') {
          // First row is damage-only; find first listing image for hero.
          for (final dynamic it in imgs) {
            if (it is Map &&
                (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
              continue;
            }
            final String s = it is Map
                ? (it['image_url'] ??
                          it['url'] ??
                          it['path'] ??
                          it['src'] ??
                          '')
                      .toString()
                : it.toString();
            if (s.isNotEmpty) {
              urls.add(buildLegacyFullImageUrl(s));
              break;
            }
          }
        } else {
          final String s = first is Map
              ? (first['image_url'] ??
                        first['url'] ??
                        first['path'] ??
                        first['src'] ??
                        '')
                    .toString()
              : first.toString();
          if (s.isNotEmpty) urls.add(buildLegacyFullImageUrl(s));
        }
      }
    }
    return urls;
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
        s = (map['video_url'] ?? map['url'] ?? map['path'] ?? '')
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
      final full = buildLegacyFullImageUrl(s);
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
