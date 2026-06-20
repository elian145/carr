part of '../api_service.dart';

/// Push, moderation, reports, blocks (split from [ApiService]).
abstract final class _ApiServiceAdmin {
  _ApiServiceAdmin._();

    /// Register FCM push notification token with the backend.
    /// Pass [enabled: false] to clear the stored token (user disabled push).
    static Future<void> registerPushToken(
      String token, {
      bool enabled = true,
    }) async {
      await ApiService._makeAuthenticatedRequest(
        'POST',
        '/users/push_token',
        body: {
          if (!enabled) 'enabled': false else 'token': token.trim(),
        },
      );
    }

    /// Whether this account has an FCM token stored and the server can send push.
    static Future<Map<String, dynamic>> getPushStatus() async {
      return ApiService._makeAuthenticatedRequest('GET', '/users/push_status');
    }

    /// Ask the server to send a test notification to this device.
    static Future<Map<String, dynamic>> sendTestPush() async {
      return ApiService._makeAuthenticatedRequest('POST', '/users/push_test');
    }

    /// Block a user.
    static Future<void> blockUser(String userId) async {
      await ApiService._makeAuthenticatedRequest('POST', '/users/$userId/block');
    }

    /// Unblock a user.
    static Future<void> unblockUser(String userId) async {
      await ApiService._makeAuthenticatedRequest('POST', '/users/$userId/unblock');
    }

    /// Report a user.
    static Future<void> reportUser(
      String userId, {
      required String reason,
      String? details,
    }) async {
      final id = Uri.encodeComponent(userId.trim());
      await ApiService._makeAuthenticatedRequest(
        'POST',
        '/users/$id/report',
        body: {
          'reason': reason,
          if (details != null && details.trim().isNotEmpty)
            'details': details.trim(),
        },
      );
    }

    /// Report a listing.
    static Future<void> reportListing(
      String listingId, {
      required String reason,
      String? details,
    }) async {
      final id = Uri.encodeComponent(listingId.trim());
      await ApiService._makeAuthenticatedRequest(
        'POST',
        '/cars/$id/report',
        body: {
          'reason': reason,
          if (details != null && details.trim().isNotEmpty)
            'details': details.trim(),
        },
      );
    }

    /// Admin: list user and listing reports.
    static Future<Map<String, dynamic>> adminListReports({
      String status = 'pending',
      String type = 'all',
      int page = 1,
      int perPage = 20,
    }) async {
      final q = Uri(queryParameters: {
        'status': status,
        'type': type,
        'page': '$page',
        'per_page': '$perPage',
      });
      return await ApiService._makeAuthenticatedRequest(
        'GET',
        '/admin/reports${q.query.isEmpty ? '' : '?${q.query}'}',
      );
    }

    /// Admin: update a user report status.
    static Future<Map<String, dynamic>> adminUpdateUserReport(
      int reportId, {
      required String status,
      String? adminNotes,
    }) async {
      return await ApiService._makeAuthenticatedRequest(
        'PATCH',
        '/admin/reports/user/$reportId',
        body: {
          'status': status,
          if (adminNotes != null && adminNotes.trim().isNotEmpty)
            'admin_notes': adminNotes.trim(),
        },
      );
    }

    /// Admin: update a listing report status.
    static Future<Map<String, dynamic>> adminUpdateListingReport(
      int reportId, {
      required String status,
      String? adminNotes,
    }) async {
      return await ApiService._makeAuthenticatedRequest(
        'PATCH',
        '/admin/reports/listing/$reportId',
        body: {
          'status': status,
          if (adminNotes != null && adminNotes.trim().isNotEmpty)
            'admin_notes': adminNotes.trim(),
        },
      );
    }

    /// Get list of blocked user IDs.
    static Future<List<String>> getBlockedUsers() async {
      final result = await ApiService._makeAuthenticatedRequest('GET', '/users/blocked');
      final raw = result['blocked_users'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return [];
    }
}
