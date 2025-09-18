import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/analytics_model.dart';
import 'api_service.dart';

class AnalyticsService {
  static String get _baseUrl {
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:5000/api';
      }
    } catch (_) {}
    return 'http://localhost:5000/api';
  }

  /// Get analytics for all user's listings
  static Future<List<ListingAnalytics>> getUserListingsAnalytics() async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) {
        throw Exception('User not authenticated');
      }

      // First try to get analytics from the analytics endpoint
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/analytics/listings'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          return data.map((json) => ListingAnalytics.fromJson(json)).toList();
        }
      } catch (e) {
        print('Analytics endpoint failed, falling back to my_listings: $e');
      }

      // Fallback: Get user's listings and create analytics data
      final response = await http.get(
        Uri.parse('$_baseUrl/my_listings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> listings = json.decode(response.body);
        
        // Convert listings to analytics format
        return listings.map((listing) {
          return ListingAnalytics(
            listingId: listing['id'].toString(),
            title: listing['title'] ?? '',
            brand: listing['brand'] ?? '',
            model: listing['model'] ?? '',
            year: listing['year'] ?? 0,
            price: (listing['price'] ?? 0).toDouble(),
            imageUrl: listing['image_url'],
            views: 0, // Will be populated when analytics are tracked
            messages: 0,
            calls: 0,
            shares: 0,
            favorites: 0,
            createdAt: DateTime.now().subtract(Duration(days: 30)), // Default to 30 days ago
            lastUpdated: DateTime.now(),
          );
        }).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed');
      } else {
        throw Exception('Failed to fetch listings: ${response.statusCode}');
      }
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

      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/listings/$listingId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ListingAnalytics.fromJson(data);
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed');
      } else if (response.statusCode == 404) {
        throw Exception('Listing not found');
      } else {
        throw Exception('Failed to fetch listing analytics: ${response.statusCode}');
      }
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
  static Future<void> trackView(String listingId) async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await http.post(
        Uri.parse('$_baseUrl/analytics/track/view'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'listing_id': listingId}),
      );
    } catch (e) {
      // Silently fail for tracking - don't interrupt user experience
      print('Failed to track view: $e');
    }
  }

  /// Track a message for a listing
  static Future<void> trackMessage(String listingId) async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await http.post(
        Uri.parse('$_baseUrl/analytics/track/message'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'listing_id': listingId}),
      );
    } catch (e) {
      print('Failed to track message: $e');
    }
  }

  /// Track a call for a listing
  static Future<void> trackCall(String listingId) async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await http.post(
        Uri.parse('$_baseUrl/analytics/track/call'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'listing_id': listingId}),
      );
    } catch (e) {
      print('Failed to track call: $e');
    }
  }

  /// Track a share for a listing
  static Future<void> trackShare(String listingId) async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await http.post(
        Uri.parse('$_baseUrl/analytics/track/share'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'listing_id': listingId}),
      );
    } catch (e) {
      print('Failed to track share: $e');
    }
  }

  /// Track a favorite for a listing
  static Future<void> trackFavorite(String listingId) async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await http.post(
        Uri.parse('$_baseUrl/analytics/track/favorite'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'listing_id': listingId}),
      );
    } catch (e) {
      print('Failed to track favorite: $e');
    }
  }

  /// Get mock analytics data for development/testing
  static Future<List<ListingAnalytics>> getMockAnalytics() async {
    // This is for development when backend analytics endpoints are not ready
    await Future.delayed(Duration(seconds: 1)); // Simulate network delay
    
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
        createdAt: DateTime.now().subtract(Duration(days: 30)),
        lastUpdated: DateTime.now().subtract(Duration(hours: 2)),
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
        createdAt: DateTime.now().subtract(Duration(days: 45)),
        lastUpdated: DateTime.now().subtract(Duration(days: 1)),
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
        createdAt: DateTime.now().subtract(Duration(days: 15)),
        lastUpdated: DateTime.now().subtract(Duration(hours: 6)),
      ),
    ];
  }
}