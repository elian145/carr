import 'dart:convert';
import 'dart:math' as math;

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prefs/sell_draft_prefs.dart';

/// Sell draft archive helpers (SharedPreferences keys in [SellDraftPrefs]).
class SellDraftArchive {
  SellDraftArchive._();

  static String newDraftId() => DateTime.now().microsecondsSinceEpoch.toString();

  static int readStep(dynamic raw, {int maxIdx = 4}) {
    if (raw == null) return 0;
    if (raw is int) return raw.clamp(0, maxIdx);
    if (raw is double) {
      if (raw.isNaN || raw.isInfinite) return 0;
      return raw.round().clamp(0, maxIdx);
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return 0;
    final asDouble = double.tryParse(s);
    if (asDouble != null) return asDouble.round().clamp(0, maxIdx);
    return int.tryParse(s)?.clamp(0, maxIdx) ?? 0;
  }

  static int mergeStep({int? jsonStep, int? prefsStep}) {
    const maxIdx = 4;
    final j = (jsonStep ?? 0).clamp(0, maxIdx);
    if (prefsStep == null) return j;
    final p = prefsStep.clamp(0, maxIdx);
    return j > p ? j : p;
  }

  static Map<String, dynamic> normalizeSnapshot(Map<String, dynamic> raw) {
    final rawCarData = raw['carData'];
    final carData = rawCarData is Map
        ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
        : <String, dynamic>{};
    final draftId = (raw['draftId'] ?? '').toString().trim();
    return <String, dynamic>{
      'draftId': draftId.isEmpty ? newDraftId() : draftId,
      'currentStep': readStep(raw['currentStep']),
      'carData': carData,
      'isPlaceholder': raw['isPlaceholder'] == true,
      'updatedAt': raw['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
    };
  }

  static List<Map<String, dynamic>> decodeArchive(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => normalizeSnapshot(
              Map<String, dynamic>.from(item.cast<String, dynamic>()),
            ),
          )
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static String encodeArchive(List<Map<String, dynamic>> drafts) {
    return json.encode(
      drafts.map((draft) => normalizeSnapshot(draft)).toList(),
    );
  }

  static bool hasMeaningfulValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is num) return value != 0;
    if (value is bool) return value;
    if (value is XFile) return value.path.trim().isNotEmpty;
    if (value is Map) {
      for (final entry in value.entries) {
        if (hasMeaningfulValue(entry.value)) return true;
      }
      return false;
    }
    if (value is Iterable) {
      for (final item in value) {
        if (hasMeaningfulValue(item)) return true;
      }
      return false;
    }
    return value.toString().trim().isNotEmpty;
  }

  static bool isVisibleDraft(Map<String, dynamic> draft) {
    return hasMeaningfulValue(draft['carData']);
  }

  static int maxStep(int a, int b, [int c = 0]) {
    const maxIdx = 4;
    return math.max(
      math.max(a.clamp(0, maxIdx), b.clamp(0, maxIdx)),
      c.clamp(0, maxIdx),
    );
  }

  static Future<bool> hasAnyVisibleDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final activeRaw = sp.getString(SellDraftPrefs.snapshotKey);
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        final decoded = json.decode(activeRaw);
        if (decoded is Map) {
          final active = normalizeSnapshot(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
          if (isVisibleDraft(active)) return true;
        }
      }
      final archive = decodeArchive(sp.getString(SellDraftPrefs.archiveKey));
      return archive.any(isVisibleDraft);
    } catch (_) {
      return false;
    }
  }
}
