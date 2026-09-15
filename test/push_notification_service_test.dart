// Regression tests for F-08: `PushNotificationService.syncTokenWithBackend`'s
// outer backend-registration-failure catch must be observable in production
// (via `logNonFatal`, which reports to Sentry), not just printed in debug
// builds — see PRODUCTION_AUDIT.md F-08.
//
// Scope is intentionally narrow (observability only): these tests prove the
// failure path still swallows the exception, still writes
// `push_last_sync_error` exactly as before, and now also reports the
// failure via `logNonFatal` with an error + stack trace and no sensitive
// payload (FCM token / Authorization header) attached. They do not exercise
// retry scheduling, `push_enabled` semantics, `syncNowForDiagnostics()`, or
// token-acquisition behavior — those are unchanged and out of scope.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/push_notification_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/debug/app_log.dart';

/// One captured invocation of `logNonFatal` (via [debugLogNonFatalOverride]).
class _ReportedNonFatal {
  _ReportedNonFatal(this.error, this.stackTrace, this.context);
  final Object error;
  final StackTrace? stackTrace;
  final String? context;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secretToken = 'super-secret-fcm-token-should-never-be-reported';

  final reported = <_ReportedNonFatal>[];

  http.Response jsonResponse(int status, Object body) => http.Response(
        json.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  /// Binds a [MockClient] as `ApiService`'s HTTP transport for one test.
  void useClient(MockClient client) {
    ApiService.testHttpClient = client;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    reported.clear();
    debugLogNonFatalOverride = (error, stackTrace, context) {
      reported.add(_ReportedNonFatal(error, stackTrace, context));
    };

    // Keep tokens entirely in-memory (no secure-storage / Firebase plugin
    // channels available in a unit-test binary).
    TokenStore.testMode = true;
    TokenStore.resetForTests();
    await TokenStore.savePushToken(secretToken);
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    debugLogNonFatalOverride = null;
    ApiService.testHttpClient = null;
    await ApiService.clearTokens();
    TokenStore.resetForTests();
    TokenStore.testMode = false;
  });

  test(
    'backend registration failure (500) is swallowed, not rethrown',
    () async {
      useClient(
        MockClient((request) async {
          if (request.url.path == '/api/users/push_token') {
            return jsonResponse(500, {'message': 'server exploded'});
          }
          return jsonResponse(200, <String, dynamic>{});
        }),
      );

      // Must complete normally — existing callers (bootstrap.dart's
      // onTokenRefresh listener, and login/reconnect call sites) invoke this
      // without a surrounding try/catch and rely on it never throwing.
      await expectLater(
        PushNotificationService.syncTokenWithBackend(),
        completes,
      );
    },
  );

  test(
    'backend registration failure (500) still writes push_last_sync_error',
    () async {
      useClient(
        MockClient((request) async {
          if (request.url.path == '/api/users/push_token') {
            return jsonResponse(500, {'message': 'server exploded'});
          }
          return jsonResponse(200, <String, dynamic>{});
        }),
      );

      await PushNotificationService.syncTokenWithBackend();

      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('push_last_sync_error'), isNotNull);
      expect(sp.getString('push_last_sync_error'), contains('server exploded'));
    },
  );

  test(
    'backend registration failure (500) invokes logNonFatal with error + stack trace',
    () async {
      useClient(
        MockClient((request) async {
          if (request.url.path == '/api/users/push_token') {
            return jsonResponse(500, {'message': 'server exploded'});
          }
          return jsonResponse(200, <String, dynamic>{});
        }),
      );

      await PushNotificationService.syncTokenWithBackend();

      expect(reported, hasLength(1));
      final r = reported.single;
      expect(r.context, 'PushNotificationService.syncTokenWithBackend');
      expect(r.error, isA<ApiException>());
      expect((r.error as ApiException).statusCode, 500);
      expect(r.stackTrace, isNotNull);
    },
  );

  test(
    'transport failure (offline / SocketException) is swallowed and reported the same way',
    () async {
      useClient(
        MockClient((request) async {
          throw const SocketException('Failed host lookup');
        }),
      );

      await expectLater(
        PushNotificationService.syncTokenWithBackend(),
        completes,
      );

      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('push_last_sync_error'), isNotNull);
      expect(sp.getString('push_last_sync_error'), contains('Failed host lookup'));

      expect(reported, hasLength(1));
      final r = reported.single;
      expect(r.context, 'PushNotificationService.syncTokenWithBackend');
      expect(r.error, isA<SocketException>());
      expect(r.stackTrace, isNotNull);
    },
  );

  test(
    'success path: push_last_sync_ok set, push_last_sync_error cleared, no telemetry generated',
    () async {
      // Seed a stale error from a hypothetical earlier failed attempt to
      // prove the success path still clears it, unchanged.
      SharedPreferences.setMockInitialValues({
        'push_last_sync_error': 'stale-error-from-earlier-attempt',
      });
      useClient(
        MockClient((request) async {
          if (request.url.path == '/api/users/push_token') {
            return jsonResponse(200, {'success': true});
          }
          return jsonResponse(200, <String, dynamic>{});
        }),
      );

      await PushNotificationService.syncTokenWithBackend();

      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('push_last_sync_ok'), isNotNull);
      expect(sp.getString('push_last_sync_error'), isNull);
      expect(reported, isEmpty);
    },
  );

  test(
    'no FCM token value or Authorization header reaches logNonFatal',
    () async {
      useClient(
        MockClient((request) async {
          if (request.url.path == '/api/users/push_token') {
            return jsonResponse(500, {'message': 'server exploded'});
          }
          return jsonResponse(200, <String, dynamic>{});
        }),
      );

      await PushNotificationService.syncTokenWithBackend();

      expect(reported, hasLength(1));
      final reportedText = reported.single.error.toString();
      expect(reportedText, isNot(contains(secretToken)));
      expect(reportedText.toLowerCase(), isNot(contains('bearer')));
      expect(reportedText.toLowerCase(), isNot(contains('authorization')));
    },
  );

  test(
    'fire-and-forget callers (no surrounding try/catch) never see an exception',
    () async {
      useClient(
        MockClient((request) async {
          throw Exception('simulated crash mid-request');
        }),
      );

      // Mirrors real call sites that await this with no try/catch at all
      // (e.g. the `onTokenRefresh` listener and the post-login/reconnect
      // call sites in auth_service.dart) — reaching the line below proves
      // it did not throw.
      await PushNotificationService.syncTokenWithBackend();

      expect(reported, hasLength(1));
      expect(reported.single.context, 'PushNotificationService.syncTokenWithBackend');
    },
  );
}
