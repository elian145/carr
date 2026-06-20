import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../sell/sell_draft_archive.dart';
import 'sell_draft_prefs.dart';

/// Loads and manages sell drafts (active snapshot + archive).
class SellDraftList {
  SellDraftList._();

  static int readStep(dynamic raw, {int maxIdx = 4}) =>
      SellDraftArchive.readStep(raw, maxIdx: maxIdx);

  static Map<String, dynamic> normalize(Map<String, dynamic> raw) {
    final base = SellDraftArchive.normalizeSnapshot(raw);
    if (raw['isActive'] == true) {
      return <String, dynamic>{...base, 'isActive': true};
    }
    return base;
  }

  static bool isVisible(Map<String, dynamic> draft) =>
      SellDraftArchive.isVisibleDraft(draft);

  /// Active + archived drafts with content, newest first.
  static Future<List<Map<String, dynamic>>> loadVisible() async {
    final sp = await SharedPreferences.getInstance();
    final drafts = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    final activeRaw = sp.getString(SellDraftPrefs.snapshotKey);
    if (activeRaw != null && activeRaw.trim().isNotEmpty) {
      try {
        final decoded = json.decode(activeRaw);
        if (decoded is Map) {
          final active = normalize(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
          if (isVisible(active)) {
            final prefsStep = sp.getInt(SellDraftPrefs.currentStepKey);
            active['currentStep'] = SellDraftArchive.mergeStep(
              jsonStep: readStep(active['currentStep']),
              prefsStep: prefsStep,
            );
            drafts.add(<String, dynamic>{...active, 'isActive': true});
            seenIds.add(active['draftId'].toString());
          }
        }
      } catch (_) {}
    }

    for (final draft
        in SellDraftArchive.decodeArchive(sp.getString(SellDraftPrefs.archiveKey))) {
      if (!isVisible(draft)) continue;
      final id = draft['draftId'].toString();
      if (seenIds.contains(id)) continue;
      drafts.add(<String, dynamic>{...draft, 'isActive': false});
      seenIds.add(id);
    }

    return drafts;
  }

  static Future<void> discard(Map<String, dynamic> draft) async {
    final draftId = (draft['draftId'] ?? '').toString();
    final isActive = draft['isActive'] == true;
    final sp = await SharedPreferences.getInstance();
    if (isActive) {
      await SellDraftPrefs.clearActiveStorage();
      return;
    }
    final archive =
        SellDraftArchive.decodeArchive(sp.getString(SellDraftPrefs.archiveKey));
    archive.removeWhere((item) => item['draftId'] == draftId);
    await sp.setString(
      SellDraftPrefs.archiveKey,
      SellDraftArchive.encodeArchive(archive),
    );
  }

  /// Promotes an archived draft to active (when opening from My Listings).
  static Future<Map<String, dynamic>> prepareForResume(
    Map<String, dynamic> draft,
  ) async {
    final normalized = normalize(Map<String, dynamic>.from(draft));
    final sp = await SharedPreferences.getInstance();

    if (draft['isActive'] != true) {
      final activeRaw = sp.getString(SellDraftPrefs.snapshotKey);
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        try {
          final decoded = json.decode(activeRaw);
          if (decoded is Map) {
            final active = normalize(
              Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
            );
            if (isVisible(active)) {
              final archive = SellDraftArchive.decodeArchive(
                sp.getString(SellDraftPrefs.archiveKey),
              );
              archive.removeWhere(
                (item) => item['draftId'] == active['draftId'],
              );
              archive.insert(0, active);
              await sp.setString(
                SellDraftPrefs.archiveKey,
                SellDraftArchive.encodeArchive(archive),
              );
            }
          }
        } catch (_) {}
      }

      final archive =
          SellDraftArchive.decodeArchive(sp.getString(SellDraftPrefs.archiveKey));
      archive.removeWhere((item) => item['draftId'] == normalized['draftId']);
      await sp.setString(
        SellDraftPrefs.archiveKey,
        SellDraftArchive.encodeArchive(archive),
      );
      await sp.setString(
        SellDraftPrefs.snapshotKey,
        json.encode(normalized),
      );
      normalized['isActive'] = true;
    }

    final prefsStep = sp.getInt(SellDraftPrefs.currentStepKey);
    normalized['currentStep'] = SellDraftArchive.mergeStep(
      jsonStep: readStep(normalized['currentStep']),
      prefsStep: prefsStep,
    );
    return normalized;
  }
}
