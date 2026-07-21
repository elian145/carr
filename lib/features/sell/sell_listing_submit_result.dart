/// Result of creating/updating a listing from the sell wizard (UX-05).
class SellListingSubmitResult {
  const SellListingSubmitResult({
    required this.id,
    required this.pendingReview,
  });

  final String id;

  /// True when the listing is not yet visible to buyers (pending/draft/hidden).
  final bool pendingReview;
}
