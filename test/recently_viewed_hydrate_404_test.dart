// RecentlyViewedService._hydrateIds: a definitive 404 ("Car not found") is
// an expected miss for deleted/inaccessible listings. It must prune the
// local stub and must NOT be reported via logNonFatal/Sentry. Unexpected
// failures (5xx) still report.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/recently_viewed_service.dart';
import 'package:car_listing_app/shared/debug/app_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final reported = <Object>[];

  setUp(() async {
    reported.clear();
    debugLogNonFatalOverride = (error, stackTrace, context) {
      reported.add(error);
    };
    SharedPreferences.setMockInitialValues({});
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
    ApiService.testHttpClient = null;
  });

  tearDown(() async {
    debugLogNonFatalOverride = null;
    ApiService.testHttpClient = null;
    await ApiService.clearTokens();
  });

  Future<void> seedLocalStub(String id) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      RecentlyViewedService.localKey,
      jsonEncode([
        {'id': id, 'public_id': id, 'viewed_at': '2026-10-12'},
      ]),
    );
  }

  test(
    '404 Car not found prunes local stub and is not reported to Sentry',
    () async {
      await seedLocalStub('gone-car');

      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path.startsWith('/api/cars/gone-car')) {
          return http.Response(
            jsonEncode({'message': 'Car not found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final list = await RecentlyViewedService.loadLocalDisplayList();
      expect(list, isEmpty);
      expect(
        reported.whereType<ApiException>(),
        isEmpty,
        reason: 'expected 404 must not be reported as ApiException',
      );

      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(RecentlyViewedService.localKey);
      final kept = raw == null || raw.isEmpty
          ? <dynamic>[]
          : (json.decode(raw) as List);
      expect(kept, isEmpty);
    },
  );

  test('non-404 hydrate failures are still reported', () async {
    await seedLocalStub('busy-car');

    ApiService.testHttpClient = MockClient((request) async {
      if (request.url.path.startsWith('/api/cars/busy-car')) {
        return http.Response(
          jsonEncode({'message': 'upstream unavailable'}),
          502,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('nope', 500);
    });

    final list = await RecentlyViewedService.loadLocalDisplayList();
    // Transient failure: bare stub stays in prefs for a later retry.
    expect(list, isNotEmpty);
    expect(list.first['id'], 'busy-car');
    expect(
      reported.whereType<ApiException>().any((e) => e.statusCode == 502),
      isTrue,
    );
  });
}
