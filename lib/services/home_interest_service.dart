import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'recently_viewed_service.dart';
import '../shared/debug/app_log.dart';

/// Soft preferences inferred from what the user browses in the app.
class HomeInterestProfile {
  const HomeInterestProfile({
    this.brands = const [],
    this.bodyTypes = const [],
    this.minPrice,
    this.maxPrice,
    this.viewCount = 0,
  });

  final List<String> brands;
  final List<String> bodyTypes;
  final double? minPrice;
  final double? maxPrice;
  final int viewCount;

  /// Enough signal to personalize the home feed.
  bool get hasInterest =>
      viewCount > 0 && (brands.isNotEmpty || bodyTypes.isNotEmpty);

  /// Default home feed sort when the user has not picked an explicit sort.
  String get defaultSortBy => hasInterest ? 'recommended' : 'random';

  Map<String, String> toPreferQueryParams() {
    if (!hasInterest) return const {};
    final out = <String, String>{};
    if (brands.isNotEmpty) {
      out['prefer_brand'] = brands.take(5).join(',');
    }
    if (bodyTypes.isNotEmpty) {
      out['prefer_body_type'] = bodyTypes.take(5).join(',');
    }
    if (minPrice != null) {
      out['prefer_min_price'] = minPrice!.round().toString();
    }
    if (maxPrice != null) {
      out['prefer_max_price'] = maxPrice!.round().toString();
    }
    return out;
  }
}

/// Builds [HomeInterestProfile] from local recently-viewed history.
class HomeInterestService {
  static Future<HomeInterestProfile> loadProfile() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(RecentlyViewedService.localKey);
      if (raw == null || raw.isEmpty) {
        return const HomeInterestProfile();
      }

      final decoded = json.decode(raw);
      if (decoded is! List) return const HomeInterestProfile();

      final brandCounts = <String, int>{};
      final bodyCounts = <String, int>{};
      final prices = <double>[];
      var viewCount = 0;

      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item.cast<String, dynamic>());
        final snap = map['snapshot'];
        final source = snap is Map
            ? Map<String, dynamic>.from(snap.cast<String, dynamic>())
            : map;

        final brand = (source['brand'] ?? '').toString().trim();
        final body = (source['body_type'] ?? source['bodyType'] ?? '')
            .toString()
            .trim();
        final price = double.tryParse(source['price']?.toString() ?? '');

        final hasSignal = brand.isNotEmpty || body.isNotEmpty;
        if (!hasSignal && price == null) continue;
        viewCount++;

        if (brand.isNotEmpty) {
          brandCounts[brand] = (brandCounts[brand] ?? 0) + 1;
        }
        if (body.isNotEmpty) {
          final key = body.toLowerCase();
          bodyCounts[key] = (bodyCounts[key] ?? 0) + 1;
        }
        if (price != null && price > 0) {
          prices.add(price);
        }
      }

      final brands = _topKeys(brandCounts, 5);
      final bodies = _topKeys(bodyCounts, 5);
      double? minPrice;
      double? maxPrice;
      if (prices.isNotEmpty) {
        prices.sort();
        final mid = prices[prices.length ~/ 2];
        minPrice = (mid * 0.55).clamp(0, double.infinity);
        maxPrice = mid * 1.55;
      }

      return HomeInterestProfile(
        brands: brands,
        bodyTypes: bodies,
        minPrice: minPrice,
        maxPrice: maxPrice,
        viewCount: viewCount,
      );
    } catch (e, st) {
      logNonFatal(e, st);
      return const HomeInterestProfile();
    }
  }

  static List<String> _topKeys(Map<String, int> counts, int limit) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }

  /// Stable score for client-side boost when the API cannot personalize.
  static int scoreListing(
    Map<String, dynamic> car,
    HomeInterestProfile profile,
  ) {
    if (!profile.hasInterest) return 0;
    var score = 0;
    final brand = (car['brand'] ?? '').toString().trim().toLowerCase();
    final body =
        (car['body_type'] ?? car['bodyType'] ?? '').toString().trim().toLowerCase();
    final price = double.tryParse(car['price']?.toString() ?? '');

    for (final b in profile.brands) {
      if (brand.isNotEmpty && brand.contains(b.toLowerCase())) {
        score += 4;
        break;
      }
    }
    for (final bt in profile.bodyTypes) {
      if (body.isNotEmpty && body == bt.toLowerCase()) {
        score += 3;
        break;
      }
    }
    if (price != null &&
        profile.minPrice != null &&
        profile.maxPrice != null &&
        price >= profile.minPrice! &&
        price <= profile.maxPrice!) {
      score += 2;
    }
    final featured = car['is_featured'] == true ||
        car['isFeatured'] == true ||
        car['is_featured']?.toString() == 'true';
    if (featured) score += 5;
    return score;
  }

  static List<Map<String, dynamic>> boostByInterest(
    List<Map<String, dynamic>> input,
    HomeInterestProfile profile,
  ) {
    if (!profile.hasInterest || input.length < 2) return input;
    final scored = List<Map<String, dynamic>>.from(input);
    scored.sort((a, b) {
      final cmp = scoreListing(b, profile).compareTo(scoreListing(a, profile));
      if (cmp != 0) return cmp;
      final dateA =
          DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
      final dateB =
          DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
      return dateB.compareTo(dateA);
    });
    return scored;
  }
}
