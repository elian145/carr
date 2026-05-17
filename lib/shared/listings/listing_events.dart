import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight bus so listing screens stay in sync after delete (e.g. detail → home).
class ListingEvents {
  ListingEvents._();

  static final ValueNotifier<String?> deletedListingId =
      ValueNotifier<String?>(null);

  static void notifyDeleted(String carId) {
    final id = carId.trim();
    if (id.isEmpty) return;
    deletedListingId.value = id;
  }
}

/// Clears home-feed and car-detail disk caches so stale listings are not re-shown.
Future<void> invalidateListingDiskCaches(String carId) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final id = carId.trim();
    if (id.isNotEmpty) {
      await sp.remove('cache_car_$id');
    }
    for (final key in sp.getKeys()) {
      if (key.startsWith('cache_home_')) {
        await sp.remove(key);
      }
    }
  } catch (_) {}
}
