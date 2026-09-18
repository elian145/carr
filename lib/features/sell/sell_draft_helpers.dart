import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/car_name_translations.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/prefs/sell_draft_step.dart';

const String kSellDraftArchiveKey = 'legacy_sell_draft_archive_v1';

String newSellDraftId() => DateTime.now().microsecondsSinceEpoch.toString();

/// Keys that are set by the wizard shell even when the user has entered no
/// listing content. Alone they must not make a draft appear as "in progress".
const Set<String> kSellDraftMetaCarDataKeys = {
  'sell_wizard_v2',
  'images_processed',
  'primary_image_index',
  'use_blurred_plates',
  'processed_image_paths',
};

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

bool hasMeaningfulSellDraftValue(dynamic value, {String? key}) {
  if (key != null && kSellDraftMetaCarDataKeys.contains(key)) {
    return false;
  }
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is num) return value != 0;
  if (value is bool) return value;
  if (value is XFile) return value.path.trim().isNotEmpty;
  if (value is Map) {
    for (final entry in value.entries) {
      if (hasMeaningfulSellDraftValue(
        entry.value,
        key: entry.key.toString(),
      )) {
        return true;
      }
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
  if (draft['isPlaceholder'] == true) return false;
  return hasMeaningfulSellDraftValue(draft['carData']);
}

/// Localized "Brand Model • Trim Year" title for a Sell Draft card/banner
/// (Continue Draft gate, in-wizard draft banner, My Listings drafts filter).
///
/// MT-11 device QA found draft cards showing the English catalog brand/model
/// even when the app locale is Arabic/Kurdish (e.g. "Toyota Avalon • TRD •
/// 2022"), because each draft-card site concatenated the raw `brand`/`model`
/// strings from `carData` directly instead of localizing them.
///
/// Drafts persist `carData['brand']`/`carData['model']` as the same English
/// catalog labels [CarNameTranslations] already keys its Arabic/Kurdish
/// lookups by (see `sell_step1_catalog.dart`), so no draft-schema change is
/// needed -- this reuses the exact same [CarNameTranslations.getLocalizedBrand]
/// / [CarNameTranslations.getLocalizedModel] helpers that published listing
/// cards (`global_listing_card.dart`) and the car details page
/// (`car_details_page_titles.dart`) already use, instead of duplicating
/// localization logic inline in each draft widget.
///
/// `trim` (e.g. "TRD", "GX", "LX600") and `year` are kept verbatim, matching
/// every other title helper in the app (`car_details_page_titles.dart`,
/// `chat_shared.dart`'s `localizedListingTitle`) -- trim values are proper
/// product names, not translated anywhere in CarNet today.
String localizedSellDraftTitle(
  BuildContext context,
  Map<String, dynamic> carData,
) {
  final brand = (carData['brand'] ?? '').toString().trim();
  final model = (carData['model'] ?? '').toString().trim();
  final trim = (carData['trim'] ?? '').toString().trim();
  final year = (carData['year'] ?? '').toString().trim();

  final locBrand = CarNameTranslations.getLocalizedBrand(
    context,
    brand.isEmpty ? null : brand,
  );
  final locModel = CarNameTranslations.getLocalizedModel(
    context,
    brand.isEmpty ? null : brand,
    model.isEmpty ? null : model,
  );

  final title = [locBrand, locModel].where((v) => v.isNotEmpty).join(' ');
  final suffix = [trim, year].where((v) => v.isNotEmpty).join(' • ');
  if (title.isEmpty && suffix.isEmpty) return 'Untitled draft';
  if (title.isEmpty) return suffix;
  if (suffix.isEmpty) return title;
  return '$title • $suffix';
}
