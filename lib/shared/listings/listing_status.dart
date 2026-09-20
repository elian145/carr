/// Listing availability (`Car.status` on the API).
bool isListingSold(Map<String, dynamic>? listing) {
  final status = (listing?['status'] ?? '').toString().trim().toLowerCase();
  return status == 'sold';
}

/// True for a listing awaiting its *first* admin review (never yet
/// published) -- distinct from [isListingHidden], which is a listing an
/// admin actively removed from public view after moderation.
bool isListingPending(Map<String, dynamic>? listing) {
  final status = (listing?['status'] ?? '').toString().trim().toLowerCase();
  return status == 'pending' || status == 'draft';
}

/// True for a listing an admin hid from public view after moderation (e.g.
/// a policy violation) -- as opposed to [isListingPending], which has simply
/// never been reviewed yet. The backend does not currently record *why* a
/// listing was hidden (see `Car.status`, `kk/routes/admin.py`), so callers
/// must not fabricate a reason -- only show that it is hidden.
bool isListingHidden(Map<String, dynamic>? listing) {
  final status = (listing?['status'] ?? '').toString().trim().toLowerCase();
  return status == 'hidden';
}

/// Any status that keeps a listing off public browse/search (pending,
/// draft, or hidden). Prefer [isListingPending]/[isListingHidden] wherever
/// the UI needs to tell those two apart; this stays for call sites that
/// only care whether the listing is publicly visible.
bool isListingPendingReview(Map<String, dynamic>? listing) =>
    isListingPending(listing) || isListingHidden(listing);

/// Browse/search/public profiles: hide listings awaiting admin approval.
bool isListingPubliclyVisible(Map<String, dynamic>? listing) =>
    !isListingPendingReview(listing);

List<Map<String, dynamic>> publicListingsOnly(
  Iterable<Map<String, dynamic>> listings,
) =>
    [for (final listing in listings) if (isListingPubliclyVisible(listing)) listing];

bool isListingActive(Map<String, dynamic>? listing) =>
    !isListingSold(listing) && !isListingPendingReview(listing);
