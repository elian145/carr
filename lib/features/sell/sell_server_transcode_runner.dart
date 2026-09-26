/// Phase 3B: resumable orchestration for the server-side video transcode
/// fallback -- sign -> PUT (direct to R2, streamed) -> finalize (idempotent
/// enqueue) -> poll (`GET /api/jobs/<task_id>`, reusing the exact same
/// transport `SellImageJobPolling` already uses) -> attach (idempotent).
///
/// Every step persists its result into `SellSubmissionRecord.serverTranscodeVideos`
/// (see `sell_server_transcode_video.dart`) BEFORE moving to the next one,
/// so [processAll] can be called again after a force-close/network loss/
/// app-kill at ANY point and resume from exactly the right next
/// operation -- see the file-level doc comment on
/// `sell_server_transcode_video.dart` for the full contract, and this
/// file's `_advanceOne` for the crash-recovery reasoning at each step
/// (mirrors the backend's own A-F crash-point audit for
/// `attach_transcoded_video()`).
///
/// NEVER invoked for a normal video (one that compressed successfully
/// on-device) -- only for entries in `carData['server_transcode_videos']`,
/// which only ever exist because `SellVideoCompression.prepare()` returned
/// `SellVideoPrepareStatus.requiresServerTranscode` for that source (see
/// `sell_step4_logic.dart:_pickVideos`).
library;

import 'dart:async';
import 'dart:io';

import '../../services/api_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/debug/expected_client_noise.dart';
import '../../shared/prefs/sell_submission_state_prefs.dart';
import 'sell_server_transcode_video.dart';

/// Coarse progress phase for [SellServerTranscodeVideoRunner], mirroring
/// the task's requested labels (Preparing/Uploading/Processing/Finishing).
/// UI-only -- carries no correctness meaning.
enum SellServerTranscodePhase {
  uploadingSource,
  processing,
  finishing,
}

class SellServerTranscodeVideoRunner {
  SellServerTranscodeVideoRunner._();

  /// Interval between `GET /api/jobs/<task_id>` polls -- matches
  /// `SellImageJobPolling.pollInterval`'s existing convention exactly
  /// (task section 6: "use the existing backoff/poll timing convention").
  static const Duration pollInterval = Duration(milliseconds: 1500);

  /// Bounded poll attempts per [processAll] call for one video -- a
  /// transcode job genuinely can take longer than this (ffmpeg on a
  /// 0.5CPU worker); when the budget is exhausted mid-job the state is
  /// simply left at `transcodeQueued`/`transcodeProcessing` with its
  /// `task_id` intact, and the NEXT `processAll` call (next app resume /
  /// `resumeAll` pass) picks the same job id back up. This is what
  /// "delayed resume" means for the client, exactly like the backend's
  /// own delayed-resume guarantee (Phase 3A's TTL audit).
  static const int maxPollsPerAttempt = 40;

  static bool _isTransientError(Object error) {
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    if (error is ApiException) {
      final code = error.statusCode;
      return code == 408 ||
          code == 429 ||
          code == 500 ||
          code == 502 ||
          code == 503 ||
          code == 504;
    }
    return isTransientNetworkError(error);
  }

  /// True for a response the task's feature-disabled contract makes
  /// unambiguous: every one of the three endpoints returns exactly
  /// `404 {"message": "Not found"}` when `VIDEO_SOURCE_STAGING_ENABLED`
  /// is off, and none of them otherwise use a bare 404 for anything this
  /// client is expected to hit in the normal course of this pipeline
  /// (a missing staged object at finalize time is the one other 404 --
  /// but that can only happen milliseconds after a confirmed-successful
  /// PUT to the SAME deterministic key, which is never expected; treating
  /// it the same, as "try again later, and eventually as feature
  /// disabled", is still strictly safer than treating it as some other
  /// unhandled error).
  static bool _isFeatureDisabled(Object error) =>
      error is ApiException && error.statusCode == 404;

  /// Processes every entry in [specs] for one (`draftId`, `carId`) to
  /// completion or to the next durable "come back later" checkpoint.
  /// Never throws for one video's own failure (persisted on its
  /// [ServerTranscodeVideoState] instead) -- only rethrows if the
  /// [draftId]'s [SellSubmissionRecord] itself has disappeared (nothing
  /// durable to resume against, e.g. the submission was already cleaned
  /// up by something else).
  static Future<void> processAll({
    required String draftId,
    required String carId,
    required List<ServerTranscodeVideoSpec> specs,
    void Function(String draftMediaId, SellServerTranscodePhase phase)?
        onPhase,
  }) async {
    for (final spec in specs) {
      await _processOne(
        draftId: draftId,
        carId: carId,
        spec: spec,
        onPhase: onPhase,
      );
    }
  }

  /// True once every entry in [specs] is durably `attached` per the
  /// submission record for [draftId] -- lets callers skip a whole
  /// re-scan of already-finished work cheaply.
  static Future<bool> allAttached({
    required String draftId,
    required List<ServerTranscodeVideoSpec> specs,
  }) async {
    if (specs.isEmpty) return true;
    final record = await SellSubmissionStatePrefs.load(draftId);
    if (record == null) return false;
    for (final spec in specs) {
      final state = record.serverTranscodeVideos[spec.draftMediaId];
      if (state == null || state.status != ServerTranscodeVideoStatus.attached) {
        return false;
      }
    }
    return true;
  }

  /// `draft_media_id`s among [specs] whose LAST attempt discovered the
  /// backend feature flag is off (never reset once seen -- see
  /// [ServerTranscodeVideoState.featureDisabled]'s doc comment). Callers
  /// use this to show the ONE localized "can't be processed on this
  /// device" message (task section 9) without leaking HTTP/feature-flag
  /// internals, and without retrying it again.
  static Future<List<String>> featureDisabledDraftMediaIds({
    required String draftId,
    required List<ServerTranscodeVideoSpec> specs,
  }) async {
    if (specs.isEmpty) return const [];
    final record = await SellSubmissionStatePrefs.load(draftId);
    if (record == null) return const [];
    final out = <String>[];
    for (final spec in specs) {
      final state = record.serverTranscodeVideos[spec.draftMediaId];
      if (state != null && state.featureDisabled) out.add(spec.draftMediaId);
    }
    return out;
  }

  /// Count of [specs] already durably `attached` per the submission
  /// record for [draftId] -- callers (`uploadForCar`) diff this
  /// before/after [processAll] to report an accurate NEW-attachments
  /// delta to `onMediaConfirmed`, without double-counting videos that
  /// were already attached in an earlier resume.
  static Future<int> attachedCount({
    required String draftId,
    required List<ServerTranscodeVideoSpec> specs,
  }) async {
    if (specs.isEmpty) return 0;
    final record = await SellSubmissionStatePrefs.load(draftId);
    if (record == null) return 0;
    var count = 0;
    for (final spec in specs) {
      if (record.serverTranscodeVideos[spec.draftMediaId]?.status ==
          ServerTranscodeVideoStatus.attached) {
        count++;
      }
    }
    return count;
  }

  static Future<ServerTranscodeVideoState> _loadState(
    String draftId,
    String draftMediaId,
  ) async {
    final record = await SellSubmissionStatePrefs.load(draftId);
    return record?.serverTranscodeVideos[draftMediaId] ??
        ServerTranscodeVideoState.initial(draftMediaId);
  }

  static Future<void> _saveState(
    String draftId,
    ServerTranscodeVideoState state,
  ) async {
    final record = await SellSubmissionStatePrefs.load(draftId);
    if (record == null) return;
    final next = Map<String, ServerTranscodeVideoState>.from(
      record.serverTranscodeVideos,
    )..[state.draftMediaId] = state;
    await SellSubmissionStatePrefs.upsert(
      record.copyWith(serverTranscodeVideos: next),
    );
  }

  static Future<void> _processOne({
    required String draftId,
    required String carId,
    required ServerTranscodeVideoSpec spec,
    void Function(String draftMediaId, SellServerTranscodePhase phase)?
        onPhase,
  }) async {
    var state = await _loadState(draftId, spec.draftMediaId);

    // Terminal states: never re-touch an attached video (it must never be
    // uploaded/attached again through any path), and never auto-retry a
    // permanent failure (feature disabled, or a permanent rejection).
    if (state.isTerminal) return;

    // Advance forward through the state machine, persisting after every
    // successful step, until either terminal, or blocked on something
    // that must wait for a later resume (still-processing job, or a
    // recoverable error to retry on the next pass).
    while (!state.isTerminal) {
      final before = state.status;
      state = await _advanceOne(
        carId: carId,
        spec: spec,
        state: state,
        onPhase: onPhase,
      );
      await _saveState(draftId, state);
      if (state.status == before) {
        // No forward progress this call (still processing / needs a
        // later retry) -- stop for now; the NEXT processAll() call
        // resumes from this exact persisted state.
        break;
      }
      if (state.status == ServerTranscodeVideoStatus.failedRecoverable) {
        // One recoverable error per processAll() call is enough -- avoid
        // hot-looping the remaining steps in the same call.
        break;
      }
    }
  }

  /// Runs exactly ONE forward step from [state.status], returning the
  /// resulting state (unchanged `status` means "blocked, try again
  /// later"). See the crash-point comments inline at each step -- each
  /// one mirrors the backend's own A-F ordering audit for
  /// `attach_transcoded_video()`: a crash before this method's `await`
  /// resolves simply means the NEXT call re-does this exact step
  /// (idempotent by construction at every step below), and a crash AFTER
  /// the underlying network call succeeded but BEFORE `_saveState`
  /// persists it just means the next call repeats the call itself (also
  /// safe -- signing again is free, PUTting again overwrites the same
  /// deterministic key, finalizing again returns the same task, attaching
  /// again returns the same CarVideo).
  /// [ServerTranscodeVideoStatus.failedRecoverable], unlike every other
  /// status, does not by itself say which step to resume at (a transient
  /// error can happen during ANY of the four steps). Reconstruct the
  /// correct resume point from the durable progress markers that are
  /// already set as soon as each step actually succeeds
  /// ([ServerTranscodeVideoState.putConfirmed] / `taskId` /
  /// [ServerTranscodeVideoState.transcodeConfirmed]) instead of the
  /// (ambiguous, for this one status) enum value itself.
  static ServerTranscodeVideoStatus _resumeStatusFor(
    ServerTranscodeVideoState state,
  ) {
    if (!state.putConfirmed) {
      return ServerTranscodeVideoStatus.requiresServerTranscode;
    }
    if (state.taskId == null || state.taskId!.isEmpty) {
      return ServerTranscodeVideoStatus.sourceStaged;
    }
    if (!state.transcodeConfirmed) {
      return ServerTranscodeVideoStatus.transcodeQueued;
    }
    return ServerTranscodeVideoStatus.transcodeSucceeded;
  }

  static Future<ServerTranscodeVideoState> _advanceOne({
    required String carId,
    required ServerTranscodeVideoSpec spec,
    required ServerTranscodeVideoState state,
    void Function(String draftMediaId, SellServerTranscodePhase phase)?
        onPhase,
  }) async {
    final id = spec.draftMediaId;
    final effectiveStatus =
        state.status == ServerTranscodeVideoStatus.failedRecoverable
            ? _resumeStatusFor(state)
            : state.status;
    switch (effectiveStatus) {
      case ServerTranscodeVideoStatus.localPending:
      case ServerTranscodeVideoStatus.requiresServerTranscode:
      case ServerTranscodeVideoStatus.sourceUploadSigning:
      case ServerTranscodeVideoStatus.sourceUploading:
        onPhase?.call(id, SellServerTranscodePhase.uploadingSource);
        return _stageSource(spec: spec, state: state);

      case ServerTranscodeVideoStatus.sourceStaged:
        onPhase?.call(id, SellServerTranscodePhase.processing);
        return _finalize(spec: spec, state: state);

      case ServerTranscodeVideoStatus.transcodeQueued:
      case ServerTranscodeVideoStatus.transcodeProcessing:
        onPhase?.call(id, SellServerTranscodePhase.processing);
        return _pollUntilTerminalOrBudgetExhausted(spec: spec, state: state);

      case ServerTranscodeVideoStatus.transcodeSucceeded:
      case ServerTranscodeVideoStatus.attaching:
        onPhase?.call(id, SellServerTranscodePhase.finishing);
        return _attach(carId: carId, spec: spec, state: state);

      case ServerTranscodeVideoStatus.failedRecoverable:
        // Unreachable in practice: `effectiveStatus` above already
        // resolves `failedRecoverable` to one of the cases above via
        // `_resumeStatusFor`. Kept only for switch exhaustiveness.
        return state;

      case ServerTranscodeVideoStatus.attached:
      case ServerTranscodeVideoStatus.failedPermanent:
        return state; // terminal -- never reached (loop checks isTerminal).
    }
  }

  /// Step 1: sign + stream-PUT the original source. Crash recovery: a
  /// crash before the sign call, during signing, or during the PUT all
  /// simply retry from the top on the next call (nothing durable was
  /// written yet). A crash AFTER a successful PUT but BEFORE this
  /// method returns (so `putConfirmed` is never persisted) means the
  /// NEXT call re-signs and re-PUTs -- safe and idempotent, because the
  /// staging key is deterministic (same object, last write wins).
  static Future<ServerTranscodeVideoState> _stageSource({
    required ServerTranscodeVideoSpec spec,
    required ServerTranscodeVideoState state,
  }) async {
    try {
      final signed = await ApiService.signVideoSourceUpload(
        draftMediaId: spec.draftMediaId,
        contentLength: spec.sourceByteSize,
        contentType: spec.sourceMimeType,
      );
      final uploadUrl = (signed['upload_url'] ?? '').toString();
      if (uploadUrl.isEmpty) {
        return state.copyWith(
          status: ServerTranscodeVideoStatus.failedRecoverable,
          attempts: state.attempts + 1,
          lastErrorMessage: 'sign_video_source_upload returned no upload_url',
        );
      }
      await ApiService.uploadVideoSourceToR2(
        uploadUrl: uploadUrl,
        localPath: spec.localSourcePath,
        contentLength: spec.sourceByteSize,
        contentType: spec.sourceMimeType,
      );
      return state.copyWith(
        status: ServerTranscodeVideoStatus.sourceStaged,
        putConfirmed: true,
        attempts: 0,
        clearLastError: true,
      );
    } catch (e, st) {
      return _classifyFailure(e, st, state, 'stageSource');
    }
  }

  /// Step 2: idempotent finalize/enqueue. Crash recovery: a lost
  /// response after a server-side-successful finalize simply means the
  /// NEXT call finalizes again for the SAME `draft_media_id` -- the
  /// backend's own Redis-backed dedupe map returns the SAME `task_id`
  /// rather than enqueueing a second transcode job (never a new
  /// `draft_media_id` is generated client-side for a retry).
  static Future<ServerTranscodeVideoState> _finalize({
    required ServerTranscodeVideoSpec spec,
    required ServerTranscodeVideoState state,
  }) async {
    try {
      final result = await ApiService.finalizeVideoSourceUpload(
        draftMediaId: spec.draftMediaId,
      );
      final taskId = (result['task_id'] ?? '').toString();
      if (taskId.isEmpty) {
        return state.copyWith(
          status: ServerTranscodeVideoStatus.failedRecoverable,
          attempts: state.attempts + 1,
          lastErrorMessage:
              'finalize_video_source_upload returned no task_id',
        );
      }
      final jobState = (result['job_state'] ?? '').toString();
      final nextStatus = jobState == 'processing'
          ? ServerTranscodeVideoStatus.transcodeProcessing
          : ServerTranscodeVideoStatus.transcodeQueued;
      return state.copyWith(
        status: nextStatus,
        taskId: taskId,
        attempts: 0,
        clearLastError: true,
      );
    } catch (e, st) {
      return _classifyFailure(e, st, state, 'finalize');
    }
  }

  /// Step 3: poll `GET /api/jobs/<task_id>` -- reuses the exact same
  /// transport `ApiService.getJobStatus` already uses for image jobs
  /// (`SellImageJobPolling`), just with its own state persisted here
  /// instead of that helper's simpler map. Network/5xx failures never
  /// discard `task_id` -- only a genuinely-confirmed terminal state
  /// (SUCCESS/FAILURE) or the poll BUDGET being exhausted (not the job
  /// itself) ends this step; a 404 here is treated the same as any other
  /// transient failure for THIS step specifically (never abandons the
  /// task id outright the way `SellAsyncJobTracker` does for images,
  /// since a video transcode job living behind
  /// `VIDEO_JOB_AUTH_TTL_SECONDS` -- 72h -- is expected to remain pollable
  /// far longer than any single resume gap).
  static Future<ServerTranscodeVideoState> _pollUntilTerminalOrBudgetExhausted({
    required ServerTranscodeVideoSpec spec,
    required ServerTranscodeVideoState state,
  }) async {
    final taskId = state.taskId;
    if (taskId == null || taskId.isEmpty) {
      // Should not happen (this status implies a task_id was persisted) --
      // fail back to finalize on the next pass rather than getting stuck.
      return state.copyWith(status: ServerTranscodeVideoStatus.sourceStaged);
    }
    for (var attempt = 0; attempt < maxPollsPerAttempt; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(pollInterval);
      }
      Map<String, dynamic> status;
      try {
        status = await ApiService.getJobStatus(taskId);
      } catch (e, st) {
        logNonFatal(e, st, 'SellServerTranscodeVideoRunner.poll');
        // Network/5xx/404 -- keep the task_id, try again on the NEXT
        // processAll() call (never burn the whole remaining budget
        // hot-looping a single transient blip within this call).
        return state.copyWith(
          status: ServerTranscodeVideoStatus.transcodeProcessing,
          attempts: state.attempts + 1,
        );
      }
      final jobState = (status['state'] ?? '').toString();
      if (jobState == 'SUCCESS') {
        return state.copyWith(
          status: ServerTranscodeVideoStatus.transcodeSucceeded,
          transcodeConfirmed: true,
          attempts: 0,
          clearLastError: true,
        );
      }
      if (jobState == 'FAILURE') {
        return state.copyWith(
          status: ServerTranscodeVideoStatus.failedPermanent,
          lastErrorMessage: 'Server-side transcode failed',
        );
      }
      // PENDING/STARTED/UNAVAILABLE -- still processing, keep polling.
    }
    // Budget exhausted for this call, job still not terminal -- leave the
    // task_id intact and resume polling on the next processAll() call.
    return state.copyWith(status: ServerTranscodeVideoStatus.transcodeProcessing);
  }

  /// Step 4: idempotent attach. Crash recovery: a lost response after a
  /// server-side-successful attach simply means the NEXT call attaches
  /// again with the SAME `(car_id, draft_media_id, task_id)` -- the
  /// backend's idempotency short-circuit (checked first, before any
  /// task/job validation) returns the SAME already-created `CarVideo`
  /// instead of creating a duplicate.
  static Future<ServerTranscodeVideoState> _attach({
    required String carId,
    required ServerTranscodeVideoSpec spec,
    required ServerTranscodeVideoState state,
  }) async {
    final taskId = state.taskId;
    if (taskId == null || taskId.isEmpty) {
      return state.copyWith(status: ServerTranscodeVideoStatus.sourceStaged);
    }
    try {
      final result = await ApiService.attachTranscodedVideo(
        carId: carId,
        draftMediaId: spec.draftMediaId,
        taskId: taskId,
      );
      final video = result['video'];
      return state.copyWith(
        status: ServerTranscodeVideoStatus.attached,
        attachedVideo: video is Map
            ? Map<String, dynamic>.from(video.cast<String, dynamic>())
            : <String, dynamic>{},
        attempts: 0,
        clearLastError: true,
      );
    } catch (e, st) {
      return _classifyFailure(e, st, state, 'attach');
    }
  }

  static ServerTranscodeVideoState _classifyFailure(
    Object e,
    StackTrace st,
    ServerTranscodeVideoState state,
    String stepTag,
  ) {
    logNonFatal(e, st, 'SellServerTranscodeVideoRunner.$stepTag');
    if (_isFeatureDisabled(e)) {
      return state.copyWith(
        status: ServerTranscodeVideoStatus.failedPermanent,
        featureDisabled: true,
        lastErrorMessage: 'feature_disabled',
      );
    }
    if (_isTransientError(e)) {
      return state.copyWith(
        status: ServerTranscodeVideoStatus.failedRecoverable,
        attempts: state.attempts + 1,
        lastErrorMessage: e.toString(),
      );
    }
    return state.copyWith(
      status: ServerTranscodeVideoStatus.failedPermanent,
      lastErrorMessage: e.toString(),
    );
  }
}
