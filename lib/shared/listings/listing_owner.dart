/// Whether [userId] owns [car] (seller match on listing or nested seller map).
bool isListingOwner(Map<String, dynamic>? car, String? userId) {
  if (car == null) return false;
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;

  final sellerId = (car['seller_id'] ?? '').toString().trim();
  if (sellerId.isNotEmpty && sellerId == uid) return true;

  final seller = car['seller'];
  if (seller is Map) {
    for (final key in ['id', 'user_id', 'seller_id']) {
      final v = (seller[key] ?? '').toString().trim();
      if (v.isNotEmpty && v == uid) return true;
    }
  }
  return false;
}

/// Whether the Listing Details app bar should offer the owner-only actions
/// (Edit / Delete / Analytics / Sold).
///
/// Requires ALL of: the entry point offers management ([allowOwnerManagement]
/// -- My Listings only; Search and other entry points never do), the listing
/// is loaded, and the signed-in account ([userId]) is its seller.
///
/// This only drives presentation. The navigation origin alone never grants
/// anything, [userId] is a hint derived from the session (see
/// `SessionIdentity`), and the backend independently authorizes every owner
/// action (edit / delete / sold / analytics) from the request's token.
bool canManageListing({
  required bool allowOwnerManagement,
  required Map<String, dynamic>? car,
  required String? userId,
}) => allowOwnerManagement && car != null && isListingOwner(car, userId);

/// Merges an edit/sold/etc. result [updated] over [current] without letting
/// a partial result (e.g. the Sell form payload, which carries no `seller`)
/// erase who owns the listing: the ownership fields of [current] are
/// restored whenever the merge would otherwise lose a known owner.
Map<String, dynamic> mergeListingKeepingOwner(
  Map<String, dynamic> current,
  Map<String, dynamic> updated,
  String? userId,
) {
  final merged = <String, dynamic>{...current, ...updated};
  if (isListingOwner(current, userId) && !isListingOwner(merged, userId)) {
    for (final key in const ['seller', 'seller_id']) {
      if (current.containsKey(key)) {
        merged[key] = current[key];
      } else {
        merged.remove(key);
      }
    }
  }
  return merged;
}
