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

/// All listing contact phones (`contact_phones` / `contact_phone`), else seller.
///
/// Public browse payloads omit raw phones; [hasDialableSellerPhone] still
/// returns true when [has_contact_phone] is set so Call/WhatsApp stay visible.
List<String> sellerPhonesForContact(Map<String, dynamic>? car) {
  if (car == null) return const [];
  final out = <String>[];
  final seen = <String>{};

  void add(String? raw) {
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return;
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty || seen.contains(digits)) return;
    seen.add(digits);
    out.add(trimmed);
  }

  final list = car['contact_phones'];
  if (list is List) {
    for (final item in list) {
      add(item?.toString());
    }
  }
  add(car['contact_phone']?.toString());

  if (out.isEmpty) {
    final seller = sellerMapFromListing(car);
    if (seller != null) {
      for (final key in [
        'phone_number',
        'phone',
        'whatsapp',
        'mobile',
        'contact_phone',
      ]) {
        add(seller[key]?.toString());
      }
    }
  }
  return out;
}

/// Listing phone for WhatsApp/call: first of [sellerPhonesForContact].
String? sellerPhoneRawForContact(Map<String, dynamic>? car) {
  final phones = sellerPhonesForContact(car);
  if (phones.isEmpty) return null;
  return phones.first;
}

bool listingHasContactAvailability(Map<String, dynamic>? car) {
  if (car == null) return false;
  if (car['has_contact_phone'] == true) return true;
  final masked = (car['contact_phone_masked'] ?? '').toString().trim();
  return masked.isNotEmpty;
}

bool hasDialableSellerPhone(Map<String, dynamic>? car) {
  if (sellerPhonesForContact(car).any((raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '').isNotEmpty;
  })) {
    return true;
  }
  return listingHasContactAvailability(car);
}

String? sellerPhoneMaskedForDisplay(Map<String, dynamic>? car) {
  if (car == null) return null;
  final masked = (car['contact_phone_masked'] ?? '').toString().trim();
  if (masked.isNotEmpty) return masked;
  final phones = sellerPhonesForContact(car);
  if (phones.isEmpty) return null;
  final digits = phones.first.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 4) return '****';
  return '${'*' * (digits.length - 4)}${digits.substring(digits.length - 4)}';
}

Set<String> listingIdentityIds(Map<String, dynamic> car, String routeCarId) {
  return <String>{
    routeCarId.toString(),
    (car['id'] ?? '').toString(),
    (car['public_id'] ?? '').toString(),
  }..removeWhere((e) => e.trim().isEmpty);
}
