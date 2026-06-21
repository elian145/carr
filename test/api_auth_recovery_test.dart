import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  test('forgotPassword POST returns success envelope', () async {
    final result = await ApiService.forgotPassword('buyer@test.example');
    expect(result['message'], isNotEmpty);
  });

  test('resetPassword POST returns success message', () async {
    final result = await ApiService.resetPassword('reset-token-123', 'Aa123456!');
    expect(result['message'], isNotEmpty);
  });

  test('verifyEmail POST returns success message', () async {
    final result = await ApiService.verifyEmail('verify-token-abc');
    expect(result['message'], isNotEmpty);
  });
}
