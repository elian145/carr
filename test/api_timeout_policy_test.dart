import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/api_service.dart';

void main() {
  tearDown(ApiService.debugResetTimeoutPolicy);

  test('requestTimeout is cold before any success', () {
    expect(ApiService.requestTimeout(), const Duration(seconds: 55));
  });

  test('requestTimeout is warm shortly after success', () {
    ApiService.debugMarkRequestSuccessAt(DateTime.now());
    expect(ApiService.requestTimeout(), const Duration(seconds: 20));
  });

  test('requestTimeout returns cold after long idle', () {
    ApiService.debugMarkRequestSuccessAt(
      DateTime.now().subtract(const Duration(minutes: 15)),
    );
    expect(ApiService.requestTimeout(), const Duration(seconds: 55));
  });
}
