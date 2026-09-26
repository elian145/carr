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
import 'sell_photo_prestage.dart';
import 'sell_video_helpers.dart';

/// Phases reported while [SellListingMediaUpload.uploadForCar] runs.
enum SellMediaUploadPhase {
  photos,
  videos,
  damagePhotos,
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

  static void _collectUploadedImageIds(
    Map<String, int> idsBySource,
    List<dynamic> sourceItems,
    Map<String, dynamic>? response,
  ) {
    final rows = response?['images'] ?? response?['uploaded'];
    if (rows is! List) return;
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
      final enqueueResponse = await ApiService.uploadCarImages(
        carId,
        freshFiles,
        imageKind: imageKind,
        async: true,
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

    return CarService().attachCarImages(carId, relPaths, kind: imageKind);
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
  }) async {
    if (files.isEmpty) return <String, dynamic>{};
    final kind = imageKind.toLowerCase() == 'damage' ? 'damage' : 'listing';
    final before = alreadyOnServer ?? await _remoteImageCount(carId, kind);
    final tracker = SellAsyncJobTracker(draftId);
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
    for (final item in attachItems) {
      final local = _stagedLocalFile(item);
      if (local != null && await _localUploadFileExists(local)) {
        files.add(local);
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
  }) async {
    final dynamic maybeImgs = carData['images'];
    final List<dynamic> imgsRaw = (maybeImgs is List) ? maybeImgs : const [];
    final List<dynamic> imgs = _imagesWithPrimaryFirst(
      imgsRaw,
      primaryIndex: _primaryImageIndex(carData, length: imgsRaw.length),
    );
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

    for (final dynamic img in imgs) {
      final existingId = ListingImageMedia.id(img);
      final source = ListingImageMedia.source(img);
      if (existingId != null) {
        if (source.isNotEmpty) imageIdsBySource[source] = existingId;
        continue;
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
        imageIdsBySource.isEmpty) {
      throw StateError(
        'Listing photos could not be read for upload. Please re-add the photos and try again.',
      );
    }

    Map<String, dynamic>? latestMediaResponse;
    var remoteListingCount = 0;
    var listingMediaConfirmed = imgs.isEmpty;
    if (toUpload.isNotEmpty) {
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
    if (videosToUpload.isNotEmpty) {
      onPhase?.call(SellMediaUploadPhase.videos);
      for (final f in videosToUpload) {
        appLog('[SELL MEDIA] attach video carId=$carId sourceKey=${f.path}');
      }
      try {
        await ApiService.uploadCarVideos(
          carId,
          videosToUpload,
          multipartFileBuilder:
              multipartFileBuilder ?? buildVideoMultipartFile,
        );
        await onMediaConfirmed?.call(videosToUpload.length);
      } catch (e, st) {
        logNonFatal(e, st, 'SellListingMediaUpload.videos');
        videoError = e;
        videoStack = st;
      }
    }

    final dynamic maybeDmg = carData['damage_images'];
    final List<dynamic> dimgs = (maybeDmg is List) ? maybeDmg : const [];
    final List<XFile> damageToUpload = <XFile>[];
    final List<String> damageToAttach = <String>[];
    final List<dynamic> damageAttachItems = <dynamic>[];
    for (final dynamic img in dimgs) {
      if (ListingImageMedia.id(img) != null) continue;
      final local = ListingImageMedia.localFile(img);
      if (local != null && await _waitForLocalUploadFile(local)) {
        damageToUpload.add(local);
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
