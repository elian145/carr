// F-42: analytics failures surface as errors, never as invented zero counts.
import 'dart:convert';

import 'package:car_listing_app/services/analytics_service.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> paths;
  late int analyticsStatus;

  setUp(() async {
    paths = [];
    analyticsStatus = 200;
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    ApiService.testHttpClient = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path == '/api/analytics/listings') {
        if (analyticsStatus != 200) {
          return http.Response('{"message":"boom"}', analyticsStatus,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(
          json.encode([
            {
              'listing_id': '7',
              'id': '7',
              'title': 'Camry',
              'views': 12,
              'created_at': '2026-01-01T00:00:00Z',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // Anything else (e.g. my-listings compat) returns a plausible listing
      // that the OLD code would have turned into fake zero analytics.
      return http.Response(
        json.encode({
          'cars': [
            {'id': 7, 'title': 'Camry'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await ApiService.setTokens(accessToken: 'a', refreshToken: 'r');
  });

  tearDown(() async {
    await ApiService.clearTokens();
    ApiService.testHttpClient = null;
    setRuntimeApiBaseOverride(null);
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  test('server error on /analytics/listings throws instead of fake zeros', () async {
    analyticsStatus = 500;
    await expectLater(
      AnalyticsService.getUserListingsAnalytics(),
      throwsA(isA<Exception>()),
    );
    expect(
      paths.where((p) => p.contains('cars')),
      isEmpty,
      reason: 'must not fall back to my-listings and invent counts',
    );
  });

  test('negative control: healthy endpoint returns the real values', () async {
    final rows = await AnalyticsService.getUserListingsAnalytics();
    expect(rows, hasLength(1));
    expect(rows.single.views, 12);
  });
}
