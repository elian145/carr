import 'dart:convert';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory API stub for widget/smoke tests (no loopback [HttpServer]).
///
/// Binds [ApiService.testHttpClient] to a [MockClient] so Flutter's test
/// binding does not intercept loopback HTTP with status 400.
class FakeApiServer {
  FakeApiServer._();

  static MockClient? _client;

  /// Starts the stub once per isolate (safe for parallel `flutter test`).
  static Future<void> ensureStarted() async {
    if (_client != null) return;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    _client = MockClient(_handle);
    ApiService.testHttpClient = _client;
  }

  static Future<void> stop() async {
    ApiService.testHttpClient = null;
    _client = null;
    setRuntimeApiBaseOverride(null);
  }

  static Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    final body = _bodyForPath(path);
    if (body == null) {
      return http.Response('Not found', 404);
    }
    return http.Response(
      json.encode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  static Object? _bodyForPath(String path) {
    if (path == '/health') {
      return {'status': 'ok'};
    }

    if (!path.startsWith('/api/')) {
      return null;
    }

    if (path.startsWith('/api/cars/') && path.length > '/api/cars/'.length) {
      final segments = path.substring('/api/cars/'.length).split('/');
      final id = segments.first;
      if (segments.length > 1 && segments[1] == 'favorite') {
        return {'is_favorited': false};
      }
      return {
        'car': {
          'id': id,
          'title': 'Test car',
          'brand': 'toyota',
          'model': 'camry',
          'year': 2020,
          'price': 10000,
          'currency': 'USD',
          'location': 'Erbil',
          'image_url': '',
          'images': <dynamic>[],
          'videos': <dynamic>[],
          'seller': {'id': 'seller_1', 'username': 'seller'},
        },
      };
    }

    if (path.startsWith('/api/dealers/') && path.length > '/api/dealers/'.length) {
      final id = path.substring('/api/dealers/'.length).split('/').first;
      return {
        'dealer': {
          'public_id': id,
          'dealership_name': 'Test Dealer',
          'dealership_location': 'Erbil',
        },
        'listings': <dynamic>[],
        'stats': {'total_listings': 0, 'featured_listings': 0},
      };
    }

    if (path.startsWith('/api/admin/dealers/')) {
      return {'message': 'ok'};
    }

    if (path.startsWith('/api/admin/reports')) {
      return {'reports': <dynamic>[]};
    }

    if (path.startsWith('/api/chat/')) {
      if (path.endsWith('/messages')) {
        return <dynamic>[];
      }
      if (path.contains('/send')) {
        return {'id': 1, 'content': 'stub'};
      }
      return <String, dynamic>{};
    }

    if (path.startsWith('/api/analytics/')) {
      return <String, dynamic>{};
    }

    switch (path) {
      case '/api/analytics/listings':
        return <dynamic>[];
      case '/api/my_listings':
      case '/api/user/my-listings':
        return {
          'cars': <dynamic>[],
          'pagination': {'has_next': false},
        };
      case '/api/cars':
        return {
          'cars': <dynamic>[],
          'pagination': {'has_next': false, 'page': 1, 'per_page': 20},
        };
      case '/api/chats':
        return <dynamic>[];
      case '/api/chat/unread_count':
        return {'unread_count': 0};
      case '/api/auth/login':
      case '/api/auth/signup':
        return {
          'access_token': 'test_access_token',
          'refresh_token': 'test_refresh_token',
          'user': {'id': 1, 'username': 'test', 'is_admin': false},
        };
      case '/api/auth/me':
      case '/api/user/profile':
        return {
          'user': {
            'id': 1,
            'username': 'test',
            'is_admin': false,
            'account_type': 'individual',
          },
        };
      case '/api/user/favorites':
      case '/api/user/recently-viewed':
        return {
          'cars': <dynamic>[],
          'pagination': {'has_next': false},
        };
      case '/api/user/dealer-profile':
        return {
          'dealer': {
            'dealership_name': 'Test Dealer',
            'dealership_location': 'Erbil',
          },
        };
      case '/api/saved-searches':
        return {'saved_searches': <dynamic>[]};
      case '/api/auth/send_otp':
        return {'sent': false, 'message': 'stub'};
      case '/api/auth/delete-account':
        return {'message': 'Account deleted successfully'};
      case '/api/auth/refresh':
        return {
          'access_token': 'test_access_token',
          'refresh_token': 'test_refresh_token',
        };
      case '/api/config/trust':
        return {
          'support_email': 'support@test.example',
          'privacy_url': 'https://example.com/privacy',
          'terms_url': 'https://example.com/terms',
        };
      case '/api/push/preferences':
        return {'push_enabled': true};
      case '/api/dealers':
        return {
          'dealers': <dynamic>[],
          'pagination': {'has_next': false, 'page': 1, 'per_page': 20},
        };
      case '/api/admin/dealers/pending':
        return {'dealers': <dynamic>[]};
      default:
        return <String, dynamic>{};
    }
  }
}
