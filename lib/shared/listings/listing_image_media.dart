import 'package:image_picker/image_picker.dart';
import 'package:flutter/painting.dart';

/// Backward-compatible helpers for listing photos represented as a String,
/// [XFile], or an API/draft metadata map.
abstract final class ListingImageMedia {
  static String source(dynamic item) {
    if (item is XFile) return item.path.trim();
    if (item is Map) {
      return (item['source'] ??
              item['image_url'] ??
              item['url'] ??
              item['path'] ??
              item['src'] ??
              '')
          .toString()
          .trim();
    }
    return item?.toString().trim() ?? '';
  }

  static int? id(dynamic item) {
    if (item is! Map) return null;
    final value = item['id'] ?? item['image_id'];
    return value is int ? value : int.tryParse(value?.toString() ?? '');
  }

  static double? focusY(dynamic item) {
    if (item is! Map) return null;
    final value = item['focus_y'] ?? item['focusY'];
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null || !parsed.isFinite) return null;
    return parsed.clamp(0.0, 1.0);
  }

  static int? width(dynamic item) =>
      _positiveInt(item is Map ? item['image_width'] ?? item['width'] : null);

  static int? height(dynamic item) =>
      _positiveInt(item is Map ? item['image_height'] ?? item['height'] : null);

  static int? _positiveInt(dynamic value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static Map<String, dynamic> map(
    dynamic item, {
    String? source,
    double? focusY,
    int? width,
    int? height,
    bool preserveFocus = true,
  }) {
    final existing = item is Map
        ? Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          )
        : <String, dynamic>{};
    final resolvedSource = source ?? ListingImageMedia.source(item);
    existing
      ..remove('url')
      ..remove('path')
      ..remove('src')
      ..['source'] = resolvedSource;
    if (focusY == null) {
      if (!preserveFocus) {
        existing.remove('focus_y');
        existing.remove('focusY');
      }
    } else {
      existing['focus_y'] = focusY.clamp(0.0, 1.0);
    }
    if (width != null && width > 0) existing['image_width'] = width;
    if (height != null && height > 0) existing['image_height'] = height;
    return existing;
  }

  static Map<String, dynamic> withFocusY(dynamic item, double? focusY) => map(
    item,
    focusY: focusY,
    width: width(item),
    height: height(item),
    preserveFocus: false,
  );

  static XFile? localFile(dynamic item) {
    if (item is XFile) return item;
    final raw = source(item);
    if (raw.isEmpty ||
        raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('uploads/') ||
        raw.startsWith('static/') ||
        raw.startsWith('/static/')) {
      return null;
    }
    return XFile(raw);
  }

  static Alignment coverAlignment(dynamic item) {
    final saved = focusY(item);
    if (saved != null) return Alignment(0, saved * 2 - 1);
    final w = width(item);
    final h = height(item);
    final portrait = w != null && h != null && h > w * 1.08;
    return portrait ? const Alignment(0, 0.4) : Alignment.center;
  }
}
