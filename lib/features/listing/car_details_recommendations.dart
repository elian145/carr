import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import 'car_details_listing_fields.dart';
import 'listing_mappers.dart';

/// Cached + network similar/related listings for a detail page.
class CarDetailsRecommendations {
  const CarDetailsRecommendations({
    required this.similar,
    required this.related,
  });

  final List<Map<String, dynamic>> similar;
  final List<Map<String, dynamic>> related;
}

Future<CarDetailsRecommendations> loadCarDetailsRecommendations({
  required Map<String, dynamic> car,
  required String cacheCarId,
  SharedPreferences? prefs,
}) async {
  final sp = prefs ?? await SharedPreferences.getInstance();
  final simKey = 'cache_similar_$cacheCarId';
  final relKey = 'cache_related_$cacheCarId';

  var similar = <Map<String, dynamic>>[];
  var related = <Map<String, dynamic>>[];

  try {
    final simCached = sp.getString(simKey);
    if (simCached != null && simCached.isNotEmpty) {
      final simData = json.decode(simCached);
      if (simData is List) {
        similar = simData.cast<Map<String, dynamic>>();
      }
    }
    final relCached = sp.getString(relKey);
    if (relCached != null && relCached.isNotEmpty) {
      final relData = json.decode(relCached);
      if (relData is List) {
        related = relData.cast<Map<String, dynamic>>();
      }
    }
  } catch (_) {
    // Ignore corrupt cache; network fetch below still runs.
  }

  final brand = (car['brand'] ?? '').toString().trim();
  final model = (car['model'] ?? '').toString().trim();
  if (brand.isEmpty) {
    return CarDetailsRecommendations(similar: similar, related: related);
  }

  final excludeIds = listingIdentityIds(car, cacheCarId);

  if (model.isNotEmpty) {
    final simData = await ApiService.getCars(
      page: 1,
      perPage: 20,
      brand: brand,
      model: model,
    );
    similar = listingMapsFromApiResponse(simData)
        .where((e) {
          final id = (e['public_id'] ?? e['id'] ?? '').toString();
          return id.isEmpty || !excludeIds.contains(id);
        })
        .take(12)
        .toList();
    await sp.setString(simKey, json.encode(similar));
  } else {
    similar = [];
  }

  final bands = relatedListingQueryBands(car);
  final relData = await ApiService.getCars(
    page: 1,
    perPage: 20,
    brand: brand,
    yearMin: bands.yearMin,
    yearMax: bands.yearMax,
    priceMin: bands.priceMin,
    priceMax: bands.priceMax,
    location: optionalListingFilterField(car, 'city') ??
        optionalListingFilterField(car, 'location'),
    condition: optionalListingFilterField(car, 'condition'),
    bodyType: optionalListingFilterField(car, 'body_type'),
    transmission: optionalListingFilterField(car, 'transmission'),
    driveType: optionalListingFilterField(car, 'drive_type'),
    engineType: optionalListingFilterField(car, 'engine_type'),
  );
  related = listingMapsFromApiResponse(relData)
      .where((e) {
        final id = (e['public_id'] ?? e['id'] ?? '').toString();
        return id.isEmpty || !excludeIds.contains(id);
      })
      .take(12)
      .toList();
  await sp.setString(relKey, json.encode(related));

  return CarDetailsRecommendations(similar: similar, related: related);
}
