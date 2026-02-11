import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/app/app.dart';
import 'package:car_listing_app/services/config.dart';

/// A best-effort full-app smoke test.
///
/// What it covers:
/// - Boots the real app widget tree (`CarzoApp`)
/// - Navigates through every named route in `buildAppRoutes()`
/// - Uses a local fake HTTP server so pages that load data on initState
///   don't hang or hit real networks during CI/dev tests
///
/// Run with:
/// `flutter test --dart-define=API_BASE=http://127.0.0.1:8081`
///
/// Note: WebSocket flows are intentionally not fully exercised here because
/// that requires a real Socket.IO server.
void main() {
  const int port = 8081;
  HttpServer? server;

  setUpAll(() async {
    // Ensure tests are pointed at our local fake server.
    final base = apiBase();
    if (base != 'http://127.0.0.1:$port') {
      throw StateError(
        'Smoke test expects API_BASE=http://127.0.0.1:$port but got "$base". '
        'Run: flutter test --dart-define=API_BASE=http://127.0.0.1:$port',
      );
    }

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server!.listen((req) async {
      final path = req.uri.path;

      Future<void> jsonOk(Object body) async {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(json.encode(body));
        await req.response.close();
      }

      // Health
      if (path == '/health') {
        return jsonOk({'status': 'ok'});
      }

      // Proxy-style API paths
      if (path.startsWith('/api/')) {
        // Minimal stubs required by pages that auto-load.
        switch (path) {
          case '/api/analytics/listings':
            return jsonOk(<dynamic>[]);
          case '/api/my_listings':
            return jsonOk(<dynamic>[]);
          case '/api/cars':
            // Legacy code sometimes expects either [] or {cars:[], pagination:{has_next:false}}
            return jsonOk({
              'cars': <dynamic>[],
              'pagination': {'has_next': false},
            });
          case '/api/auth/login':
            return jsonOk({
              'access_token': 'test_access_token',
              'user': {'id': 1, 'username': 'test'},
            });
          case '/api/auth/me':
            return jsonOk({
              'user': {'id': 1, 'username': 'test'},
            });
          case '/api/auth/send_otp':
            return jsonOk({'sent': false, 'dev_code': '123456'});
          case '/api/auth/signup':
            return jsonOk({
              'access_token': 'test_access_token',
              'user': {'id': 1, 'username': 'test'},
            });
          default:
            return jsonOk(<String, dynamic>{});
        }
      }

      // Default fallback
      req.response.statusCode = 404;
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server?.close(force: true);
  });

  testWidgets('Full app smoke: boot and visit all routes', (tester) async {
    await tester.pumpWidget(const CarzoApp());
    // Avoid pumpAndSettle here: many screens contain indeterminate animations
    // (e.g. progress indicators) which would never "settle".
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    Future<void> pushNamed(String name, {Object? args}) async {
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed(name, arguments: args);
      await tester.pump();
      // Allow a short window for initState async work and route transitions.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
      final ex = tester.takeException();
      expect(ex, isNull, reason: 'Exception while opening route: $name');

      // Pop back to exercise dispose lifecycles and keep the route stack small.
      if (nav.canPop()) {
        nav.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        final ex2 = tester.takeException();
        expect(ex2, isNull, reason: 'Exception while closing route: $name');
      }
    }

    // Build coverage for all named routes we ship.
    await pushNamed('/sell');
    await pushNamed('/settings');
    await pushNamed('/favorites');
    await pushNamed('/chat');
    await pushNamed('/login');
    await pushNamed('/signup');
    await pushNamed('/profile');
    await pushNamed('/edit-profile');
    await pushNamed('/payment/history');
    await pushNamed('/payment/initiate');
    await pushNamed(
      '/car_detail',
      args: {'carId': '1'},
    );
    await pushNamed(
      '/chat/conversation',
      // Use carId; route also accepts legacy conversationId.
      args: {'carId': '1'},
    );
    await pushNamed(
      '/payment/status',
      args: {'paymentId': 'p_1'},
    );
    await pushNamed(
      '/edit',
      args: {'car': <String, dynamic>{'id': 1, 'title': 'Test car'}},
    );
    await pushNamed('/my_listings');
    await pushNamed('/comparison');
    await pushNamed('/analytics');

    // Allow any SnackBar timers to complete so the test binding doesn't fail
    // on pending timers at teardown.
    await tester.pump(const Duration(seconds: 5));
  });
}

