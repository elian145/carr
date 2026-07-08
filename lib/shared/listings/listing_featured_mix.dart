import 'dart:math';

import 'listing_identity.dart';

bool _isFeaturedFlag(Map car) {
  final value = car['is_featured'];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

bool _sameListing(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aId = listingPrimaryId(a);
  if (aId.isNotEmpty && listingMatchesId(b, aId)) return true;
  final aAlt = listingAltId(a);
  return aAlt.isNotEmpty && listingMatchesId(b, aAlt);
}

/// Spreads featured listings randomly through [feed].
///
/// Featured cars clustered at the top of the API response are pulled out and
/// re-inserted at random positions among normal listings.
List<Map<String, dynamic>> mixFeaturedIntoListingFeed({
  required List<Map<String, dynamic>> feed,
  required List<Map<String, dynamic>> featured,
  int? seed,
}) {
  if (feed.isEmpty && featured.isEmpty) return const [];

  final featuredIds = <String>{};
  void rememberIds(Map<String, dynamic> car) {
    final id = listingPrimaryId(car);
    final alt = listingAltId(car);
    if (id.isNotEmpty) featuredIds.add(id);
    if (alt.isNotEmpty) featuredIds.add(alt);
  }

  for (final car in featured) {
    rememberIds(car);
  }

  final normals = <Map<String, dynamic>>[];
  final featuredFromFeed = <Map<String, dynamic>>[];

  for (final raw in feed) {
    final car = Map<String, dynamic>.from(raw);
    final id = listingPrimaryId(car);
    final alt = listingAltId(car);
    final isFeatured = _isFeaturedFlag(car) ||
        (id.isNotEmpty && featuredIds.contains(id)) ||
        (alt.isNotEmpty && featuredIds.contains(alt));
    if (isFeatured) {
      car['is_featured'] = true;
      featuredFromFeed.add(car);
      rememberIds(car);
    } else {
      normals.add(car);
    }
  }

  final extraFeatured = <Map<String, dynamic>>[];
  for (final raw in featured) {
    final car = Map<String, dynamic>.from(raw);
    car['is_featured'] = true;
    final already = featuredFromFeed.any((f) => _sameListing(f, car)) ||
        normals.any((n) => _sameListing(n, car));
    if (!already) extraFeatured.add(car);
  }

  final allFeatured = <Map<String, dynamic>>[
    ...featuredFromFeed,
    ...extraFeatured,
  ];

  if (allFeatured.isEmpty) return normals;

  final rng = Random(seed ?? _stableSeed(feed, featured));
  allFeatured.shuffle(rng);

  if (normals.isEmpty) return allFeatured;

  // Pick distinct insert indices in [0, normals.length] (after that many normals).
  final slotCount = allFeatured.length;
  final candidates = List<int>.generate(normals.length + 1, (i) => i);
  candidates.shuffle(rng);
  final slots = candidates.take(slotCount).toList()..sort();

  final result = <Map<String, dynamic>>[];
  var featuredIdx = 0;
  for (var i = 0; i <= normals.length; i++) {
    while (featuredIdx < slots.length && slots[featuredIdx] == i) {
      result.add(allFeatured[featuredIdx]);
      featuredIdx++;
    }
    if (i < normals.length) {
      result.add(normals[i]);
    }
  }
  // Safety: any leftover featured (shouldn't happen) go at the end.
  while (featuredIdx < allFeatured.length) {
    result.add(allFeatured[featuredIdx]);
    featuredIdx++;
  }
  return result;
}

int _stableSeed(
  List<Map<String, dynamic>> feed,
  List<Map<String, dynamic>> featured,
) {
  var hash = Object.hash(feed.length, featured.length);
  for (final car in featured.take(8)) {
    hash = Object.hash(hash, listingPrimaryId(car));
  }
  if (feed.isNotEmpty) {
    hash = Object.hash(hash, listingPrimaryId(feed.first));
    hash = Object.hash(hash, listingPrimaryId(feed.last));
  }
  return hash;
}
