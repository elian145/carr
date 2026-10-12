import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/car_name_translations.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/prefs/legacy_sell_draft_prefs.dart';
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
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    // Default "Any" filter placeholders are not user content.
    if (trimmed.toLowerCase() == 'any') return false;
    return true;
  }
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
  final asString = value.toString().trim();
  if (asString.isEmpty || asString.toLowerCase() == 'any') return false;
  return true;
}

bool isVisibleSellDraft(Map<String, dynamic> draft) {
  if (draft['isPlaceholder'] == true) return false;
  return hasMeaningfulSellDraftValue(draft['carData']);
}

/// True when [carData] still has user-entered listing content after media
/// lists are ignored (used when deciding whether deleting the last photo
/// should auto-discard the whole draft).
bool carDataHasMeaningfulNonMediaContent(Map<String, dynamic>? carData) {
  if (carData == null || carData.isEmpty) return false;
  const mediaKeys = <String>{
    'images',
    'original_images',
    'blurred_images',
    'damage_images',
    'original_damage_images',
    'blurred_damage_images',
    'videos',
    'processed_image_paths',
    'image_paths',
    'damage_image_paths',
    'video_paths',
    'existing_video_records',
    'server_transcode_videos',
  };
  for (final entry in carData.entries) {
    final key = entry.key.toString();
    if (mediaKeys.contains(key)) continue;
    if (hasMeaningfulSellDraftValue(entry.value, key: key)) return true;
  }
  return false;
}

/// Raw listing-photo list for draft-card thumbnails (My Listings, etc.).
///
/// When `original_images` is present as a List — including an empty list
/// after the user deleted every photo — that list is authoritative. Do
/// not fall back to `images`, which can still hold a pre-delete path
/// until the async media sync finishes (or forever if that sync aborted
/// on unmount).
List<dynamic>? sellDraftCardRawImages(Map<String, dynamic> carData) {
  final originals = carData['original_images'];
  if (originals is List) {
    return List<dynamic>.from(originals);
  }
  final images = carData['images'];
  if (images is List) {
    return List<dynamic>.from(images);
  }
  final paths = carData['image_paths'];
  if (paths is List) {
    return List<dynamic>.from(paths);
  }
  return null;
}

/// Cover index for a draft card, clamped to [0, length).
int sellDraftCardPrimaryImageIndex(
  Map<String, dynamic> carData, {
  int length = 0,
}) {
  final raw = carData['primary_image_index'];
  final parsed = raw is int
      ? raw
      : int.tryParse(raw?.toString() ?? '') ?? 0;
  if (length <= 0) return parsed < 0 ? 0 : parsed;
  if (parsed < 0) return 0;
  if (parsed >= length) return 0;
  return parsed;
}

/// Widget-independent equivalent of `_SellCarPageDraftPersist._clearSubmittedDraftOnly`,
/// usable from `PendingSellSubmissionService` when a submission completes
/// with no `SellCarPage` mounted (e.g. resumed at app startup).
///
/// Only clears the single "active" draft slot when it actually belongs to
/// [draftId] (so finishing a background submission for one draft can never
/// wipe a *different* draft the user is actively editing in the
/// foreground) and always removes any matching archive entry.
///
/// Does **not** delete `sell_draft_media/<draftId>/`. Submission calls this
/// immediately after listing create so My Listings no longer shows a draft,
/// but upload/retry/owner-optimistic fallback still read those local files
/// until [OwnerOptimisticMediaCleanup] (or empty-draft auto-delete) releases
/// them. Deleting the folder here caused PathNotFoundException mid-upload
/// (Codemagic ios-testflight / e2a4693 regression).
Future<void> discardSellDraftById(String draftId) async {
  final id = draftId.trim();
  if (id.isEmpty) return;
  try {
    final sp = await SharedPreferences.getInstance();
    final activeRaw = sp.getString(LegacySellDraftPrefs.snapshotKey);
    var activeMatches = false;
    if (activeRaw != null && activeRaw.trim().isNotEmpty) {
      try {
        final decoded = json.decode(activeRaw);
        if (decoded is Map &&
            (decoded['draftId'] ?? '').toString().trim() == id) {
          activeMatches = true;
        }
      } catch (e, st) {
        logNonFatal(e, st);
      }
    }
    if (activeMatches) {
      await LegacySellDraftPrefs.clearActiveStorage();
    }
    final archive = decodeSellDraftArchive(
      sp.getString(LegacySellDraftPrefs.archiveKey),
    );
    final before = archive.length;
    archive.removeWhere((item) => (item['draftId'] ?? '').toString() == id);
    if (archive.length != before) {
      await sp.setString(
        LegacySellDraftPrefs.archiveKey,
        encodeSellDraftArchive(archive),
      );
    }
  } catch (e, st) {
    logNonFatal(e, st);
  }
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
  if (title.isEmpty && suffix.isEmpty) {
    return AppLocalizations.of(context)?.untitledDraftTitle ?? 'Untitled draft';
  }
  if (title.isEmpty) return suffix;
  if (suffix.isEmpty) return title;
  return '$title • $suffix';
}
