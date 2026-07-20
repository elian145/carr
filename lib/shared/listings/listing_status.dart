/// Listing availability (`Car.status` on the API).
bool isListingSold(Map<String, dynamic>? listing) {
  final status = (listing?['status'] ?? '').toString().trim().toLowerCase();
  return status == 'sold';
}

bool isListingPendingReview(Map<String, dynamic>? listing) {
  final status = (listing?['status'] ?? '').toString().trim().toLowerCase();
  return status == 'pending' || status == 'draft' || status == 'hidden';
}

bool isListingActive(Map<String, dynamic>? listing) =>
    !isListingSold(listing) && !isListingPendingReview(listing);
