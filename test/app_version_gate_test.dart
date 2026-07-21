import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:car_listing_app/services/app_version_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppVersionGate.resetCacheForTests();
    AppVersionGate.debugPackageInfo = PackageInfo(
      appName: 'CarNet',
      packageName: 'com.carzo.app',
      version: '1.0.0',
      buildNumber: '10',
    );
  });

  tearDown(AppVersionGate.resetCacheForTests);

  test('compareSemver orders dotted versions', () {
    expect(AppVersionGate.compareSemver('1.0.0', '1.0.1'), lessThan(0));
    expect(AppVersionGate.compareSemver('1.2.0', '1.1.9'), greaterThan(0));
    expect(AppVersionGate.compareSemver('2.0', '2.0.0'), 0);
  });

  test('soft recommend when below recommended_app_version (M-20)', () async {
    AppVersionGate.setCachedForTests(
      const AppVersionRequirement(
        recommendedAppVersion: '1.2.0',
        softUpdateMessage: 'Please consider updating.',
        androidStoreUrl: 'https://example.com/android',
      ),
    );

    final decision = await AppVersionGate.evaluate();
    expect(decision.required, isFalse);
    expect(decision.softRecommended, isTrue);
    expect(decision.message, 'Please consider updating.');
    expect(decision.softPromptKey, '1.2.0');
  });

  test('force required beats soft recommend', () async {
    AppVersionGate.setCachedForTests(
      const AppVersionRequirement(
        minAppVersion: '2.0.0',
        forceUpdateMessage: 'Must update',
        recommendedAppVersion: '3.0.0',
        softUpdateMessage: 'Soft',
      ),
    );

    final decision = await AppVersionGate.evaluate();
    expect(decision.required, isTrue);
    expect(decision.softRecommended, isFalse);
    expect(decision.message, 'Must update');
  });

  test('no prompt when already on recommended version', () async {
    AppVersionGate.debugPackageInfo = PackageInfo(
      appName: 'CarNet',
      packageName: 'com.carzo.app',
      version: '1.2.0',
      buildNumber: '20',
    );
    AppVersionGate.setCachedForTests(
      const AppVersionRequirement(recommendedAppVersion: '1.2.0'),
    );

    final decision = await AppVersionGate.evaluate();
    expect(decision.required, isFalse);
    expect(decision.softRecommended, isFalse);
  });
}
