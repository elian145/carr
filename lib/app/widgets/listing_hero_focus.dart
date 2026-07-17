import 'package:flutter/painting.dart';

import '../../shared/listings/listing_image_media.dart';

/// Default CSS-equivalent of `object-position: center 70%`.
///
/// Flutter [Alignment] maps 0% → -1 and 100% → 1, so 70% → 0.4.
const Alignment kListingHeroObjectPosition = Alignment(0, 0.4);

/// Normalized vehicle box in image space: left/top/width/height in `0..1`.
class ListingHeroCarBBox {
  const ListingHeroCarBBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Rect get asRect => Rect.fromLTWH(left, top, width, height);

  Alignment get centerAlignment {
    final cx = (left + width / 2).clamp(0.0, 1.0);
    final cy = (top + height / 2).clamp(0.0, 1.0);
    return Alignment(cx * 2 - 1, cy * 2 - 1);
  }
}

/// Expand [box] by [paddingFraction] of its own size on each side, clamped to
/// the unit square.
ListingHeroCarBBox expandCarBBox(
  ListingHeroCarBBox box, {
  double paddingFraction = 0.08,
}) {
  final padX = box.width * paddingFraction;
  final padY = box.height * paddingFraction;
  var left = box.left - padX;
  var top = box.top - padY;
  var right = box.left + box.width + padX;
  var bottom = box.top + box.height + padY;

  left = left.clamp(0.0, 1.0);
  top = top.clamp(0.0, 1.0);
  right = right.clamp(0.0, 1.0);
  bottom = bottom.clamp(0.0, 1.0);

  final w = (right - left).clamp(0.0, 1.0);
  final h = (bottom - top).clamp(0.0, 1.0);
  return ListingHeroCarBBox(left: left, top: top, width: w, height: h);
}

/// Compute a cover crop (normalized `0..1`) that keeps the padded car inside
/// the frame, targets ~80% vehicle fill height, and prefers cutting sky.
Rect resolveHeroCoverSourceRect({
  required double viewportAspect,
  required ListingHeroCarBBox carBBox,
  double paddingFraction = 0.08,
  double targetCarHeightFill = 0.80,
  double minCarHeightFill = 0.70,
  double maxCarHeightFill = 0.90,
}) {
  assert(viewportAspect > 0);
  final padded = expandCarBBox(carBBox, paddingFraction: paddingFraction);
  final fill = targetCarHeightFill.clamp(minCarHeightFill, maxCarHeightFill);

  // Ideal crop sized so the padded car is ~[fill] of visible height.
  var cropH = (padded.height / fill).clamp(padded.height, 1.0);
  var cropW = cropH * viewportAspect;

  if (cropW < padded.width) {
    cropW = padded.width.clamp(0.0, 1.0);
    cropH = (cropW / viewportAspect).clamp(padded.height, 1.0);
    if (cropH * viewportAspect < padded.width) {
      cropW = padded.width.clamp(0.0, 1.0);
      cropH = (cropW / viewportAspect).clamp(0.0, 1.0);
    }
  }

  if (cropW > 1.0) {
    cropW = 1.0;
    cropH = (cropW / viewportAspect).clamp(0.0, 1.0);
  }
  if (cropH > 1.0) {
    cropH = 1.0;
    cropW = (cropH * viewportAspect).clamp(0.0, 1.0);
  }

  // Center on the car, then shift to keep the full padded box visible.
  var left = padded.left + padded.width / 2 - cropW / 2;
  var top = padded.top + padded.height / 2 - cropH / 2;

  if (left > padded.left) left = padded.left;
  if (left + cropW < padded.left + padded.width) {
    left = padded.left + padded.width - cropW;
  }
  if (top > padded.top) top = padded.top;
  if (top + cropH < padded.top + padded.height) {
    top = padded.top + padded.height - cropH;
  }

  // Prefer cropping sky: when clamping vertically, stick to the bottom first.
  if (top < 0) top = 0;
  if (top + cropH > 1.0) top = 1.0 - cropH;
  if (left < 0) left = 0;
  if (left + cropW > 1.0) left = 1.0 - cropW;

  return Rect.fromLTWH(
    left.clamp(0.0, 1.0),
    top.clamp(0.0, 1.0),
    cropW.clamp(0.0, 1.0),
    cropH.clamp(0.0, 1.0),
  );
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

ListingHeroCarBBox? _bboxFromNumbers({
  required double? left,
  required double? top,
  required double? width,
  required double? height,
  required double? right,
  required double? bottom,
  double? imageWidth,
  double? imageHeight,
}) {
  double? l = left;
  double? t = top;
  double? w = width;
  double? h = height;

  if ((l == null || t == null) && right != null && bottom != null) {
    // May be x,y,w,h already via width/height; otherwise ltrb.
  }

  if (l != null && t != null && right != null && bottom != null && w == null) {
    w = right - l;
    h = bottom - t;
  }

  if (l == null || t == null || w == null || h == null) return null;
  if (w <= 0 || h <= 0) return null;

  // Pixel → normalized when values look like pixels.
  final looksLikePixels = (imageWidth != null && imageHeight != null)
      ? (l > 1.5 || t > 1.5 || w > 1.5 || h > 1.5)
      : (l > 1.5 || t > 1.5 || w > 1.5 || h > 1.5);
  if (looksLikePixels) {
    final iw = imageWidth ?? 1.0;
    final ih = imageHeight != null && imageHeight > 0
        ? imageHeight
        : (imageWidth ?? 1.0);
    if (iw <= 0 || ih <= 0) return null;
    l /= iw;
    t /= ih;
    w /= iw;
    h /= ih;
  }

  l = l.clamp(0.0, 1.0);
  t = t.clamp(0.0, 1.0);
  w = w.clamp(0.0, 1.0 - l);
  h = h.clamp(0.0, 1.0 - t);
  if (w <= 0.01 || h <= 0.01) return null;
  return ListingHeroCarBBox(left: l, top: t, width: w, height: h);
}

ListingHeroCarBBox? _parseBBoxMap(
  Map raw, {
  double? imageWidth,
  double? imageHeight,
}) {
  final map = Map<String, dynamic>.from(raw);
  final img = map['image'];
  if (img is Map) {
    imageWidth ??= _asDouble(img['width']);
    imageHeight ??= _asDouble(img['height']);
  }
  imageWidth ??= _asDouble(map['image_width'] ?? map['img_width']);
  imageHeight ??= _asDouble(map['image_height'] ?? map['img_height']);

  final w = _asDouble(map['width'] ?? map['w']);
  final h = _asDouble(map['height'] ?? map['h']);
  final looksCentered =
      map.containsKey('center_x') ||
      map.containsKey('cx') ||
      map.containsKey('center_y') ||
      map.containsKey('cy') ||
      map['format']?.toString() == 'center' ||
      (map.containsKey('confidence') &&
          map.containsKey('class') &&
          map.containsKey('x') &&
          map.containsKey('y'));

  if (looksCentered && w != null && h != null) {
    final cx = _asDouble(map['center_x'] ?? map['cx'] ?? map['x']);
    final cy = _asDouble(map['center_y'] ?? map['cy'] ?? map['y']);
    if (cx != null && cy != null) {
      return _bboxFromNumbers(
        left: cx - w / 2,
        top: cy - h / 2,
        width: w,
        height: h,
        right: null,
        bottom: null,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    }
  }

  return _bboxFromNumbers(
    left: _asDouble(map['left'] ?? map['x'] ?? map['xmin']),
    top: _asDouble(map['top'] ?? map['y'] ?? map['ymin']),
    width: w,
    height: h,
    right: _asDouble(map['right'] ?? map['xmax']),
    bottom: _asDouble(map['bottom'] ?? map['ymax']),
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  );
}

ListingHeroCarBBox? _parseBBoxList(
  List raw, {
  double? imageWidth,
  double? imageHeight,
}) {
  if (raw.length < 4) return null;
  final a = _asDouble(raw[0]);
  final b = _asDouble(raw[1]);
  final c = _asDouble(raw[2]);
  final d = _asDouble(raw[3]);
  if (a == null || b == null || c == null || d == null) return null;

  // Prefer [l,t,w,h] unless [l,t,r,b] is the only plausible reading.
  final asWh = _bboxFromNumbers(
    left: a,
    top: b,
    width: c,
    height: d,
    right: null,
    bottom: null,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  );
  if (asWh != null) return asWh;

  return _bboxFromNumbers(
    left: a,
    top: b,
    width: null,
    height: null,
    right: c,
    bottom: d,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  );
}

/// Best-effort parse of car-detection metadata from a listing image map / JSON.
ListingHeroCarBBox? parseListingHeroCarBBox(dynamic source) {
  if (source == null) return null;

  if (source is ListingHeroCarBBox) return source;

  if (source is List) {
    return _parseBBoxList(source);
  }

  if (source is! Map) return null;
  final map = Map<String, dynamic>.from(source);

  final imageWidth = _asDouble(map['image_width'] ?? map['img_width']);
  final imageHeight = _asDouble(map['image_height'] ?? map['img_height']);

  const keys = <String>[
    'car_detection',
    'car_bbox',
    'vehicle_bbox',
    'subject_bbox',
    'detection',
    'bbox',
    'object_bbox',
    'detected_car',
  ];

  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    if (value is Map) {
      final parsed = _parseBBoxMap(
        value,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      if (parsed != null) return parsed;
      // Nested predictions list (Roboflow-style).
      final preds = value['predictions'];
      if (preds is List && preds.isNotEmpty) {
        final first = preds.first;
        if (first is Map) {
          final p = _parseBBoxMap(
            first,
            imageWidth:
                imageWidth ??
                _asDouble(
                  (value['image'] is Map) ? value['image']['width'] : null,
                ),
            imageHeight:
                imageHeight ??
                _asDouble(
                  (value['image'] is Map) ? value['image']['height'] : null,
                ),
          );
          if (p != null) return p;
        }
      }
    } else if (value is List) {
      final parsed = _parseBBoxList(
        value,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      if (parsed != null) return parsed;
    }
  }

  // Direct bbox fields on the image object.
  final direct = _parseBBoxMap(
    map,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  );
  if (direct != null &&
      (map.containsKey('left') ||
          map.containsKey('xmin') ||
          map.containsKey('bbox_left') ||
          (map.containsKey('width') &&
              map.containsKey('height') &&
              map.containsKey('x')))) {
    return direct;
  }

  return null;
}

/// Focus point alignment from metadata, else [kListingHeroObjectPosition].
Alignment listingHeroAlignmentFor(dynamic source) {
  // A seller's explicit crop always wins over detection metadata.
  if (ListingImageMedia.focusY(source) != null) {
    return ListingImageMedia.coverAlignment(source);
  }

  final bbox = parseListingHeroCarBBox(source);
  if (bbox != null) return bbox.centerAlignment;

  if (source is Map) {
    final map = Map<String, dynamic>.from(source);
    for (final key in [
      'object_position',
      'focus',
      'focus_point',
      'crop_focus',
    ]) {
      final value = map[key];
      if (value is Map) {
        final x = _asDouble(value['x']);
        final y = _asDouble(value['y']);
        if (x != null && y != null) {
          final nx = x > 1.0 ? 0.5 : x; // ignore invalid
          final ny = y > 1.0 ? 0.7 : y;
          return Alignment(
            nx.clamp(0.0, 1.0) * 2 - 1,
            ny.clamp(0.0, 1.0) * 2 - 1,
          );
        }
      }
    }
    final fy = _asDouble(map['focus_y'] ?? map['object_position_y']);
    final fx = _asDouble(map['focus_x'] ?? map['object_position_x']);
    if (fy != null) {
      final nx = (fx ?? 0.5).clamp(0.0, 1.0);
      final ny = fy.clamp(0.0, 1.0);
      return Alignment(nx * 2 - 1, ny * 2 - 1);
    }
  }

  if (ListingImageMedia.width(source) != null &&
      ListingImageMedia.height(source) != null) {
    return ListingImageMedia.coverAlignment(source);
  }
  return Alignment.center;
}
