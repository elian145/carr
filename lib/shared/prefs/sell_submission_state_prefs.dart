import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../debug/app_log.dart';

/// Lifecycle of one Sell-flow "Submit" action, tracked independently of the
/// [SellStep5Page]/`SellCarPage` widget lifecycle so it can be resumed after
/// the user navigates away, backgrounds the app, or the process is killed.
///
/// State machine (see `PendingSellSubmissionService`):
///   pending -> inProgress -> completed
///                    \-> retryable -> inProgress (auto retry) -> ...
///                    \-> needsAttention (permanent failure; no auto-retry)
enum SellSubmissionStatus {
  /// Submit was pressed and durably recorded, but no attempt has completed
  /// a full pass yet (covers "about to start" and "interrupted before the
  /// first checkpoint").
  pending,

  /// A worker is actively (or was, before an interruption) creating the
  /// listing / uploading media for this draft right now.
  inProgress,

  /// The last attempt failed with a transient (network/server-hiccup)
  /// error. Safe to retry automatically once connectivity/app state allow.
  retryable,

  /// The last attempt failed with a permanent error (validation, auth,
  /// rejected media, etc). Must not be retried automatically — the user
  /// has to reopen the draft to fix it.
  needsAttention,

  /// Finished successfully. Records in this state are removed promptly;
  /// this value exists mainly for in-memory status snapshots/tests.
  completed,
}

String sellSubmissionStatusToStorageString(SellSubmissionStatus s) => s.name;

SellSubmissionStatus? sellSubmissionStatusFromStorageString(String? s) {
  if (s == null) return null;
  for (final v in SellSubmissionStatus.values) {
    if (v.name == s) return v;
  }
  return null;
}

/// JSON-safe conversion mirroring the existing sell-draft snapshot encoder
/// (`_SellCarPageDraftPersist._draftValue`) — never serializes secrets since
/// [carData] never carries auth tokens (only listing form fields + local
/// media paths / already-persisted media metadata maps).
dynamic sellSubmissionJsonSafeValue(dynamic value) {
  if (value == null) return null;
  if (value is String || value is num || value is bool) return value;
  if (value is XFile) return value.path;
  if (value is Map) {
    return value.map(
      (k, v) => MapEntry(k.toString(), sellSubmissionJsonSafeValue(v)),
    );
  }
  if (value is Iterable) {
    return value.map(sellSubmissionJsonSafeValue).toList();
  }
  return value.toString();
}

Map<String, dynamic> sellSubmissionJsonSafeCarData(
  Map<String, dynamic> carData,
) {
  final safe = sellSubmissionJsonSafeValue(carData);
  return safe is Map
      ? Map<String, dynamic>.from(safe.cast<String, dynamic>())
      : <String, dynamic>{};
}

/// Durable record of one active/interrupted Sell submission.
///
/// Persists everything required to resume without re-asking the user to
/// press Submit and without creating a duplicate listing:
/// - [carId]: the backend listing id once created (empty until then).
/// - [carData]: JSON-safe snapshot of the submitted form + media metadata
///   (media paths point at durable app-controlled storage — see
///   `SellDraftMediaPersistence` — never OS temp/cache paths that can
///   disappear when the app is killed).
/// - [idempotencyKey]: stable per-draft key reused across every create
///   attempt (including resumes), so a repeated create call after a kill
///   replays the backend's first successful response instead of making a
///   second listing (see `kk/idempotency.py`).
/// - [currentPhase] / progress counters: cheap UI-facing progress; actual
///   duplicate-avoidance for media is enforced server-side by
///   `SellListingMediaUpload` re-querying the listing's current media
///   count before uploading anything (belt-and-suspenders, not the only
///   safety net).
///
/// Never stores auth tokens or other secrets.
class SellSubmissionRecord {
  SellSubmissionRecord({
    required this.draftId,
    required this.status,
    required this.carData,
    required this.idempotencyKey,
    required this.createdAt,
    required this.updatedAt,
    this.isEdit = false,
    this.editListingId,
    this.carId,
    this.pendingReview = false,
    this.currentPhase = 'creating',
    this.completedMediaCount = 0,
    this.totalMediaCount = 0,
    this.lastErrorMessage,
    this.lastErrorStatusCode,
    this.lastErrorRetryable = false,
    this.attempts = 0,
    this.ownerUserId,
  });

  final String draftId;
  final SellSubmissionStatus status;
  final bool isEdit;
  final String? editListingId;

  /// Account (`AuthService().currentUser?['id']`) that was signed in when
  /// Submit was first pressed for this draft. Not a secret — just an
  /// opaque account id, the same one already visible in every other
  /// authenticated API response — but load-bearing:
  /// `PendingSellSubmissionService._runSubmission` refuses to resume a
  /// record whose [ownerUserId] is known and does NOT match the
  /// currently signed-in account, so a submission started by one user on
  /// a shared device can never be silently created/finished under a
  /// different user who later signs in on the same device. `null` only
  /// when the profile genuinely hadn't loaded yet at Submit time (a rare
  /// race — see `AuthGuard`'s optimistic render) — resumable by whichever
  /// account is current, same as before this field existed, since there
  /// is no known owner to protect.
  final String? ownerUserId;

  /// Backend listing id once created. Presence of this (non-empty) is what
  /// makes a resume idempotent for the "create" step: it is never
  /// re-created once set, only reused.
  final String? carId;
  final bool pendingReview;

  /// JSON-safe snapshot of the submitted carData (durable media paths).
  final Map<String, dynamic> carData;

  final String idempotencyKey;

  /// One of 'creating' | 'photos' | 'videos' | 'damagePhotos' | 'done'.
  final String currentPhase;

  final int completedMediaCount;
  final int totalMediaCount;

  final String? lastErrorMessage;
  final int? lastErrorStatusCode;
  final bool lastErrorRetryable;

  /// Number of times a worker has attempted this submission (bounds retry
  /// UI/telemetry; auto-retry itself is bounded by caller-side spacing, not
  /// this count, so a legitimate reconnect always gets another try).
  final int attempts;

  final int createdAt;
  final int updatedAt;

  SellSubmissionRecord copyWith({
    SellSubmissionStatus? status,
    String? carId,
    bool? pendingReview,
    Map<String, dynamic>? carData,
    String? currentPhase,
    int? completedMediaCount,
    int? totalMediaCount,
    String? lastErrorMessage,
    int? lastErrorStatusCode,
    bool? lastErrorRetryable,
    int? attempts,
    int? updatedAt,
    bool clearLastError = false,
  }) {
    return SellSubmissionRecord(
      draftId: draftId,
      status: status ?? this.status,
      isEdit: isEdit,
      editListingId: editListingId,
      carId: carId ?? this.carId,
      pendingReview: pendingReview ?? this.pendingReview,
      carData: carData ?? this.carData,
      idempotencyKey: idempotencyKey,
      currentPhase: currentPhase ?? this.currentPhase,
      completedMediaCount: completedMediaCount ?? this.completedMediaCount,
      totalMediaCount: totalMediaCount ?? this.totalMediaCount,
      lastErrorMessage:
          clearLastError ? null : (lastErrorMessage ?? this.lastErrorMessage),
      lastErrorStatusCode: clearLastError
          ? null
          : (lastErrorStatusCode ?? this.lastErrorStatusCode),
      lastErrorRetryable:
          clearLastError ? false : (lastErrorRetryable ?? this.lastErrorRetryable),
      attempts: attempts ?? this.attempts,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      ownerUserId: ownerUserId,
    );
  }

  Map<String, dynamic> toJson() => {
        'draftId': draftId,
        'status': sellSubmissionStatusToStorageString(status),
        'isEdit': isEdit,
        if (editListingId != null) 'editListingId': editListingId,
        if (carId != null) 'carId': carId,
        'pendingReview': pendingReview,
        'carData': carData,
        'idempotencyKey': idempotencyKey,
        'currentPhase': currentPhase,
        'completedMediaCount': completedMediaCount,
        'totalMediaCount': totalMediaCount,
        if (lastErrorMessage != null) 'lastErrorMessage': lastErrorMessage,
        if (lastErrorStatusCode != null)
          'lastErrorStatusCode': lastErrorStatusCode,
        'lastErrorRetryable': lastErrorRetryable,
        'attempts': attempts,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        if (ownerUserId != null) 'ownerUserId': ownerUserId,
      };

  static SellSubmissionRecord? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(raw.cast<String, dynamic>());
      final draftId = (map['draftId'] ?? '').toString().trim();
      final idempotencyKey = (map['idempotencyKey'] ?? '').toString().trim();
      final status = sellSubmissionStatusFromStorageString(
        map['status']?.toString(),
      );
      if (draftId.isEmpty || idempotencyKey.isEmpty || status == null) {
        return null;
      }
      final rawCarData = map['carData'];
      final carData = rawCarData is Map
          ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
          : <String, dynamic>{};
      return SellSubmissionRecord(
        draftId: draftId,
        status: status,
        isEdit: map['isEdit'] == true,
        editListingId: map['editListingId']?.toString(),
        carId: (map['carId']?.toString().trim().isNotEmpty ?? false)
            ? map['carId'].toString().trim()
            : null,
        pendingReview: map['pendingReview'] == true,
        carData: carData,
        idempotencyKey: idempotencyKey,
        currentPhase: (map['currentPhase'] ?? 'creating').toString(),
        completedMediaCount:
            (map['completedMediaCount'] as num?)?.toInt() ?? 0,
        totalMediaCount: (map['totalMediaCount'] as num?)?.toInt() ?? 0,
        lastErrorMessage: map['lastErrorMessage']?.toString(),
        lastErrorStatusCode: (map['lastErrorStatusCode'] as num?)?.toInt(),
        lastErrorRetryable: map['lastErrorRetryable'] == true,
        attempts: (map['attempts'] as num?)?.toInt() ?? 0,
        createdAt: (map['createdAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        updatedAt: (map['updatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        ownerUserId: (map['ownerUserId']?.toString().trim().isNotEmpty ?? false)
            ? map['ownerUserId'].toString().trim()
            : null,
      );
    } catch (e, st) {
      logNonFatal(e, st);
      return null;
    }
  }
}

/// Durable storage for [SellSubmissionRecord]s.
///
/// One small JSON-list `SharedPreferences` entry, mirroring the existing
/// `ChatPendingSendPrefs` / `SellPendingMediaPrefs` convention already used
/// elsewhere in the app for durable "finish this later" state.
class SellSubmissionStatePrefs {
  SellSubmissionStatePrefs._();

  static const String prefsKey = 'sell_submission_state_v1';

  static Future<List<SellSubmissionRecord>> loadAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(prefsKey);
      if (raw == null || raw.trim().isEmpty) {
        return const <SellSubmissionRecord>[];
      }
      final decoded = json.decode(raw);
      if (decoded is! List) return const <SellSubmissionRecord>[];
      final out = <SellSubmissionRecord>[];
      for (final item in decoded) {
        final rec = SellSubmissionRecord.fromJson(item);
        if (rec != null) out.add(rec);
      }
      return out;
    } catch (e, st) {
      logNonFatal(e, st);
      return const <SellSubmissionRecord>[];
    }
  }

  static Future<SellSubmissionRecord?> load(String draftId) async {
    final all = await loadAll();
    for (final r in all) {
      if (r.draftId == draftId) return r;
    }
    return null;
  }

  static Future<void> _saveAll(List<SellSubmissionRecord> records) async {
    final sp = await SharedPreferences.getInstance();
    if (records.isEmpty) {
      await sp.remove(prefsKey);
      return;
    }
    final encoded = json.encode(records.map((r) => r.toJson()).toList());
    await sp.setString(prefsKey, encoded);
  }

  /// Insert or update a record (matched by [SellSubmissionRecord.draftId]).
  static Future<void> upsert(SellSubmissionRecord record) async {
    try {
      final all = List<SellSubmissionRecord>.from(await loadAll());
      final idx = all.indexWhere((r) => r.draftId == record.draftId);
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

  /// Idempotent — safe to call more than once or for a draftId never saved.
  static Future<void> remove(String draftId) async {
    try {
      final all = await loadAll();
      final next = all.where((r) => r.draftId != draftId).toList();
      if (next.length == all.length) return;
      await _saveAll(next);
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }
}
