import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/trust_config.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  setUp(() {
    TrustConfig.resetCacheForTests();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  test('TrustConfig.load reads support email from mock API', () async {
    final cfg = await TrustConfig.load();
    expect(cfg.supportEmail, 'support@test.example');
    expect(cfg.termsUrl, isNotEmpty);
  });
}
