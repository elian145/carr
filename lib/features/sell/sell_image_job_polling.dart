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
  static Future<String?> awaitImageJobRelPath(
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
          return null;
        }
        logNonFatal(e, st, '$logTag.pollJob');
        continue;
      }
      final state = (status['state'] ?? '').toString();
      if (state == 'SUCCESS') {
        final result = status['result'];
        if (result is Map) {
          final relPath = (result['rel_path'] ?? '').toString().trim();
          if (relPath.isNotEmpty) return relPath;
        }
        appLog('$logTag: job $jobId succeeded with no rel_path');
        return null;
      }
      if (state == 'FAILURE') {
        appLog('$logTag: image job $jobId failed');
        return null;
      }
      // PENDING / STARTED / UNAVAILABLE -- still processing, keep polling.
    }
    appLog('$logTag: image job $jobId timed out while polling');
    return null;
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

  /// Previously-recorded outstanding job id for [localPath], if any.
  Future<String?> lookup(String localPath) async {
    final id = draftId;
    final path = localPath.trim();
    if (id == null || path.isEmpty) return null;
    try {
      final record = await SellSubmissionStatePrefs.load(id);
      final jobId = record?.pendingAsyncImageJobs[path]?.trim();
      return (jobId != null && jobId.isNotEmpty) ? jobId : null;
    } catch (e, st) {
      logNonFatal(e, st, 'SellAsyncJobTracker.lookup');
      return null;
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
        ..[path] = jobId.trim();
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
