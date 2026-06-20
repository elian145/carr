import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/debug/app_log.dart';

typedef ListingDeletedHandler = void Function(String carId);

/// Lightweight bus so listing screens stay in sync after delete (e.g. my listings → home).
class ListingEvents {
  ListingEvents._();

  static final ValueNotifier<String?> deletedListingId =
      ValueNotifier<String?>(null);

  static final List<ListingDeletedHandler> _deleteHandlers =
      <ListingDeletedHandler>[];

  /// Register a handler that must run even when the home screen is not mounted
  /// (e.g. to update static feed caches before tab navigation rebuilds home).
  static void addDeleteHandler(ListingDeletedHandler handler) {
    if (!_deleteHandlers.contains(handler)) {
      _deleteHandlers.add(handler);
    }
  }

  static void removeDeleteHandler(ListingDeletedHandler handler) {
    _deleteHandlers.remove(handler);
  }

  static void notifyDeleted(String carId) {
    final id = carId.trim();
    if (id.isEmpty) return;
    for (final handler in List<ListingDeletedHandler>.from(_deleteHandlers)) {
      handler(id);
    }
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
  } catch (e, st) { logNonFatal(e, st); }
}
