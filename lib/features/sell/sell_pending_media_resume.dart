import '../../services/api_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/prefs/sell_pending_media_prefs.dart';
import 'sell_listing_media_upload.dart';
import 'sell_video_helpers.dart';

/// Completes media upload after the app was killed mid-submit.
class SellPendingMediaResume {
  SellPendingMediaResume._();

  static bool _inFlight = false;

  /// Returns true when pending media was uploaded (or already present and cleared).
  static Future<bool> tryResume() async {
    if (_inFlight) return false;
    _inFlight = true;
    try {
      final pending = await SellPendingMediaPrefs.load();
      if (pending == null) return false;

      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return false;

      final carId = (pending['carId'] ?? '').toString().trim();
      if (carId.isEmpty) {
        await SellPendingMediaPrefs.clear();
        return false;
      }

      final rawCarData = pending['carData'];
      final carData = rawCarData is Map
          ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
          : <String, dynamic>{};

      // If any media already landed, skip to avoid duplicate uploads.
      if (await SellListingMediaUpload.listingAlreadyHasMedia(carId)) {
        await SellPendingMediaPrefs.clear();
        return true;
      }

      await SellListingMediaUpload.uploadForCar(
        carId: carId,
        carData: carData,
        multipartFileBuilder: buildVideoMultipartFile,
      );
      await SellPendingMediaPrefs.clear();
      return true;
    } catch (e, st) {
      logNonFatal(e, st, 'SellPendingMediaResume');
      // Keep pending so a later cold start / My Listings can retry.
      return false;
    } finally {
      _inFlight = false;
    }
  }
}
