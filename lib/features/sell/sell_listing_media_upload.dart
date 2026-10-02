import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/car_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/debug/expected_client_noise.dart';
import '../../shared/listings/listing_image_media.dart';
import '../../shared/prefs/sell_draft_media_persistence.dart';
import 'sell_image_job_polling.dart';
import 'sell_media_identity.dart';
import 'sell_photo_prestage.dart';
import 'sell_server_transcode_runner.dart';
import 'sell_server_transcode_video.dart';
import 'sell_video_helpers.dart';

/// Phases reported while [SellListingMediaUpload.uploadForCar] runs.
enum SellMediaUploadPhase {
  photos,
  videos,
  damagePhotos,

  /// Phase 3B: finer-grained sub-phases for the server-transcode video
  /// pipeline (`sell_server_transcode_runner.dart`'s own
  /// `SellServerTranscodePhase`, mapped 1:1 here) -- reported INSTEAD OF
  /// the coarse [videos] value while a `server_transcode_videos` entry is
  /// being processed, so callers that want finer UI text (see
  /// `PendingSellSubmissionService`'s `onPhase` switch and the global
  /// `SellSubmissionStatusBanner`) can distinguish "uploading the
  /// original source", "processing on the server", and "attaching the
  /// result" instead of one generic "uploading videos" label for the
  /// whole pipeline. Callers that only switch on the pre-existing three
  /// values above are unaffected by this addition to a *new* dart
  /// enum -- Dart requires an exhaustive switch to be updated at compile
  /// time, which is intentional here (see the call site below).
  serverTranscodeUploading,
  serverTranscodeProcessing,
  serverTranscodeFinishing,
}

/// Maps the server-transcode runner's own phase enum to the
/// [SellMediaUploadPhase] values above -- kept here (not inside the
/// runner) so `sell_server_transcode_runner.dart` itself never needs to
/// know about [SellMediaUploadPhase] or any UI concern, preserving its
/// existing, already-verified resume/idempotency logic untouched.
SellMediaUploadPhase _mediaUploadPhaseForTranscode(
  SellServerTranscodePhase phase,
) {
  switch (phase) {
    case SellServerTranscodePhase.uploadingSource:
      return SellMediaUploadPhase.serverTranscodeUploading;
    case SellServerTranscodePhase.processing:
      return SellMediaUploadPhase.serverTranscodeProcessing;
    case SellServerTranscodePhase.finishing:
      return SellMediaUploadPhase.serverTranscodeFinishing;
  }
}

/// Uploads listing / damage / video media for a car that already exists on the server.
class SellListingMediaUpload {
  SellListingMediaUpload._();

  static String? _imageUrlFromApiDict(dynamic item) {
    if (item is Map) {
      return (item['image_url'] ?? item['url'] ?? item['path'] ?? '')
          .toString()
          .trim();
    }
    return item?.toString().trim();
  }

  /// Placeholder-regression fix (real-device evidence): zips each row of
  /// the attach response against the ORIGINAL item it actually belongs
  /// to. [sourceItems] is the caller's FULL original item list, but the
  /// response's `rows` can be SHORTER than it whenever an upload path
  /// drops a failed/timed-out item before attaching the rest (see
  /// [_uploadImagesViaAsyncJobs]'s `relPaths` compaction) -- zipping
  /// `rows[i]` against `sourceItems[i]` by raw position in that case
  /// silently misassigns every row from the first failure onward (wrong
  /// item gets the id, and the true last-successful item gets none at
  /// all). When the upload path recorded which original item survived
  /// that compaction (`response['_client_succeeded_sources']`, aligned
  /// 1:1 with `rows`), use THAT instead of raw position; only fall back
  /// to positional zipping when it is absent (the pre-existing,
  /// already-1:1 call sites, e.g. the synchronous `attachCarImages`
  /// legacy path with no prior compaction).
  static void _collectUploadedImageIds(
    Map<String, int> idsBySource,
    List<dynamic> sourceItems,
    Map<String, dynamic>? response,
  ) {
    final rows = response?['images'] ?? response?['uploaded'];
    if (rows is! List) return;
    final succeededSources = response?['_client_succeeded_sources'];
    if (succeededSources is List && succeededSources.length == rows.length) {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row is! Map) continue;
        final id = int.tryParse((row['id'] ?? '').toString());
        final source = succeededSources[i].toString();
        if (id != null && source.isNotEmpty) idsBySource[source] = id;
      }
      return;
    }
    for (var i = 0; i < sourceItems.length && i < rows.length; i++) {
      final row = rows[i];
      if (row is! Map) continue;
      final id = int.tryParse((row['id'] ?? '').toString());
      final source = ListingImageMedia.source(sourceItems[i]);
      if (id != null && source.isNotEmpty) idsBySource[source] = id;
    }
  }

  static Future<void> _saveListingImageLayout(
    String carId,
    List<dynamic> orderedImages,
    Map<String, int> idsBySource,
  ) async {
    final payload = <Map<String, dynamic>>[];
    for (var i = 0; i < orderedImages.length; i++) {
      final item = orderedImages[i];
      final source = ListingImageMedia.source(item);
      final id = ListingImageMedia.id(item) ?? idsBySource[source];
      if (id == null) continue;
      final row = <String, dynamic>{
        'id': id,
        'order': i,
        'is_primary': i == 0,
        'focus_y': ListingImageMedia.focusY(item),
      };
      final width = ListingImageMedia.width(item);
      final height = ListingImageMedia.height(item);
      if (width != null) row['image_width'] = width;
      if (height != null) row['image_height'] = height;
      payload.add(row);
    }
    if (payload.isNotEmpty) {
      await ApiService.updateCarImageLayout(carId, payload);
    }
  }

  static String? _primaryListingImageRef(
    dynamic firstImage, {
    Map<String, dynamic>? listingMediaResponse,
  }) {
    final s = ListingImageMedia.source(firstImage);
    if (s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('uploads/') ||
        s.startsWith('static/') ||
        s.startsWith('/static/')) {
      return s;
    }
    if (listingMediaResponse != null) {
      final dynamic responseImages =
          listingMediaResponse['images'] ?? listingMediaResponse['uploaded'];
      if (responseImages is List && responseImages.isNotEmpty) {
        final url = _imageUrlFromApiDict(responseImages.first);
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  static Future<void> _applyPrimaryListingImage(
    String carId,
    List<dynamic> orderedImages, {
    Map<String, dynamic>? listingMediaResponse,
  }) async {
    if (orderedImages.isEmpty) return;
    final primaryRef = _primaryListingImageRef(
      orderedImages.first,
      listingMediaResponse: listingMediaResponse,
    );
    if (primaryRef == null || primaryRef.isEmpty) return;
    try {
      await ApiService.setCarPrimaryImage(carId, primaryRef);
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  static List<dynamic> _imagesWithPrimaryFirst(
    List<dynamic> images, {
    int primaryIndex = 0,
  }) {
    if (images.isEmpty) return const <dynamic>[];
    final i = primaryIndex.clamp(0, images.length - 1);
    if (i == 0) return List<dynamic>.from(images);
    final copy = List<dynamic>.from(images);
    final item = copy.removeAt(i);
    copy.insert(0, item);
    return copy;
  }

  static int _primaryImageIndex(Map<String, dynamic> carData, {int length = 0}) {
    final raw = carData['primary_image_index'];
    final parsed = raw is int
        ? raw
        : int.tryParse(raw?.toString() ?? '') ?? 0;
    if (length <= 0) return parsed < 0 ? 0 : parsed;
    if (parsed < 0) return 0;
    if (parsed >= length) return 0;
    return parsed;
  }

  static int _imageCountOfKind(Map<String, dynamic> car, String kind) {
    final imgs = car['images'];
    if (imgs is! List) return 0;
    var count = 0;
    for (final it in imgs) {
      final itemKind = it is Map
          ? (it['kind'] ?? 'listing').toString().toLowerCase()
          : 'listing';
      if (kind == 'damage') {
        if (itemKind == 'damage') count++;
      } else if (itemKind != 'damage') {
        count++;
      }
    }
    return count;
  }

  static int _listingImageCount(Map<String, dynamic> car) =>
      _imageCountOfKind(car, 'listing');

  static Future<Map<String, dynamic>?> _fetchCarMap(String carId) async {
    try {
      final fresh = await ApiService.getCar(carId);
      // [ApiService.getCar] already unwraps `{car: ...}`; keep a nested
      // fallback for callers that still return the envelope.
      final inner = fresh['car'];
      if (inner is Map) {
        return Map<String, dynamic>.from(inner.cast<String, dynamic>());
      }
      return fresh;
    } catch (e, st) {
      logNonFatal(e, st);
      return null;
    }
  }

  static Future<int> _remoteImageCount(String carId, String kind) async {
    final car = await _fetchCarMap(carId);
    if (car == null) return 0;
    return _imageCountOfKind(car, kind);
  }

  /// C-fix (real-device evidence): sources (URL/path) of every [kind] image
  /// the server already has attached to [carId], right now.
  ///
  /// Used to skip re-attaching a staged/already-uploaded source on a
  /// resumed run -- `attachCarImages` itself performs no dedupe, so
  /// calling it again for a source the server already attached (e.g. a
  /// `resumeAll` re-running a submission whose "attach succeeded" ack was
  /// lost client-side, or an earlier run in the same process that already
  /// finished this step) creates a duplicate image row for the same
  /// carId. Best-effort — any failure returns an empty set (the pre-
  /// existing "assume nothing landed yet" behavior), never blocks upload.
  static Future<Set<String>> _existingAttachedSources(
    String carId,
    String kind,
  ) async {
    final car = await _fetchCarMap(carId);
    final imgs = car?['images'];
    if (imgs is! List) return const <String>{};
    final result = <String>{};
    for (final it in imgs) {
      if (it is! Map) continue;
      final itemKind = (it['kind'] ?? 'listing').toString().toLowerCase();
      final matchesKind = kind == 'damage'
          ? itemKind == 'damage'
          : itemKind != 'damage';
      if (!matchesKind) continue;
      final url = _imageUrlFromApiDict(it);
      if (url != null && url.isNotEmpty) result.add(url);
    }
    return result;
  }

  /// Removes entries from [sources]/[items] (parallel lists, filtered
  /// in-place so both stay index-aligned) whose source is already in
  /// [existing]. Returns how many were removed, for logging.
  static int _dropAlreadyAttached(
    List<String> sources,
    List<dynamic> items,
    Set<String> existing,
  ) {
    if (existing.isEmpty || sources.isEmpty) return 0;
    final keepSources = <String>[];
    final keepItems = <dynamic>[];
    var dropped = 0;
    for (var i = 0; i < sources.length; i++) {
      if (existing.contains(sources[i])) {
        dropped++;
      } else {
        keepSources.add(sources[i]);
        keepItems.add(items[i]);
      }
    }
    if (dropped > 0) {
      sources
        ..clear()
        ..addAll(keepSources);
      items
        ..clear()
        ..addAll(keepItems);
    }
    return dropped;
  }

  static bool _isTransientUploadError(Object error) {
    if (error is TimeoutException) return true;
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

  /// P-01: poll one Celery image-processing job until it reaches a terminal
  /// state. Returns the processed image's server-relative path on success,
  /// or `null` on failure/timeout. Delegates to the shared
  /// [SellImageJobPolling] helper also used by [SellPhotoPrestage]'s async
  /// prestage path (OOM-fix follow-up), so both callers share one polling
  /// budget/interval instead of maintaining two copies.
  static Future<String?> _awaitImageJobRelPath(String jobId) =>
      SellImageJobPolling.awaitImageJobRelPath(
        jobId,
        logTag: 'SellListingMediaUpload',
      );

  /// P-01: enqueues [files] on the existing async image-processing pipeline
  /// (`?async=1` on `POST /api/cars/<id>/images` ->
  /// `kk.tasks.image_tasks.process_car_image_file`) instead of blocking the
  /// upload request on the Roboflow plate-blur call, polls
  /// `GET /api/jobs/<task_id>` (existing job-status endpoint) for every
  /// enqueued job, then attaches the resulting server paths via the
  /// existing `POST /api/cars/<id>/images/attach` endpoint -- the same
  /// endpoint already used elsewhere in this file for pre-staged photos.
  ///
  /// Returns the attach response (`{"images": [...]}`), the exact same
  /// shape the old synchronous multipart upload returned, so every caller
  /// in this file (`_collectUploadedImageIds`, `_attachedRowCount`,
  /// primary-image/layout logic) needs no changes.
  /// OOM-fix follow-up: when [tracker] has a durably-recorded outstanding
  /// job id for one of [files] (from an earlier, possibly killed,
  /// process), that job is polled directly instead of enqueueing a
  /// duplicate one -- see [SellAsyncJobTracker].
  static Future<Map<String, dynamic>> _uploadImagesViaAsyncJobs({
    required String carId,
    required List<XFile> files,
    required String imageKind,
    SellAsyncJobTracker? tracker,

    /// Media-readiness: clientMediaIds[i] is the manifest id for files[i]
    /// (positionally aligned, same length as [files]) -- see
    /// [ApiService.uploadCarImages]'s doc for the full contract. A job
    /// resumed from [tracker] (already enqueued in an earlier, possibly
    /// killed, process) never re-sends its id -- the manifest row was
    /// already advanced to `processing` by that earlier enqueue call.
    List<String?>? clientMediaIds,

    /// Placeholder-regression fix: positionally aligned with [files]
    /// (same length) when provided -- used ONLY to reconstruct which
    /// ORIGINAL item each row of the attach response below corresponds
    /// to, since [relPaths] (built further down) drops any index whose
    /// job failed/timed out, breaking a naive 1:1 zip against the full
    /// original item list once any item in the batch fails (see
    /// `_collectUploadedImageIds`'s doc comment).
    List<dynamic>? items,

    /// Architecture fix (see [SellMediaIdentity.skipBlurForFinalSubmission]):
    /// forwarded to the enqueue call below as `blurPlates: !skipBlur`.
    /// Defaults to `true` (the pre-fix, always-unblurred behavior) so any
    /// not-yet-updated caller keeps its exact previous behavior.
    bool skipBlur = true,
  }) async {
    // resolved[i] corresponds to files[i]; filled either by reusing a
    // previously-recorded job or by a fresh enqueue below.
    final resolved = List<String?>.filled(files.length, null);
    final freshIndexes = <int>[];
    for (var i = 0; i < files.length; i++) {
      final path = files[i].path;
      final existingJobId = await tracker?.lookup(path);
      if (existingJobId == null) {
        freshIndexes.add(i);
        continue;
      }
      final relPath = await _awaitImageJobRelPath(existingJobId);
      await tracker?.clear(path);
      if (relPath != null && relPath.isNotEmpty) {
        resolved[i] = relPath;
      } else {
        // Recorded job is gone/failed/expired -- enqueue a replacement.
        freshIndexes.add(i);
      }
    }

    if (freshIndexes.isNotEmpty) {
      final freshFiles = [for (final i in freshIndexes) files[i]];
      final freshClientMediaIds = clientMediaIds == null
          ? null
          : [
              for (final i in freshIndexes)
                i < clientMediaIds.length ? clientMediaIds[i] : null,
            ];
      final enqueueResponse = await ApiService.uploadCarImages(
        carId,
        freshFiles,
        imageKind: imageKind,
        async: true,
        clientMediaIds: freshClientMediaIds,
        blurPlates: !skipBlur,
      );
      final rawJobIds = enqueueResponse['job_ids'];
      final jobIds = rawJobIds is List
          ? rawJobIds
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList()
          : const <String>[];
      if (jobIds.isEmpty) {
        // Every file was rejected before it could even be enqueued (bad
        // extension/size/cap) -- surface the server's message exactly like
        // the synchronous path's 400 would have.
        throw ApiException(
          statusCode: 400,
          message: (enqueueResponse['message'] as String?) ??
              'No valid images were uploaded.',
        );
      }
      // jobIds correspond 1:1, in order, to freshFiles -- the server
      // validates every file before enqueueing any of them for this
      // route, so a rejected file fails the whole request rather than
      // silently shifting positions (see AiService.enqueueCarImagesAsync).
      if (tracker != null) {
        for (var k = 0; k < jobIds.length && k < freshFiles.length; k++) {
          await tracker.record(freshFiles[k].path, jobIds[k]);
        }
      }
      for (var k = 0; k < jobIds.length && k < freshIndexes.length; k++) {
        final relPath = await _awaitImageJobRelPath(jobIds[k]);
        await tracker?.clear(freshFiles[k].path);
        if (relPath != null && relPath.isNotEmpty) {
          resolved[freshIndexes[k]] = relPath;
        }
      }
    }

    final relPaths = [for (final r in resolved) if (r != null) r];
    if (relPaths.isEmpty) {
      // Every enqueued job failed or timed out -- treat like a transient
      // server-side failure so the outer retry loop gets another attempt.
      throw ApiException(
        statusCode: 502,
        message: 'Photo processing failed. Please try again.',
      );
    }

    // Placeholder-regression fix: [relPaths] is a COMPACTED (nulls
    // dropped) view of [resolved] -- when [items] is available and
    // aligned with [files], record which ORIGINAL item survived that
    // compaction, in the SAME order as [relPaths], so the caller can zip
    // the attach response's rows against the correct original item
    // instead of blindly against the full, un-compacted original list.
    final succeededSources = (items != null && items.length == files.length)
        ? [
            for (var i = 0; i < resolved.length; i++)
              if (resolved[i] != null) ListingImageMedia.source(items[i]),
          ]
        : null;
    final response = await CarService().attachCarImages(
      carId,
      relPaths,
      kind: imageKind,
    );
    if (succeededSources != null) {
      response['_client_succeeded_sources'] = succeededSources;
    }
    return response;
  }

  /// Uploads [files] and treats "client timed out after the server saved them"
  /// as success so a retry does not duplicate photos.
  ///
  /// P-01: uploads now go through the async job pipeline
  /// ([_uploadImagesViaAsyncJobs]) -- the request that stages each file on
  /// the server returns almost immediately, and the (potentially slow)
  /// plate-blur work happens in a Celery worker while this polls a
  /// lightweight status endpoint, instead of one HTTP upload request
  /// blocking on Roboflow for up to a minute per photo.
  static Future<Map<String, dynamic>> _uploadImagesResilient({
    required String carId,
    required List<XFile> files,
    String imageKind = 'listing',
    int? alreadyOnServer,
    String? draftId,

    /// Media-readiness: draft-media items positionally aligned with
    /// [files] (same length), used ONLY to derive each file's stable
    /// `client_media_id` (see [SellMediaIdentity.forImageItem]) -- never
    /// read for anything else here. `null`/mismatched length is fully
    /// backwards compatible (no ids sent, matching pre-existing
    /// behavior).
    List<dynamic>? items,

    /// Architecture fix (see [SellMediaIdentity.skipBlurForFinalSubmission]):
    /// forwarded to [_uploadImagesViaAsyncJobs]. Defaults to `true` (the
    /// pre-fix, always-unblurred behavior) for any not-yet-updated caller.
    bool skipBlur = true,
  }) async {
    if (files.isEmpty) return <String, dynamic>{};
    final kind = imageKind.toLowerCase() == 'damage' ? 'damage' : 'listing';
    final before = alreadyOnServer ?? await _remoteImageCount(carId, kind);
    final tracker = SellAsyncJobTracker(draftId);
    final clientMediaIds = (items != null && items.length == files.length)
        ? [
            for (final item in items)
              SellMediaIdentity.forImageItem(item, kind: kind),
          ]
        : null;
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        final landed = await _remoteImageCount(carId, kind);
        if (landed > before) {
          appLog(
            'SellListingMediaUpload: $kind images already on server '
            '($landed) after prior attempt',
          );
          return <String, dynamic>{'images': <dynamic>[]};
        }
        ApiService.recycleProductionHttpClient();
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
      try {
        return await _uploadImagesViaAsyncJobs(
          carId: carId,
          files: files,
          imageKind: imageKind,
          tracker: tracker,
          clientMediaIds: clientMediaIds,
          items: items,
          skipBlur: skipBlur,
        );
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        final landed = await _remoteImageCount(carId, kind);
        if (landed > before) {
          appLog(
            'SellListingMediaUpload: $kind images landed despite error: $e',
          );
          return <String, dynamic>{'images': <dynamic>[]};
        }
        if (!_isTransientUploadError(e) || attempt == 2) {
          Error.throwWithStackTrace(e, st);
        }
        appLog(
          'SellListingMediaUpload: retrying $kind upload '
          '(${attempt + 1}/3): $e',
        );
      }
    }
    Error.throwWithStackTrace(
      lastError!,
      lastStack ?? StackTrace.current,
    );
  }

  /// True when [file] can be read for multipart upload.
  ///
  /// Prefer [File.existsSync] for normal paths; fall back to [XFile.length]
  /// for content URIs / sandbox paths where dart:io File lies.
  static Future<bool> _localUploadFileExists(XFile file) async {
    final path = file.path.trim();
    if (path.isEmpty) return false;
    try {
      if (File(path).existsSync()) return true;
    } catch (e, st) {
      logNonFatal(e, st);
    }
    try {
      final len = await file.length();
      return len > 0;
    } catch (e, st) {
      logNonFatal(e, st);
      return false;
    }
  }

  static Future<bool> _waitForLocalUploadFile(XFile file) async {
    if (await _localUploadFileExists(file)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (await _localUploadFileExists(file)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return _localUploadFileExists(file);
  }

  /// Local copy of a photo that was uploaded to storage before the listing
  /// existed, used when the server refuses to attach the staged URL.
  static XFile? _stagedLocalFile(dynamic item) {
    if (item is! Map) return null;
    final path = (item[SellPhotoPrestage.stagedFromKey] ?? '')
        .toString()
        .trim();
    return path.isEmpty ? null : XFile(path);
  }

  static int _attachedRowCount(Map<String, dynamic>? response) {
    final rows = response?['images'] ?? response?['uploaded'];
    return rows is List ? rows.length : 0;
  }

  /// Re-uploads staged photos the server would not attach.
  ///
  /// A build that predates owner-tagged storage keys skips those URLs silently,
  /// which would otherwise publish a listing with no photos at all.
  static Future<Map<String, dynamic>?> _recoverRejectedAttach({
    required String carId,
    required List<dynamic> attachItems,
    required String kind,
    String? draftId,
  }) async {
    final files = <XFile>[];
    final matchedItems = <dynamic>[];
    for (final item in attachItems) {
      final local = _stagedLocalFile(item);
      if (local != null && await _localUploadFileExists(local)) {
        files.add(local);
        matchedItems.add(item);
      }
    }
    if (files.isEmpty) return null;
    appLog(
      'SellListingMediaUpload: attach rejected ${attachItems.length} staged '
      '$kind photos; re-uploading ${files.length} local copies',
    );
    return _uploadImagesResilient(
      carId: carId,
      files: files,
      imageKind: kind,
      alreadyOnServer: 0,
      draftId: draftId,
      items: matchedItems,
    );
  }

  /// Issue-2 follow-up fix (real-device correctness audit: "progress must
  /// reconcile from SERVER on resume" -- crash window between a confirmed
  /// server attach and the client persisting that confirmation locally).
  ///
  /// Computes exactly how many of THIS submission's own [carData] media
  /// items -- listing images, damage images, videos -- are ALREADY
  /// confirmed on the server for [carId], using the EXACT SAME identity
  /// semantics [uploadForCar] itself uses to decide what NOT to
  /// re-upload/re-attach (`ListingImageMedia.id(item) != null`, or a
  /// per-item `source` match against [_existingAttachedSources] of the
  /// SAME kind):
  ///   - an item that already carries a server `id` is always confirmed;
  ///   - otherwise an item is confirmed ONLY if its own `source` matches a
  ///     server-attached source of the same kind (listing vs damage).
  /// This deliberately does NOT use a raw server-side item COUNT (the
  /// previous approach) -- a count can't tell "5 images on the server"
  /// apart from "5 images on the server, only 2 of which are actually in
  /// THIS carData's list" (e.g. an edit session where photos were removed,
  /// or unrelated media on the same car from a different context). Only
  /// items this submission's OWN carData actually describes are ever
  /// counted, so pre-existing/unrelated edit-mode server media can never
  /// inflate this submission's progress.
  ///
  /// Videos have no per-item identity in `carData` (plain local file
  /// paths, never annotated with a server id/url the way images are), so
  /// -- exactly like the existing-video count guard already used inside
  /// [uploadForCar] -- video progress is the server's video count, capped
  /// at how many videos THIS submission's carData describes.
  static Future<int> confirmedServerMediaCount({
    required String carId,
    required Map<String, dynamic> carData,
  }) async {
    final car = await _fetchCarMap(carId);
    if (car == null) return 0;

    Set<String> existingSourcesOfKind(String kind) {
      final imgs = car['images'];
      if (imgs is! List) return const <String>{};
      final result = <String>{};
      for (final it in imgs) {
        if (it is! Map) continue;
        final itemKind = (it['kind'] ?? 'listing').toString().toLowerCase();
        final matchesKind = kind == 'damage'
            ? itemKind == 'damage'
            : itemKind != 'damage';
        if (!matchesKind) continue;
        final url = _imageUrlFromApiDict(it);
        if (url != null && url.isNotEmpty) result.add(url);
      }
      return result;
    }

    int confirmedForKey(String carDataKey, String kind) {
      final dynamic raw = carData[carDataKey];
      final List<dynamic> items = (raw is List) ? raw : const [];
      if (items.isEmpty) return 0;
      final existingSources = existingSourcesOfKind(kind);
      var confirmed = 0;
      for (final item in items) {
        if (ListingImageMedia.id(item) != null) {
          confirmed++;
          continue;
        }
        final source = ListingImageMedia.source(item);
        if (source.isNotEmpty && existingSources.contains(source)) {
          confirmed++;
        }
      }
      return confirmed;
    }

    final listingConfirmed = confirmedForKey('images', 'listing');
    final damageConfirmed = confirmedForKey('damage_images', 'damage');

    final dynamic rawVideos = carData['videos'];
    final videosExpected = rawVideos is List ? rawVideos.length : 0;
    final vids = car['videos'];
    final videosOnServer = vids is List ? vids.length : 0;
    final videosConfirmed = videosOnServer.clamp(0, videosExpected);

    return listingConfirmed + damageConfirmed + videosConfirmed;
  }

  // ---------------------------------------------------------------------
  // Media-readiness: Phase A ONLY.
  //
  // Everything below performs JUST the transfer step the backend manifest
  // (`kk/media_readiness.py`) requires to consider an item's Phase A
  // complete: source bytes durably server/R2-owned AND (for anything that
  // needs further server-side work) the async job durably accepted by the
  // broker -- NEVER waiting for that job to actually finish, and NEVER
  // polling/attaching a processed result client-side (the backend task
  // self-attaches -- see `attach_processed_car_image()` /
  // `attach_one_transcoded_video()`). [uploadForCar] above is UNCHANGED
  // and still runs afterward as "Phase B": it re-classifies the exact same
  // `carData` from scratch and, thanks to its own pre-existing
  // already-attached/already-uploaded skip checks (`_dropAlreadyAttached`,
  // the remote-count guards, [SellAsyncJobTracker]'s job-id reuse, and
  // [SellServerTranscodeVideoRunner]'s own resumable state machine), never
  // duplicates any work Phase A already did -- it simply continues driving
  // whatever Phase A left in flight through to full completion (polling,
  // legacy-endpoint attach as an idempotent backstop, primary-image/layout
  // once ids exist).
  // ---------------------------------------------------------------------

  /// Phase-A-only classification+transfer for one image list (`images` or
  /// `damage_images`). Mirrors [uploadForCar]'s own per-item
  /// classification exactly (same `ListingImageMedia.id`/`localFile`/
  /// source-prefix checks) so Phase B's later re-classification of the
  /// SAME list always agrees with what Phase A already did.
  static Future<void> _runImagePhaseA({
    required String carId,
    required List<dynamic> items,
    required String kind,
    String? draftId,

    /// Architecture fix (see [SellMediaIdentity.skipBlurForFinalSubmission]):
    /// forwarded verbatim to the Phase-A upload -- `true` publishes the
    /// original bytes as-is, `false` lets the backend produce + self-attach
    /// the blurred output. Never derived from which preview list [items]
    /// happens to be (always [SellMediaIdentity.finalListingImages]/
    /// [finalDamageImages], i.e. always original local sources here).
    required bool skipBlur,
  }) async {
    if (items.isEmpty) return;
    final List<XFile> toUpload = <XFile>[];
    final List<dynamic> uploadItems = <dynamic>[];
    var existingIdCount = 0;
    for (final dynamic img in items) {
      if (ListingImageMedia.id(img) != null) {
        existingIdCount++;
        continue;
      }
      final local = ListingImageMedia.localFile(img);
      if (local != null && await _waitForLocalUploadFile(local)) {
        toUpload.add(local);
        uploadItems.add(img);
      }
      // Deliberately no `else` branch here for an already-remote source
      // (`uploads/`/`static/`/http(s) prefix, e.g. one `SellPhotoPrestage`
      // staged before `create_car()`): such a source was never declared
      // in `expected_media` at all (see
      // `SellMediaIdentity.buildExpectedMedia`'s `_looksAlreadyRemote`
      // check), so it can never affect `phase_a_complete` either way --
      // it is ALREADY "safely server/R2-owned" (requirement #3), and
      // attaching the resulting `CarImage` row is Phase B's job, exactly
      // as before this Phase-A split existed (see [uploadForCar]'s own
      // `toAttach` handling just below it in this file). Attaching it
      // here too would just be a duplicate call racing Phase B's own.
    }
    if (toUpload.isNotEmpty) {
      // Multi-photo partial-failure fix (mirrors the analogous fix applied
      // to [uploadForCar]'s own listing-photo path, and the pre-existing
      // video-side exclusion just below in [runPhaseAOnly]): exclude, by
      // exact `client_media_id`, any photo the manifest already reports
      // `attached` BEFORE the coarse count check below runs -- otherwise
      // that coarse check (identical class of flaw as the two-video
      // regression this session already fixed) cannot tell WHICH photo
      // already landed, so a sibling photo's earlier rejection would
      // cause an already-successful photo to be re-enqueued here on
      // every later Phase-A/resume pass. Backend-safe either way (the
      // `source_media_id` unique constraint prevents an actual duplicate
      // `CarImage` row), but this avoids the wasted enqueue/Celery-task
      // entirely.
      final attachedImageIds = await _attachedMediaClientMediaIds(carId);
      if (attachedImageIds.isNotEmpty) {
        final keptFiles = <XFile>[];
        final keptItems = <dynamic>[];
        for (var i = 0; i < toUpload.length; i++) {
          final id = SellMediaIdentity.forImageItem(uploadItems[i], kind: kind);
          if (id != null && attachedImageIds.contains(id)) {
            appLog(
              'SellListingMediaUpload: Phase A skipping already-attached '
              '$kind photo client_media_id=$id',
            );
            continue;
          }
          keptFiles.add(toUpload[i]);
          keptItems.add(uploadItems[i]);
        }
        toUpload
          ..clear()
          ..addAll(keptFiles);
        uploadItems
          ..clear()
          ..addAll(keptItems);
        if (toUpload.isEmpty) return;
      } else {
        // C-fix parity: [uploadForCar] treats a resumed run's LOCAL
        // reference as already-satisfied whenever the server already has
        // at least as many items of this [kind] as this carData describes
        // by id + about-to-upload count -- a coarse, count-only
        // reconciliation (NOT identity-based) that exists specifically for
        // "the server was truly already told about this many, even though
        // this resumed carData snapshot's own local reference is stale/
        // unconfirmed" (see `uploadForCar`'s matching `remoteListingCount`/
        // `remoteDamageCount` checks just below it in this file). Only
        // used as a fallback here now, when the manifest gave no
        // per-item signal at all (empty/unavailable) -- otherwise it
        // would double-count against the already-filtered list above.
        final remoteCount = await _remoteImageCount(carId, kind);
        final alreadySatisfied = kind == 'damage'
            ? remoteCount >= toUpload.length
            : remoteCount >= existingIdCount + toUpload.length;
        if (alreadySatisfied) {
          appLog(
            'SellListingMediaUpload: Phase A skipping $kind photo enqueue; '
            'server already has $remoteCount',
          );
          return;
        }
      }
      await _enqueuePhaseAImages(
        carId: carId,
        files: toUpload,
        imageKind: kind,
        items: uploadItems,
        draftId: draftId,
        skipBlur: skipBlur,
      );
    }
  }

  /// Enqueues [files] on the async image-processing pipeline (exactly the
  /// same `?async=1` endpoint [_uploadImagesViaAsyncJobs] uses) WITHOUT
  /// polling any resulting job to a terminal state -- once the server
  /// durably accepts the enqueue, `mark_item_phase_a_accepted()` has
  /// already run (synchronously, inside that same request) and this
  /// function returns. The backend task itself performs the eventual
  /// attach (`attach_processed_car_image`); [uploadForCar]'s own
  /// (unchanged) poll-then-legacy-attach path later either finds it
  /// already attached (idempotent, see `kk/routes/media.py`'s
  /// `attach_car_images()`) or performs it, exactly as before.
  static Future<void> _enqueuePhaseAImages({
    required String carId,
    required List<XFile> files,
    required String imageKind,
    required List<dynamic> items,
    String? draftId,
    required bool skipBlur,
  }) async {
    if (files.isEmpty) return;
    final tracker = SellAsyncJobTracker(draftId);
    // A job already durably recorded for this exact local path means an
    // earlier (possibly killed) Phase-A attempt already enqueued it --
    // the manifest row was already advanced then; nothing further to do
    // here. (Re-enqueuing anyway would still be SAFE -- the backend's
    // at-least-once design tolerates a duplicate -- this is purely to
    // avoid an unnecessary extra request on every resume.)
    final freshFiles = <XFile>[];
    final freshItems = <dynamic>[];
    for (var i = 0; i < files.length; i++) {
      final existingJobId = await tracker.lookup(files[i].path);
      if (existingJobId != null) continue;
      freshFiles.add(files[i]);
      freshItems.add(items[i]);
    }
    if (freshFiles.isEmpty) return;

    final clientMediaIds = [
      for (final item in freshItems)
        SellMediaIdentity.forImageItem(item, kind: imageKind),
    ];
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        ApiService.recycleProductionHttpClient();
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
      try {
        final enqueueResponse = await ApiService.uploadCarImages(
          carId,
          freshFiles,
          imageKind: imageKind,
          async: true,
          clientMediaIds: clientMediaIds,
          // Architecture fix: this is now ALWAYS the ORIGINAL local file
          // (see [_runImagePhaseA]'s docstring) -- `blurPlates` (inverse of
          // `skipBlur`) is what tells the backend whether to produce the
          // blurred output from these exact bytes before self-attaching,
          // instead of the old design of swapping which bytes got sent.
          blurPlates: !skipBlur,
        );
        final rawJobIds = enqueueResponse['job_ids'];
        final jobIds = rawJobIds is List
            ? rawJobIds
                .map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toList()
            : const <String>[];
        if (jobIds.isEmpty) {
          throw ApiException(
            statusCode: 400,
            message: (enqueueResponse['message'] as String?) ??
                'No valid images were uploaded.',
          );
        }
        for (var k = 0; k < jobIds.length && k < freshFiles.length; k++) {
          await tracker.record(freshFiles[k].path, jobIds[k]);
        }
        return;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (!_isTransientUploadError(e) || attempt == 2) {
          Error.throwWithStackTrace(e, st);
        }
        appLog(
          'SellListingMediaUpload: retrying Phase-A $imageKind enqueue '
          '(${attempt + 1}/3): $e',
        );
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack ?? StackTrace.current);
  }

  /// Media-readiness: performs Phase A -- and ONLY Phase A -- for every
  /// media item [carData] describes on [carId]. Callers MUST follow this
  /// with [waitForPhaseAComplete] before treating the submission as ready
  /// (this function's own successful return means "every transfer call
  /// was accepted", which in practice already implies Phase A completion
  /// server-side -- see `kk/media_readiness.py` -- but
  /// [waitForPhaseAComplete] is the actual authority, never this).
  ///
  /// Safe/idempotent to call again later (e.g. on a resumed run after an
  /// app kill mid-Phase-A) -- every sub-step here re-checks current server
  /// state (or reuses a durably-recorded job id) before doing anything,
  /// so it only ever transfers whatever is STILL missing.
  static Future<void> runPhaseAOnly({
    required String carId,
    required Map<String, dynamic> carData,
    Future<http.MultipartFile> Function(XFile video)? multipartFileBuilder,
    String? draftId,
    // Normal video only: for every OTHER kind, Phase A merely enqueues an
    // async job (no attach yet, so no progress to credit), but a normal
    // video's Phase A call IS its full, final atomic upload+attach --
    // exactly what Phase B's own `uploadForCar` would otherwise have
    // credited via its own (identically-shaped) `onMediaConfirmed`
    // callback. Without this, that credit would be silently lost: once
    // Phase B later sees the video already attached, it clears it from
    // its own to-upload list and never calls its own callback for it.
    Future<void> Function(int delta)? onMediaConfirmed,
  }) async {
    // Architecture fix (real-device evidence: "chose UNBLURRED, final
    // listing still shows blurred"): Phase A always transfers the
    // ORIGINAL durable source, and always tells the backend the ACTUAL
    // choice via `skipBlur` -- never derived from swapping which preview
    // list happened to be in `carData['images']`. See
    // [SellMediaIdentity.finalListingImages]/[skipBlurForFinalSubmission].
    final skipBlur = SellMediaIdentity.skipBlurForFinalSubmission(carData);
    final imgsRaw = SellMediaIdentity.finalListingImages(carData);
    await _runImagePhaseA(
      carId: carId,
      items: imgsRaw,
      kind: 'listing',
      draftId: draftId,
      skipBlur: skipBlur,
    );

    final dimgs = SellMediaIdentity.finalDamageImages(carData);
    await _runImagePhaseA(
      carId: carId,
      items: dimgs,
      kind: 'damage',
      draftId: draftId,
      skipBlur: skipBlur,
    );

    // Normal (already client-compressed) video: Phase A and Phase B are
    // the SAME atomic request (see `kk/media_readiness.py`'s state-machine
    // doc comment) -- this call must run to full completion here, there
    // is no "enqueue only" variant for it.
    final dynamic maybeVideos = carData['videos'];
    final List<dynamic> vids = (maybeVideos is List) ? maybeVideos : const [];
    final videosToUploadRaw = SellDraftMediaPersistence.xFilesForUpload(vids);
    if (videosToUploadRaw.isNotEmpty) {
      final car = await _fetchCarMap(carId);
      final existingVideos = car?['videos'];
      final existingVideoCount =
          existingVideos is List ? existingVideos.length : 0;
      if (existingVideoCount < videosToUploadRaw.length) {
        final videoClientMediaIdsRaw =
            videosToUploadRaw.length == vids.length
            ? [for (final v in vids) SellMediaIdentity.forNormalVideoItem(v)]
            : null;
        // Two-video regression fix: a coarse count check above cannot
        // tell WHICH videos already landed -- exclude any video whose
        // own `client_media_id` the manifest already reports `attached`,
        // so a sibling video's earlier permanent Phase-A rejection never
        // causes an already-successful video to be re-uploaded (a
        // genuine duplicate `CarVideo` row) on this or a later
        // Phase-A/resume pass.
        final attachedIds = await _attachedMediaClientMediaIds(carId);
        final (videosToUpload, videoClientMediaIds) =
            _excludeAlreadyAttachedVideos(
          videosToUploadRaw,
          videoClientMediaIdsRaw,
          attachedIds,
        );
        if (videosToUpload.isNotEmpty) {
          final response = await ApiService.uploadCarVideos(
            carId,
            videosToUpload,
            multipartFileBuilder:
                multipartFileBuilder ?? buildVideoMultipartFile,
            clientMediaIds: videoClientMediaIds,
          );
          // Two-video regression fix: credit ONLY the videos the backend
          // actually confirmed uploaded (`response['videos']`), never the
          // requested count -- `upload_car_videos` accepts partial
          // per-file success (see `kk/routes/media.py`), so blindly
          // crediting `videosToUpload.length` here previously overcounted
          // `completedMediaCount` whenever one video in the batch was
          // rejected while a sibling succeeded.
          final confirmedVideos = response['videos'];
          final confirmedCount = confirmedVideos is List
              ? confirmedVideos.length
              : videosToUpload.length;
          if (confirmedCount > 0) {
            await onMediaConfirmed?.call(confirmedCount);
          }
        }
      }
    }

    // Server-transcode video: Phase A ends at `finalize` (sign -> PUT ->
    // finalize) -- never waits for the transcode job or its attach.
    final serverTranscodeSpecs = ServerTranscodeVideoSpec.listFromJson(
      carData['server_transcode_videos'],
    );
    if (serverTranscodeSpecs.isNotEmpty &&
        draftId != null &&
        draftId.isNotEmpty) {
      await SellServerTranscodeVideoRunner.processAllPhaseAOnly(
        draftId: draftId,
        carId: carId,
        specs: serverTranscodeSpecs,
      );
    }
  }

  /// Media-readiness: server-authoritative confirmation that every
  /// expected media item for [carId] has completed Phase A -- see
  /// `GET /api/cars/<id>/media-summary`
  /// (`kk/media_readiness.py::media_summary`'s `phase_a_complete` field).
  /// This is the ONLY thing `submitFast()`'s ready signal may depend on
  /// once any `expected_media` was declared for this car -- never a local
  /// assumption ("the transfer call above returned, therefore we're
  /// done"). A listing with no expected media (or whose only media was
  /// already pre-staged/attached before `create_car()`) trivially
  /// satisfies this (`phase_a_complete` is `true` over an empty/attached
  /// manifest), so a zero-media submission is unaffected.
  ///
  /// A short bounded retry absorbs a single transient network hiccup on
  /// this cheap GET itself -- NOT a wait for the backend to finish
  /// anything: every Phase-A transfer call [runPhaseAOnly] makes already
  /// advances `phase_a_completed_at` synchronously, server-side, before
  /// that call's own HTTP response returns (see
  /// `kk/media_readiness.py:mark_item_phase_a_accepted` /
  /// `mark_normal_video_attached_locked`), so in the overwhelmingly common
  /// case this succeeds on the very first read.
  static Future<bool> waitForPhaseAComplete(
    String carId, {
    int maxAttempts = 5,
    Duration retryDelay = const Duration(milliseconds: 400),
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelay);
      try {
        final summary = await ApiService.getCarMediaSummary(carId);
        if (summary['phase_a_complete'] == true) return true;
      } catch (e, st) {
        logNonFatal(e, st, 'SellListingMediaUpload.waitForPhaseAComplete');
      }
    }
    return false;
  }

  /// Two-video regression fix (real-device evidence): per-item
  /// `client_media_id`s already `attached` for [carId], read from the
  /// SAME authoritative manifest `waitForPhaseAComplete` uses
  /// (`GET /api/cars/{carId}/media-summary`'s `items[].status`) -- never
  /// a coarse "existing server videos = count" comparison. A count comparison
  /// cannot tell WHICH of several videos already landed, so when one
  /// video in a multi-video batch is rejected server-side (bad codec,
  /// oversized file, etc) while a sibling succeeds, a count check like
  /// `existingVideoCount >= videosToUpload.length` stays false forever
  /// for that car and keeps re-sending the WHOLE batch on every
  /// Phase-A/Phase-B/resume pass -- re-uploading the already-successful
  /// sibling video every time (a genuine duplicate `CarVideo` row: see
  /// `kk/routes/media.py::upload_car_videos`, which never sets
  /// `CarVideo.source_draft_media_id`, so its unique constraint gives no
  /// protection against this) while the permanently-rejected video keeps
  /// failing the same way forever. Comparing this exact per-id set
  /// against each video's own `client_media_id` lets the caller exclude
  /// only the ones that are truly already attached, and retry only the
  /// one(s) that are not -- best-effort: any failure returns an empty
  /// set (the pre-existing, less-precise count-based skip elsewhere is
  /// the safety net, not this).
  static Future<Set<String>> _attachedMediaClientMediaIds(
    String carId,
  ) async {
    try {
      final summary = await ApiService.getCarMediaSummary(carId);
      final items = summary['items'];
      if (items is! List) return <String>{};
      return <String>{
        for (final it in items)
          if (it is Map &&
              (it['status'] ?? '').toString() == 'attached' &&
              (it['client_media_id'] ?? '').toString().isNotEmpty)
            (it['client_media_id'] ?? '').toString(),
      };
    } catch (e, st) {
      logNonFatal(e, st, 'SellListingMediaUpload._attachedMediaClientMediaIds');
      return <String>{};
    }
  }

  /// Architecture fix (real-device evidence: "chose UNBLURRED, final
  /// listing still shows blurred" -- traced to Phase B re-driving an
  /// image Phase A already durably owned, racing the worker's own
  /// self-attach): unlike [_attachedMediaClientMediaIds] (status EXACTLY
  /// `'attached'` only), this returns every `client_media_id` for which
  /// the server reports Phase A as durably complete.
  ///
  /// CORRECTNESS-CRITICAL: Phase-A completeness is tracked SEPARATELY
  /// from `status` in the backend's own manifest contract (see
  /// `kk/media_readiness.py`'s module docstring and `CarMediaItem.
  /// phase_a_completed_at` in `kk/models.py`) via the write-once
  /// `phase_a_completed_at` timestamp -- non-null means the source bytes
  /// were confirmed server/R2-owned AND the required async job was
  /// durably accepted by the broker. `status` alone is NOT a reliable
  /// proxy for this: it is mutable, can move through transient/retry
  /// states, and per the backend's own contract must never be used to
  /// infer Phase-A completion. The server exposes the derived boolean
  /// directly as `items[].phase_a_complete` (see `CarMediaItem.to_dict()`
  /// -- `'phase_a_complete': self.phase_a_completed_at is not None`)
  /// specifically so clients check exactly that, never raw `status`.
  ///
  /// `uploadForCar` (new-listing path) uses this to recognize "Phase A
  /// already owns this item" the moment `phase_a_complete` flips true
  /// (which happens as soon as the transfer is durably accepted, before
  /// the worker necessarily finishes self-attaching) -- closing exactly
  /// the race window that let the old, unconditional Phase-B code
  /// re-poll/re-attach an item the worker was already about to
  /// self-attach.
  /// Best-effort: any failure returns an empty set (falls back to the
  /// pre-existing per-item classification, never blocks progress).
  static Future<Set<String>> _phaseAAcceptedClientMediaIds(
    String carId,
  ) async {
    try {
      final summary = await ApiService.getCarMediaSummary(carId);
      final items = summary['items'];
      if (items is! List) return <String>{};
      return <String>{
        for (final it in items)
          if (it is Map &&
              it['phase_a_complete'] == true &&
              (it['client_media_id'] ?? '').toString().isNotEmpty)
            (it['client_media_id'] ?? '').toString(),
      };
    } catch (e, st) {
      logNonFatal(
        e,
        st,
        'SellListingMediaUpload._phaseAAcceptedClientMediaIds',
      );
      return <String>{};
    }
  }

  /// Filters [videosToUpload]/[videoClientMediaIds] (kept 1:1 aligned, per
  /// their shared caller's own invariant) down to only the videos whose
  /// `client_media_id` is NOT already in [attachedIds]. When
  /// [videoClientMediaIds] is null (the rare case where
  /// `videosToUpload.length != vids.length`, so no reliable 1:1 id
  /// mapping exists), returns the inputs unchanged -- best-effort only,
  /// never a correctness dependency for that edge case.
  static (List<XFile>, List<String?>?) _excludeAlreadyAttachedVideos(
    List<XFile> videosToUpload,
    List<String?>? videoClientMediaIds,
    Set<String> attachedIds,
  ) {
    if (videoClientMediaIds == null ||
        videoClientMediaIds.length != videosToUpload.length ||
        attachedIds.isEmpty) {
      // Bug fix: must return a NEW list, never the same [videosToUpload]
      // reference -- a caller that does `videosToUpload..clear()
      // ..addAll(result)` (to keep using one variable name throughout the
      // rest of its function) would otherwise clear THIS return value
      // too, since it would be the exact same List object, silently
      // turning "nothing needs filtering" into "upload nothing at all".
      return (List<XFile>.from(videosToUpload), videoClientMediaIds);
    }
    final keptFiles = <XFile>[];
    final keptIds = <String?>[];
    for (var i = 0; i < videosToUpload.length; i++) {
      final id = (videoClientMediaIds[i] ?? '').trim();
      if (id.isNotEmpty && attachedIds.contains(id)) {
        appLog(
          'SellListingMediaUpload: skipping already-attached video '
          'client_media_id=$id',
        );
        continue;
      }
      keptFiles.add(videosToUpload[i]);
      keptIds.add(videoClientMediaIds[i]);
    }
    return (keptFiles, keptIds);
  }

  /// True when the server listing already has any listing media.
  static Future<bool> listingAlreadyHasMedia(String carId) async {
    final car = await _fetchCarMap(carId);
    if (car == null) return false;
    if (_listingImageCount(car) > 0) return true;
    return (car['image_url'] ?? '').toString().trim().isNotEmpty;
  }

  /// Uploads images, videos, and damage media for [carId] from [carData].
  ///
  /// Returns true when listing photos are confirmed on the server (or none
  /// were needed), so the caller can skip a redundant confirmation poll.
  static Future<bool> uploadForCar({
    required String carId,
    required Map<String, dynamic> carData,
    Future<http.MultipartFile> Function(XFile video)? multipartFileBuilder,
    void Function(SellMediaUploadPhase phase)? onPhase,
    // Issue-2 fix (real-device evidence: "persisted progress incorrectly
    // resets to 0/N"): invoked (and awaited by the caller) after EVERY
    // confirmed successful server operation -- a listing-image attach
    // call, a listing-image upload call, the video upload call, a
    // damage-image attach call, or a damage-image upload call -- with how
    // many NEW media items that specific call just confirmed on the
    // server. This lets the caller durably persist progress incrementally
    // instead of only estimating it from coarse phase transitions.
    Future<void> Function(int confirmedDelta)? onMediaConfirmed,
    String? draftId,

    /// Architecture fix (real-device evidence: "chose UNBLURRED, final
    /// listing still shows blurred"): `true` for a brand-new listing that
    /// declared an `expected_media` manifest at `create_car()` time (i.e.
    /// `!record.isEdit` -- see `PendingSellSubmissionService`). For such a
    /// listing, [runPhaseAOnly] already fully transferred every local
    /// image/damage-photo (upload/enqueue, with `client_media_id`) BEFORE
    /// this function ever runs, and the backend worker self-attaches the
    /// result on its own (`attach_processed_car_image`) -- so this
    /// function must never independently re-poll/re-attach an item Phase A
    /// already owns (that legacy "backstop" is exactly what caused a
    /// stale/duplicate/racy second attach in production). Left `false`
    /// (the default) for edit-mode, where no `expected_media` manifest
    /// exists at all and this function's pre-existing synchronous
    /// upload/attach behavior remains the ONLY path -- completely
    /// unchanged.
    bool isNewListing = false,
  }) async {
    final imgsRaw = SellMediaIdentity.finalListingImages(carData);
    final List<dynamic> imgs = _imagesWithPrimaryFirst(
      imgsRaw,
      primaryIndex: _primaryImageIndex(carData, length: imgsRaw.length),
    );
    // Architecture fix: the actual skip_blur choice for any image THIS
    // function still needs to transfer itself (edit-mode, or a Phase-A
    // retry/backstop) -- see [SellMediaIdentity.skipBlurForFinalSubmission].
    final skipBlur = SellMediaIdentity.skipBlurForFinalSubmission(carData);
    // For a new listing, every local image/damage-photo was already
    // declared in `expected_media` and handed to Phase A -- fetch ONCE
    // which of those the manifest already reports `phase_a_complete` (the
    // server-authoritative boolean derived from `phase_a_completed_at`,
    // NOT `status` -- see `_phaseAAcceptedClientMediaIds`'s doc comment)
    // so the classification loops below can skip them entirely instead
    // of re-driving them.
    final Set<String> phaseAOwnedIds = isNewListing
        ? await _phaseAAcceptedClientMediaIds(carId)
        : const <String>{};
    final dynamic maybeVideos = carData['videos'];
    final List<dynamic> vids = (maybeVideos is List) ? maybeVideos : const [];
    // Bug-3 instrumentation (real-device trace): the "desired" set this
    // resume/run intends to have attached for [carId], captured BEFORE any
    // network call below -- compare against `existing server images=` /
    // `existing server videos=` (logged just before the actual
    // attach/upload calls) to prove whether a resume is only ever adding
    // to what the server already has, never shrinking it.
    appLog('[SELL MEDIA] resume desired images=${imgs.length} carId=$carId');
    appLog('[SELL MEDIA] resume desired videos=${vids.length} carId=$carId');
    final List<XFile> toUpload = <XFile>[];
    final List<String> toAttach = <String>[];
    final List<dynamic> uploadItems = <dynamic>[];
    final List<dynamic> attachItems = <dynamic>[];
    final Map<String, int> imageIdsBySource = <String, int>{};
    final List<XFile> videosToUpload =
        SellDraftMediaPersistence.xFilesForUpload(vids);

    // Architecture fix: counts items skipped below because Phase A
    // already durably owns them (new-listing path only) -- these are
    // legitimately neither uploaded, attached, nor carrying a server
    // `existingId` in [carData] yet (that only lands once the worker's
    // self-attach is reflected back into a later car refresh), so the
    // "could not be read" guard just below must not treat them as
    // missing/corrupt photos.
    var phaseAOwnedSkipCount = 0;
    for (final dynamic img in imgs) {
      final existingId = ListingImageMedia.id(img);
      final source = ListingImageMedia.source(img);
      if (existingId != null) {
        if (source.isNotEmpty) imageIdsBySource[source] = existingId;
        continue;
      }
      // Architecture fix: for a new listing, any item the server reports
      // as `phase_a_complete: true` is fully owned by the backend
      // worker's self-attach from here -- this function must not
      // enqueue/poll/attach it a second time.
      if (isNewListing) {
        final id = SellMediaIdentity.forImageItem(img, kind: 'listing');
        if (id != null && phaseAOwnedIds.contains(id)) {
          phaseAOwnedSkipCount++;
          continue;
        }
      }
      final local = ListingImageMedia.localFile(img);
      if (local != null && await _waitForLocalUploadFile(local)) {
        toUpload.add(local);
        uploadItems.add(img);
      } else {
        final s = source;
        if (s.startsWith('uploads/') ||
            s.startsWith('static/') ||
            s.startsWith('/static/')) {
          toAttach.add(s);
          attachItems.add(img);
        } else if (s.startsWith('http://') || s.startsWith('https://')) {
          toAttach.add(s);
          attachItems.add(img);
        }
      }
    }

    if (imgs.isNotEmpty &&
        toUpload.isEmpty &&
        toAttach.isEmpty &&
        imageIdsBySource.isEmpty &&
        phaseAOwnedSkipCount == 0) {
      throw StateError(
        'Listing photos could not be read for upload. Please re-add the photos and try again.',
      );
    }

    // Multi-photo partial-failure fix (mirrors the two-video regression
    // fix applied to `videosToUpload` further down): the coarse count
    // check further below cannot tell WHICH specific photos already
    // landed -- e.g. if photo B's earlier attempt was rejected while
    // sibling photo A already attached, `remoteListingCount` (1) stays
    // less than `toUpload.length` (2), so that check never fires and
    // BOTH photos -- including the already-successful A -- get resent on
    // every later resume pass. Exclude, by exact `client_media_id`, any
    // photo the manifest already reports `attached`, BEFORE the coarse
    // check runs, so a resume only ever re-drives the genuinely missing
    // photo(s) (the backend's own `source_media_id` unique constraint
    // already prevented a literal duplicate `CarImage` row either way,
    // but this avoids the wasted upload/enqueue call entirely, exactly
    // like `_excludeAlreadyAttachedVideos` does for videos).
    //
    // `idFilterIsAuthoritative` is true only when the manifest actually
    // reported at least one attached item for this car -- i.e. this
    // listing IS using the media-readiness system, so the (precise,
    // per-item) result above is trustworthy on its own. When it's false
    // (manifest empty/unavailable -- e.g. a car created before this
    // system existed, or a transient media-summary error), the OLD
    // coarse `remoteListingCount` check below remains the only signal and
    // must still run exactly as before; running BOTH checks in sequence
    // in that true case would double-count (the coarse check would then
    // compare the ALREADY-FILTERED remaining length against the FULL
    // server count, which can misfire and wrongly skip the real upload).
    var idFilterIsAuthoritative = false;
    if (toUpload.isNotEmpty) {
      final attachedImageIds = await _attachedMediaClientMediaIds(carId);
      if (attachedImageIds.isNotEmpty) {
        idFilterIsAuthoritative = true;
        final keptFiles = <XFile>[];
        final keptItems = <dynamic>[];
        for (var i = 0; i < toUpload.length; i++) {
          final id = SellMediaIdentity.forImageItem(
            uploadItems[i],
            kind: 'listing',
          );
          if (id != null && attachedImageIds.contains(id)) {
            appLog(
              'SellListingMediaUpload: skipping already-attached listing '
              'photo client_media_id=$id',
            );
            continue;
          }
          keptFiles.add(toUpload[i]);
          keptItems.add(uploadItems[i]);
        }
        toUpload
          ..clear()
          ..addAll(keptFiles);
        uploadItems
          ..clear()
          ..addAll(keptItems);
      }
    }

    Map<String, dynamic>? latestMediaResponse;
    var remoteListingCount = 0;
    // Architecture fix: an item skipped above because Phase A already
    // durably owns it counts as "confirmed" from this function's
    // perspective too -- there is nothing left for it to upload/attach,
    // and the backend worker's self-attach is the authoritative
    // completion signal `waitForPhaseAComplete` already waited on before
    // this function ever ran.
    var listingMediaConfirmed =
        imgs.isEmpty || (imgs.length == phaseAOwnedSkipCount);
    if (idFilterIsAuthoritative) {
      // The per-item filter above already determined the precise
      // remaining set -- still fetch the count (cheap, and other code
      // below uses it as `alreadyOnServer` for retry-recovery
      // heuristics), but never let it override/clear an authoritative,
      // already-correct `toUpload`.
      remoteListingCount = await _remoteImageCount(carId, 'listing');
      if (toUpload.isEmpty) listingMediaConfirmed = true;
    } else if (toUpload.isNotEmpty) {
      remoteListingCount = await _remoteImageCount(carId, 'listing');
      if (remoteListingCount >= imageIdsBySource.length + toUpload.length) {
        appLog(
          'SellListingMediaUpload: skipping listing photo upload; '
          'server already has $remoteListingCount',
        );
        toUpload.clear();
        uploadItems.clear();
        listingMediaConfirmed = true;
      }
    }
    if (toAttach.isNotEmpty || toUpload.isNotEmpty || imgs.isNotEmpty) {
      onPhase?.call(SellMediaUploadPhase.photos);
    }
    if (toAttach.isNotEmpty) {
      // C-fix (real-device evidence): a resumed run must never re-attach a
      // source the server already has -- this call used to run
      // unconditionally on every resume, with no equivalent of the
      // `toUpload` skip-if-already-landed check above.
      final existingSources =
          await _existingAttachedSources(carId, 'listing');
      // Issue-4 fix (real-device evidence): this was previously logged as
      // the ambiguous `existing server images=<N>`, which could be
      // misread as "all server images", when it is actually scoped to
      // LISTING-kind images only (`_existingAttachedSources(carId,
      // 'listing')` filters `kind != 'damage'`). Made explicit so a
      // log reader can never conflate this with the damage-only count
      // logged separately below.
      appLog(
        '[SELL MEDIA] existing server listing images=${existingSources.length} '
        'carId=$carId',
      );
      final dropped = _dropAlreadyAttached(toAttach, attachItems, existingSources);
      if (dropped > 0) {
        appLog(
          'SellListingMediaUpload: skipping $dropped already-attached '
          'listing photo(s) for $carId',
        );
        if (toAttach.isEmpty) listingMediaConfirmed = true;
      }
    }
    if (toAttach.isNotEmpty) {
      for (final s in toAttach) {
        appLog('[SELL MEDIA] attach image carId=$carId sourceKey=$s');
      }
      final attachResponse = await CarService().attachCarImages(carId, toAttach);
      latestMediaResponse = attachResponse;
      _collectUploadedImageIds(imageIdsBySource, attachItems, attachResponse);
      final attachedCount = _attachedRowCount(attachResponse);
      if (attachedCount > 0) {
        listingMediaConfirmed = true;
        await onMediaConfirmed?.call(attachedCount);
      } else {
        final recovered = await _recoverRejectedAttach(
          carId: carId,
          attachItems: attachItems,
          kind: 'listing',
          draftId: draftId,
        );
        final recoveredCount = _attachedRowCount(recovered);
        if (recoveredCount > 0) {
          latestMediaResponse = recovered;
          _collectUploadedImageIds(imageIdsBySource, attachItems, recovered);
          listingMediaConfirmed = true;
          await onMediaConfirmed?.call(recoveredCount);
        }
      }
    }
    if (toUpload.isNotEmpty) {
      for (final f in toUpload) {
        appLog('[SELL MEDIA] attach image carId=$carId sourceKey=${f.path}');
      }
      final uploadResponse = await _uploadImagesResilient(
        carId: carId,
        files: toUpload,
        alreadyOnServer: remoteListingCount,
        draftId: draftId,
        items: uploadItems,
        skipBlur: skipBlur,
      );
      latestMediaResponse = uploadResponse;
      _collectUploadedImageIds(imageIdsBySource, uploadItems, uploadResponse);
      final uploadedCount = _attachedRowCount(uploadResponse);
      if (uploadedCount > 0 || imageIdsBySource.isNotEmpty) {
        listingMediaConfirmed = true;
      }
      // Only report a progress delta from an actual confirmed row count in
      // THIS call's response -- `imageIdsBySource` also accumulates
      // already-had-a-server-id images from earlier in this function that
      // the caller's initial server-confirmed baseline already counted,
      // so using it here would double-count progress.
      if (uploadedCount > 0) {
        await onMediaConfirmed?.call(uploadedCount);
      }
    }
    if (imageIdsBySource.isNotEmpty && toUpload.isEmpty && toAttach.isEmpty) {
      listingMediaConfirmed = true;
    }
    if (imgs.isNotEmpty) {
      await _applyPrimaryListingImage(
        carId,
        imgs,
        listingMediaResponse: latestMediaResponse,
      );
    }
    await _saveListingImageLayout(carId, imgs, imageIdsBySource);

    // Videos must not abort the remaining photo work, but the failure still has
    // to reach the caller so the user isn't told the listing published intact.
    Object? videoError;
    StackTrace? videoStack;
    if (videosToUpload.isNotEmpty) {
      final car = await _fetchCarMap(carId);
      final existingVideos = car?['videos'];
      final existingVideoCount =
          existingVideos is List ? existingVideos.length : 0;
      appLog(
        '[SELL MEDIA] existing server videos=$existingVideoCount carId=$carId',
      );
      if (existingVideoCount >= videosToUpload.length) {
        videosToUpload.clear();
      }
    }
    // Two-video regression fix: the coarse count check above cannot tell
    // WHICH videos already landed -- exclude, by exact `client_media_id`,
    // any video the manifest already reports `attached`, so a sibling
    // video's earlier Phase-A rejection never causes an already-successful
    // video to be re-uploaded here (a genuine duplicate `CarVideo` row;
    // see `_attachedMediaClientMediaIds`'s doc comment).
    List<String?>? videoClientMediaIds;
    if (videosToUpload.isNotEmpty) {
      // Media-readiness: ids are derived from the RAW `carData['videos']`
      // list (the SAME list `SellMediaIdentity.buildExpectedMedia` reads
      // when building the `create_car` payload), so a given video's id
      // here always matches the manifest row registered for it -- but
      // only when [videosToUpload] (after
      // `SellDraftMediaPersistence.xFilesForUpload`'s own
      // resolve/dedupe/missing-file filtering) is still 1:1 positionally
      // aligned with [vids]. A mismatched length (dedup/missing-file
      // edge case) simply sends no ids -- this upload is otherwise
      // completely unaffected, it just isn't tracked by the manifest.
      final videoClientMediaIdsRaw = videosToUpload.length == vids.length
          ? [for (final v in vids) SellMediaIdentity.forNormalVideoItem(v)]
          : null;
      final attachedIds = await _attachedMediaClientMediaIds(carId);
      final (filteredVideos, filteredIds) = _excludeAlreadyAttachedVideos(
        videosToUpload,
        videoClientMediaIdsRaw,
        attachedIds,
      );
      videoClientMediaIds = filteredIds;
      videosToUpload
        ..clear()
        ..addAll(filteredVideos);
    }
    if (videosToUpload.isNotEmpty) {
      onPhase?.call(SellMediaUploadPhase.videos);
      for (final f in videosToUpload) {
        appLog('[SELL MEDIA] attach video carId=$carId sourceKey=${f.path}');
      }
      try {
        final response = await ApiService.uploadCarVideos(
          carId,
          videosToUpload,
          multipartFileBuilder:
              multipartFileBuilder ?? buildVideoMultipartFile,
          clientMediaIds: videoClientMediaIds,
        );
        // Two-video regression fix: credit ONLY the videos the backend
        // actually confirmed uploaded (`response['videos']`), never the
        // requested count -- `upload_car_videos` accepts partial per-file
        // success (see `kk/routes/media.py`), so blindly crediting
        // `videosToUpload.length` here previously overcounted
        // `completedMediaCount` whenever one video in the batch was
        // rejected while a sibling succeeded.
        final confirmedVideos = response['videos'];
        final confirmedCount =
            confirmedVideos is List ? confirmedVideos.length : videosToUpload.length;
        if (confirmedCount > 0) {
          await onMediaConfirmed?.call(confirmedCount);
        }
      } catch (e, st) {
        logNonFatal(e, st, 'SellListingMediaUpload.videos');
        videoError = e;
        videoStack = st;
        // Issue-3 instrumentation (real-device trace: `POST
        // /api/cars/<id>/videos` -> HTTP 400): safe (no auth/token/file
        // content) diagnostics for exactly what was sent and exactly why
        // the server rejected it, using the SAME sniffing logic
        // `buildVideoMultipartFile` used to build the actual request.
        final statusCode = e is ApiException ? e.statusCode : null;
        final backendCode = e is ApiException ? (e.errorCode ?? 'none') : 'none';
        final safeMessage = e is ApiException
            ? e.message.replaceAll(RegExp(r'\s+'), ' ').trim()
            : e.runtimeType.toString();
        for (final f in videosToUpload) {
          try {
            final diag = await videoUploadDiagnostics(f);
            appLog(
              '[SELL MEDIA] video upload failed carId=$carId '
              'status=${statusCode ?? 'unknown'} backendCode=$backendCode '
              'message=$safeMessage filenameExtension=.${diag.extension} '
              'mime=${diag.mime} bytes=${diag.bytes}',
            );
          } catch (diagError, diagStack) {
            logNonFatal(diagError, diagStack);
          }
        }
      }
    }

    // Phase 3B: videos that could not be compressed locally
    // (`SellVideoPrepareStatus.requiresServerTranscode` at pick time --
    // see `sell_step4_logic.dart:_pickVideos`) go through the separate
    // sign -> PUT -> finalize -> poll -> attach pipeline here, entirely
    // independent of the normal multipart video path above. Safe to run
    // after the normal video block regardless of whether it succeeded --
    // one video type's failure must never block the other's progress,
    // exactly like the videoError/photos/damage-photos independence
    // already documented above. Requires [draftId] (durable per-video
    // progress is keyed by it) -- `uploadForCar`'s only current caller
    // (`PendingSellSubmissionService._runSubmission`) always supplies a
    // real one, but this degrades to "skip" rather than crash if it
    // somehow doesn't, matching this function's existing defensive style.
    final serverTranscodeSpecs = ServerTranscodeVideoSpec.listFromJson(
      carData['server_transcode_videos'],
    );
    if (serverTranscodeSpecs.isNotEmpty &&
        draftId != null &&
        draftId.isNotEmpty) {
      onPhase?.call(SellMediaUploadPhase.videos);
      try {
        final beforeAttached = await SellServerTranscodeVideoRunner
            .attachedCount(draftId: draftId, specs: serverTranscodeSpecs);
        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: serverTranscodeSpecs,
          // Forwards the runner's own already-existing (previously
          // unconsumed) per-step phase callback straight to this
          // function's own `onPhase` -- see `_mediaUploadPhaseForTranscode`
          // above. Fires on EVERY call, including a resume that starts
          // mid-pipeline (e.g. straight at `_attach`), so a resumed
          // submission's very first `onPhase` call already reports the
          // correct current sub-phase instead of a stale/generic one.
          onPhase: (_, phase) =>
              onPhase?.call(_mediaUploadPhaseForTranscode(phase)),
        );
        final afterAttached = await SellServerTranscodeVideoRunner
            .attachedCount(draftId: draftId, specs: serverTranscodeSpecs);
        final delta = afterAttached - beforeAttached;
        if (delta > 0) {
          await onMediaConfirmed?.call(delta);
        }
      } catch (e, st) {
        // Never abort remaining (damage-photo) work for this -- same
        // independence guarantee as the normal video block above. Most
        // per-video failures (transient network, feature disabled,
        // permanent rejection) are already captured as durable STATE by
        // the runner itself and never reach this catch at all; only a
        // genuinely unexpected failure (e.g. durable-prefs I/O) does.
        logNonFatal(e, st, 'SellListingMediaUpload.serverTranscodeVideos');
        videoError ??= e;
        videoStack ??= st;
      }
    }

    final dimgs = SellMediaIdentity.finalDamageImages(carData);
    final List<XFile> damageToUpload = <XFile>[];
    final List<dynamic> damageUploadItems = <dynamic>[];
    final List<String> damageToAttach = <String>[];
    final List<dynamic> damageAttachItems = <dynamic>[];
    for (final dynamic img in dimgs) {
      if (ListingImageMedia.id(img) != null) continue;
      // Architecture fix: same Phase-A-owned skip as the listing-photo
      // loop above.
      if (isNewListing) {
        final id = SellMediaIdentity.forImageItem(img, kind: 'damage');
        if (id != null && phaseAOwnedIds.contains(id)) continue;
      }
      final local = ListingImageMedia.localFile(img);
      if (local != null && await _waitForLocalUploadFile(local)) {
        damageToUpload.add(local);
        damageUploadItems.add(img);
        continue;
      }
      final s = ListingImageMedia.source(img);
      if (s.startsWith('uploads/') ||
          s.startsWith('static/') ||
          s.startsWith('/static/') ||
          s.startsWith('http://') ||
          s.startsWith('https://')) {
        damageToAttach.add(s);
        damageAttachItems.add(img);
      }
    }
    var remoteDamageCount = 0;
    if (damageToUpload.isNotEmpty) {
      remoteDamageCount = await _remoteImageCount(carId, 'damage');
      if (remoteDamageCount >= damageToUpload.length) {
        damageToUpload.clear();
        damageUploadItems.clear();
      }
    }
    if (damageToAttach.isNotEmpty || damageToUpload.isNotEmpty) {
      onPhase?.call(SellMediaUploadPhase.damagePhotos);
    }
    if (damageToAttach.isNotEmpty) {
      // C-fix (real-device evidence): same already-attached guard as the
      // listing-photo `toAttach` path above.
      final existingDamageSources =
          await _existingAttachedSources(carId, 'damage');
      // Issue-4 fix (real-device evidence): previously logged as the
      // ambiguous `existing server images=<N> (damage)`, which real-device
      // logs showed could be misread as "all server images = 0" right
      // after normal listing images had already been attached. Confirmed
      // by code reading that `_existingAttachedSources(carId, 'damage')`
      // is correctly scoped to damage-kind images ONLY (`kind == 'damage'`)
      // -- the classification itself was always correct; only the log
      // wording was ambiguous. Made explicit and unambiguous.
      appLog(
        '[SELL MEDIA] existing server damage images='
        '${existingDamageSources.length} carId=$carId',
      );
      final droppedDamage = _dropAlreadyAttached(
        damageToAttach,
        damageAttachItems,
        existingDamageSources,
      );
      if (droppedDamage > 0) {
        appLog(
          'SellListingMediaUpload: skipping $droppedDamage already-attached '
          'damage photo(s) for $carId',
        );
      }
    }
    if (damageToAttach.isNotEmpty) {
      for (final s in damageToAttach) {
        appLog(
          '[SELL MEDIA] attach image carId=$carId sourceKey=$s kind=damage',
        );
      }
      final damageAttachResponse = await CarService().attachCarImages(
        carId,
        damageToAttach,
        kind: 'damage',
      );
      final damageAttachedCount = _attachedRowCount(damageAttachResponse);
      if (damageAttachedCount == 0) {
        final recovered = await _recoverRejectedAttach(
          carId: carId,
          attachItems: damageAttachItems,
          kind: 'damage',
          draftId: draftId,
        );
        final recoveredCount = _attachedRowCount(recovered);
        if (recoveredCount > 0) {
          await onMediaConfirmed?.call(recoveredCount);
        }
      } else {
        await onMediaConfirmed?.call(damageAttachedCount);
      }
    }
    if (damageToUpload.isNotEmpty) {
      for (final f in damageToUpload) {
        appLog(
          '[SELL MEDIA] attach image carId=$carId sourceKey=${f.path} '
          'kind=damage',
        );
      }
      final damageUploadResponse = await _uploadImagesResilient(
        carId: carId,
        files: damageToUpload,
        imageKind: 'damage',
        alreadyOnServer: remoteDamageCount,
        draftId: draftId,
        items: damageUploadItems,
        skipBlur: skipBlur,
      );
      final damageUploadedCount = _attachedRowCount(damageUploadResponse);
      if (damageUploadedCount > 0) {
        await onMediaConfirmed?.call(damageUploadedCount);
      }
    }

    try {
      await CarService().getCars(refresh: true);
    } catch (e, st) {
      logNonFatal(e, st);
    }

    if (videoError != null) {
      Error.throwWithStackTrace(videoError, videoStack ?? StackTrace.current);
    }
    if (!listingMediaConfirmed && imgs.isNotEmpty) {
      listingMediaConfirmed = await listingAlreadyHasMedia(carId);
    }
    return listingMediaConfirmed;
  }
}
