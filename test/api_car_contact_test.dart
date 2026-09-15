// Regression tests for F-07: `ApiService.getCarContactPhones` must classify
// failures instead of swallowing everything into `const []` (which made a
// network failure, a 401, a 429 rate limit, and a 500 indistinguishable
// from "this listing genuinely has no contact phone" — see
// PRODUCTION_AUDIT.md F-07).
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
  /// mirrors the established pattern in `api_car_detail_test.dart`.
  void useClient(MockClient client) {
    final original = ApiService.boundTestHttpClient;
    ApiService.testHttpClient = client;
    addTearDown(() => ApiService.testHttpClient = original);
  }

  test(
    '200 with a populated phone list returns the phones',
    () async {
      const carId = 'f07_contact_populated';
      FakeApiServer.carContactOverrides[carId] = () => jsonResponse(200, {
            'contact_phone': '+9647701234567',
            'contact_phones': ['+9647701234567', '+9647709876543'],
            'has_contact_phone': true,
          });

      final phones = await ApiService.getCarContactPhones(carId);

      expect(phones, ['+9647701234567', '+9647709876543']);
    },
  );

  test(
    '200 with a genuinely empty phone list returns const []',
    () async {
      const carId = 'f07_contact_empty';
      FakeApiServer.carContactOverrides[carId] = () => jsonResponse(200, {
            'contact_phone': null,
            'contact_phones': <dynamic>[],
            'has_contact_phone': false,
          });

      final phones = await ApiService.getCarContactPhones(carId);

      expect(phones, isEmpty);
    },
  );

  test('401 with a failed refresh throws ApiException(statusCode: 401)', () async {
    const carId = 'f07_contact_401';
    useClient(
      MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          // No access_token in the body -> _refreshAccessTokenOnce() fails.
          return jsonResponse(200, <String, dynamic>{});
        }
        if (request.url.path == '/api/cars/$carId/contact') {
          return jsonResponse(401, {'message': 'Token has expired'});
        }
        return jsonResponse(200, <String, dynamic>{});
      }),
    );

    await expectLater(
      ApiService.getCarContactPhones(carId),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('429 throws ApiException(statusCode: 429), not []', () async {
    const carId = 'f07_contact_429';
    FakeApiServer.carContactOverrides[carId] =
        () => jsonResponse(429, {'message': 'Too many requests'});

    await expectLater(
      ApiService.getCarContactPhones(carId),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 429),
      ),
    );
  });

  test('500 throws ApiException(statusCode: 500), not []', () async {
    const carId = 'f07_contact_500';
    FakeApiServer.carContactOverrides[carId] =
        () => jsonResponse(500, {'message': 'Failed to get contact'});

    await expectLater(
      ApiService.getCarContactPhones(carId),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
      ),
    );
  });

  test(
    'timeout propagates as TimeoutException, not []',
    () async {
      const carId = 'f07_contact_timeout';
      FakeApiServer.carContactOverrides[carId] =
          () => throw TimeoutException('Simulated timeout');

      await expectLater(
        ApiService.getCarContactPhones(carId),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test(
    'transport failure propagates as SocketException, not []',
    () async {
      const carId = 'f07_contact_offline';
      FakeApiServer.carContactOverrides[carId] =
          () => throw const SocketException('Failed host lookup');

      await expectLater(
        ApiService.getCarContactPhones(carId),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test(
    'malformed JSON body throws instead of returning []',
    () async {
      const carId = 'f07_contact_malformed';
      FakeApiServer.carContactOverrides[carId] =
          () => http.Response('not-valid-json{', 200);

      await expectLater(
        ApiService.getCarContactPhones(carId),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'unexpected (non-Map) 200 payload shape throws instead of returning []',
    () async {
      const carId = 'f07_contact_weird_shape';
      // Valid JSON, but a List rather than the expected Map — the shape
      // ApiService._handleResponse's `Map<String, dynamic>` return type
      // cannot accept.
      FakeApiServer.carContactOverrides[carId] =
          () => jsonResponse(200, <dynamic>['unexpected-array-payload']);

      await expectLater(
        ApiService.getCarContactPhones(carId),
        throwsA(isA<TypeError>()),
      );
    },
  );

  test(
    '401 followed by a successful refresh retries and returns the phones',
    () async {
      const carId = 'f07_contact_refresh_ok';
      var contactCalls = 0;
      useClient(
        MockClient((request) async {
          if (request.url.path == '/api/auth/refresh') {
            return jsonResponse(200, {
              'access_token': 'new_access_token',
              'refresh_token': 'new_refresh_token',
            });
          }
          if (request.url.path == '/api/cars/$carId/contact') {
            contactCalls++;
            if (contactCalls == 1) {
              return jsonResponse(401, {'message': 'Token has expired'});
            }
            return jsonResponse(200, {
              'contact_phone': '+9647701234567',
              'contact_phones': ['+9647701234567'],
              'has_contact_phone': true,
            });
          }
          return jsonResponse(200, <String, dynamic>{});
        }),
      );

      final phones = await ApiService.getCarContactPhones(carId);

      expect(phones, ['+9647701234567']);
      expect(contactCalls, 2);
    },
  );
}
