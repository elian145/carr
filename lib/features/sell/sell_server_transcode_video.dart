/// Phase 3B: durable per-video state for the resumable server-side video
/// transcode fallback (see `sell_video_compression.dart`'s
/// `SellVideoPrepareStatus.requiresServerTranscode` -- the only trigger for
/// this pipeline; every other video keeps using the existing normal
/// local-compression + `POST /api/cars/<id>/videos` path unchanged).
///
/// Two separate, deliberately non-overlapping pieces of state:
///
///   1. [ServerTranscodeVideoSpec] -- WHAT to upload. Written ONCE, at pick
///      time (`sell_step4_logic.dart:_pickVideos`), into
///      `carData['server_transcode_videos']`. Carries the stable
///      [draftMediaId] plus the durable local source metadata (already
///      copied into `sell_draft_media/<draftId>/` by the EXISTING
///      `SellDraftMediaPersistence` pipeline, exactly like every other
///      Sell media file). Immutable for the lifetime of the draft --
///      never mutated by the upload pipeline itself.
///
///   2. [ServerTranscodeVideoState] -- HOW FAR the upload pipeline got.
///      Lives in `SellSubmissionRecord.serverTranscodeVideos` (keyed by
///      [ServerTranscodeVideoSpec.draftMediaId]), mutated as the pipeline
///      advances through sign -> PUT -> finalize -> poll -> attach. This
///      is what makes a force-close/network-loss at ANY point resumable:
///      the next attempt reads this state back and continues from the
///      correct next idempotent operation, never restarting from scratch
///      and never uploading/attaching the same video twice.
///
/// Deliberately NEVER persisted anywhere in either type: a presigned
/// upload URL (expires; must always be re-acquired via a fresh
/// sign-video-source-upload call, which is safe because the staging key
/// is deterministic -- see `kk/media_processing.py::video_source_staging_key`).
library;

/// Lifecycle of one server-transcode-required video, mirrored 1:1 from the
/// task's state list (verbatim names).
enum ServerTranscodeVideoStatus {
  /// Picked; not yet even determined it needs server transcode (should not
  /// normally be persisted -- see [ServerTranscodeVideoStatus.requiresServerTranscode]
  /// which is the actual starting state written at pick time).
  localPending,

  /// `SellVideoCompression.prepare()` returned
  /// `SellVideoPrepareStatus.requiresServerTranscode` for this source.
  /// Starting state for every entry in `carData['server_transcode_videos']`.
  requiresServerTranscode,

  /// `POST /api/media/r2/sign-video-source-upload` is in flight (or about
  /// to be retried).
  sourceUploadSigning,

  /// The direct-to-R2 PUT of the original source bytes is in flight (or
  /// about to be retried).
  sourceUploading,

  /// The PUT completed (verified by [ServerTranscodeVideoState.putConfirmed]);
  /// finalize has not yet been confirmed to have registered a task.
  sourceStaged,

  /// `finalize-video-source-upload` returned a `task_id`; the Celery job
  /// state was `queued`/unknown at last check.
  transcodeQueued,

  /// The Celery job is `STARTED`/processing.
  transcodeProcessing,

  /// The Celery job reached `SUCCESS`; attach has not yet been confirmed.
  transcodeSucceeded,

  /// `attach-transcoded-video` is in flight (or about to be retried).
  attaching,

  /// Attach succeeded; [ServerTranscodeVideoState.attachedVideo] holds the
  /// resulting `CarVideo` dict. Terminal success state -- this video must
  /// never be uploaded again through any path.
  attached,

  /// The last attempt failed with a transient (network/5xx) error. Safe
  /// to retry automatically.
  failedRecoverable,

  /// The last attempt failed with a permanent error (server feature
  /// disabled, validation rejection, a source the backend also cannot
  /// transcode, etc). Must not be auto-retried.
  failedPermanent,
}

String serverTranscodeVideoStatusToStorageString(
  ServerTranscodeVideoStatus s,
) => s.name;

ServerTranscodeVideoStatus? serverTranscodeVideoStatusFromStorageString(
  String? s,
) {
  if (s == null) return null;
  for (final v in ServerTranscodeVideoStatus.values) {
    if (v.name == s) return v;
  }
  return null;
}

/// WHAT to upload for one server-transcode-required video -- see the
/// file-level doc comment. Written once at pick time; never mutated
/// afterward by the upload pipeline.
class ServerTranscodeVideoSpec {
  const ServerTranscodeVideoSpec({
    required this.draftMediaId,
    required this.localSourcePath,
    required this.sourceByteSize,
    required this.sourceMimeType,
  });

  /// Stable per-video id, generated once at pick time and reused for the
  /// lifetime of this draft/submission. Must satisfy the backend's
  /// `^[A-Za-z0-9_-]{1,128}$` `is_valid_draft_media_id` contract.
  final String draftMediaId;

  /// Durable local path (already copied into
  /// `sell_draft_media/<draftId>/` by `SellDraftMediaPersistence`) to the
  /// UNTOUCHED original source video.
  final String localSourcePath;

  final int sourceByteSize;
  final String sourceMimeType;

  Map<String, dynamic> toJson() => {
        'draft_media_id': draftMediaId,
        'local_source_path': localSourcePath,
        'source_byte_size': sourceByteSize,
        'source_mime_type': sourceMimeType,
      };

  static ServerTranscodeVideoSpec? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(raw.cast<String, dynamic>());
      final draftMediaId = (map['draft_media_id'] ?? '').toString().trim();
      final localSourcePath =
          (map['local_source_path'] ?? '').toString().trim();
      if (draftMediaId.isEmpty || localSourcePath.isEmpty) return null;
      return ServerTranscodeVideoSpec(
        draftMediaId: draftMediaId,
        localSourcePath: localSourcePath,
        sourceByteSize: (map['source_byte_size'] as num?)?.toInt() ?? 0,
        sourceMimeType: (map['source_mime_type'] ?? '').toString().trim(),
      );
    } catch (_) {
      return null;
    }
  }

  static List<ServerTranscodeVideoSpec> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map(ServerTranscodeVideoSpec.fromJson)
        .whereType<ServerTranscodeVideoSpec>()
        .toList();
  }

  static List<Map<String, dynamic>> listToJson(
    List<ServerTranscodeVideoSpec> specs,
  ) => specs.map((s) => s.toJson()).toList();
}

/// HOW FAR the upload pipeline got for one [ServerTranscodeVideoSpec] --
/// see the file-level doc comment. Never persists a presigned URL.
class ServerTranscodeVideoState {
  const ServerTranscodeVideoState({
    required this.draftMediaId,
    required this.status,
    this.taskId,
    this.putConfirmed = false,
    this.transcodeConfirmed = false,
    this.attachedVideo,
    this.featureDisabled = false,
    this.lastErrorMessage,
    this.attempts = 0,
    this.updatedAt = 0,
  });

  final String draftMediaId;
  final ServerTranscodeVideoStatus status;

  /// Celery task id returned by `finalize-video-source-upload`. Kept even
  /// across a network/5xx failure while polling -- never discarded except
  /// when the server has AFFIRMATIVELY confirmed the job id itself is
  /// gone (see `SellAsyncJobTracker`'s identical policy for images).
  final String? taskId;

  /// True once the direct-to-R2 PUT has been observed to succeed in THIS
  /// process. Best-effort only: a crash immediately after a successful
  /// PUT but before this is persisted simply means the next attempt PUTs
  /// again -- safe, because the staging key is deterministic (same
  /// object, same key, last write wins).
  final bool putConfirmed;

  /// True once a poll has observed the Celery job reach `SUCCESS` --
  /// distinguishes "still needs to poll" from "already confirmed
  /// succeeded, just needs attach" when resuming from
  /// [ServerTranscodeVideoStatus.failedRecoverable] (which, unlike every
  /// other status, does not by itself say which step to resume at -- see
  /// `sell_server_transcode_runner.dart`'s resume-step reconstruction).
  final bool transcodeConfirmed;

  /// The `CarVideo` dict returned by a successful attach. Non-null iff
  /// [status] is [ServerTranscodeVideoStatus.attached].
  final Map<String, dynamic>? attachedVideo;

  /// True once any step has observed the backend's server-side-staging
  /// feature flag is OFF (a 404 from sign/finalize/attach while the
  /// feature-disabled contract applies). Drives the "can't be processed
  /// on this device" localized message instead of an infinite retry loop.
  final bool featureDisabled;

  final String? lastErrorMessage;
  final int attempts;
  final int updatedAt;

  bool get isTerminal =>
      status == ServerTranscodeVideoStatus.attached ||
      status == ServerTranscodeVideoStatus.failedPermanent;

  ServerTranscodeVideoState copyWith({
    ServerTranscodeVideoStatus? status,
    String? taskId,
    bool? putConfirmed,
    bool? transcodeConfirmed,
    Map<String, dynamic>? attachedVideo,
    bool? featureDisabled,
    String? lastErrorMessage,
    int? attempts,
    int? updatedAt,
    bool clearTaskId = false,
    bool clearLastError = false,
  }) {
    return ServerTranscodeVideoState(
      draftMediaId: draftMediaId,
      status: status ?? this.status,
      taskId: clearTaskId ? null : (taskId ?? this.taskId),
      putConfirmed: putConfirmed ?? this.putConfirmed,
      transcodeConfirmed: transcodeConfirmed ?? this.transcodeConfirmed,
      attachedVideo: attachedVideo ?? this.attachedVideo,
      featureDisabled: featureDisabled ?? this.featureDisabled,
      lastErrorMessage:
          clearLastError ? null : (lastErrorMessage ?? this.lastErrorMessage),
      attempts: attempts ?? this.attempts,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static ServerTranscodeVideoState initial(String draftMediaId) =>
      ServerTranscodeVideoState(
        draftMediaId: draftMediaId,
        status: ServerTranscodeVideoStatus.requiresServerTranscode,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'draft_media_id': draftMediaId,
        'status': serverTranscodeVideoStatusToStorageString(status),
        if (taskId != null) 'task_id': taskId,
        'put_confirmed': putConfirmed,
        'transcode_confirmed': transcodeConfirmed,
        if (attachedVideo != null) 'attached_video': attachedVideo,
        'feature_disabled': featureDisabled,
        if (lastErrorMessage != null) 'last_error_message': lastErrorMessage,
        'attempts': attempts,
        'updated_at': updatedAt,
      };

  static ServerTranscodeVideoState? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(raw.cast<String, dynamic>());
      final draftMediaId = (map['draft_media_id'] ?? '').toString().trim();
      final status = serverTranscodeVideoStatusFromStorageString(
        map['status']?.toString(),
      );
      if (draftMediaId.isEmpty || status == null) return null;
      final rawAttached = map['attached_video'];
      return ServerTranscodeVideoState(
        draftMediaId: draftMediaId,
        status: status,
        taskId: (map['task_id']?.toString().trim().isNotEmpty ?? false)
            ? map['task_id'].toString().trim()
            : null,
        putConfirmed: map['put_confirmed'] == true,
        transcodeConfirmed: map['transcode_confirmed'] == true,
        attachedVideo: rawAttached is Map
            ? Map<String, dynamic>.from(rawAttached.cast<String, dynamic>())
            : null,
        featureDisabled: map['feature_disabled'] == true,
        lastErrorMessage: map['last_error_message']?.toString(),
        attempts: (map['attempts'] as num?)?.toInt() ?? 0,
        updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Decodes the `Map<String, dynamic>` -> raw-JSON-map shape used by
  /// `SellSubmissionRecord.serverTranscodeVideos`.
  static Map<String, ServerTranscodeVideoState> mapFromJson(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, ServerTranscodeVideoState>{};
    raw.forEach((k, v) {
      final state = ServerTranscodeVideoState.fromJson(v);
      if (state != null) out[k.toString()] = state;
    });
    return out;
  }

  static Map<String, dynamic> mapToJson(
    Map<String, ServerTranscodeVideoState> states,
  ) => states.map((k, v) => MapEntry(k, v.toJson()));
}
