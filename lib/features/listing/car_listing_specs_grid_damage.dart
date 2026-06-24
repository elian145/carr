part of 'car_listing_specs_grid.dart';

List<String> listingDamageImageFullUrls(Map<String, dynamic> car) {
  final List<String> urls = [];
  final List<dynamic> imgs =
      (car['images'] is List) ? (car['images'] as List) : const [];
  for (final dynamic it in imgs) {
    if (it is! Map) continue;
    if ((it['kind'] ?? '').toString().toLowerCase() != 'damage') continue;
    final s =
        (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '').toString();
    if (s.isNotEmpty) {
      final full = buildLegacyFullImageUrl(s);
      if (!urls.contains(full)) urls.add(full);
    }
  }
  return urls;
}

/// Damage photos for preview / review: API `images` with `kind: damage`, else
/// sell-flow `damage_images` (XFile or path strings) before submit.
List<dynamic> listingDamagePreviewEntries(Map<String, dynamic> car) {
  final List<dynamic> out = [];
  for (final url in listingDamageImageFullUrls(car)) {
    if (url.trim().isNotEmpty) out.add(url);
  }
  if (out.isNotEmpty) return out;
  final raw = car['damage_images'];
  if (raw is! List) return out;
  for (final e in raw) {
    if (e is XFile) {
      if (e.path.trim().isNotEmpty) out.add(e);
    } else {
      final s = e?.toString().trim() ?? '';
      if (s.isNotEmpty) out.add(e);
    }
  }
  return out;
}

/// Specification grid matching [CarDetailsPage] (shared with sell-flow review).
