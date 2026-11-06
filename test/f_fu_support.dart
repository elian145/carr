// Shared fakes for the force-update hardening tests (test/f_fu_*).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/app_version_gate.dart';

/// Scriptable fake `/api/config/app` server.
class FakeConfigServer {
  FakeConfigServer([Map<String, dynamic>? initial]) {
    body = initial ?? <String, dynamic>{};
  }

  /// JSON-encodable body (or a raw String when [rawBody] is set).
  Object? body;
  String? rawBody;
  int status = 200;

  /// When set, the request throws this instead of answering.
  Object? failWith;

  /// When set, the response is held until it completes.
  Completer<void>? hold;

  int calls = 0;
  final List<Map<String, String>> requestHeaders = [];

  void respond(Object? newBody) {
    body = newBody;
    rawBody = null;
    status = 200;
    failWith = null;
  }

  MockClient client() {
    return MockClient((request) async {
      if (request.url.path != '/api/config/app') {
        return http.Response('{}', 200);
      }
      calls++;
      requestHeaders.add(Map<String, String>.from(request.headers));
      final gate = hold;
      if (gate != null) await gate.future;
      final err = failWith;
      if (err != null) throw err;
      return http.Response(
        rawBody ?? json.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }
}

/// A clock tests can move forward.
class FakeClock {
  FakeClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 11, 6, 12);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

http.Client? _originalClient;

/// Installs [server] as the HTTP client, a fake clock and a fixed installed
/// build. Pair with [tearDownGateFakes].
FakeClock setUpGateFakes(
  FakeConfigServer server, {
  String version = '1.0.0',
  String build = '10',
  TargetPlatform platform = TargetPlatform.android,
}) {
  _originalClient = ApiService.boundTestHttpClient;
  ApiService.testHttpClient = server.client();
  AppVersionGate.resetCacheForTests();
  // ApiService keeps a process-wide GET stale-while-revalidate cache (used on
  // timeouts only); isolate tests from each other.
  ApiService.debugResetTimeoutPolicy();
  final clock = FakeClock();
  AppVersionGate.clock = clock.call;
  AppVersionGate.debugPlatform = platform;
  AppVersionGate.debugPackageInfo = PackageInfo(
    appName: 'CarNet',
    packageName: 'com.carnetiq.app',
    version: version,
    buildNumber: build,
  );
  return clock;
}

void tearDownGateFakes() {
  ApiService.testHttpClient = _originalClient;
  ApiService.debugResetTimeoutPolicy();
  AppVersionGate.resetCacheForTests();
}

/// A response shaped like the pre-hardening server (no `latest_app_version`).
Map<String, dynamic> oldShapeConfig({
  String minAppVersion = '',
  int? minAndroidBuild,
  int? minIosBuild,
  String recommended = '',
  String androidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.carnetiq.app',
  String iosStoreUrl = '',
}) =>
    <String, dynamic>{
      'min_app_version': minAppVersion,
      'min_android_build': minAndroidBuild,
      'min_ios_build': minIosBuild,
      'force_update_message': 'Please update CarNet to continue.',
      'recommended_app_version': recommended,
      'recommended_android_build': null,
      'recommended_ios_build': null,
      'soft_update_message': 'A newer version of CarNet is available.',
      'android_store_url': androidStoreUrl,
      'ios_store_url': iosStoreUrl,
      'listing_require_approval': false,
      'feature_flags': <String, dynamic>{
        'sell': true,
        'chat': true,
        'dealers': true,
        'comparison': true,
        'saved_searches': true,
      },
    };
