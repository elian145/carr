/// Listing availability (`Car.status` on the API).
bool isListingSold(Map<String, dynamic>? listing) {
  final status = (listing?['status'] ?? '').toString().trim().toLowerCase();
  return status == 'sold';
}

bool isListingPendingReview(Map<String, dynamic>? listing) {
  final status = (listing?['status'] ?? '').toString().trim().toLowerCase();
  return status == 'pending' || status == 'draft' || status == 'hidden';
}

/// Browse/search/public profiles: hide listings awaiting admin approval.
bool isListingPubliclyVisible(Map<String, dynamic>? listing) =>
    !isListingPendingReview(listing);

List<Map<String, dynamic>> publicListingsOnly(
  Iterable<Map<String, dynamic>> listings,
) =>
    [for (final listing in listings) if (isListingPubliclyVisible(listing)) listing];

bool isListingActive(Map<String, dynamic>? listing) =>
    !isListingSold(listing) && !isListingPendingReview(listing);
