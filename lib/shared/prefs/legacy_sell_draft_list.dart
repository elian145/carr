import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'legacy_sell_draft_prefs.dart';
import 'sell_draft_step.dart';

/// Loads and manages multiple legacy sell drafts (active + archive).
class LegacySellDraftList {
  LegacySellDraftList._();

  static String _newDraftId() => DateTime.now().microsecondsSinceEpoch.toString();

  static int readStep(dynamic raw, {int maxIdx = 4}) =>
      readSellDraftStepDynamic(raw, maxIdx: maxIdx);

  static int _mergeStep({required int jsonStep, int? prefsStep}) =>
      mergeSellDraftStep(jsonStep: jsonStep, prefsStep: prefsStep);

  static Map<String, dynamic> normalize(Map<String, dynamic> raw) {
    final rawCarData = raw['carData'];
    final carData = rawCarData is Map
        ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
        : <String, dynamic>{};
    final draftId = (raw['draftId'] ?? '').toString().trim();
    return <String, dynamic>{
      'draftId': draftId.isEmpty ? _newDraftId() : draftId,
      'currentStep': readStep(raw['currentStep']),
      'carData': carData,
      'isPlaceholder': raw['isPlaceholder'] == true,
      'updatedAt': raw['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      if (raw['isActive'] == true) 'isActive': true,
    };
  }

  static bool _hasMeaningfulValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is num) return value != 0;
    if (value is bool) return value;
    if (value is XFile) return value.path.trim().isNotEmpty;
    if (value is Map) {
      for (final entry in value.entries) {
        if (_hasMeaningfulValue(entry.value)) return true;
      }
      return false;
    }
    if (value is Iterable) {
      for (final item in value) {
        if (_hasMeaningfulValue(item)) return true;
      }
      return false;
    }
    return value.toString().trim().isNotEmpty;
  }

  static bool isVisible(Map<String, dynamic> draft) {
    return _hasMeaningfulValue(draft['carData']);
  }

  static List<Map<String, dynamic>> _decodeArchive(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => normalize(
              Map<String, dynamic>.from(item.cast<String, dynamic>()),
            ),
          )
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static String _encodeArchive(List<Map<String, dynamic>> drafts) {
    return json.encode(drafts.map(normalize).toList());
  }

  /// Active + archived drafts with content, newest first.
  static Future<List<Map<String, dynamic>>> loadVisible() async {
    final sp = await SharedPreferences.getInstance();
    final drafts = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    final activeRaw = sp.getString(LegacySellDraftPrefs.snapshotKey);
    if (activeRaw != null && activeRaw.trim().isNotEmpty) {
      try {
        final decoded = json.decode(activeRaw);
        if (decoded is Map) {
          final active = normalize(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
          if (isVisible(active)) {
            final prefsStep = sp.getInt(LegacySellDraftPrefs.currentStepKey);
            active['currentStep'] = _mergeStep(
              jsonStep: readStep(active['currentStep']),
              prefsStep: prefsStep,
            );
            drafts.add(<String, dynamic>{...active, 'isActive': true});
            seenIds.add(active['draftId'].toString());
          }
        }
      } catch (_) {}
    }

    for (final draft in _decodeArchive(sp.getString(LegacySellDraftPrefs.archiveKey))) {
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
      await LegacySellDraftPrefs.clearActiveStorage();
      return;
    }
    final archive = _decodeArchive(sp.getString(LegacySellDraftPrefs.archiveKey));
    archive.removeWhere((item) => item['draftId'] == draftId);
    await sp.setString(LegacySellDraftPrefs.archiveKey, _encodeArchive(archive));
  }

  /// Promotes an archived draft to active (when opening from My Listings).
  static Future<Map<String, dynamic>> prepareForResume(
    Map<String, dynamic> draft,
  ) async {
    final normalized = normalize(Map<String, dynamic>.from(draft));
    final sp = await SharedPreferences.getInstance();

    if (draft['isActive'] != true) {
      final activeRaw = sp.getString(LegacySellDraftPrefs.snapshotKey);
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        try {
          final decoded = json.decode(activeRaw);
          if (decoded is Map) {
            final active = normalize(
              Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
            );
            if (isVisible(active)) {
              final archive =
                  _decodeArchive(sp.getString(LegacySellDraftPrefs.archiveKey));
              archive.removeWhere(
                (item) => item['draftId'] == active['draftId'],
              );
              archive.insert(0, active);
              await sp.setString(
                LegacySellDraftPrefs.archiveKey,
                _encodeArchive(archive),
              );
            }
          }
        } catch (_) {}
      }

      final archive =
          _decodeArchive(sp.getString(LegacySellDraftPrefs.archiveKey));
      archive.removeWhere((item) => item['draftId'] == normalized['draftId']);
      await sp.setString(LegacySellDraftPrefs.archiveKey, _encodeArchive(archive));
      await sp.setString(
        LegacySellDraftPrefs.snapshotKey,
        json.encode(normalized),
      );
      normalized['isActive'] = true;
    }

    final prefsStep = sp.getInt(LegacySellDraftPrefs.currentStepKey);
    normalized['currentStep'] = _mergeStep(
      jsonStep: readStep(normalized['currentStep']),
      prefsStep: prefsStep,
    );
    return normalized;
  }
}
