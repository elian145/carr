import 'package:flutter/foundation.dart';

/// Lightweight bus so listing screens stay in sync after delete (e.g. detail → my listings).
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
