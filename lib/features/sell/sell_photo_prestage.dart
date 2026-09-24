import 'package:image_picker/image_picker.dart';

import '../../services/ai_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/listings/listing_image_media.dart';
import 'sell_image_job_polling.dart';

/// Uploads listing photos to storage *before* the listing row is created.
///
/// `POST /api/cars` takes no photos, so photos can only be linked to a listing
/// that already exists. Staging the bytes first turns that second request into
/// a small "attach these URLs" call, so a new listing is never published with
/// its photos still in flight.
///
/// OOM-fix follow-up: staging now goes through the existing Celery async
/// image-processing pipeline (`POST /api/process-car-images?async=1` ->
/// `kk.tasks.image_tasks.process_car_image_file`) instead of running the
/// full synchronous PIL decode/plate-blur/downscale/encode pipeline inline
/// on this request, inside the single-worker `carr` Gunicorn web process.
/// That synchronous call (previously via
/// `AiService.processCarImagesToServerPayload`, with no `async=1`) was the
/// confirmed root cause of a production out-of-memory crash: every new Sell
/// submission ran two such synchronous batches (listing + damage photos) in
/// parallel at the very start of submission, on top of an already
/// memory-tight web process. See [stageCarData] for why those two batches
/// are now sequential instead of parallel.
class SellPhotoPrestage {
  SellPhotoPrestage._();

  /// Draft-only key holding the local path a staged photo was uploaded from.
  static const String stagedFromKey = 'staged_from';

  static const List<String> _mediaKeys = <String>['images', 'damage_images'];

  /// Rewrites local photo entries in [carData] to server URLs.
  ///
  /// Returns the number of photos staged. Returns 0 (leaving [carData]
  /// untouched) when there is nothing to stage or the upload did not fully
  /// succeed, so the caller falls back to uploading after the listing exists.
  static Future<int> stageCarData(
    Map<String, dynamic> carData, {
    void Function(int staged, int total)? onProgress,
    String? draftId,
  }) async {
    // OOM-fix follow-up: listing and damage photos used to stage in
    // parallel (`Future.wait`). Both batches now enqueue work on the same
    // shared `carr-worker-fra` Celery pool (`--concurrency=2`) instead of
    // running inline in the web process, so running them in parallel no
    // longer buys meaningful wall-clock time for the user (the bottleneck
    // moved from "one web request's CPU" to "the worker pool's queue
    // depth") -- it would only double the number of jobs one seller can
    // have in flight against that pool at once. Staging sequentially keeps
    // per-submission worker-queue pressure bounded without adding a
    // separate concurrency-limiting mechanism.
    var total = 0;
    for (final key in _mediaKeys) {
      total += await _stageList(
        carData,
        key,
        onProgress: onProgress,
        draftId: draftId,
      );
    }
    return total;
  }

  static Future<int> _stageList(
    Map<String, dynamic> carData,
    String key, {
    void Function(int staged, int total)? onProgress,
    String? draftId,
  }) async {
    final raw = carData[key];
    if (raw is! List || raw.isEmpty) return 0;

    final items = List<dynamic>.from(raw);
    final pendingIndexes = <int>[];
    final files = <XFile>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (ListingImageMedia.id(item) != null) continue;
      final source = ListingImageMedia.source(item);
      if (source.startsWith('http://') ||
          source.startsWith('https://') ||
          source.startsWith('uploads/') ||
          source.startsWith('static/') ||
          source.startsWith('/static/')) {
        continue;
      }
      final local = ListingImageMedia.localFile(item);
      if (local == null) continue;
      pendingIndexes.add(i);
      files.add(local);
    }
    if (files.isEmpty) return 0;

    onProgress?.call(0, files.length);
    List<String>? urls;
    try {
      urls = await _enqueueAndAwaitAll(
        files,
        logTag: 'SellPhotoPrestage.$key',
        tracker: SellAsyncJobTracker(draftId),
      );
    } catch (e, st) {
      logNonFatal(e, st, 'SellPhotoPrestage.$key');
      return 0;
    }

    urls ??= const <String>[];
    // A short response means some photo failed and the remaining URLs can no
    // longer be matched to their slots; re-upload all of them after create
    // rather than attaching photos to the wrong positions.
    if (urls.length != files.length) {
      appLog(
        'SellPhotoPrestage: staged ${urls.length}/${files.length} $key; '
        'falling back to upload after create',
      );
      return 0;
    }

    for (var i = 0; i < pendingIndexes.length; i++) {
      final index = pendingIndexes[i];
      final item = items[index];
      final rewritten = ListingImageMedia.map(
        item,
        source: urls[i],
        focusY: ListingImageMedia.focusY(item),
        width: ListingImageMedia.width(item),
        height: ListingImageMedia.height(item),
      );
      // Kept so the upload can fall back to the local copy if the server
      // refuses the staged URL (e.g. an older backend build).
      rewritten[stagedFromKey] = files[i].path;
      items[index] = rewritten;
    }
    carData[key] = items;
    onProgress?.call(files.length, files.length);
    appLog('SellPhotoPrestage: staged ${files.length} $key before create');
    return files.length;
  }

  /// Enqueues [files] on `POST /api/process-car-images?async=1` and polls
  /// each resulting job for its `rel_path`, batching by 3 with a
  /// same-size retry and a per-file fallback -- mirrors the batching/retry
  /// shape the old synchronous `AiService.processCarImagesToServerPayload`
  /// call used, so the same connection-size/timeout safety margins this
  /// method was tuned for (see that method's comment) are preserved even
  /// though the actual image processing no longer happens inline.
  ///
  /// Returns one path per input file that staged successfully, in order,
  /// possibly shorter than [files] if any file (or a whole batch) could not
  /// be staged -- callers must treat a short result as "not all photos
  /// staged" exactly as before.
  ///
  /// OOM-fix follow-up: when [tracker] has a durably-recorded outstanding
  /// job id for a file (from an earlier, possibly killed, process), that
  /// job is polled directly instead of enqueueing a duplicate one -- see
  /// [SellAsyncJobTracker].
  static Future<List<String>?> _enqueueAndAwaitAll(
    List<XFile> files, {
    required String logTag,
    SellAsyncJobTracker? tracker,
  }) async {
    // resolved[i] corresponds to files[i]; null until staged. Filled either
    // by reusing a previously-recorded job (below) or by a fresh enqueue.
    final resolved = List<String?>.filled(files.length, null);
    final freshIndexes = <int>[];
    for (var i = 0; i < files.length; i++) {
      final path = files[i].path;
      final existingJobId = await tracker?.lookup(path);
      if (existingJobId == null) {
        freshIndexes.add(i);
        continue;
      }
      final relPath = await SellImageJobPolling.awaitImageJobRelPath(
        existingJobId,
        logTag: logTag,
      );
      await tracker?.clear(path);
      if (relPath != null && relPath.isNotEmpty) {
        resolved[i] = relPath;
      } else {
        // Recorded job is gone/failed/expired -- enqueue a replacement.
        freshIndexes.add(i);
      }
    }

    Future<List<String>?> sendBatch(List<XFile> batch) async {
      final jobIds = await AiService.enqueueCarImagesAsync(
        batch,
        skipBlur: true,
      );
      if (jobIds == null || jobIds.length != batch.length) return null;
      if (tracker != null) {
        for (var k = 0; k < batch.length; k++) {
          await tracker.record(batch[k].path, jobIds[k]);
        }
      }
      // Poll every job (even after one fails) so every recorded id is
      // cleared before this returns -- never leaves a stale tracker entry
      // for a job this call already learned the outcome of.
      final paths = List<String?>.filled(batch.length, null);
      for (var k = 0; k < jobIds.length; k++) {
        final relPath = await SellImageJobPolling.awaitImageJobRelPath(
          jobIds[k],
          logTag: logTag,
        );
        await tracker?.clear(batch[k].path);
        paths[k] = (relPath != null && relPath.isNotEmpty) ? relPath : null;
      }
      if (paths.any((p) => p == null)) return null;
      return paths.cast<String>();
    }

    const int batchSize = 3;
    for (int i = 0; i < freshIndexes.length; i += batchSize) {
      final end = (i + batchSize) > freshIndexes.length
          ? freshIndexes.length
          : (i + batchSize);
      final batchIndexes = freshIndexes.sublist(i, end);
      final batch = [for (final idx in batchIndexes) files[idx]];
      List<String>? res;

      // Retry per-batch; if still failing, fall back to single-image batches.
      for (int attempt = 0; attempt < 2 && res == null; attempt++) {
        try {
          if (attempt > 0) await Future.delayed(const Duration(seconds: 2));
          res = await sendBatch(batch);
        } catch (e) {
          appLog(
            '$logTag: Batch error (size=${batch.length}, attempt=${attempt + 1}): $e',
          );
        }
      }

      if (res != null && res.length == batch.length) {
        for (var k = 0; k < batchIndexes.length; k++) {
          resolved[batchIndexes[k]] = res[k];
        }
        continue;
      }

      if (batch.length > 1) {
        for (var k = 0; k < batch.length; k++) {
          try {
            final one = await sendBatch([batch[k]]);
            if (one != null && one.length == 1) {
              resolved[batchIndexes[k]] = one[0];
            }
          } catch (e) {
            appLog('$logTag: Single-image batch error: $e');
          }
        }
      }
    }

    return [for (final r in resolved) if (r != null) r];
  }
}
