/// Result of creating/updating a listing from the sell wizard (UX-05).
class SellListingSubmitResult {
  const SellListingSubmitResult({
    required this.id,
    required this.pendingReview,
    this.editSubmittedForReview = false,
  });

  final String id;

  /// True when the listing is not yet visible to buyers (pending/draft/hidden).
  final bool pendingReview;

  /// True when this was an edit of an already-published listing: the changes
  /// were saved as a pending revision awaiting admin review, and buyers keep
  /// seeing the previously approved version until it is approved.
  final bool editSubmittedForReview;
}
