import 'listing_identity.dart';
import 'listing_image_media.dart';

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
  final normalImages = <dynamic>[];
  final damageImages = <dynamic>[];
  if (listingImages is List) {
    for (final it in listingImages) {
      if (it is! Map) continue;
      final kind = (it['kind'] ?? '').toString().toLowerCase();
      final url = ListingImageMedia.source(it);
      if (url.isEmpty) continue;
      final media = ListingImageMedia.map(it, source: url);
      if (kind == 'damage') {
        damageImages.add(media);
      } else {
        normalImages.add(media);
      }
    }
  }
  final primary = (listing['image_url'] ?? '').toString().trim();
  var primaryIndex = 0;
  if (primary.isNotEmpty) {
    final match = normalImages.indexWhere((item) {
      final source = ListingImageMedia.source(item);
      return source == primary ||
          source.endsWith(primary) ||
          primary.endsWith(source);
    });
    if (match >= 0) {
      primaryIndex = match;
    } else {
      normalImages.insert(0, ListingImageMedia.map(primary));
      primaryIndex = 0;
    }
  } else {
    for (var i = 0; i < normalImages.length; i++) {
      final item = normalImages[i];
      if (item is Map &&
          (item['is_primary'] == true || item['isPrimary'] == true)) {
        primaryIndex = i;
        break;
      }
    }
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
    'transmission': _capitalizeFirst(
      (listing['transmission'] ?? 'automatic').toString(),
    ),
    'fuel_type': _capitalizeFirst(
      (listing['fuel_type'] ?? listing['engine_type'] ?? 'gasoline').toString(),
    ),
    'engine_type': _capitalizeFirst(
      (listing['engine_type'] ?? listing['fuel_type'] ?? 'gasoline').toString(),
    ),
    'body_type': _capitalizeFirst((listing['body_type'] ?? 'sedan').toString()),
    'drive_type': _capitalizeFirst((listing['drive_type'] ?? 'fwd').toString()),
    'color': (listing['color'] ?? '').toString(),
    'seating': (listing['seating'] ?? '5').toString(),
    'region_specs': (listing['region_specs'] ?? '').toString(),
    'title_status': (listing['title_status'] ?? 'clean')
        .toString()
        .toLowerCase(),
    'damaged_parts': (listing['damaged_parts'] ?? '').toString(),
    'cylinder_count': (listing['cylinder_count'] ?? listing['cylinders'] ?? '')
        .toString(),
    'engine_size': (listing['engine_size'] ?? '').toString(),
    'fuel_economy': (listing['fuel_economy'] ?? '').toString(),
    'location': location,
    'city': city.isNotEmpty ? city : location,
    'plate_type': (listing['plate_type'] ?? listing['plateType'] ?? '')
        .toString(),
    'plate_city': (listing['plate_city'] ?? listing['plateCity'] ?? '')
        .toString(),
    'description': (listing['description'] ?? '').toString(),
    'contact_phone':
        (listing['contact_phone'] ?? sellerPhone).toString().trim().isNotEmpty
        ? (listing['contact_phone'] ?? sellerPhone).toString()
        : (contactPhoneFallback ?? ''),
    'currency': (listing['currency'] ?? 'USD').toString(),
    'images': normalImages,
    'primary_image_index': primaryIndex,
    'videos': videoPaths,
    if ((listing['contact_phones'] is List
            ? (listing['contact_phones'] as List)
            : const [])
        .isNotEmpty)
      'contact_phones': (listing['contact_phones'] as List)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .take(3)
          .toList(),
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
