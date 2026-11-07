import '../shared/debug/app_log.dart';

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


  /// Get analytics for all user's listings
  static Future<List<ListingAnalytics>> getUserListingsAnalytics() async {
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) {
        throw Exception('User not authenticated');
      }

      // F-42: no invented fallback (zero counts / fake "created 30 days
      // ago"). A failed fetch must surface as an error so the UI can show
      // an error state with retry instead of fake numbers.
      final rows =
          await ApiService.getAuthenticatedJsonList('/analytics/listings');
      return _parseListingAnalyticsRows(rows);
    } catch (e, st) {
      logNonFatal(e, st, 'AnalyticsService.getUserListingsAnalytics');
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
    } catch (e, st) {
      logNonFatal(e, st, 'AnalyticsService.recentlyViewed');
    }

    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;

      await ApiService.makeAuthenticatedRequest(
        'POST',
        '/analytics/track/view',
        body: {'listing_id': id},
      );
    } catch (e, st) {
      logNonFatal(e, st, 'AnalyticsService.trackView');
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
    } catch (e, st) {
      logNonFatal(e, st, 'AnalyticsService.trackMessage');
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
    } catch (e, st) {
      logNonFatal(e, st, 'AnalyticsService.trackCall');
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
    } catch (e, st) {
      logNonFatal(e, st, 'AnalyticsService.trackShare');
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
    } catch (e, st) {
      logNonFatal(e, st, 'AnalyticsService.trackFavorite');
    }
  }

  /// Product funnel events (sign-up, listing created, search).
  static Future<void> trackProductEvent(
    String event, {
    Map<String, dynamic>? metadata,
  }) async {
    final name = event.trim().toLowerCase();
    if (name.isEmpty) return;
    try {
      await ApiService.makeAuthenticatedRequest(
        'POST',
        '/analytics/events',
        body: {
          'event': name,
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        },
      );
    } catch (e, st) {
      // Guests may not have a token; still try once without failing the UX.
      logNonFatal(e, st, 'AnalyticsService.trackProductEvent');
    }
  }
}
