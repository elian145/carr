// Focused F-06 regression tests: GET-only request cancellation via
// `ApiCancelToken`, exercised directly against `ApiService.getCarDetail`
// (no widget tree).
//
// `FakeApiServer` is backed by `package:http/testing.dart`'s `MockClient`,
// which explicitly does *not* wire up real request abortion — its own doc
// comment says "This client does not support aborting requests directly."
// So these tests cover the classification/control-flow contract that is
// entirely under this repo's own control: the pre-cancel fast path (no
// network call at all), the interaction with the existing 401-refresh
// retry, and that normal success/404/500/timeout behavior is completely
// unaffected when cancellation is not used.
//
// Genuine socket-level abortion — proving `AbortableRequest.abortTrigger`
// actually reaches and aborts a real `dart:io` HTTP request — is covered
// separately in `test/api_cancel_token_real_abort_test.dart`, which
// bypasses `MockClient` entirely and uses a real loopback `HttpServer` +
// a real `IOClient`.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';

http.Response _jsonResponse(int status, Object body) => http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
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

  test('D: a normal GET with a fresh (non-cancelled) token still succeeds', () async {
    const carId = 'f06_normal_success';
    FakeApiServer.carDetailOverrides[carId] = () => _jsonResponse(200, {
          'car': {'id': carId, 'brand': 'toyota', 'model': 'camry', 'year': 2020},
        });

    final token = ApiCancelToken();
    final result = await ApiService.getCarDetail(carId, cancelToken: token);

    expect(result['brand'], 'toyota');
    expect(token.isCancelled, isFalse);
  });

  test(
    'pre-cancel fast path: an already-cancelled token throws immediately '
    'and never makes a network call',
    () async {
      const carId = 'f06_precancelled';
      final before = FakeApiServer.carDetailFetchCount;
      FakeApiServer.carDetailOverrides[carId] = () => _jsonResponse(200, {
            'car': {'id': carId, 'brand': 'toyota', 'model': 'camry', 'year': 2020},
          });

      final token = ApiCancelToken();
      token.cancel();

      await expectLater(
        ApiService.getCarDetail(carId, cancelToken: token),
        throwsA(isA<ApiCancelledException>()),
      );
      // The fast-path check in `_sendAbortableGet` must reject before ever
      // reaching the network layer.
      expect(FakeApiServer.carDetailFetchCount, before);
    },
  );

  test('E: 404 remains a real 404, distinguishable from cancellation', () async {
    const carId = 'f06_404_unaffected';
    FakeApiServer.carDetailOverrides[carId] =
        () => _jsonResponse(404, {'message': 'Car not found'});

    final token = ApiCancelToken();
    await expectLater(
      ApiService.getCarDetail(carId, cancelToken: token),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
    expect(token.isCancelled, isFalse);
  });

  test('F: 500 remains a real server error, distinguishable from cancellation', () async {
    const carId = 'f06_500_unaffected';
    FakeApiServer.carDetailOverrides[carId] =
        () => _jsonResponse(500, {'message': 'Failed to get car'});

    final token = ApiCancelToken();
    await expectLater(
      ApiService.getCarDetail(carId, cancelToken: token),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
      ),
    );
    expect(token.isCancelled, isFalse);
  });

  test(
    'I: existing timeout behavior is unaffected when a token is passed but '
    'never cancelled',
    () async {
      const carId = 'f06_timeout_unaffected';
      FakeApiServer.carDetailOverrides[carId] =
          () => throw TimeoutException('Simulated timeout');

      final token = ApiCancelToken();
      await expectLater(
        ApiService.getCarDetail(carId, cancelToken: token),
        throwsA(isA<TimeoutException>()),
      );
      expect(token.isCancelled, isFalse);
    },
  );

  test(
    'G: cancelling while a 401-triggered refresh is in-flight aborts the '
    'retried GET (never dispatched) without clearing tokens/logging out',
    () async {
      const carId = 'f06_cancel_during_refresh';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(401, {'message': 'Unauthorized'});
      FakeApiServer.authRefreshGate = Completer<http.Response>();
      final fetchesBefore = FakeApiServer.carDetailFetchCount;

      final token = ApiCancelToken();
      final future = ApiService.getCarDetail(carId, cancelToken: token);

      // Give the initial GET (401) + the refresh call time to actually
      // dispatch and reach the gated `/api/auth/refresh` await point (no
      // real network latency here, but the gate itself only ever resolves
      // when we complete it below, so this just drains pending microtasks
      // deterministically).
      await pumpEventQueue();
      expect(
        FakeApiServer.carDetailFetchCount,
        fetchesBefore + 1,
        reason: 'the initial GET should have already happened by now',
      );

      // Cancel while refresh is deliberately still pending, then let the
      // refresh succeed.
      token.cancel();
      FakeApiServer.authRefreshGate!.complete(
        _jsonResponse(200, {
          'access_token': 'new_access_token',
          'refresh_token': 'new_refresh_token',
        }),
      );

      await expectLater(future, throwsA(isA<ApiCancelledException>()));
      // The retried GET must never have been dispatched.
      expect(FakeApiServer.carDetailFetchCount, fetchesBefore + 1);
      // A cancellation must never itself clear tokens / force a logout.
      expect(ApiService.isAuthenticated, isTrue);
    },
  );
}
