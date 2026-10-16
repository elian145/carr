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

// ---------------------------------------------------------------------------
// Pending edits of a published listing.
//
// Editing an Active listing never changes what buyers see: the owner's
// changes live in a separate "pending revision" of the SAME listing that an
// admin must approve (see `kk/listing_revisions.py`). Owner payloads
// (`GET /api/cars/<id>`, `GET /api/cars/my-listings`) carry it as
// `pending_revision`; the top-level listing fields stay the APPROVED ones.
// ---------------------------------------------------------------------------

/// The `pending_revision` object of an owner listing payload, or null.
Map<String, dynamic>? listingPendingRevision(Map<String, dynamic>? listing) {
  final raw = listing?['pending_revision'];
  if (raw is Map) return Map<String, dynamic>.from(raw.cast<String, dynamic>());
  return null;
}

String _pendingRevisionStatus(Map<String, dynamic>? listing) =>
    (listingPendingRevision(listing)?['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

/// A public listing whose owner-submitted edits are waiting for admin review.
bool listingHasPendingEditsUnderReview(Map<String, dynamic>? listing) =>
    !isListingPendingReview(listing) &&
    _pendingRevisionStatus(listing) == 'pending';

/// A public listing whose last submitted edits were rejected by an admin
/// (the approved version stays live; the owner can fix and resubmit).
bool listingHasRejectedEdits(Map<String, dynamic>? listing) =>
    !isListingPendingReview(listing) &&
    _pendingRevisionStatus(listing) == 'rejected';

/// A public listing with saved-but-not-yet-submitted edits (e.g. media was
/// changed but the owner never finished saving).
bool listingHasUnsubmittedEdits(Map<String, dynamic>? listing) =>
    !isListingPendingReview(listing) &&
    _pendingRevisionStatus(listing) == 'editing';

/// True when any pending revision exists (under review, rejected, unsaved).
bool listingHasPendingRevision(Map<String, dynamic>? listing) =>
    !isListingPendingReview(listing) && _pendingRevisionStatus(listing).isNotEmpty;

/// The admin's rejection reason for the owner's last submitted edits.
String listingRevisionRejectionReason(Map<String, dynamic>? listing) =>
    (listingPendingRevision(listing)?['rejection_reason'] ?? '')
        .toString()
        .trim();

/// The version of the listing the owner should see/edit: the pending
/// revision's working copy when one exists, otherwise the listing itself.
/// The result keeps the approved listing's identity (id/public_id/status) so
/// it can be passed to the edit wizard unchanged -- an edit always targets
/// the same listing.
Map<String, dynamic> listingForOwnerEditing(Map<String, dynamic> listing) {
  final pending = listingPendingRevision(listing);
  final working = pending?['car'];
  if (pending == null || working is! Map) return listing;
  if (isListingPendingReview(listing)) return listing;
  final merged = Map<String, dynamic>.from(working.cast<String, dynamic>());
  for (final key in const ['id', 'public_id', 'numeric_id', 'status']) {
    if (listing.containsKey(key)) merged[key] = listing[key];
  }
  merged['pending_revision'] = pending;
  return merged;
}
