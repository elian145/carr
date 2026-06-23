import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import '../../shared/debug/app_log.dart';
import '../../shared/prefs/sell_draft_step.dart';

const String kSellDraftArchiveKey = 'legacy_sell_draft_archive_v1';

String newSellDraftId() => DateTime.now().microsecondsSinceEpoch.toString();

Map<String, dynamic> normalizeSellDraftSnapshot(Map<String, dynamic> raw) {
  final rawCarData = raw['carData'];
  final carData = rawCarData is Map
      ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
      : <String, dynamic>{};
  final draftId = (raw['draftId'] ?? '').toString().trim();
  return <String, dynamic>{
    'draftId': draftId.isEmpty ? newSellDraftId() : draftId,
    'currentStep': readSellDraftStepDynamic(raw['currentStep']),
    'carData': carData,
    'isPlaceholder': raw['isPlaceholder'] == true,
    'updatedAt': raw['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
  };
}

List<Map<String, dynamic>> decodeSellDraftArchive(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
  try {
    final decoded = json.decode(raw);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map(
          (item) => normalizeSellDraftSnapshot(
            Map<String, dynamic>.from(item.cast<String, dynamic>()),
          ),
        )
        .toList();
  } catch (e, st) {
    logNonFatal(e, st);
    return <Map<String, dynamic>>[];
  }
}

String encodeSellDraftArchive(List<Map<String, dynamic>> drafts) {
  return json.encode(
    drafts.map((draft) => normalizeSellDraftSnapshot(draft)).toList(),
  );
}

bool hasMeaningfulSellDraftValue(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is num) return value != 0;
  if (value is bool) return value;
  if (value is XFile) return value.path.trim().isNotEmpty;
  if (value is Map) {
    for (final entry in value.entries) {
      if (hasMeaningfulSellDraftValue(entry.value)) return true;
    }
    return false;
  }
  if (value is Iterable) {
    for (final item in value) {
      if (hasMeaningfulSellDraftValue(item)) return true;
    }
    return false;
  }
  return value.toString().trim().isNotEmpty;
}

bool isVisibleSellDraft(Map<String, dynamic> draft) {
  return hasMeaningfulSellDraftValue(draft['carData']);
}
