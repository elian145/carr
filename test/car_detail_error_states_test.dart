// Regression tests for F-01/B-02: `CarDetailsPage` must distinguish a
// confirmed 404 ("Car not found") from transient/server/network/malformed
// failures (error + retry state, with the existing offline-cache fallback
// preserved) instead of collapsing every failure into "Car not found".
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

http.Response _jsonResponse(int status, Object body) => http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Pre-existing, unrelated rendering defect in this test environment:
/// `MainShell`'s `BottomNavigationBar` (the app's `/` initial route, which
/// stays mounted underneath any pushed route, including `/car_detail`)
/// reports a `RenderFlex` overflow — and, at some viewport sizes, a
/// `TextScaler` `maxScale > minScale` assertion — regardless of which page
/// is pushed on top of it. Verified reproducible on unmodified HEAD via the
/// pre-existing `legacy_car_detail_widget_test.dart` (both of its cases fail
/// the same way with zero F-01/B-02 changes applied). It is not caused by,
/// and is out of scope for, this fix (no `MainShell`/`BottomNavigationBar`
/// changes are permitted here) — so it is filtered out here by message,
/// leaving any other, genuinely unexpected error free to fail the test.
bool _isKnownPreexistingShellRenderingNoise(FlutterErrorDetails details) {
  final message = details.exceptionAsString();
  return message.contains('RenderFlex overflowed') ||
      message.contains('maxScale > minScale');
}

/// Pushes `/car_detail` for [carId] and pumps until either "Car not found",
/// a listing title ("Camry"), or a retry button ("Retry") appears — whatever
/// comes first — then returns. All fixtures here respond synchronously (no
/// real network delay), so a short, bounded pump loop is enough.
Future<void> _openCarDetailAndSettle(WidgetTester tester, String carId) async {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_isKnownPreexistingShellRenderingNoise(details)) return;
    originalOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalOnError);

  await tester.pumpWidget(const legacy.MyApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav.pushNamed('/car_detail', arguments: {'carId': carId});
  await tester.pump();

  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Car not found').evaluate().isNotEmpty ||
        find.textContaining('Camry').evaluate().isNotEmpty ||
        find.text('Retry').evaluate().isNotEmpty) {
      break;
    }
  }
  // Let any post-frame callbacks/animations settle without hanging on
  // pending timers (pumpAndSettle would hang on retry-able error UIs).
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('404 with no cache shows "Car not found"', (tester) async {
    const carId = 'f01_404_no_cache';
    FakeApiServer.carDetailOverrides[carId] =
        () => _jsonResponse(404, {'message': 'Car not found'});

    await _openCarDetailAndSettle(tester, carId);

    expect(find.text('Car not found'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets(
    '404 with an existing cache STILL shows "Car not found" (no stale fallback)',
    (tester) async {
      const carId = 'f01_404_with_cache';
      seedCarDetailCache(carId);
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(404, {'message': 'Car not found'});

      await _openCarDetailAndSettle(tester, carId);

      expect(find.text('Car not found'), findsOneWidget);
      expect(find.textContaining('Camry'), findsNothing);
    },
  );

  testWidgets(
    'network/transport failure with no cache shows an error state, not "Car not found"',
    (tester) async {
      const carId = 'f01_network_no_cache';
      FakeApiServer.carDetailOverrides[carId] =
          () => throw const SocketException('Failed host lookup');

      await _openCarDetailAndSettle(tester, carId);

      expect(find.text('Car not found'), findsNothing);
      expect(
        find.text(
          'Could not reach the server. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    '500 with no cache shows a server error state, not "Car not found"',
    (tester) async {
      const carId = 'f01_500_no_cache';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(500, {'message': 'Failed to get car'});

      await _openCarDetailAndSettle(tester, carId);

      expect(find.text('Car not found'), findsNothing);
      expect(
        find.text('Server error (500). Please try again later.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'timeout with no cache shows a network error state, not "Car not found"',
    (tester) async {
      const carId = 'f01_timeout_no_cache';
      FakeApiServer.carDetailOverrides[carId] =
          () => throw TimeoutException('Simulated timeout');

      await _openCarDetailAndSettle(tester, carId);

      expect(find.text('Car not found'), findsNothing);
      expect(
        find.text(
          'Could not reach the server. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'malformed response with no cache shows an error state, not "Car not found"',
    (tester) async {
      const carId = 'f01_malformed_no_cache';
      FakeApiServer.carDetailOverrides[carId] =
          () => http.Response('not-valid-json{', 200);

      await _openCarDetailAndSettle(tester, carId);

      expect(find.text('Car not found'), findsNothing);
      expect(
        find.text(
          'Could not reach the server. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'network/transport failure with a cache renders the cached listing',
    (tester) async {
      const carId = 'f01_network_with_cache';
      seedCarDetailCache(carId);
      FakeApiServer.carDetailOverrides[carId] =
          () => throw const SocketException('Failed host lookup');

      await _openCarDetailAndSettle(tester, carId);

      expect(find.textContaining('Camry'), findsWidgets);
      expect(find.text('Car not found'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    },
  );

  testWidgets('500 with a cache renders the cached listing', (tester) async {
    const carId = 'f01_500_with_cache';
    seedCarDetailCache(carId);
    FakeApiServer.carDetailOverrides[carId] =
        () => _jsonResponse(500, {'message': 'Failed to get car'});

    await _openCarDetailAndSettle(tester, carId);

    expect(find.textContaining('Camry'), findsWidgets);
    expect(find.text('Car not found'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets(
    'retry button re-invokes the load and can recover to a successful listing',
    (tester) async {
      const carId = 'f01_retry_recovers';
      var attempt = 0;
      FakeApiServer.carDetailOverrides[carId] = () {
        attempt++;
        if (attempt == 1) {
          return _jsonResponse(500, {'message': 'Failed to get car'});
        }
        return _jsonResponse(200, {
          'car': {
            'id': carId,
            'public_id': carId,
            'brand': 'toyota',
            'model': 'camry',
            'year': 2020,
          },
        });
      };

      await _openCarDetailAndSettle(tester, carId);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Camry'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.textContaining('Camry').evaluate().isNotEmpty) break;
      }

      expect(attempt, 2);
      expect(find.textContaining('Camry'), findsWidgets);
      expect(find.text('Car not found'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    },
  );
}
