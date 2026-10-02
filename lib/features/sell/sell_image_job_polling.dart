import '../../services/api_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/prefs/sell_submission_state_prefs.dart';

/// P-01 / OOM-fix follow-up: shared helper for polling one Celery
/// image-processing job (`kk.tasks.image_tasks.process_car_image_file`)
/// enqueued via `?async=1` -- on either `/api/cars/<id>/images`
/// (post-create upload, see `SellListingMediaUpload`) or
/// `/api/process-car-images` (pre-create Sell prestage, see
/// `SellPhotoPrestage`) -- until it reaches a terminal state.
///
/// Extracted into one place so both callers share the same polling
/// budget/interval and the same interpretation of the job-status response
/// shape, instead of maintaining two copies that could silently drift
/// apart.
/// The full outcome of one polled image-processing job -- unlike a bare
/// `rel_path` string, this also carries whether plate-blur was actually
/// applied (`_trace_plate_blur_applied` in the task's result dict, see
/// `kk/tasks/image_tasks.py`), so a caller that cares about the DISTINCTION
/// between "job succeeded, no plate found" and "job genuinely failed" (the
/// blur-choice preview screen's truthful-state contract -- see
/// `sell_plate_blur_merge.dart`) can tell them apart instead of collapsing
/// both into a single `null`/empty `rel_path`.
class SellImageJobResult {
  const SellImageJobResult({required this.relPath, required this.plateBlurApplied});

  /// The processed image's server-relative path, or `null` on
  /// `FAILURE`/timeout/a malformed result/404 -- a genuine job failure.
  final String? relPath;

  /// Whether plate-blur was actually applied for this job. Only meaningful
  /// when [relPath] is non-null; defaults to `true` when the job succeeded
  /// but the result dict is missing the field entirely (e.g. an older
  /// server response, or a test fixture that only sets `rel_path`) -- this
  /// matches the PRE-EXISTING behavior of always treating a successful,
  /// non-empty `rel_path` as "genuinely blurred" before this field existed.
  final bool plateBlurApplied;

  bool get failed => relPath == null || relPath!.isEmpty;
}

class SellImageJobPolling {
  SellImageJobPolling._();

  /// Interval between `GET /api/jobs/<task_id>` polls.
  static const Duration pollInterval = Duration(milliseconds: 1500);

  /// Total poll budget per job -- matches [ApiService]'s existing 180s
  /// multipart upload timeout (`_uploadTimeout`), i.e. the same worst-case
  /// wait the old synchronous upload already tolerated, just spent polling
  /// a cheap status endpoint instead of blocking one HTTP upload request on
  /// the server's Roboflow call.
  static const int maxPolls = 120;

  /// Poll one Celery image-processing job until it reaches a terminal
  /// state. Returns the processed image's server-relative path
  /// (`result.rel_path`) on `SUCCESS`, or `null` on
  /// `FAILURE`/timeout/a malformed result -- callers drop that one file
  /// rather than attaching/staging a bogus path, mirroring how the old
  /// synchronous path already skipped a single rejected file instead of
  /// failing the whole batch.
  ///
  /// Thin wrapper over [awaitImageJobResult] (kept for every pre-existing
  /// caller that only ever needed the path, not the blur-applied signal --
  /// behavior here is byte-for-byte unchanged).
  static Future<String?> awaitImageJobRelPath(
    String jobId, {
    String logTag = 'SellImageJobPolling',
  }) async {
    final result = await awaitImageJobResult(jobId, logTag: logTag);
    return result.relPath;
  }

  /// Same polling loop as [awaitImageJobRelPath], but returns the full
  /// [SellImageJobResult] (including `plateBlurApplied`) instead of just
  /// the path -- used by the blur-choice preview lifecycle
  /// (`sell_car_page_plate_blur.dart`) so it can render a truthful
  /// "not blurred -- no plate detected" state instead of conflating that
  /// with a genuine job failure.
  static Future<SellImageJobResult> awaitImageJobResult(
    String jobId, {
    String logTag = 'SellImageJobPolling',
  }) async {
    for (var attempt = 0; attempt < maxPolls; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(pollInterval);
      }
      Map<String, dynamic> status;
      try {
        status = await ApiService.getJobStatus(jobId);
      } catch (e, st) {
        // A 404 means the server has no record of this job for us (e.g. the
        // Celery result backend already expired/evicted it) -- that can
        // never resolve, so stop polling immediately rather than burning
        // the full budget. Anything else (503 broker hiccup, timeout,
        // transient network error) is worth retrying within budget.
        if (e is ApiException && e.statusCode == 404) {
          appLog('$logTag: job $jobId not found while polling');
          return const SellImageJobResult(relPath: null, plateBlurApplied: false);
        }
        logNonFatal(e, st, '$logTag.pollJob');
        continue;
      }
      final state = (status['state'] ?? '').toString();
      if (state == 'SUCCESS') {
        final result = status['result'];
        if (result is Map) {
          final relPath = (result['rel_path'] ?? '').toString().trim();
          if (relPath.isNotEmpty) {
            // Missing key (older response shape/test fixture) defaults to
            // `true` -- see [SellImageJobResult.plateBlurApplied]'s doc.
            final applied = result.containsKey('_trace_plate_blur_applied')
                ? result['_trace_plate_blur_applied'] == true
                : true;
            return SellImageJobResult(relPath: relPath, plateBlurApplied: applied);
          }
        }
        appLog('$logTag: job $jobId succeeded with no rel_path');
        return const SellImageJobResult(relPath: null, plateBlurApplied: false);
      }
      if (state == 'FAILURE') {
        appLog('$logTag: image job $jobId failed');
        return const SellImageJobResult(relPath: null, plateBlurApplied: false);
      }
      // PENDING / STARTED / UNAVAILABLE -- still processing, keep polling.
    }
    appLog('$logTag: image job $jobId timed out while polling');
    return const SellImageJobResult(relPath: null, plateBlurApplied: false);
  }
}

/// OOM-fix follow-up: durable per-draft tracker for in-flight Celery image
/// job ids, keyed by the local source-photo path they were enqueued for.
///
/// Backs [SellSubmissionRecord.pendingAsyncImageJobs] so a submission
/// resumed after the app process was killed while a job was still running
/// (enqueued by `SellPhotoPrestage` or `SellListingMediaUpload`) polls the
/// SAME already-enqueued job instead of enqueueing a duplicate one for the
/// same source image -- Celery job state lives in Redis, independent of
/// which app process enqueued it, so an old job id is just as pollable as
/// one enqueued moments ago.
///
/// Purely additive/best-effort: every method is a no-op (returns `null` for
/// [lookup]) when [draftId] is `null`, so any caller that cannot supply one
/// behaves exactly as before this existed.
class SellAsyncJobTracker {
  const SellAsyncJobTracker(this.draftId);

  final String? draftId;

  /// B-fix (real-device evidence): a job id recorded longer ago than this
  /// is treated as expired/abandoned rather than re-polled. A single
  /// [SellImageJobPolling.awaitImageJobRelPath] attempt already spends up
  /// to [SellImageJobPolling.pollInterval] * [SellImageJobPolling.maxPolls]
  /// (3 minutes) before giving up and clearing its own entry -- an entry
  /// can only still be sitting in [SellSubmissionRecord.pendingAsyncImageJobs]
  /// this much later if an earlier resume attempt was interrupted (app
  /// killed/backgrounded) mid-poll, was itself already re-polled once and
  /// interrupted again, or the underlying Celery task was silently dropped
  /// (e.g. enqueued while the worker was OOM-crash-looping) and will never
  /// reach a terminal state. Real-device evidence: production repeatedly
  /// re-polling the exact same job id (`c2520566-22b1-418d-a5f9-de20f6aa1b74`)
  /// while newer jobs completed normally -- i.e. exactly this case. Set to
  /// twice the single-attempt poll budget so a genuinely slow (but alive)
  /// job surviving one interrupted poll still gets one full re-poll before
  /// being abandoned.
  /// = 2 * [SellImageJobPolling.maxPolls] * [SellImageJobPolling.pollInterval]
  /// (1.5s * 120 = 3 minutes per attempt); written as a literal since a
  /// `const` field can't call `Duration.inMilliseconds` on another const.
  static const Duration maxJobAge = Duration(minutes: 6);

  /// Encodes `jobId|recordedAtEpochMs` so [lookup] can tell an outstanding
  /// job apart from one that has been sitting unresolved for too long,
  /// without changing [SellSubmissionRecord.pendingAsyncImageJobs]'s
  /// `Map<String, String>` shape (kept JSON-simple, no schema/migration).
  static String _encode(String jobId, int recordedAtMs) => '$jobId|$recordedAtMs';

  static ({String jobId, int recordedAtMs})? _decode(String raw) {
    final parts = raw.split('|');
    if (parts.length != 2) {
      // Pre-fix records ('jobId' with no timestamp) are treated as
      // recorded "now" so they get exactly one more full poll rather than
      // being discarded outright by this change.
      final jobId = raw.trim();
      return jobId.isEmpty
          ? null
          : (jobId: jobId, recordedAtMs: DateTime.now().millisecondsSinceEpoch);
    }
    final jobId = parts[0].trim();
    final recordedAtMs = int.tryParse(parts[1]);
    if (jobId.isEmpty || recordedAtMs == null) return null;
    return (jobId: jobId, recordedAtMs: recordedAtMs);
  }

  /// Previously-recorded outstanding job id for [localPath], if any and
  /// not abandoned (see [maxJobAge]) -- an abandoned entry is cleared as a
  /// side effect and treated the same as "no recorded job", so the caller
  /// enqueues a fresh one instead of re-polling a job that will never
  /// resolve.
  ///
  /// Resume-audit fix (real-device evidence): [maxJobAge] alone used to be
  /// the abandonment decision -- a fixed wall-clock cutoff with no check
  /// of whether the job is actually still alive. A genuinely slow (but
  /// still processing) Celery job crossing that age -- e.g. a large
  /// backlog, or several short interrupted resumes adding up -- would be
  /// abandoned and a duplicate job enqueued for the same source image
  /// purely because of the clock, not because the job was actually gone.
  /// Age is now only a trigger to double-check the job's real server-side
  /// state via [ApiService.getJobStatus].
  ///
  /// Follow-up correction: the double-check must only ever ABANDON
  /// (clear + return `null`, letting the caller enqueue a replacement)
  /// when the server has *affirmatively confirmed the job id itself is
  /// unknown* (404 -- e.g. evicted from the Celery result backend). Every
  /// other outcome of the check must return the existing job id unchanged
  /// so nothing is duplicated and nothing durable is discarded:
  ///  - PENDING/STARTED: still genuinely in flight -- obviously keep it.
  ///  - SUCCESS/FAILURE/REVOKED (or any other non-404 terminal state):
  ///    the job already has an outcome that hasn't been consumed yet --
  ///    handing the id back lets the normal poll immediately below
  ///    (a single fast round-trip, since it's already terminal) reconcile
  ///    a success or apply the existing failure/needsAttention policy,
  ///    instead of this age check silently discarding the result and
  ///    enqueueing a pointless duplicate job for an image already done.
  ///  - Network timeout / socket error / offline / any 5xx: the server's
  ///    real state is simply unknown right now -- NOT evidence the job is
  ///    gone. Keep the entry persisted and let the caller's own bounded
  ///    retry (the next resume, or the next poll attempt) re-check later
  ///    instead of abandoning a possibly-live job because of a transient
  ///    connectivity blip.
  Future<String?> lookup(String localPath) async {
    final id = draftId;
    final path = localPath.trim();
    if (id == null || path.isEmpty) return null;
    try {
      final record = await SellSubmissionStatePrefs.load(id);
      final raw = record?.pendingAsyncImageJobs[path]?.trim();
      if (raw == null || raw.isEmpty) return null;
      final decoded = _decode(raw);
      if (decoded == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - decoded.recordedAtMs;
      if (age > maxJobAge.inMilliseconds) {
        if (await _isJobGenuinelyUnknown(decoded.jobId)) {
          appLog(
            'SellAsyncJobTracker: job ${decoded.jobId} for $path is stale '
            '(recorded ${Duration(milliseconds: age).inMinutes}m ago) and '
            'the server confirms via 404 it no longer knows this job id; '
            'abandoning instead of re-polling forever',
          );
          await clear(path);
          return null;
        }
        appLog(
          'SellAsyncJobTracker: job ${decoded.jobId} for $path is older '
          'than ${maxJobAge.inMinutes}m but the server has not confirmed '
          'it is gone (still active, already resolved, or unreachable); '
          'returning it so the normal poll can reconcile/retry instead of '
          'abandoning on wall-clock age alone',
        );
      }
      return decoded.jobId;
    } catch (e, st) {
      logNonFatal(e, st, 'SellAsyncJobTracker.lookup');
      return null;
    }
  }

  /// True ONLY when the server affirmatively confirms via a 404 that
  /// [jobId] itself is unknown to it (e.g. evicted from the Celery result
  /// backend) -- the one case where continuing to track/poll this id can
  /// never resolve, so it is safe to abandon. Every other outcome --
  /// a successful status fetch in ANY state (including terminal
  /// SUCCESS/FAILURE/REVOKED, which the normal poll below must still get
  /// a chance to reconcile), a non-404 [ApiException] (e.g. a transient
  /// 5xx), or a raw transport failure (`TimeoutException`,
  /// `SocketException`, offline, etc.) -- returns `false`, i.e. "do not
  /// treat this as gone."
  static Future<bool> _isJobGenuinelyUnknown(String jobId) async {
    try {
      await ApiService.getJobStatus(jobId);
      return false;
    } catch (e) {
      return e is ApiException && e.statusCode == 404;
    }
  }

  /// Records that [jobId] is now outstanding for [localPath].
  Future<void> record(String localPath, String jobId) async {
    final id = draftId;
    final path = localPath.trim();
    if (id == null || path.isEmpty || jobId.trim().isEmpty) return;
    try {
      final record = await SellSubmissionStatePrefs.load(id);
      if (record == null) return;
      final next = Map<String, String>.from(record.pendingAsyncImageJobs)
        ..[path] = _encode(jobId.trim(), DateTime.now().millisecondsSinceEpoch);
      await SellSubmissionStatePrefs.upsert(
        record.copyWith(pendingAsyncImageJobs: next),
      );
    } catch (e, st) {
      logNonFatal(e, st, 'SellAsyncJobTracker.record');
    }
  }

  /// Clears any recorded job id for [localPath] -- call once its job has
  /// resolved, success or failure, so a stale/expired id is never reused.
  Future<void> clear(String localPath) async {
    final id = draftId;
    final path = localPath.trim();
    if (id == null || path.isEmpty) return;
    try {
      final record = await SellSubmissionStatePrefs.load(id);
      if (record == null || !record.pendingAsyncImageJobs.containsKey(path)) {
        return;
      }
      final next = Map<String, String>.from(record.pendingAsyncImageJobs)
        ..remove(path);
      await SellSubmissionStatePrefs.upsert(
        record.copyWith(pendingAsyncImageJobs: next),
      );
    } catch (e, st) {
      logNonFatal(e, st, 'SellAsyncJobTracker.clear');
    }
  }
}
