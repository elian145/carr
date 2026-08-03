import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../debug/app_log.dart';

/// Survives process death between [createCar] and finished media upload.
///
/// Without this, killing the app mid-submit leaves a server listing (no images)
/// plus the local draft (with images).
class SellPendingMediaPrefs {
  SellPendingMediaPrefs._();

  static const String prefsKey = 'legacy_sell_pending_media_v1';

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
        'images': carData['images'],
        'damage_images': carData['damage_images'],
        'videos': carData['videos'],
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
