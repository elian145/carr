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
