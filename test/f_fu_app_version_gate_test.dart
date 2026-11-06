// Force-update hardening: AppVersionGate unit tests (fake HTTP + fake clock).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/app_version_gate.dart';

import 'f_fu_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeConfigServer server;
  late FakeClock clock;

  setUp(() {
    server = FakeConfigServer(oldShapeConfig());
    clock = setUpGateFakes(server);
  });
  tearDown(tearDownGateFakes);

  group('failed fetch is never cached', () {
    test('a failed first fetch fails open and the next call refetches', () async {
      server.status = 500;
      final first = await AppVersionGate.evaluate();
      expect(first.required, isFalse);
      expect(server.calls, 1);

      // Server recovers with a real floor; once the failure back-off has
      // passed the very next evaluate() must see it (nothing was cached).
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      clock.advance(AppVersionGate.failureBackoff + const Duration(seconds: 1));
      final second = await AppVersionGate.evaluate();
      expect(server.calls, 2);
      expect(second.required, isTrue);
    });

    test('timeout / transport error / garbage body / non-object / non-200 all fail open', () async {
      final failures = <void Function()>[
        () => server.failWith = TimeoutException('slow'),
        () => server.failWith = const SocketException('offline'),
        () {
          server.failWith = null;
          server.rawBody = '<html>captive portal</html>';
        },
        () => server.rawBody = '[1,2,3]',
        () => server.rawBody = 'null',
        () {
          server.rawBody = null;
          server.status = 503;
        },
        () => server.status = 404,
      ];
      for (final arm in failures) {
        ApiService.debugResetTimeoutPolicy();
        AppVersionGate.resetCacheForTests();
        AppVersionGate.clock = clock.call;
        AppVersionGate.debugPlatform = TargetPlatform.android;
        AppVersionGate.debugPackageInfo = PackageInfo(
          appName: 'CarNet',
          packageName: 'com.carnetiq.app',
          version: '1.0.0',
          buildNumber: '10',
        );
        server
          ..respond(oldShapeConfig(minAppVersion: '9.0.0'))
          ..status = 200;
        arm();
        final d = await AppVersionGate.evaluate();
        expect(d.required, isFalse, reason: 'must fail open');
        expect(d.softRecommended, isFalse);
        expect(AppVersionGate.lastSuccessAt, isNull,
            reason: 'a failure is never recorded as a success');
      }
    });

    test('within the back-off window a failing server is not hammered', () async {
      server.status = 500;
      for (var i = 0; i < 100; i++) {
        await AppVersionGate.evaluate();
      }
      expect(server.calls, 1, reason: 'no refetch loop while failing');
      clock.advance(AppVersionGate.failureBackoff + const Duration(seconds: 1));
      await AppVersionGate.evaluate();
      expect(server.calls, 2);
    });

    test('forceRefresh bypasses the failure back-off', () async {
      server.status = 500;
      await AppVersionGate.evaluate();
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      final d = await AppVersionGate.evaluate(forceRefresh: true);
      expect(server.calls, 2);
      expect(d.required, isTrue);
    });
  });

  group('success caching (TTL) and last known-good', () {
    test('a success is reused within the TTL and refetched after it', () async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      expect((await AppVersionGate.evaluate()).required, isTrue);
      expect((await AppVersionGate.evaluate()).required, isTrue);
      expect(server.calls, 1);

      clock.advance(AppVersionGate.cacheTtl + const Duration(seconds: 1));
      server.respond(oldShapeConfig(minAppVersion: '0.5.0'));
      expect((await AppVersionGate.evaluate()).required, isFalse,
          reason: 'a stale blocked decision must not outlive the TTL');
      expect(server.calls, 2);
    });

    test('after a success, a failure keeps the last known-good value only up to staleMax', () async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      expect((await AppVersionGate.evaluate()).required, isTrue);

      server.status = 500;
      clock.advance(AppVersionGate.cacheTtl + const Duration(minutes: 1));
      expect((await AppVersionGate.evaluate()).required, isTrue,
          reason: 'offline blip: keep the known-good decision');

      clock.advance(AppVersionGate.staleMax);
      expect((await AppVersionGate.evaluate()).required, isFalse,
          reason: 'too old to trust: fail open');
    });

    test('forceRefresh sees a lowered floor immediately', () async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      expect((await AppVersionGate.evaluate()).required, isTrue);
      server.respond(oldShapeConfig(minAppVersion: '1.0.0'));
      // cached decision still blocked...
      expect((await AppVersionGate.evaluate()).required, isTrue);
      // ...a forced refetch releases it.
      expect((await AppVersionGate.evaluate(forceRefresh: true)).required, isFalse);
    });

    test('concurrent loads share one request', () async {
      final gate = Completer<void>();
      server.hold = gate;
      final futures = [
        AppVersionGate.load(),
        AppVersionGate.load(),
        AppVersionGate.load(forceRefresh: true),
      ];
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait(futures);
      expect(server.calls, 1);
    });
  });

  group('malformed floors never block', () {
    Future<ForceUpdateDecision> evalWith(Map<String, dynamic> overrides) async {
      server.respond({...oldShapeConfig(), ...overrides});
      AppVersionGate.resetCacheForTests();
      AppVersionGate.clock = clock.call;
      AppVersionGate.debugPlatform = TargetPlatform.android;
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: '1.0.0',
        buildNumber: '10',
      );
      return AppVersionGate.evaluate();
    }

    const badFloors = <Object?>[
      'garbage',
      '',
      '   ',
      'v2.0.0',
      '1.x',
      '1..2',
      '-1.0.0',
      '-5',
      '999.0.0',
      '100.0.0',
      '10000.0',
      '1.2.3.4.5',
      '2.0.0-beta',
      '2,0,0',
      '٢.٠',
      '99999999999999999999.0.0',
      2,
      2.5,
      -2,
      true,
      false,
      <Object?>['2.0.0'],
      <String, Object?>{'v': '2.0.0'},
      null,
    ];
    for (final bad in badFloors) {
      test('min_app_version=${bad.runtimeType}:$bad is "no floor"', () async {
        final d = await evalWith({'min_app_version': bad});
        expect(d.required, isFalse);
      });
    }

    const badBuilds = <Object?>[
      -1,
      '-1',
      'abc',
      '',
      2.5,
      true,
      <Object?>[1],
      <String, Object?>{'x': 1},
      2100000001,
      '99999999999999999999999',
      9223372036854775807,
    ];
    for (final bad in badBuilds) {
      test('min_android_build=${bad.runtimeType}:$bad is "no floor"', () async {
        final d = await evalWith({'min_android_build': bad});
        expect(d.required, isFalse);
      });
    }

    test('missing fields / empty object / old-shape response never block', () async {
      for (final body in <Object?>[
        <String, dynamic>{},
        <String, dynamic>{'feature_flags': <String, dynamic>{}},
        oldShapeConfig(),
      ]) {
        server.respond(body);
        AppVersionGate.resetCacheForTests();
        AppVersionGate.clock = clock.call;
        AppVersionGate.debugPackageInfo = PackageInfo(
          appName: 'CarNet',
          packageName: 'com.carnetiq.app',
          version: '1.0.0',
          buildNumber: '10',
        );
        expect((await AppVersionGate.evaluate()).required, isFalse);
      }
    });

    test('wrong-typed messages / urls do not throw and cannot become the message', () async {
      final d = await evalWith({
        'min_app_version': '2.0.0',
        'force_update_message': <String, Object?>{'a': 1},
        'android_store_url': 12345,
      });
      expect(d.required, isTrue);
      expect(d.message, isNot(contains('{')));
      expect(d.message, isNotEmpty); // localized fallback
      expect(d.storeUrl, '');
    });

    test('fromJson never throws on hostile input', () {
      final hostile = <String, dynamic>{
        for (final k in [
          'min_app_version',
          'min_android_build',
          'min_ios_build',
          'force_update_message',
          'recommended_app_version',
          'recommended_android_build',
          'recommended_ios_build',
          'latest_app_version',
          'soft_update_message',
          'android_store_url',
          'ios_store_url',
        ])
          k: Object(),
      };
      final r = AppVersionRequirement.fromJson(hostile);
      expect(r.minAppVersion, '');
      expect(r.minAndroidBuild, isNull);
      expect(r.minIosBuild, isNull);
      expect(r.latestAppVersion, '');
    });

    test('unparseable installed version / build never block', () async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0', minAndroidBuild: 99));
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: '',
        buildNumber: '',
      );
      expect((await AppVersionGate.evaluate()).required, isFalse);
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: 'dev-build',
        buildNumber: 'x',
      );
      expect((await AppVersionGate.evaluate()).required, isFalse);
    });
  });

  group('valid floors', () {
    test('floor above the installed version blocks (old response shape)', () async {
      server.respond(oldShapeConfig(minAppVersion: '1.0.1'));
      final d = await AppVersionGate.evaluate();
      expect(d.required, isTrue);
      expect(d.message, 'Please update CarNet to continue.');
      expect(d.storeUrl, contains('play.google.com'));
    });

    test('floor equal to / below the installed version passes', () async {
      for (final floor in ['1.0.0', '1.0', '1', '0.9.9', '0.0.0']) {
        AppVersionGate.resetCacheForTests();
        AppVersionGate.clock = clock.call;
        AppVersionGate.debugPackageInfo = PackageInfo(
          appName: 'CarNet',
          packageName: 'com.carnetiq.app',
          version: '1.0.0',
          buildNumber: '10',
        );
        server.respond(oldShapeConfig(minAppVersion: floor));
        expect((await AppVersionGate.evaluate()).required, isFalse, reason: floor);
      }
    });

    test('installed -dev / +build suffixes compare numerically', () async {
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: '1.2.0-dev',
        buildNumber: '10',
      );
      server.respond(oldShapeConfig(minAppVersion: '1.2.0'));
      expect((await AppVersionGate.evaluate()).required, isFalse);
    });

    test('build-number floors use the platform field; 0 means no gate', () async {
      server.respond(oldShapeConfig(minAndroidBuild: 20, minIosBuild: 5));
      expect((await AppVersionGate.evaluate()).required, isTrue,
          reason: 'android build 10 < 20');

      AppVersionGate.resetCacheForTests();
      AppVersionGate.clock = clock.call;
      AppVersionGate.debugPlatform = TargetPlatform.iOS;
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: '1.0.0',
        buildNumber: '10',
      );
      expect((await AppVersionGate.evaluate()).required, isFalse,
          reason: 'ios build 10 >= 5 (android floor ignored)');

      AppVersionGate.resetCacheForTests();
      AppVersionGate.clock = clock.call;
      AppVersionGate.debugPlatform = TargetPlatform.android;
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: '1.0.0',
        buildNumber: '10',
      );
      server.respond(oldShapeConfig(minAndroidBuild: 0));
      expect((await AppVersionGate.evaluate()).required, isFalse);
    });

    test('a 18-digit iOS build floor parses and compares', () async {
      AppVersionGate.debugPlatform = TargetPlatform.iOS;
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: '1.0.0',
        buildNumber: '123456789012345677',
      );
      server.respond(oldShapeConfig(minIosBuild: 123456789012345678));
      expect((await AppVersionGate.evaluate()).required, isTrue);
    });

    test('soft prompt (recommended) still works and is never "required"', () async {
      final body = oldShapeConfig(recommended: '1.1.0');
      server.respond(body);
      final d = await AppVersionGate.evaluate();
      expect(d.required, isFalse);
      expect(d.softRecommended, isTrue);
      expect(d.softPromptKey, '1.1.0');
    });
  });

  group('latest-aware escape', () {
    Map<String, dynamic> cfg({
      String min = '',
      String latest = '',
      int? minBuild,
    }) =>
        {
          ...oldShapeConfig(minAppVersion: min, minAndroidBuild: minBuild),
          'latest_app_version': latest,
        };

    test('floor above the server-declared latest is ignored (fail open)', () async {
      server.respond(cfg(min: '5.0.0', latest: '1.2.0'));
      expect((await AppVersionGate.evaluate()).required, isFalse);
    });

    test('floor <= latest still blocks an older install', () async {
      server.respond(cfg(min: '1.1.0', latest: '1.2.0'));
      expect((await AppVersionGate.evaluate()).required, isTrue);
    });

    test('a device already on the latest version is never hard-blocked', () async {
      // Build floor the store can never satisfy for this version (e.g. a
      // mistyped build number), but the device is on `latest`: no dead end.
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: '1.2.0',
        buildNumber: '10',
      );
      server.respond(cfg(min: '1.2.0', latest: '1.2.0', minBuild: 99999));
      expect((await AppVersionGate.evaluate()).required, isFalse);
    });

    test('a device beyond latest (e.g. beta) is not blocked either', () async {
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: '1.3.0',
        buildNumber: '10',
      );
      server.respond(cfg(latest: '1.2.0', minBuild: 99999));
      expect((await AppVersionGate.evaluate()).required, isFalse);
    });

    test('without a latest marker the build floor still applies', () async {
      server.respond(cfg(minBuild: 99999));
      expect((await AppVersionGate.evaluate()).required, isTrue);
    });

    test('garbage latest is ignored, not trusted to bypass the gate', () async {
      server.respond(cfg(min: '1.5.0', latest: 'abc'));
      expect((await AppVersionGate.evaluate()).required, isTrue);
    });
  });

  group('store URL safety', () {
    test('sanitizeStoreUrl only lets real store-ish URLs through', () {
      expect(AppVersionGate.sanitizeStoreUrl(' https://apps.apple.com/app/id1 '),
          'https://apps.apple.com/app/id1');
      expect(AppVersionGate.sanitizeStoreUrl('market://details?id=com.carnetiq.app'),
          startsWith('market://'));
      for (final bad in <Object?>[
        '',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'ftp://x.example/a',
        'https://',
        'https://a b.example',
        'nope',
        null,
        42,
      ]) {
        expect(AppVersionGate.sanitizeStoreUrl(bad), '', reason: '$bad');
      }
    });

    test('a malformed URL from the server becomes "no update button"', () async {
      server.respond(oldShapeConfig(
        minAppVersion: '2.0.0',
        androidStoreUrl: 'javascript:alert(1)',
      ));
      final d = await AppVersionGate.evaluate();
      expect(d.required, isTrue);
      expect(d.storeUrl, '');
    });
  });

  group('resume re-check policy (fake clock)', () {
    test('never within minResumeGap of the previous attempt', () async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      await AppVersionGate.evaluate();
      expect(AppVersionGate.shouldRecheckOnResume(blocked: true), isFalse);
      clock.advance(AppVersionGate.minResumeGap - const Duration(seconds: 1));
      expect(AppVersionGate.shouldRecheckOnResume(blocked: true), isFalse);
      clock.advance(const Duration(seconds: 2));
      expect(AppVersionGate.shouldRecheckOnResume(blocked: true), isTrue);
    });

    test('not blocked: only once the last success is >= cacheTtl old', () async {
      await AppVersionGate.evaluate();
      clock.advance(const Duration(minutes: 14));
      expect(AppVersionGate.shouldRecheckOnResume(blocked: false), isFalse);
      clock.advance(const Duration(minutes: 1, seconds: 1));
      expect(AppVersionGate.shouldRecheckOnResume(blocked: false), isTrue);
    });

    test('no successful fetch yet: re-check (after the gap), keep trying', () async {
      server.status = 500;
      await AppVersionGate.evaluate();
      expect(AppVersionGate.shouldRecheckOnResume(blocked: false), isFalse);
      clock.advance(AppVersionGate.minResumeGap + const Duration(seconds: 1));
      expect(AppVersionGate.shouldRecheckOnResume(blocked: false), isTrue);
    });

    test('simulated resume storm issues at most one request per gap', () async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      await AppVersionGate.evaluate();
      var fetches = 0;
      // 600 resumes, one per second for 10 minutes, user stays blocked.
      for (var i = 0; i < 600; i++) {
        clock.advance(const Duration(seconds: 1));
        if (AppVersionGate.shouldRecheckOnResume(blocked: true)) {
          fetches++;
          await AppVersionGate.evaluate(forceRefresh: true);
        }
      }
      expect(fetches, lessThanOrEqualTo(60));
      expect(server.calls, 1 + fetches);
    });
  });

  test('Accept-Language still sent (MI-03) on the config request', () async {
    await AppVersionGate.evaluate();
    expect(server.requestHeaders.single.keys.map((k) => k.toLowerCase()),
        contains('accept-language'));
  });
}
