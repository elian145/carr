import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../debug/app_log.dart';
import '../listings/listing_image_media.dart';

/// Survives process death between [createCar] and finished media upload.
///
/// Without this, killing the app mid-submit leaves a server listing (no images)
/// plus the local draft (with images).
class SellPendingMediaPrefs {
  SellPendingMediaPrefs._();

  static const String prefsKey = 'legacy_sell_pending_media_v1';

  /// JSON-safe media item (XFile → path, Map → string/num fields only).
  static dynamic jsonSafeMediaItem(dynamic item) {
    if (item == null) return null;
    if (item is String || item is num || item is bool) return item;
    if (item is XFile) {
      final path = item.path.trim();
      return path.isEmpty ? null : path;
    }
    if (item is Map) {
      final source = ListingImageMedia.source(item);
      if (source.isEmpty) return null;
      final out = <String, dynamic>{'source': source};
      final id = ListingImageMedia.id(item);
      if (id != null) out['id'] = id;
      final focus = ListingImageMedia.focusY(item);
      if (focus != null) out['focus_y'] = focus;
      final width = ListingImageMedia.width(item);
      if (width != null) out['image_width'] = width;
      final height = ListingImageMedia.height(item);
      if (height != null) out['image_height'] = height;
      return out;
    }
    final asString = item.toString().trim();
    return asString.isEmpty ? null : asString;
  }

  static List<dynamic> jsonSafeMediaList(dynamic raw) {
    if (raw is! List) return const <dynamic>[];
    final out = <dynamic>[];
    for (final item in raw) {
      final safe = jsonSafeMediaItem(item);
      if (safe != null) out.add(safe);
    }
    return out;
  }

  static Future<Map<String, dynamic>?> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(prefsKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = json.decode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      final carId = (map['carId'] ?? '').toString().trim();
      if (carId.isEmpty) return null;
      return map;
    } catch (e, st) {
      logNonFatal(e, st);
      return null;
    }
  }

  static Future<void> save({
    required String carId,
    required String draftId,
    required Map<String, dynamic> carData,
    bool pendingReview = false,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'carId': carId.trim(),
      'draftId': draftId.trim(),
      'pendingReview': pendingReview,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'carData': <String, dynamic>{
        'images': jsonSafeMediaList(carData['images']),
        'damage_images': jsonSafeMediaList(carData['damage_images']),
        'videos': jsonSafeMediaList(carData['videos']),
        'primary_image_index': carData['primary_image_index'],
      },
    };
    await sp.setString(prefsKey, json.encode(payload));
  }

  static Future<void> clear() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(prefsKey);
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  /// Stable Idempotency-Key so a killed create + retry does not duplicate.
  static String createIdempotencyKey(String draftId) {
    final id = draftId.trim();
    if (id.isEmpty) {
      return 'sell-create-${DateTime.now().microsecondsSinceEpoch}';
    }
    return 'sell-create-$id';
  }
}
