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

/// What the Listing Details app bar should show for the owner-only actions
/// (Edit / Delete / Analytics / Sold).
enum OwnerControlsAccess {
  /// Not an owner view: the entry point does not offer management, the
  /// listing is not loaded, the viewer is not the seller, or there is no
  /// session. Render nothing owner-specific.
  hidden,

  /// A session exists but the signed-in user's profile has not been
  /// confirmed yet (`/auth/me` pending or failed), so ownership cannot be
  /// decided. Never granted and never silently hidden: the UI shows a
  /// progress / retry affordance and re-evaluates when the user arrives.
  resolving,

  /// The signed-in user is the seller of this listing and the entry point
  /// offers management.
  granted,
}

/// Pure ownership-to-UI decision for the Listing Details owner controls.
///
/// [hasSession] is "a stored/active auth token exists" -- it distinguishes a
/// still-loading profile (token present, [userId] not known yet; the state
/// `AuthGuard` deliberately mounts My Listings in during a cold start) from a
/// genuinely logged-out viewer.
///
/// This only drives presentation. The backend independently authorizes every
/// owner action (edit / delete / sold / analytics), so [resolving] can never
/// grant anything -- it only avoids a wrong "not the owner" verdict.
OwnerControlsAccess resolveOwnerControlsAccess({
  required bool allowOwnerManagement,
  required Map<String, dynamic>? car,
  required String? userId,
  required bool hasSession,
}) {
  if (!allowOwnerManagement || car == null) return OwnerControlsAccess.hidden;
  if (isListingOwner(car, userId)) return OwnerControlsAccess.granted;
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty && hasSession) return OwnerControlsAccess.resolving;
  return OwnerControlsAccess.hidden;
}

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
