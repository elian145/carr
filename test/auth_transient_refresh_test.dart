// Regression tests for the "false upload failure after backgrounding" bug.
//
// Real-device bug (Galaxy A17): after the app had been backgrounded, the
// first authenticated request got a 401, the follow-up token refresh failed
// only because the network was not back yet, and every caller treated
// "refresh returned false" as "the session is dead": it wiped the stored
// tokens and threw a NON-retryable error. For a pending Sell submission
// that classified a healthy upload as permanently failed, and it logged the
// seller out of a valid session ("Failed to load user data").
//
// These tests pin down the corrected behaviour:
//   * a TRANSIENT refresh failure keeps the tokens and surfaces a retryable
//     error;
//   * a DEFINITIVE refresh rejection still clears the session;
//   * a stranded profile (token present, /auth/me budget spent while
//     backgrounded) is recovered on foreground.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(int status, Object body) => http.Response(
  json.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    TokenStore.testMode = true;
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDown(() async {
    ApiService.testHttpClient = null;
    AuthService.debugProfileRetryDelaysOverride = null;
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  /// Every authenticated endpoint answers 401 (expired access token);
  /// `/auth/refresh` behaves as [refresh].
  MockClient expiredAccessClient(
    Future<http.Response> Function() refresh,
  ) => MockClient((request) async {
    if (request.url.path == '/api/auth/refresh') return refresh();
    return _json(401, {'message': 'Token has expired'});
  });

  test(
    'T1. 401 + refresh fails with a network error: tokens are KEPT and a '
    'retryable error is thrown (not a permanent "Authentication failed")',
    () async {
      ApiService.testHttpClient = expiredAccessClient(
        () async => throw const SocketException('radio asleep'),
      );
      await ApiService.setTokens(
        accessToken: 'access_a',
        refreshToken: 'refresh_a',
      );

      Object? error;
      try {
        await ApiService.getProfile();
      } catch (e) {
        error = e;
      }

      expect(error, isA<ApiException>());
      expect((error as ApiException).statusCode, 503);
      expect(
        isRetryableSellSubmissionError(error),
        isTrue,
        reason: 'a pending submission must keep retrying, not need attention',
      );
      expect(ApiService.lastRefreshWasTransient, isTrue);
      expect(
        ApiService.accessToken,
        'access_a',
        reason: 'a transient refresh failure must not log the seller out',
      );
      expect(ApiService.isAuthenticated, isTrue);
    },
  );

  test(
    'T2. 401 + refresh answered 503: same -- tokens kept, retryable error',
    () async {
      ApiService.testHttpClient = expiredAccessClient(
        () async => _json(503, {'message': 'warming up'}),
      );
      await ApiService.setTokens(
        accessToken: 'access_b',
        refreshToken: 'refresh_b',
      );

      Object? error;
      try {
        await ApiService.getProfile();
      } catch (e) {
        error = e;
      }
      expect(error, isA<ApiException>());
      expect(isRetryableSellSubmissionError(error!), isTrue);
      expect(ApiService.accessToken, 'access_b');
    },
  );

  test(
    'T3. 401 + the server DEFINITIVELY rejects the refresh token (401): the '
    'session is still cleared (genuine failures are preserved)',
    () async {
      ApiService.testHttpClient = expiredAccessClient(
        () async => _json(401, {'message': 'Refresh token revoked'}),
      );
      await ApiService.setTokens(
        accessToken: 'access_c',
        refreshToken: 'refresh_c',
      );

      Object? error;
      try {
        await ApiService.getProfile();
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(ApiService.lastRefreshWasTransient, isFalse);
      expect(ApiService.accessToken, isNull);
      expect(ApiService.isAuthenticated, isFalse);
      expect(
        isRetryableSellSubmissionError(error!),
        isFalse,
        reason: 'a revoked session is a genuine, permanent failure',
      );
    },
  );

  test(
    'T4. profile refresh failure after backgrounding: the retry budget is '
    'spent so the session is stranded; recoverStrandedProfile() on '
    'foreground restores it without logging out',
    () async {
      AuthService.debugProfileRetryDelaysOverride = const [Duration.zero];
      var meCalls = 0;
      var networkUp = false;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCalls++;
          if (!networkUp) throw const SocketException('radio asleep');
          return _json(200, {
            'id': 7,
            'username': 'seller',
            'account_type': 'individual',
          });
        }
        return _json(200, <String, dynamic>{});
      });
      await ApiService.setTokens(
        accessToken: 'access_d',
        refreshToken: 'refresh_d',
      );

      await AuthService().initialize();
      // Let the bounded automatic retries run out (3 attempts, zero delay).
      for (var i = 0; i < 40 && meCalls < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(meCalls, 4, reason: '1 initial + 3 bounded retries');
      expect(AuthService().isAuthenticated, isFalse);
      expect(AuthService().isProfileStranded, isTrue);
      expect(ApiService.accessToken, 'access_d', reason: 'token kept');

      // No more automatic attempts -- stranded for good without a trigger.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(meCalls, 4);

      // Foregrounded, network back.
      networkUp = true;
      await AuthService().recoverStrandedProfile();
      expect(AuthService().isAuthenticated, isTrue);
      expect(AuthService().currentUser?['username'], 'seller');
      expect(AuthService().isProfileStranded, isFalse);
    },
  );

  test(
    'T5. recoverStrandedProfile() is a no-op when the session is healthy or '
    'there is no token (never creates extra /auth/me traffic)',
    () async {
      var meCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') meCalls++;
        return _json(200, {'id': 1, 'username': 'u'});
      });

      // No token at all.
      await AuthService().recoverStrandedProfile();
      expect(meCalls, 0);

      // Healthy session.
      await AuthService().adoptTestSession();
      await AuthService().recoverStrandedProfile();
      expect(meCalls, 0);
    },
  );
}
