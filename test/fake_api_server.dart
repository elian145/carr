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
    final response = _responseFor(request);
    return response ?? http.Response('Not found', 404);
  }

  static http.Response _json(int status, Object body) {
    return http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  static Map<String, dynamic> _sampleCar(String id) => {
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
      };

  static List<Map<String, dynamic>> _sampleChats() => [
        {
          'conversation_id': 1,
          'car_id': 'list_car_1',
          'car_title': 'Test car',
          'car_brand': 'toyota',
          'car_model': 'camry',
          'car_year': 2020,
          'other_user': {'id': 'buyer_1', 'name': 'Test Buyer'},
          'last_message': {
            'id': 'msg_stub_1',
            'content': 'Hello from stub',
            'message_type': 'text',
            'created_at': '2026-01-01T12:00:00.000Z',
            'sender_id': 'buyer_1',
          },
          'unread_count': 1,
        },
      ];

  static http.Response? _responseFor(http.Request request) {
    final method = request.method.toUpperCase();
    final path = request.url.path;

    if (path == '/health') {
      return _json(200, {'status': 'ok'});
    }

    if (!path.startsWith('/api/')) {
      return null;
    }

    if (path.startsWith('/api/cars/') && path.length > '/api/cars/'.length) {
      final segments = path.substring('/api/cars/'.length).split('/');
      final id = segments.first;
      if (segments.length > 1 && segments[1] == 'favorite') {
        if (method == 'POST') {
          return _json(200, {'is_favorited': true, 'message': 'added'});
        }
        return _json(200, {'is_favorited': false});
      }
      if (segments.length > 1 && segments[1] == 'images' && method == 'POST') {
        return _json(201, {
          'images': <dynamic>[],
          'image_url': 'https://example.com/car.jpg',
        });
      }
      if (segments.length > 1 && segments[1] == 'videos' && method == 'POST') {
        return _json(201, {'videos': <dynamic>[], 'message': 'stub'});
      }
      if (method == 'PUT' || method == 'PATCH') {
        return _json(200, {'car': _sampleCar(id), 'message': 'updated'});
      }
      if (method == 'DELETE') {
        return _json(200, {'message': 'deleted'});
      }
      if (segments.length > 1 && segments[1] == 'mark-sold' && method == 'POST') {
        return _json(200, {
          'message': 'Listing marked as sold',
          'car': {..._sampleCar(id), 'status': 'sold'},
        });
      }
      if (segments.length > 1 && segments[1] == 'mark-active' && method == 'POST') {
        return _json(200, {
          'message': 'Listing marked as available',
          'car': {..._sampleCar(id), 'status': 'active'},
        });
      }
      return _json(200, {'car': _sampleCar(id)});
    }

    if (path.startsWith('/api/dealers/') && path.length > '/api/dealers/'.length) {
      final id = path.substring('/api/dealers/'.length).split('/').first;
      return _json(200, {
        'dealer': {
          'public_id': id,
          'dealership_name': 'Test Dealer',
          'dealership_location': 'Erbil',
        },
        'listings': <dynamic>[],
        'stats': {'total_listings': 0, 'featured_listings': 0},
      });
    }

    if (path.startsWith('/api/admin/dealers/')) {
      return _json(200, {'message': 'ok'});
    }

    if (path.startsWith('/api/admin/reports')) {
      return _json(200, {'reports': <dynamic>[]});
    }

    if (path.startsWith('/api/chat/')) {
      if (path.endsWith('/messages')) {
        return _json(200, <dynamic>[]);
      }
      if (path.contains('/send') && method == 'POST') {
        return _json(201, {'id': 1, 'content': 'stub'});
      }
      return _json(200, <String, dynamic>{});
    }

    if (path.startsWith('/api/saved-searches/') && method == 'DELETE') {
      return _json(200, {'message': 'deleted'});
    }

    if (path.startsWith('/api/analytics/')) {
      return _json(200, <String, dynamic>{});
    }

    switch (path) {
      case '/api/analytics/listings':
        return _json(200, <dynamic>[]);
      case '/api/my_listings':
        return _json(200, <dynamic>[]);
      case '/api/user/my-listings':
        return _json(200, {
          'cars': <dynamic>[],
          'pagination': {'has_next': false},
        });
      case '/api/cars':
        if (method == 'POST') {
          return _json(201, {
            'message': 'Car listing created successfully',
            'car': _sampleCar('mock_car_new'),
          });
        }
        return _json(200, {
          'cars': <dynamic>[_sampleCar('list_car_1')],
          'pagination': {'has_next': false, 'page': 1, 'per_page': 20},
        });
      case '/api/chats':
        return _json(200, _sampleChats());
      case '/api/chat/unread_count':
        return _json(200, {'unread_count': 0});
      case '/api/auth/login':
      case '/api/auth/signup':
        return _json(200, {
          'access_token': 'test_access_token',
          'refresh_token': 'test_refresh_token',
          'user': {'id': 1, 'username': 'test', 'is_admin': false},
        });
      case '/api/auth/me':
        return _json(200, {
          'id': 1,
          'username': 'testuser',
          'email': 'test@example.com',
          'is_admin': false,
          'account_type': 'individual',
          'first_name': 'Test',
          'last_name': 'User',
        });
      case '/api/user/profile':
        return _json(200, {
          'user': {
            'id': 1,
            'username': 'test',
            'is_admin': false,
            'account_type': 'individual',
          },
        });
      case '/api/user/favorites':
      case '/api/user/recently-viewed':
        return _json(200, {
          'cars': <dynamic>[],
          'pagination': {'has_next': false},
        });
      case '/api/user/dealer-profile':
        return _json(200, {
          'dealer': {
            'dealership_name': 'Test Dealer',
            'dealership_location': 'Erbil',
          },
        });
      case '/api/saved-searches':
        if (method == 'POST') {
          return _json(201, {
            'saved_search': {
              'id': 'ss_mock_1',
              'name': 'Mock search',
              'filters': {'brand': 'toyota'},
              'notify': true,
            },
          });
        }
        return _json(200, {'saved_searches': <dynamic>[]});
      case '/api/auth/send_otp':
        return _json(200, {'sent': false, 'message': 'stub'});
      case '/api/auth/delete-account':
        return _json(200, {'message': 'Account deleted successfully'});
      case '/api/auth/refresh':
        return _json(200, {
          'access_token': 'test_access_token',
          'refresh_token': 'test_refresh_token',
        });
      case '/api/config/trust':
        return _json(200, {
          'support_email': 'support@test.example',
          'privacy_url': 'https://example.com/privacy',
          'terms_url': 'https://example.com/terms',
        });
      case '/api/push/preferences':
        return _json(200, {'push_enabled': true});
      case '/api/dealers':
        return _json(200, {
          'dealers': <dynamic>[],
          'pagination': {'has_next': false, 'page': 1, 'per_page': 20},
        });
      case '/api/admin/dealers/pending':
        return _json(200, {'dealers': <dynamic>[]});
      default:
        return _json(200, <String, dynamic>{});
    }
  }
}
