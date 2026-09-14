// Regression tests for F-04: `_FavoritesPageState._loadFavorites()` must not
// call `setState` (or touch `BuildContext`) after the widget has been
// disposed. Each `setState` site that follows an `await` is now guarded with
// either `if (mounted) { setState(...) }` or `if (!mounted) return;`,
// matching the pattern already used by this file's own `finally` block and
// by `lib/pages/my_listings_page.dart`.
//
// `FakeApiServer.favoritesResponseGate` (added for this fix) lets these
// tests deterministically control exactly when `GET /api/user/favorites`
// resolves relative to widget disposal, with no timers/sleeps involved.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';

http.Response _jsonResponse(int status, Object body) => http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _sampleFavoriteCar(String id) => {
      'id': id,
      'title': 'Test Favorite',
      'brand': 'toyota',
      'model': 'camry',
      'year': 2020,
      'price': 12000,
      'currency': 'USD',
      'location': 'Erbil',
      'image_url': '',
      'images': <dynamic>[],
      'videos': <dynamic>[],
    };

/// Pre-existing, unrelated rendering defect in this test environment (also
/// documented in `test/car_detail_error_states_test.dart`): `MainShell`'s
/// `BottomNavigationBar` stays mounted underneath any pushed route and
/// reports `RenderFlex`/`TextScaler` noise regardless of which page is
/// pushed on top of it. Not caused by, and out of scope for, F-04 — filtered
/// out here by message so any other, genuinely unexpected error still fails
/// the test.
bool _isKnownPreexistingShellRenderingNoise(FlutterErrorDetails details) {
  final message = details.exceptionAsString();
  return message.contains('RenderFlex overflowed') ||
      message.contains('maxScale > minScale');
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
    FakeApiServer.favoritesResponseGate = null;
    await ApiService.clearTokens();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('A. happy path: favorites load normally with the guards in place', (
    tester,
  ) async {
    final capturedErrors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (_isKnownPreexistingShellRenderingNoise(details)) return;
      capturedErrors.add(details);
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/favorites');
    await tester.pump();

    var ready = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('No favorites yet').evaluate().isNotEmpty) {
        ready = true;
        break;
      }
    }

    expect(
      ready,
      isTrue,
      reason: 'Favorites page should render the empty state once loaded',
    );
    expect(find.text('Favorites'), findsWidgets);
    expect(capturedErrors, isEmpty);
  });

  testWidgets(
    'B. dispose during a delayed successful favorites response does not throw',
    (tester) async {
      final capturedErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (_isKnownPreexistingShellRenderingNoise(details)) return;
        capturedErrors.add(details);
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final gate = Completer<http.Response>();
      FakeApiServer.favoritesResponseGate = gate;

      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed('/favorites');
      await tester.pump();
      // Let _loadFavorites run up to (and block on) the gated GET request.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Dispose the page (drive the pop transition to completion via bounded
      // pumps, not pumpAndSettle: the loading skeleton's shimmer animation
      // repeats indefinitely and would make pumpAndSettle hang) while the
      // favorites request is still pending.
      expect(nav.canPop(), isTrue);
      nav.pop();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Now let the in-flight request resolve after disposal.
      gate.complete(
        _jsonResponse(200, {
          'cars': [_sampleFavoriteCar('fav_b_1')],
          'pagination': {'has_next': false},
        }),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        capturedErrors
            .where((d) => d.exceptionAsString().contains(
                  'setState() called after dispose()',
                ))
            .toList(),
        isEmpty,
      );
      expect(capturedErrors, isEmpty);
    },
  );

  testWidgets(
    'C. dispose during a delayed non-401 API error does not throw',
    (tester) async {
      final capturedErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (_isKnownPreexistingShellRenderingNoise(details)) return;
        capturedErrors.add(details);
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final gate = Completer<http.Response>();
      FakeApiServer.favoritesResponseGate = gate;

      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed('/favorites');
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(nav.canPop(), isTrue);
      nav.pop();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      gate.complete(http.Response('Internal error', 500));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        capturedErrors
            .where((d) => d.exceptionAsString().contains(
                  'setState() called after dispose()',
                ))
            .toList(),
        isEmpty,
      );
      expect(capturedErrors, isEmpty);
    },
  );

  testWidgets(
    'D. dispose during a delayed 401 (with refresh+retry) does not throw',
    (tester) async {
      final capturedErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (_isKnownPreexistingShellRenderingNoise(details)) return;
        capturedErrors.add(details);
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final gate = Completer<http.Response>();
      FakeApiServer.favoritesResponseGate = gate;

      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed('/favorites');
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(nav.canPop(), isTrue);
      nav.pop();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // 401 triggers ApiService's refresh+retry path; the retry re-reads the
      // same (already-completed) gate, so no second gate is needed.
      gate.complete(_jsonResponse(401, {'message': 'Invalid token'}));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        capturedErrors
            .where((d) => d.exceptionAsString().contains(
                  'setState() called after dispose()',
                ))
            .toList(),
        isEmpty,
      );
      expect(capturedErrors, isEmpty);
    },
  );
}
