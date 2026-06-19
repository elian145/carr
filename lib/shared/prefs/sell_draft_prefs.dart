import 'package:shared_preferences/shared_preferences.dart';

/// Sell flow draft keys in [SharedPreferences].
///
/// Storage key strings retain the `legacy_sell_draft_*` prefix for upgrades from
/// older app builds.
class SellDraftPrefs {
  static const String currentStepKey = 'legacy_sell_draft_current_step_v1';
  static const String snapshotKey = 'legacy_sell_draft_snapshot_v1';
  static const String archiveKey = 'legacy_sell_draft_archive_v1';
  static const String step1Key = 'legacy_sell_draft_step1_v1';
  static const String step2Key = 'legacy_sell_draft_step2_v1';
  static const String step3Key = 'legacy_sell_draft_step3_v1';
  static const String step4Key = 'legacy_sell_draft_step4_v1';

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
}
