// F-06 widget-level regression tests: disposing the car-detail screen
// genuinely cancels its in-flight `getCarDetail` load, and that
// cancellation never surfaces as a generic error or writes to the offline
// cache.
//
// Uses `FakeApiServer`'s new `carDetailResponseGate` (mirrors the existing
// `favoritesResponseGate` pattern) to hold the mock GET response open until
// the test controls exactly when it resolves relative to widget disposal.
//
// `MockClient` does not implement real request abortion (see its own doc
// comment), so once the gate is released here it is completed with the
// exact exception type (`http.RequestAbortedException`) a real client
// delivers on genuine abort — this test proves the WIDGET's reaction to
// that exception (never crashes, never writes cache, cancels its token on
// dispose). The separate `test/api_cancel_token_real_abort_test.dart`
// proves the underlying `package:http` wiring itself genuinely delivers
// that exception when a real socket is aborted.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/pages/car_details_page.dart';
import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';

/// Pre-existing, unrelated rendering defect in this test environment (see
/// the identical filter + explanation in `car_detail_error_states_test.dart`):
/// `MainShell`'s `BottomNavigationBar` overflows regardless of which page is
/// pushed on top of it. Not caused by, and out of scope for, F-06.
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
    await ApiService.clearTokens();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets(
    'H+B+C: disposing the car-detail screen cancels its load token; the '
    "resulting cancellation doesn't crash, show an error, or get cached",
    (tester) async {
      const carId = 'f06_dispose_cancels';
      FakeApiServer.carDetailResponseGate = Completer<http.Response>();

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
      await tester.pump(const Duration(milliseconds: 100));

      final pageFinder = find.byType(CarDetailsPage);
      expect(pageFinder, findsOneWidget);
      // ignore: avoid_dynamic_calls
      final dynamic state = tester.state(pageFinder);
      // ignore: avoid_dynamic_calls
      final ApiCancelToken? token = state.debugLoadCarCancelToken;
      expect(token, isNotNull);
      expect(
        token!.isCancelled,
        isFalse,
        reason: 'the GET is still gated/pending at this point',
      );

      // Navigate away while the GET is still pending. Give the route's exit
      // transition time to finish so the old page is actually disposed
      // (not just visually covered).
      nav.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        token.isCancelled,
        isTrue,
        reason: 'dispose() must cancel the token for its in-flight load',
      );

      // The (mocked) response "arrives" after we've already navigated away
      // and cancelled — completed with the exact exception type a real
      // client delivers on genuine abort (see file header comment).
      FakeApiServer.carDetailResponseGate!.completeError(
        http.RequestAbortedException(),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Must not crash / must not surface as an unhandled framework error.
      expect(tester.takeException(), isNull);

      // Must never have been written to the offline cache.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cache_car_$carId'), isNull);
    },
  );
}
