import 'package:image_picker/image_picker.dart';

import '../../services/ai_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/listings/listing_image_media.dart';

/// Uploads listing photos to storage *before* the listing row is created.
///
/// `POST /api/cars` takes no photos, so photos can only be linked to a listing
/// that already exists. Staging the bytes first turns that second request into
/// a small "attach these URLs" call, so a new listing is never published with
/// its photos still in flight.
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
  }) async {
    // Listing + damage in parallel — they hit separate upload batches.
    final results = await Future.wait([
      for (final key in _mediaKeys)
        _stageList(carData, key, onProgress: onProgress),
    ]);
    return results.fold<int>(0, (sum, n) => sum + n);
  }

  static Future<int> _stageList(
    Map<String, dynamic> carData,
    String key, {
    void Function(int staged, int total)? onProgress,
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
    Map<String, List<String>>? payload;
    try {
      payload = await AiService.processCarImagesToServerPayload(
        files,
        skipBlur: true,
        inlineBase64: false,
      );
    } catch (e, st) {
      logNonFatal(e, st, 'SellPhotoPrestage.$key');
      return 0;
    }

    final urls = payload?['paths'] ?? const <String>[];
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
}
