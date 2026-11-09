/// Unwraps `GET /api/cars/:id` payloads (`{ "car": { ... } }` or flat map).
Map<String, dynamic> unwrapCarApiPayload(Map<String, dynamic> payload) {
  final inner = payload['car'];
  if (inner is Map) {
    return Map<String, dynamic>.from(inner.cast<String, dynamic>());
  }
  return Map<String, dynamic>.from(payload);
}

/// N-1: the only part of a chat listing preview the server honours is the
/// listing id (it derives title/price/image from its own Listing row and
/// ignores everything else). Send just that instead of the whole local card.
/// An empty id still yields a non-empty map so the server falls back to the
/// conversation's own listing.
Map<String, dynamic>? chatListingPreviewRefForSend(
  Map<String, dynamic>? preview,
) {
  if (preview == null || preview.isEmpty) return null;
  return <String, dynamic>{'id': listingPrimaryId(preview)};
}

String listingPrimaryId(Map<String, dynamic> listing) {
  final publicId = (listing['public_id'] ?? '').toString().trim();
  if (publicId.isNotEmpty) return publicId;
  return (listing['id'] ?? '').toString().trim();
}

String listingAltId(Map<String, dynamic> listing) {
  final id = (listing['id'] ?? '').toString().trim();
  if (id.isNotEmpty) return id;
  return (listing['public_id'] ?? '').toString().trim();
}

bool listingMatchesId(Map<String, dynamic> listing, String candidate) {
  final c = candidate.trim();
  if (c.isEmpty) return false;
  return listingPrimaryId(listing) == c || listingAltId(listing) == c;
}
