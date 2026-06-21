import 'dart:developer' as developer;

import '../models/analytics_model.dart';
import 'api_service.dart';
import 'config.dart';
import 'recently_viewed_service.dart';

class AnalyticsService {
  static String get _imageBaseUrl => apiBase();

  static List<ListingAnalytics> _parseListingAnalyticsRows(
    List<Map<String, dynamic>> rows,
  ) {
    final out = <ListingAnalytics>[];
    for (final map in rows) {
      final copy = Map<String, dynamic>.from(map);
      final imageUrl = copy['image_url']?.toString();
      if (imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
        copy['image_url'] = '$_imageBaseUrl/static/uploads/$imageUrl';
      }
      out.add(ListingAnalytics.fromJson(copy));
    }
    return out;
  }

  static List<ListingAnalytics> _listingsCompatToAnalytics(
    List<Map<String, dynamic>> listings,
  ) {
    int? parseMileage(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.toInt();
      final s = v.toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (s.isEmpty) return null;
      return int.tryParse(s);
    }

    return listings.map((listing) {
      String? fullImageUrl;
      final imageUrl = listing['image_url']?.toString();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        fullImageUrl = imageUrl.startsWith('http')
            ? imageUrl
            : '$_imageBaseUrl/static/uploads/$imageUrl';
      }

      return ListingAnalytics(
        listingId: listing['id'].toString(),
        title: listing['title'] ?? '',
        brand: listing['brand'] ?? '',
        model: listing['model'] ?? '',
        year: listing['year'] ?? 0,
        price: (listing['price'] ?? 0).toDouble(),
        imageUrl: fullImageUrl,
        mileage: parseMileage(
          listing['mileage'] ?? listing['odometer'] ?? listing['miles'],
        ),
        city: listing['city']?.toString() ?? listing['location']?.toString(),
        views: 0,
        messages: 0,
        calls: 0,
        shares: 0,
        favorites: 0,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        lastUpdated: DateTime.now(),
      );
    }).toList();
  }

  /// Get analytics for all user's listings
  static Future<List<ListingAnalytics>> getUserListingsAnalytics() async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) {
        throw Exception('User not authenticated');
      }

      try {
        final rows =
            await ApiService.getAuthenticatedJsonList('/analytics/listings');
        return _parseListingAnalyticsRows(rows);
      } catch (e) {
        developer.log(
          'Analytics endpoint failed, falling back to my_listings: $e',
          name: 'AnalyticsService',
        );
      }

      final listings = await ApiService.getMyListingsCompat();
      return _listingsCompatToAnalytics(listings);
    } catch (e) {
      throw Exception('Error fetching analytics: $e');
    }
  }

  /// Get analytics for a specific listing
  static Future<ListingAnalytics> getListingAnalytics(String listingId) async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) {
        throw Exception('User not authenticated');
      }

      final data = await ApiService.makeAuthenticatedRequest(
        'GET',
        '/analytics/listings/$listingId',
      );
      return ListingAnalytics.fromJson(data);
    } catch (e) {
      throw Exception('Error fetching listing analytics: $e');
    }
  }

  /// Get analytics summary for all listings
  static Future<AnalyticsSummary> getAnalyticsSummary() async {
    try {
      final listings = await getUserListingsAnalytics();
      return AnalyticsSummary.fromListings(listings);
    } catch (e) {
      throw Exception('Error fetching analytics summary: $e');
    }
  }

  /// Track a view for a listing
  static Future<void> trackView(
    String listingId, {
    Map<String, dynamic>? listingSnapshot,
  }) async {
    final id = listingId.trim();
    if (id.isEmpty) return;

    try {
      await RecentlyViewedService.recordView(
        id,
        snapshot: listingSnapshot,
      );
    } catch (e) {
      developer.log(
        'Failed to record recently viewed: $e',
        name: 'AnalyticsService',
      );
    }

    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await ApiService.makeAuthenticatedRequest(
        'POST',
        '/analytics/track/view',
        body: {'listing_id': id},
      );
    } catch (e) {
      developer.log('Failed to track view: $e', name: 'AnalyticsService');
    }
  }

  /// Track a message for a listing
  static Future<void> trackMessage(String listingId) async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await ApiService.makeAuthenticatedRequest(
        'POST',
        '/analytics/track/message',
        body: {'listing_id': listingId},
      );
    } catch (e) {
      developer.log('Failed to track message: $e', name: 'AnalyticsService');
    }
  }

  /// Track a call for a listing
  static Future<void> trackCall(String listingId) async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await ApiService.makeAuthenticatedRequest(
        'POST',
        '/analytics/track/call',
        body: {'listing_id': listingId},
      );
    } catch (e) {
      developer.log('Failed to track call: $e', name: 'AnalyticsService');
    }
  }

  /// Track a share for a listing
  static Future<void> trackShare(String listingId) async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await ApiService.makeAuthenticatedRequest(
        'POST',
        '/analytics/track/share',
        body: {'listing_id': listingId},
      );
    } catch (e) {
      developer.log('Failed to track share: $e', name: 'AnalyticsService');
    }
  }

  /// Track a favorite for a listing
  static Future<void> trackFavorite(String listingId) async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await ApiService.makeAuthenticatedRequest(
        'POST',
        '/analytics/track/favorite',
        body: {'listing_id': listingId},
      );
    } catch (e) {
      developer.log('Failed to track favorite: $e', name: 'AnalyticsService');
    }
  }

  /// Get mock analytics data for development/testing
  static Future<List<ListingAnalytics>> getMockAnalytics() async {
    await Future.delayed(const Duration(seconds: 1));

    return [
      ListingAnalytics(
        listingId: '1',
        title: '2020 Toyota Camry LE',
        brand: 'Toyota',
        model: 'Camry',
        year: 2020,
        price: 25000,
        imageUrl: null,
        views: 156,
        messages: 12,
        calls: 8,
        shares: 5,
        favorites: 23,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        lastUpdated: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      ListingAnalytics(
        listingId: '2',
        title: '2019 Honda Civic Sport',
        brand: 'Honda',
        model: 'Civic',
        year: 2019,
        price: 22000,
        imageUrl: null,
        views: 89,
        messages: 6,
        calls: 4,
        shares: 2,
        favorites: 15,
        createdAt: DateTime.now().subtract(const Duration(days: 45)),
        lastUpdated: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ListingAnalytics(
        listingId: '3',
        title: '2021 Ford Mustang GT',
        brand: 'Ford',
        model: 'Mustang',
        year: 2021,
        price: 45000,
        imageUrl: null,
        views: 234,
        messages: 18,
        calls: 12,
        shares: 8,
        favorites: 45,
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
        lastUpdated: DateTime.now().subtract(const Duration(hours: 6)),
      ),
    ];
  }
}
