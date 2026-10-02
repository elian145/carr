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
    return _unwrapMapToString(item?.toString().trim() ?? '');
  }

  /// Dart [Map.toString] leak: `{source: /var/mobile/...}`.
  static String _unwrapMapToString(String raw) {
    if (raw.isEmpty) return '';
    if (raw.startsWith('{') && raw.contains('source:')) {
      final match = RegExp(r'source:\s*([^,}]+)').firstMatch(raw);
      final extracted = match?.group(1)?.trim() ?? '';
      if (extracted.isNotEmpty) return extracted;
    }
    return raw;
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
    String? previewSource,
    String? uiMediaId,
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
    // `preview_source` (HEIC/HEIF local-rendering fix): a locally-generated
    // JPEG copy consumed ONLY by `previewSource()`/`previewLocalFile()`
    // below -- never by `source()`/`localFile()`, so upload/submission
    // code is unaffected. Only set when explicitly provided; otherwise any
    // value already on `item` is preserved as-is (same "leave alone unless
    // explicitly overridden" behavior as every other field here), so a
    // preview generated at pick time survives later `map()` calls made for
    // unrelated reasons (e.g. the durable-copy step rewriting `source`).
    if (previewSource != null) {
      final trimmed = previewSource.trim();
      if (trimmed.isEmpty) {
        existing.remove('preview_source');
      } else {
        existing['preview_source'] = trimmed;
      }
    }
    // `_ui_media_id` (stale-media-after-delete fix): a LOCAL-only, UI-side
    // tracking identity -- deliberately NOT the same value or concept as
    // `SellMediaIdentity.forImageItem()`'s submission-time
    // `client_media_id` (that one is derived from the DURABLE source path
    // at submit time; this one is assigned once at PICK time, from the
    // original picker path PLUS a per-pick sequence number, specifically
    // so it survives every later `source` rewrite -- durable copy, blur
    // merge -- unchanged, and so re-picking the exact same file after
    // deleting it gets a genuinely NEW id, never the old one). Preserved
    // across `map()` calls unless explicitly overridden, exactly like
    // `preview_source` above -- see `sell_step4_logic.dart`'s pick
    // handlers (where it's first assigned) and `_removePhotoAt`/
    // `_syncMediaDraftToParent` (where it's used to detect and drop stale
    // entries for a since-deleted photo).
    if (uiMediaId != null) {
      final trimmed = uiMediaId.trim();
      if (trimmed.isEmpty) {
        existing.remove('_ui_media_id');
      } else {
        existing['_ui_media_id'] = trimmed;
      }
    }
    return existing;
  }

  /// See [map]'s `uiMediaId` doc comment above. `null` for anything that
  /// never went through a Sell-flow pick handler this session (e.g.
  /// pre-existing edit-mode server images) -- callers must treat a `null`
  /// id as "not tracked by this mechanism", never as "stale"/"unmatched".
  static String? uiMediaId(dynamic item) {
    if (item is! Map) return null;
    final raw = (item['_ui_media_id'] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  static Map<String, dynamic> withFocusY(dynamic item, double? focusY) => map(
    item,
    focusY: focusY,
    width: width(item),
    height: height(item),
    preserveFocus: false,
  );

  /// A locally-generated JPEG preview path for [item], if one exists --
  /// see `heic_preview_converter.dart`. This is ONLY ever populated for
  /// HEIC/HEIF originals that Flutter's own decoders can't render; for
  /// JPEG/PNG/etc. it's always absent (no conversion happens, no field is
  /// set). This is deliberately separate from [source]: it exists purely
  /// so local rendering (Step4 grid, blur-choice "Original photos" grid)
  /// has something Skia can display -- upload/submission must keep using
  /// [source]/[localFile], never this.
  static String? previewSource(dynamic item) {
    if (item is! Map) return null;
    final raw = (item['preview_source'] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  /// [previewSource] as an [XFile], falling back to [localFile] when no
  /// preview exists yet (JPEG/PNG originals, or a HEIC/HEIF original whose
  /// conversion hasn't finished/failed) -- so every existing call site that
  /// switches from [localFile] to this keeps rendering exactly as before
  /// for every case except "HEIC/HEIF preview is ready", which is strictly
  /// additive.
  static XFile? previewLocalFile(dynamic item) {
    final preview = previewSource(item);
    if (preview != null) return XFile(preview);
    return localFile(item);
  }

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

  /// Reconstructs local [XFile]s from picker files, path strings, or draft maps.
  static List<XFile> localFiles(Iterable<dynamic> items) {
    final out = <XFile>[];
    final seen = <String>{};
    for (final item in items) {
      final file = localFile(item);
      if (file == null) continue;
      final key = file.path;
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(file);
    }
    return out;
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
