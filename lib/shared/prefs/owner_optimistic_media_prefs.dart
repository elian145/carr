import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../debug/app_log.dart';

/// Optimistic-local-media fix (Critical Issue 1 -- "local media cleanup is
/// still too early"): durable, per-listing record of every media item the
/// owner is still optimistically showing locally on THIS device, tracked
/// independently of `SellSubmissionRecord`
/// (`sell_submission_state_prefs.dart`).
///
/// `SellSubmissionRecord` is cleared as soon as the BACKEND finishes
/// (`PendingSellSubmissionService._runSubmission`'s success path) -- that
/// is correct for ITS OWN job (retry/idempotency bookkeeping for the
/// create-listing/upload-media flow is genuinely done at that point) but
/// backend-done is NOT the same thing as "the remote photo/video has
/// actually been fetched and decoded on this device yet". Deleting local
/// optimistic files at backend-done time can blank a tile that is still
/// mid-download, and is not restart-safe (kill the app between
/// backend-done and the remote asset's first successful decode, and
/// there would be nothing left -- no submission record, no local files
/// -- to fall back to).
///
/// This record is the fix: it is written (and kept up to date) the first
/// time `OwnerMediaOverlay` computes slots for a listing (whether the
/// live `SellSubmissionRecord` still exists or not), and it OUTLIVES that
/// record. Each item tracks its own [OwnerOptimisticMediaItem.
/// remoteDisplayReady] flag, persisted the moment a fallback widget
/// (`OwnerFallbackHeroImage`/`OwnerFallbackVideoThumbnail`) confirms a
/// successful remote decode/initialization -- see
/// `owner_optimistic_media_cleanup.dart`. A local file is only ever
/// deleted once ITS OWN item is confirmed remote-display-ready; the
/// whole record (and its owning listing's mapping) is only removed once
/// EVERY expected item is.
class OwnerOptimisticMediaItem {
  const OwnerOptimisticMediaItem({
    required this.clientMediaId,
    required this.kind,
    required this.order,
    this.localPath,
    this.remoteUrl,
    this.remoteDisplayReady = false,
  });

  /// Stable per-item id -- see `SellMediaIdentity`/`draft_media_id`.
  final String clientMediaId;

  /// 'image' or 'video'.
  final String kind;

  /// Position among this listing's own expected items of the SAME [kind]
  /// -- positional-pairing fallback basis, mirrors `OwnerMediaSlot.order`.
  final int order;

  /// Durable local file path (already copied into app storage), or
  /// `null`/empty if unknown/already cleaned up.
  final String? localPath;

  /// The best-known remote URL for this item, or `null` while not yet
  /// known/attached server-side.
  final String? remoteUrl;

  /// `true` once a fallback widget has confirmed a successful remote
  /// decode/initialization for this item on THIS device -- see the
  /// file-level doc comment. Once `true`, [localPath]'s file has
  /// already been deleted (or never existed) and must not be relied on.
  final bool remoteDisplayReady;

  bool get hasLocal => (localPath ?? '').trim().isNotEmpty;
  bool get hasRemote => (remoteUrl ?? '').trim().isNotEmpty;

  OwnerOptimisticMediaItem copyWith({
    String? localPath,
    bool clearLocalPath = false,
    String? remoteUrl,
    bool? remoteDisplayReady,
  }) {
    return OwnerOptimisticMediaItem(
      clientMediaId: clientMediaId,
      kind: kind,
      order: order,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      remoteUrl: remoteUrl ?? this.remoteUrl,
      remoteDisplayReady: remoteDisplayReady ?? this.remoteDisplayReady,
    );
  }

  Map<String, dynamic> toJson() => {
        'clientMediaId': clientMediaId,
        'kind': kind,
        'order': order,
        if (localPath != null) 'localPath': localPath,
        if (remoteUrl != null) 'remoteUrl': remoteUrl,
        'remoteDisplayReady': remoteDisplayReady,
      };

  static OwnerOptimisticMediaItem? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(raw.cast<String, dynamic>());
      final clientMediaId = (map['clientMediaId'] ?? '').toString().trim();
      final kind = (map['kind'] ?? '').toString().trim();
      if (clientMediaId.isEmpty || kind.isEmpty) return null;
      return OwnerOptimisticMediaItem(
        clientMediaId: clientMediaId,
        kind: kind,
        order: (map['order'] as num?)?.toInt() ?? 0,
        localPath: (map['localPath']?.toString().trim().isNotEmpty ?? false)
            ? map['localPath'].toString().trim()
            : null,
        remoteUrl: (map['remoteUrl']?.toString().trim().isNotEmpty ?? false)
            ? map['remoteUrl'].toString().trim()
            : null,
        remoteDisplayReady: map['remoteDisplayReady'] == true,
      );
    } catch (e, st) {
      logNonFatal(e, st);
      return null;
    }
  }
}

/// Every expected optimistic media item for one listing, on this device.
class OwnerOptimisticMediaRecord {
  const OwnerOptimisticMediaRecord({
    required this.listingId,
    required this.items,
    required this.updatedAt,
    this.draftId,
  });

  final String listingId;
  final List<OwnerOptimisticMediaItem> items;
  final int updatedAt;

  /// The originating Sell-draft id (`SellSubmissionRecord.draftId`), when
  /// known -- NOT this record's own identity (that is [listingId]; this
  /// record is deliberately independent of `SellSubmissionRecord`'s own
  /// retry/idempotency lifecycle, per the file-level doc comment). Kept
  /// SOLELY so whole-record cleanup (`OwnerOptimisticMediaCleanup.
  /// markRemoteDisplayReadyAndCleanup`) can also remove the now-empty
  /// (or near-empty -- untracked sibling files like a blur-preview/
  /// damage-photo copy never get an [OwnerOptimisticMediaItem] of their
  /// own) `sell_draft_media/<draftId>/` directory itself, not merely the
  /// individual files this record explicitly tracks. `null` only if this
  /// record was created before that id was known (should not happen in
  /// practice -- every write site has it).
  final String? draftId;

  bool get isEmpty => items.isEmpty;

  /// Whole-record cleanup gate -- see the file-level doc comment.
  bool get allRemoteDisplayReady =>
      items.isNotEmpty && items.every((i) => i.remoteDisplayReady);

  OwnerOptimisticMediaRecord copyWith({
    List<OwnerOptimisticMediaItem>? items,
    int? updatedAt,
    String? draftId,
  }) {
    return OwnerOptimisticMediaRecord(
      listingId: listingId,
      items: items ?? this.items,
      updatedAt: updatedAt ?? this.updatedAt,
      draftId: draftId ?? this.draftId,
    );
  }

  Map<String, dynamic> toJson() => {
        'listingId': listingId,
        'items': items.map((i) => i.toJson()).toList(),
        'updatedAt': updatedAt,
        if (draftId != null) 'draftId': draftId,
      };

  static OwnerOptimisticMediaRecord? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(raw.cast<String, dynamic>());
      final listingId = (map['listingId'] ?? '').toString().trim();
      if (listingId.isEmpty) return null;
      final rawItems = map['items'];
      final items = <OwnerOptimisticMediaItem>[];
      if (rawItems is List) {
        for (final it in rawItems) {
          final parsed = OwnerOptimisticMediaItem.fromJson(it);
          if (parsed != null) items.add(parsed);
        }
      }
      return OwnerOptimisticMediaRecord(
        listingId: listingId,
        items: items,
        updatedAt: (map['updatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        draftId: (map['draftId']?.toString().trim().isNotEmpty ?? false)
            ? map['draftId'].toString().trim()
            : null,
      );
    } catch (e, st) {
      logNonFatal(e, st);
      return null;
    }
  }
}

/// Durable storage for [OwnerOptimisticMediaRecord]s -- same one
/// small JSON-list `SharedPreferences` entry convention as
/// `SellSubmissionStatePrefs` (`sell_submission_state_prefs.dart`).
class OwnerOptimisticMediaPrefs {
  OwnerOptimisticMediaPrefs._();

  static const String prefsKey = 'owner_optimistic_media_v1';

  static Future<List<OwnerOptimisticMediaRecord>> loadAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(prefsKey);
      if (raw == null || raw.trim().isEmpty) {
        return const <OwnerOptimisticMediaRecord>[];
      }
      final decoded = json.decode(raw);
      if (decoded is! List) return const <OwnerOptimisticMediaRecord>[];
      final out = <OwnerOptimisticMediaRecord>[];
      for (final item in decoded) {
        final rec = OwnerOptimisticMediaRecord.fromJson(item);
        if (rec != null) out.add(rec);
      }
      return out;
    } catch (e, st) {
      logNonFatal(e, st);
      return const <OwnerOptimisticMediaRecord>[];
    }
  }

  static Future<OwnerOptimisticMediaRecord?> load(String listingId) async {
    final all = await loadAll();
    for (final r in all) {
      if (r.listingId == listingId) return r;
    }
    return null;
  }

  static Future<void> _saveAll(
    List<OwnerOptimisticMediaRecord> records,
  ) async {
    final sp = await SharedPreferences.getInstance();
    if (records.isEmpty) {
      await sp.remove(prefsKey);
      return;
    }
    final encoded = json.encode(records.map((r) => r.toJson()).toList());
    await sp.setString(prefsKey, encoded);
  }

  /// Insert or update a record (matched by [OwnerOptimisticMediaRecord.
  /// listingId]).
  static Future<void> upsert(OwnerOptimisticMediaRecord record) async {
    try {
      final all = List<OwnerOptimisticMediaRecord>.from(await loadAll());
      final idx = all.indexWhere((r) => r.listingId == record.listingId);
      if (idx == -1) {
        all.add(record);
      } else {
        all[idx] = record;
      }
      await _saveAll(all);
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  /// Idempotent -- safe to call more than once or for a listingId never
  /// saved.
  static Future<void> remove(String listingId) async {
    try {
      final all = await loadAll();
      final next = all.where((r) => r.listingId != listingId).toList();
      if (next.length == all.length) return;
      await _saveAll(next);
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }
}
