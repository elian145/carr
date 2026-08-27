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

  /// Uploads [files] and treats "client timed out after the server saved them"
  /// as success so a retry does not duplicate photos.
  static Future<Map<String, dynamic>> _uploadImagesResilient({
    required String carId,
    required List<XFile> files,
    String imageKind = 'listing',
    int? alreadyOnServer,
  }) async {
    if (files.isEmpty) return <String, dynamic>{};
    final kind = imageKind.toLowerCase() == 'damage' ? 'damage' : 'listing';
    final before = alreadyOnServer ?? await _remoteImageCount(carId, kind);
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
        return await CarService().uploadCarImages(
          carId,
          files,
          imageKind: imageKind,
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
    );
  }

  /// True when the server listing already has any listing media.
  static Future<bool> listingAlreadyHasMedia(String carId) async {
    final car = await _fetchCarMap(carId);
    if (car == null) return false;
    if (_listingImageCount(car) > 0) return true;
    return (car['image_url'] ?? '').toString().trim().isNotEmpty;
  }

  /// Uploads images, videos, and damage media for [carId] from [carData].
  static Future<void> uploadForCar({
    required String carId,
    required Map<String, dynamic> carData,
    Future<http.MultipartFile> Function(XFile video)? multipartFileBuilder,
    void Function(SellMediaUploadPhase phase)? onPhase,
  }) async {
    final dynamic maybeImgs = carData['images'];
    final List<dynamic> imgsRaw = (maybeImgs is List) ? maybeImgs : const [];
    final List<dynamic> imgs = _imagesWithPrimaryFirst(
      imgsRaw,
      primaryIndex: _primaryImageIndex(carData, length: imgsRaw.length),
    );
    final dynamic maybeVideos = carData['videos'];
    final List<dynamic> vids = (maybeVideos is List) ? maybeVideos : const [];
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
    if (toUpload.isNotEmpty) {
      remoteListingCount = await _remoteImageCount(carId, 'listing');
      if (remoteListingCount >= imageIdsBySource.length + toUpload.length) {
        appLog(
          'SellListingMediaUpload: skipping listing photo upload; '
          'server already has $remoteListingCount',
        );
        toUpload.clear();
        uploadItems.clear();
      }
    }
    if (toAttach.isNotEmpty || toUpload.isNotEmpty || imgs.isNotEmpty) {
      onPhase?.call(SellMediaUploadPhase.photos);
    }
    if (toAttach.isNotEmpty) {
      final attachResponse = await CarService().attachCarImages(carId, toAttach);
      latestMediaResponse = attachResponse;
      _collectUploadedImageIds(imageIdsBySource, attachItems, attachResponse);
      if (_attachedRowCount(attachResponse) == 0) {
        final recovered = await _recoverRejectedAttach(
          carId: carId,
          attachItems: attachItems,
          kind: 'listing',
        );
        if (recovered != null) {
          latestMediaResponse = recovered;
          _collectUploadedImageIds(imageIdsBySource, attachItems, recovered);
        }
      }
    }
    if (toUpload.isNotEmpty) {
      final uploadResponse = await _uploadImagesResilient(
        carId: carId,
        files: toUpload,
        alreadyOnServer: remoteListingCount,
      );
      latestMediaResponse = uploadResponse;
      _collectUploadedImageIds(imageIdsBySource, uploadItems, uploadResponse);
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
      if (existingVideoCount >= videosToUpload.length) {
        videosToUpload.clear();
      }
    }
    if (videosToUpload.isNotEmpty) {
      onPhase?.call(SellMediaUploadPhase.videos);
      try {
        await ApiService.uploadCarVideos(
          carId,
          videosToUpload,
          multipartFileBuilder:
              multipartFileBuilder ?? buildVideoMultipartFile,
        );
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
      final damageAttachResponse = await CarService().attachCarImages(
        carId,
        damageToAttach,
        kind: 'damage',
      );
      if (_attachedRowCount(damageAttachResponse) == 0) {
        await _recoverRejectedAttach(
          carId: carId,
          attachItems: damageAttachItems,
          kind: 'damage',
        );
      }
    }
    if (damageToUpload.isNotEmpty) {
      await _uploadImagesResilient(
        carId: carId,
        files: damageToUpload,
        imageKind: 'damage',
        alreadyOnServer: remoteDamageCount,
      );
    }

    try {
      await CarService().getCars(refresh: true);
    } catch (e, st) {
      logNonFatal(e, st);
    }

    if (videoError != null) {
      Error.throwWithStackTrace(videoError, videoStack ?? StackTrace.current);
    }
  }
}
