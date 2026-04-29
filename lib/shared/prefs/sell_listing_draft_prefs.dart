import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SellListingDraftPrefs {
  static const String _prefix = 'sell_listing_draft_v1_';
  static const String _globalKey = '$_prefixglobal';

  static String _safeOwnerKey(String ownerKey) {
    final trimmed = ownerKey.trim();
    final source = trimmed.isEmpty ? 'guest' : trimmed;
    return source.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  static String keyFor(String ownerKey) {
    return '$_prefix${_safeOwnerKey(ownerKey)}';
  }

  static Future<Map<String, dynamic>?> load(String ownerKey) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final candidates = <String>[
        _globalKey,
        keyFor(ownerKey),
      ];
      for (final key in candidates) {
        final raw = sp.getString(key);
        if (raw == null || raw.trim().isEmpty) continue;

        final decoded = json.decode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> save(
    String ownerKey,
    Map<String, dynamic> draft,
  ) async {
    final sp = await SharedPreferences.getInstance();
    final encoded = json.encode(draft);
    await sp.setString(_globalKey, encoded);
    await sp.setString(keyFor(ownerKey), encoded);
  }

  static Future<void> clear(String ownerKey) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_globalKey);
    await sp.remove(keyFor(ownerKey));
  }
}
