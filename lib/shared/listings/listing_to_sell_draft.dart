import 'listing_identity.dart';

/// Builds a sell-wizard draft snapshot from an existing API listing map.
Map<String, dynamic> listingToSellDraftSnapshot(
  Map<String, dynamic> listing, {
  String? contactPhoneFallback,
}) {
  final listingId = listingPrimaryId(listing);
  final seller = listing['seller'];
  String sellerPhone = '';
  if (seller is Map) {
    sellerPhone = (seller['phone_number'] ?? seller['phone'] ?? '')
        .toString()
        .trim();
  }

  final listingImages = listing['images'];
  final normalImages = <String>[];
  final damageImages = <String>[];
  if (listingImages is List) {
    for (final it in listingImages) {
      if (it is! Map) continue;
      final kind = (it['kind'] ?? '').toString().toLowerCase();
      final url = (it['image_url'] ?? it['url'] ?? it['path'] ?? '')
          .toString()
          .trim();
      if (url.isEmpty) continue;
      if (kind == 'damage') {
        damageImages.add(url);
      } else {
        normalImages.add(url);
      }
    }
  }
  final primary = (listing['image_url'] ?? '').toString().trim();
  if (primary.isNotEmpty && !normalImages.contains(primary)) {
    normalImages.insert(0, primary);
  }

  final videoPaths = <String>[];
  final videos = listing['videos'];
  if (videos is List) {
    for (final it in videos) {
      final path = it is Map
          ? (it['video_url'] ?? it['url'] ?? it['path'] ?? '').toString()
          : it.toString();
      if (path.trim().isNotEmpty) videoPaths.add(path.trim());
    }
  }

  final location = (listing['location'] ?? listing['city'] ?? '').toString();
  final city = (listing['city'] ?? listing['plate_city'] ?? location)
      .toString()
      .trim();

  final carData = <String, dynamic>{
    '_editListingId': listingId,
    'brand': (listing['brand'] ?? '').toString(),
    'model': (listing['model'] ?? '').toString(),
    'trim': (listing['trim'] ?? 'Base').toString().trim().isEmpty
        ? 'Base'
        : (listing['trim'] ?? 'Base').toString(),
    'year': (listing['year'] ?? '').toString(),
    'mileage': (listing['mileage'] ?? '').toString(),
    'price': (listing['price'] ?? '').toString(),
    'condition': _capitalizeFirst((listing['condition'] ?? 'used').toString()),
    'transmission':
        _capitalizeFirst((listing['transmission'] ?? 'automatic').toString()),
    'fuel_type': _capitalizeFirst(
      (listing['fuel_type'] ?? listing['engine_type'] ?? 'gasoline').toString(),
    ),
    'engine_type': _capitalizeFirst(
      (listing['engine_type'] ?? listing['fuel_type'] ?? 'gasoline').toString(),
    ),
    'body_type':
        _capitalizeFirst((listing['body_type'] ?? 'sedan').toString()),
    'drive_type':
        _capitalizeFirst((listing['drive_type'] ?? 'fwd').toString()),
    'color': (listing['color'] ?? '').toString(),
    'seating': (listing['seating'] ?? '5').toString(),
    'region_specs': (listing['region_specs'] ?? '').toString(),
    'title_status': (listing['title_status'] ?? 'clean').toString().toLowerCase(),
    'damaged_parts': (listing['damaged_parts'] ?? '').toString(),
    'cylinder_count':
        (listing['cylinder_count'] ?? listing['cylinders'] ?? '').toString(),
    'engine_size': (listing['engine_size'] ?? '').toString(),
    'fuel_economy': (listing['fuel_economy'] ?? '').toString(),
    'location': location,
    'city': city.isNotEmpty ? city : location,
    'plate_type': (listing['plate_type'] ?? listing['plateType'] ?? '')
        .toString(),
    'plate_city': (listing['plate_city'] ?? listing['plateCity'] ?? '')
        .toString(),
    'description': (listing['description'] ?? '').toString(),
    'contact_phone': (listing['contact_phone'] ?? sellerPhone)
            .toString()
            .trim()
            .isNotEmpty
        ? (listing['contact_phone'] ?? sellerPhone).toString()
        : (contactPhoneFallback ?? ''),
    'currency': (listing['currency'] ?? 'USD').toString(),
    'images': normalImages,
    'videos': videoPaths,
    if (damageImages.isNotEmpty) 'damage_images': damageImages,
  };

  return {
    'draftId': listingId.isNotEmpty ? 'edit_$listingId' : 'edit_listing',
    'currentStep': 0,
    'carData': carData,
    'isEditMode': true,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };
}

String _capitalizeFirst(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}
