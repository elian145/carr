// Regression tests for F-01: `ApiService.getCarDetail` must classify
// failures instead of swallowing everything into `null` (which made a
// network failure, a 401, and a 500 indistinguishable from a deleted
// listing — see PRODUCTION_AUDIT.md F-01 / B-02).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
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

  http.Response jsonResponse(int status, Object body) => http.Response(
        json.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  /// Swaps in [client] for the duration of one test and restores whatever
  /// was bound before (the shared [FakeApiServer] client) afterwards —
  /// mirrors the established pattern in `auth_service_test.dart`.
  void useClient(MockClient client) {
    final original = ApiService.boundTestHttpClient;
    ApiService.testHttpClient = client;
    addTearDown(() => ApiService.testHttpClient = original);
  }

  test('200 with a valid payload returns the car map', () async {
    final detail = await ApiService.getCarDetail('unit-car-ok');
    expect(detail['brand'], 'toyota');
    expect(detail['model'], 'camry');
  });

  test('404 throws ApiException(statusCode: 404)', () async {
    useClient(
      MockClient((request) async {
        if (request.url.path.startsWith('/api/cars/')) {
          return jsonResponse(404, {'message': 'Car not found'});
        }
        return jsonResponse(200, <String, dynamic>{});
      }),
    );

    await expectLater(
      ApiService.getCarDetail('missing-car'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  });

  test('500 throws ApiException(statusCode: 500)', () async {
    useClient(
      MockClient((request) async {
        if (request.url.path.startsWith('/api/cars/')) {
          return jsonResponse(500, {'message': 'Failed to get car'});
        }
        return jsonResponse(200, <String, dynamic>{});
      }),
    );

    await expectLater(
      ApiService.getCarDetail('broken-car'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
      ),
    );
  });

  test('429 throws ApiException(statusCode: 429)', () async {
    useClient(
      MockClient((request) async {
        if (request.url.path.startsWith('/api/cars/')) {
          return jsonResponse(429, {'message': 'Too many requests'});
        }
        return jsonResponse(200, <String, dynamic>{});
      }),
    );

    await expectLater(
      ApiService.getCarDetail('throttled-car'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 429),
      ),
    );
  });

  test('malformed JSON body throws instead of returning null', () async {
    useClient(
      MockClient((request) async {
        if (request.url.path.startsWith('/api/cars/')) {
          return http.Response('not-valid-json{', 200);
        }
        return jsonResponse(200, <String, dynamic>{});
      }),
    );

    await expectLater(
      ApiService.getCarDetail('malformed-car'),
      throwsA(isA<FormatException>()),
    );
  });

  test('empty 200 body throws instead of returning null', () async {
    useClient(
      MockClient((request) async {
        if (request.url.path.startsWith('/api/cars/')) {
          return http.Response('', 200);
        }
        return jsonResponse(200, <String, dynamic>{});
      }),
    );

    await expectLater(
      ApiService.getCarDetail('empty-body-car'),
      throwsA(isA<FormatException>()),
    );
  });

  test('unexpected payload shape throws instead of returning null', () async {
    useClient(
      MockClient((request) async {
        if (request.url.path.startsWith('/api/cars/')) {
          // Valid JSON, but neither a Map nor a non-empty List — the shape
          // parseCarDetailPayload() cannot make sense of.
          return jsonResponse(200, 'unexpected-string-payload');
        }
        return jsonResponse(200, <String, dynamic>{});
      }),
    );

    await expectLater(
      ApiService.getCarDetail('weird-shape-car'),
      throwsA(isA<FormatException>()),
    );
  });

  test('timeout propagates as TimeoutException, not null', () async {
    useClient(
      MockClient((request) async {
        if (request.url.path.startsWith('/api/cars/')) {
          throw TimeoutException('Simulated timeout');
        }
        return jsonResponse(200, <String, dynamic>{});
      }),
    );

    await expectLater(
      ApiService.getCarDetail('timeout-car'),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('transport failure propagates as SocketException, not null', () async {
    useClient(
      MockClient((request) async {
        if (request.url.path.startsWith('/api/cars/')) {
          throw const SocketException('Failed host lookup');
        }
        return jsonResponse(200, <String, dynamic>{});
      }),
    );

    await expectLater(
      ApiService.getCarDetail('offline-car'),
      throwsA(isA<SocketException>()),
    );
  });

  test('401 followed by a successful refresh retries and succeeds', () async {
    var carCalls = 0;
    useClient(
      MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          return jsonResponse(200, {
            'access_token': 'new_access_token',
            'refresh_token': 'new_refresh_token',
          });
        }
        if (request.url.path.startsWith('/api/cars/')) {
          carCalls++;
          if (carCalls == 1) {
            return jsonResponse(401, {'message': 'Token has expired'});
          }
          return jsonResponse(200, {
            'car': {'id': 'refreshed-car', 'brand': 'toyota', 'model': 'camry'},
          });
        }
        return jsonResponse(200, <String, dynamic>{});
      }),
    );

    final detail = await ApiService.getCarDetail('refreshed-car');
    expect(detail['brand'], 'toyota');
    expect(carCalls, 2);
  });

  test(
    '401 with a failed refresh surfaces an auth ApiException, not null',
    () async {
      useClient(
        MockClient((request) async {
          if (request.url.path == '/api/auth/refresh') {
            // No access_token in the body -> _refreshAccessTokenOnce() fails.
            return jsonResponse(200, <String, dynamic>{});
          }
          if (request.url.path.startsWith('/api/cars/')) {
            return jsonResponse(401, {'message': 'Token has expired'});
          }
          return jsonResponse(200, <String, dynamic>{});
        }),
      );

      await expectLater(
        ApiService.getCarDetail('locked-car'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    },
  );
}
