/// Field accessors for listing detail maps (API shape varies).
library;

String? listingFirstNonEmpty(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final dynamic value = map[key];
    if (value == null) continue;
    final stringValue = value.toString().trim();
    if (stringValue.isNotEmpty) return stringValue;
  }
  return null;
}

Map<String, dynamic>? sellerMapFromListing(Map<String, dynamic>? car) {
  if (car == null) return null;
  final dynamic seller = car['seller'];
  if (seller is Map) {
    return Map<String, dynamic>.from(seller);
  }
  return null;
}

/// Listing phone for WhatsApp/call: `contact_phone` or nested `seller.*`.
String? sellerPhoneRawForContact(Map<String, dynamic>? car) {
  if (car == null) return null;
  final direct = car['contact_phone']?.toString().trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final seller = sellerMapFromListing(car);
  if (seller != null) {
    for (final key in [
      'phone_number',
      'phone',
      'whatsapp',
      'mobile',
      'contact_phone',
    ]) {
      final v = seller[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
  }
  return null;
}

bool hasDialableSellerPhone(Map<String, dynamic>? car) {
  final raw = sellerPhoneRawForContact(car);
  if (raw == null || raw.isEmpty) return false;
  return raw.replaceAll(RegExp(r'[^0-9]'), '').isNotEmpty;
}

Set<String> listingIdentityIds(Map<String, dynamic> car, String routeCarId) {
  return <String>{
    routeCarId.toString(),
    (car['id'] ?? '').toString(),
    (car['public_id'] ?? '').toString(),
  }..removeWhere((e) => e.trim().isEmpty);
}

/// Price/year bands for "related" recommendations on the detail page.
({double? priceMin, double? priceMax, int? yearMin, int? yearMax})
    relatedListingQueryBands(Map<String, dynamic> car) {
  final num? priceNum = car['price'] is num
      ? car['price'] as num
      : num.tryParse((car['price'] ?? '').toString());
  double? priceMin;
  double? priceMax;
  if (priceNum != null && priceNum > 0) {
    priceMin = (priceNum * 0.85).floorToDouble();
    priceMax = (priceNum * 1.15).ceilToDouble();
  }

  final int? yearNum = car['year'] is int
      ? (car['year'] as int)
      : int.tryParse((car['year'] ?? '').toString());
  int? yearMin;
  int? yearMax;
  if (yearNum != null && yearNum > 0) {
    yearMin = yearNum - 2;
    yearMax = yearNum + 2;
  }

  return (
    priceMin: priceMin,
    priceMax: priceMax,
    yearMin: yearMin,
    yearMax: yearMax,
  );
}

String? optionalListingFilterField(Map<String, dynamic> car, String snakeKey) {
  final camelKey = snakeKey.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (m) => m.group(1)!.toUpperCase(),
  );
  final raw = (car[snakeKey] ?? car[camelKey] ?? '').toString().trim();
  return raw.isEmpty ? null : raw;
}
