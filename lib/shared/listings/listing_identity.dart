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
