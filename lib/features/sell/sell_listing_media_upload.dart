import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/car_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/listings/listing_image_media.dart';
import '../../shared/prefs/sell_draft_media_persistence.dart';
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

  static int _listingImageCount(Map<String, dynamic> car) {
    final imgs = car['images'];
    if (imgs is! List) return 0;
    var count = 0;
    for (final it in imgs) {
      if (it is Map &&
          (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
        continue;
      }
      count++;
    }
    return count;
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

  /// True when the server listing already has any listing media.
  static Future<bool> listingAlreadyHasMedia(String carId) async {
    try {
      final fresh = await ApiService.getCar(carId);
      final inner = fresh['car'];
      if (inner is! Map) return false;
      final car = Map<String, dynamic>.from(inner.cast<String, dynamic>());
      if (_listingImageCount(car) > 0) return true;
      return (car['image_url'] ?? '').toString().trim().isNotEmpty;
    } catch (e, st) {
      logNonFatal(e, st);
      return false;
    }
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
      if (existingId != null && source.isNotEmpty) {
        imageIdsBySource[source] = existingId;
      }
      final local = ListingImageMedia.localFile(img);
      if (local != null && await _localUploadFileExists(local)) {
        toUpload.add(local);
        uploadItems.add(img);
      } else {
        final s = source;
        if (s.startsWith('uploads/') ||
            s.startsWith('static/') ||
            s.startsWith('/static/')) {
          if (existingId == null) {
            toAttach.add(s);
            attachItems.add(img);
          }
        } else if (s.startsWith('http://') || s.startsWith('https://')) {
          if (existingId == null) {
            toAttach.add(s);
            attachItems.add(img);
          }
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
    if (toAttach.isNotEmpty || toUpload.isNotEmpty || imgs.isNotEmpty) {
      onPhase?.call(SellMediaUploadPhase.photos);
    }
    if (toAttach.isNotEmpty) {
      final attachResponse = await CarService().attachCarImages(carId, toAttach);
      latestMediaResponse = attachResponse;
      _collectUploadedImageIds(imageIdsBySource, attachItems, attachResponse);
    }
    if (toUpload.isNotEmpty) {
      final uploadResponse = await CarService().uploadCarImages(carId, toUpload);
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
    for (final dynamic img in dimgs) {
      final local = ListingImageMedia.localFile(img);
      if (local != null && await _localUploadFileExists(local)) {
        damageToUpload.add(local);
        continue;
      }
      final s = ListingImageMedia.source(img);
      if (s.startsWith('uploads/') ||
          s.startsWith('static/') ||
          s.startsWith('/static/')) {
        damageToAttach.add(s);
      } else if (s.startsWith('http://') || s.startsWith('https://')) {
        // Skip absolute URLs for attach/upload here.
      }
    }
    if (damageToAttach.isNotEmpty || damageToUpload.isNotEmpty) {
      onPhase?.call(SellMediaUploadPhase.damagePhotos);
    }
    if (damageToAttach.isNotEmpty) {
      await CarService().attachCarImages(
        carId,
        damageToAttach,
        kind: 'damage',
      );
    }
    if (damageToUpload.isNotEmpty) {
      await CarService().uploadCarImages(
        carId,
        damageToUpload,
        imageKind: 'damage',
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
