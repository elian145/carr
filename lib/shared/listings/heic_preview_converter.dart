import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../debug/app_log.dart';
import '../prefs/sell_draft_media_persistence.dart';

/// Fixes real-device evidence that a picked Sell photo can be HEIC/HEIF
/// (e.g. `listing_orig_125689253.heif` from a Samsung device) and that
/// Flutter's own Skia-based decoders -- `Image.file`/`Image.memory`, and
/// `dart:ui`'s `instantiateImageCodec` -- cannot decode HEIC/HEIF at all:
///
///   Image.file failed: Exception: Could not decompress image
///   XFile.readAsBytes() succeeds: 1758621 bytes loaded
///   Image.memory also fails: Exception: Could not decompress image
///   image/vnd.android.heic ... Format is not supported
///   FlutterImageDecoderImplDefault: Failed to decode image
///
/// The file itself is fine (bytes read succeed); only Skia's own decoder
/// is the gap.
///
/// A first fix attempt used `flutter_image_compress`, but real-device logs
/// then proved ITS Android decode path also routes through
/// `android.graphics.BitmapFactory` (the OS's own decoder) -- which fails
/// on this exact Samsung HEIF with:
///
///   [HEIC PREVIEW] conversion failed error=CompressError:
///   Attempt to invoke virtual method
///   'void android.graphics.Bitmap.recycle()' on a null object reference
///
/// (`BitmapFactory` returned `null`; the plugin then tried to recycle that
/// null Bitmap.) A package audit found no maintained Flutter plugin that
/// decodes HEIC/HEIF on Android without ultimately delegating to
/// `BitmapFactory`/`android.graphics.ImageDecoder` -- including
/// `heif_converter`, `heic_native`, `flutter_heic_to_jpg`, and
/// `platform_image_converter`, all confirmed via their own source/docs to
/// use the same OS decoder.
///
/// This is now fixed via a small native Android decoder
/// (`android/app/src/main/kotlin/com/carzo/app/HeifPreviewDecoder.kt`,
/// registered as a `MethodChannel` in `MainActivity.kt`) built on
/// `io.github.awxkee:avif-coder:2.2.1`, which bundles its OWN native
/// `libheif`/`libde265` and never touches `BitmapFactory`/`ImageDecoder`
/// for the decode step -- see that Kotlin file's doc comment for the
/// license-metadata discrepancy note (GitHub repo says MIT; the Maven
/// Central POM says Apache-2.0 + BSD-3-Clause; both are preserved there,
/// no legal conclusion is made here).
///
/// This helper only ever produces an *additional* JPEG preview file; it
/// never touches, renames, or replaces the original HEIC/HEIF source --
/// that original stays the only thing `ListingImageMedia.source()`/
/// `localFile()` (and therefore upload/submission) ever return.
abstract final class HeicPreviewConverter {
  static const _heicExtensions = {'.heic', '.heif'};

  /// Matches the channel registered in `MainActivity.configureFlutterEngine`
  /// (Kotlin) -- see `HeifPreviewDecoder.kt`.
  static const MethodChannel _channel = MethodChannel('carzo/heif_preview');

  /// Whether [path]'s extension is HEIC/HEIF. JPEG/PNG/etc. photos should
  /// never be run through conversion -- they already render fine.
  static bool isHeic(String path) {
    final detected = _heicExtensions.contains(p.extension(path).toLowerCase());
    // TEMPORARY diagnostic logging -- narrow pass to determine why the
    // JPEG preview path isn't showing up on real devices. Remove once the
    // root cause is confirmed.
    appLog('[HEIC PREVIEW] inputPath=$path');
    appLog('[HEIC PREVIEW] detected=$detected');
    return detected;
  }

  /// Converts already-read HEIC/HEIF [bytes] to a JPEG (via the native
  /// decoder above) and durably persists it under [draftId]'s draft-media
  /// folder (the same convention/location `SellDraftMediaPersistence`
  /// already uses for every other Sell media file), returning the
  /// resulting path.
  ///
  /// [maxDimension] bounds the decoded bitmap's longer side (aspect ratio
  /// preserved natively via `ScaleMode.FIT` on the Android side) so a
  /// large original can't spike memory -- this is a preview only, never
  /// the upload source. [quality] bounds the JPEG re-encode quality.
  ///
  /// Returns `null` on any failure -- callers must treat that exactly like
  /// "no preview available yet" (fall back to the original), never as a
  /// fatal error: a photo that fails to get a preview is no worse off
  /// than before this fix existed.
  static Future<String?> ensureJpegPreview(
    Uint8List bytes, {
    required String draftId,
    int maxDimension = 2048,
    int quality = 90,
  }) async {
    if (bytes.isEmpty) return null;
    // TEMPORARY diagnostic logging -- see isHeic() above.
    appLog('[HEIC PREVIEW] conversion start bytes=${bytes.length}');
    try {
      final jpeg = await _channel.invokeMethod<Uint8List>(
        'decodeHeifToJpeg',
        <String, Object?>{
          'bytes': bytes,
          'maxDimension': maxDimension,
          'quality': quality,
        },
      );
      if (jpeg == null || jpeg.isEmpty) {
        appLog('[HEIC PREVIEW] conversion success outputBytes=0');
        return null;
      }
      appLog('[HEIC PREVIEW] conversion success outputBytes=${jpeg.length}');
      final persistedPath = await SellDraftMediaPersistence.persistBytesToDraft(
        jpeg,
        draftId: draftId,
        namePrefix: 'listing_preview',
        extension: '.jpg',
      );
      appLog('[HEIC PREVIEW] persistedPath=$persistedPath');
      return persistedPath;
    } catch (e, st) {
      appLog('[HEIC PREVIEW] conversion failed error=${e.runtimeType}: $e');
      logNonFatal(e, st);
      return null;
    }
  }
}
