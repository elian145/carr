import 'package:car_listing_app/services/feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  setUp(() {
    FeatureFlags.resetCacheForTests();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  test('FeatureFlags.load reads flags from /api/config/app (L-10)', () async {
    final snap = await FeatureFlags.load();
    expect(snap.sellEnabled, isTrue);
    expect(snap.chatEnabled, isTrue);
    expect(snap.isEnabled('unknown_flag'), isTrue); // fail-open
  });

  test('FeatureFlags.applyFromAppConfigJson disables known keys', () {
    FeatureFlags.applyFromAppConfigJson({
      'feature_flags': {'sell': false, 'chat': true},
    });
    expect(FeatureFlags.current.sellEnabled, isFalse);
    expect(FeatureFlags.current.chatEnabled, isTrue);
  });
}
