import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Sell flow draft keys and persistence in [SharedPreferences].
///
/// Two storage layers share this module (key strings unchanged for upgrades):
/// - **Step scratch / archive** — `legacy_sell_draft_*` keys for multi-step UI state.
/// - **Per-owner listing draft** — `sell_listing_draft_v1_*` JSON snapshot for resume.
class SellDraftPrefs {
  static const String currentStepKey = 'legacy_sell_draft_current_step_v1';
  static const String snapshotKey = 'legacy_sell_draft_snapshot_v1';
  static const String archiveKey = 'legacy_sell_draft_archive_v1';
  static const String step1Key = 'legacy_sell_draft_step1_v1';
  static const String step2Key = 'legacy_sell_draft_step2_v1';
  static const String step3Key = 'legacy_sell_draft_step3_v1';
  static const String step4Key = 'legacy_sell_draft_step4_v1';

  static const String _listingDraftPrefix = 'sell_listing_draft_v1_';
  static const String _listingDraftGlobalKey = '${_listingDraftPrefix}global';

  /// While true, step pages must not persist draft data on [State.dispose].
  static bool suppressPersist = false;

  /// Clears per-step scratch storage (photos, fields) without touching the archive.
  static Future<void> clearActiveStepStorage() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(currentStepKey);
    await sp.remove(step1Key);
    await sp.remove(step2Key);
    await sp.remove(step3Key);
    await sp.remove(step4Key);
  }

  /// Clears the in-progress snapshot and step scratch storage (not the archive).
  static Future<void> clearActiveStorage() async {
    final sp = await SharedPreferences.getInstance();
    await clearActiveStepStorage();
    await sp.remove(snapshotKey);
  }

  /// Blocks dispose-time re-save and clears step scratch so a new listing starts empty.
  static Future<void> beginFreshListing() async {
    suppressPersist = true;
    await clearActiveStepStorage();
  }

  static void allowPersist() {
    suppressPersist = false;
  }

  static String _safeOwnerKey(String ownerKey) {
    final trimmed = ownerKey.trim();
    final source = trimmed.isEmpty ? 'guest' : trimmed;
    return source.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  static String listingDraftKeyFor(String ownerKey) {
    return '$_listingDraftPrefix${_safeOwnerKey(ownerKey)}';
  }

  static Future<Map<String, dynamic>?> loadListingDraft(String ownerKey) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final candidates = <String>[
        _listingDraftGlobalKey,
        listingDraftKeyFor(ownerKey),
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

  static Future<void> saveListingDraft(
    String ownerKey,
    Map<String, dynamic> draft,
  ) async {
    final sp = await SharedPreferences.getInstance();
    final encoded = json.encode(draft);
    await sp.setString(_listingDraftGlobalKey, encoded);
    await sp.setString(listingDraftKeyFor(ownerKey), encoded);
  }

  static Future<void> clearListingDraft(String ownerKey) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_listingDraftGlobalKey);
    await sp.remove(listingDraftKeyFor(ownerKey));
  }
}
