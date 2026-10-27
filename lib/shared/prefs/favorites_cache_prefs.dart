import 'package:shared_preferences/shared_preferences.dart';

import '../debug/app_log.dart';

/// Per-account on-device snapshot of the favorites list (F-34 follow-up).
///
/// The snapshot used to live under ONE global key (`cache_favorites`), so the
/// next account to open Favorites briefly saw the previous account's cars. It
/// is now keyed by the verified account id; the old global key is deleted and
/// never read.
class FavoritesCachePrefs {
  FavoritesCachePrefs._();

  /// Former global key. Only ever deleted.
  static const String legacyKey = 'cache_favorites';

  static const String _prefix = 'cache_favorites_v2:';

  static String keyForOwner(String ownerId) => '$_prefix$ownerId';

  static Future<void> _dropLegacy(SharedPreferences sp) async {
    if (sp.containsKey(legacyKey)) await sp.remove(legacyKey);
  }

  /// Cached JSON for [ownerId]; null for a missing/unverified owner.
  static Future<String?> read(String? ownerId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await _dropLegacy(sp);
      if (ownerId == null || ownerId.isEmpty) return null;
      return sp.getString(keyForOwner(ownerId));
    } catch (e, st) {
      logNonFatal(e, st);
      return null;
    }
  }

  static Future<void> write(String? ownerId, String json) async {
    if (ownerId == null || ownerId.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(keyForOwner(ownerId), json);
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  static Future<void> purgeOwner(String ownerId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(keyForOwner(ownerId));
  }

  /// Deletes the pre-isolation global snapshot (app start / upgrade).
  static Future<void> purgeLegacyUnowned() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await _dropLegacy(sp);
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }
}
