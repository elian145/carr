import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/services/config.dart';

/// Local HTTP stub for widget/smoke tests (no real backend).
///
/// Binds an ephemeral port and sets [setRuntimeApiBaseOverride] so parallel
/// test files do not collide on a fixed port.
class FakeApiServer {
  FakeApiServer._();

  static HttpServer? _server;

  /// Starts the stub once per isolate (safe for parallel `flutter test`).
  static Future<void> ensureStarted() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = _server!.port;
    setRuntimeApiBaseOverride('http://127.0.0.1:$port');
    _server!.listen(_handle);
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    setRuntimeApiBaseOverride(null);
  }

  static Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;

    Future<void> jsonOk(Object body) async {
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.json;
      req.response.write(json.encode(body));
      await req.response.close();
    }

    if (path == '/health') {
      return jsonOk({'status': 'ok'});
    }

    if (path.startsWith('/api/')) {
      if (path.startsWith('/api/cars/') && path.length > '/api/cars/'.length) {
        final segments = path.substring('/api/cars/'.length).split('/');
        final id = segments.first;
        if (segments.length > 1 && segments[1] == 'favorite') {
          return jsonOk({'is_favorited': false});
        }
        return jsonOk({
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
        });
      }

      switch (path) {
        case '/api/analytics/listings':
          return jsonOk(<dynamic>[]);
        case '/api/my_listings':
        case '/api/user/my-listings':
          return jsonOk({
            'cars': <dynamic>[],
            'pagination': {'has_next': false},
          });
        case '/api/cars':
          return jsonOk({
            'cars': <dynamic>[],
            'pagination': {'has_next': false, 'page': 1, 'per_page': 20},
          });
        case '/api/auth/login':
        case '/api/auth/signup':
          return jsonOk({
            'access_token': 'test_access_token',
            'refresh_token': 'test_refresh_token',
            'user': {'id': 1, 'username': 'test'},
          });
        case '/api/auth/me':
        case '/api/user/profile':
          return jsonOk({
            'user': {'id': 1, 'username': 'test'},
          });
        case '/api/user/favorites':
        case '/api/user/recently-viewed':
          return jsonOk({
            'cars': <dynamic>[],
            'pagination': {'has_next': false},
          });
        case '/api/saved-searches':
          return jsonOk({'saved_searches': <dynamic>[]});
        case '/api/auth/send_otp':
          return jsonOk({'sent': false, 'message': 'stub'});
        case '/api/config/trust':
          return jsonOk({
            'support_email': 'support@test.example',
            'privacy_url': 'https://example.com/privacy',
            'terms_url': 'https://example.com/terms',
          });
        case '/api/push/preferences':
          return jsonOk({'push_enabled': true});
        case '/api/dealers':
          return jsonOk({'dealers': <dynamic>[]});
        default:
          return jsonOk(<String, dynamic>{});
      }
    }

    req.response.statusCode = 404;
    await req.response.close();
  }
}
