import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';

import 'fake_api_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  test('adoptTestSession sets authenticated user without HTTP', () async {
    await AuthService().adoptTestSession();
    expect(AuthService().isAuthenticated, isTrue);
    expect(AuthService().currentUser?['username'], 'test');
    expect(ApiService.isAuthenticated, isTrue);
  });

  test('resetTestSession clears auth flags', () async {
    await AuthService().adoptTestSession();
    AuthService().resetTestSession();
    expect(AuthService().isAuthenticated, isFalse);
    expect(AuthService().currentUser, isNull);
  });

  test('login via mock API sets authenticated user', () async {
    await AuthService().login('testuser', 'secret');
    expect(AuthService().isAuthenticated, isTrue);
    expect(AuthService().currentUser?['username'], 'test');
  });

  test('userMapFrom accepts generic Map payloads from JSON', () {
    final raw = <dynamic, dynamic>{'username': 'elian', 'id': 'abc123'};
    expect(AuthService.userMapFrom(raw)?['username'], 'elian');
  });

  test('userMapFrom stringifies numeric user ids', () {
    final raw = <String, dynamic>{'username': 'buyer', 'id': 1};
    expect(AuthService.userMapFrom(raw)?['id'], '1');
    expect(AuthService().userId, isNull);
  });

  test('login survives stale profile load from startup init', () async {
    await ApiService.setTokens(
      accessToken: 'stale_access_token',
      refreshToken: 'stale_refresh_token',
    );
    final initFuture = AuthService().initialize();
    final loginFuture = AuthService().login('testuser', 'secret');
    await Future.wait([initFuture, loginFuture]);
    expect(AuthService().isAuthenticated, isTrue);
    expect(AuthService().currentUser?['username'], 'test');
    expect(ApiService.accessToken, 'test_access_token');
  });

  // --------------------------------------------------------------------
  // Regression tests: transient (non-401) /auth/me failure must not
  // permanently strand ApiService.isAuthenticated == true while
  // AuthService.isAuthenticated stays false forever (production bug that
  // left AuthGuard-protected pages, e.g. Chat, spinning indefinitely).
  // --------------------------------------------------------------------

  http.Response _jsonResponse(int status, Object body) => http.Response(
        json.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  /// A minimal `/auth/me`-only mock client: the Nth call (1-indexed) returns
  /// [firstStatus]; every call after that returns 200 with a valid profile.
  /// Any other endpoint is stubbed with an empty 200 (not exercised by these
  /// tests — `_loadUserProfile()` only calls `/auth/me`).
  MockClient _profileFlakyThenOkClient({required int firstStatus}) {
    var call = 0;
    return MockClient((request) async {
      if (request.url.path == '/api/auth/me') {
        call++;
        if (call == 1) {
          return firstStatus == 401
              ? _jsonResponse(401, {'message': 'Token has expired'})
              : _jsonResponse(firstStatus, {'message': 'temporary failure'});
        }
        return _jsonResponse(200, {
          'id': 1,
          'username': 'testuser',
          'account_type': 'individual',
        });
      }
      return _jsonResponse(200, <String, dynamic>{});
    });
  }

  test(
    'A: existing valid authentication still succeeds normally',
    () async {
      await ApiService.setTokens(
        accessToken: 'good_token',
        refreshToken: 'good_refresh',
      );
      await AuthService().initialize();
      expect(AuthService().isAuthenticated, isTrue);
      expect(AuthService().currentUser?['username'], 'testuser');
      expect(ApiService.isAuthenticated, isTrue);
    },
  );

  test(
    'B+C: a transient non-401 /auth/me failure does not permanently strand '
    'the session, and the bounded auto-retry recovers it',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);

      ApiService.testHttpClient = _profileFlakyThenOkClient(firstStatus: 500);
      await ApiService.setTokens(
        accessToken: 'flaky_token',
        refreshToken: 'flaky_refresh',
      );

      await AuthService().initialize();

      // Immediately after the transient failure: token must NOT be cleared
      // (this is not a real auth failure), but the profile-derived
      // `isAuthenticated` flag has not been set yet — this is exactly the
      // `ApiService.isAuthenticated == true && AuthService.isAuthenticated
      // == false` combination that used to strand AuthGuard forever.
      expect(ApiService.isAuthenticated, isTrue);
      expect(ApiService.accessToken, 'flaky_token');
      expect(AuthService().isAuthenticated, isFalse);

      // The bounded internal retry (first attempt delay: 2s) must recover
      // the session on its own, with no external caller (e.g. AuthGuard)
      // ever needing to invoke anything.
      await Future.delayed(const Duration(seconds: 3));

      expect(AuthService().isAuthenticated, isTrue);
      expect(AuthService().currentUser?['username'], 'testuser');
    },
  );

  test(
    'D: a genuine 401 on /auth/me still clears auth state',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);

      ApiService.testHttpClient = _profileFlakyThenOkClient(firstStatus: 401);
      await ApiService.setTokens(
        accessToken: 'expired_token',
        refreshToken: 'expired_refresh',
      );

      await AuthService().initialize();

      // A real 401 must still clear the session immediately — no retry,
      // no lingering authenticated token.
      expect(AuthService().isAuthenticated, isFalse);
      expect(ApiService.isAuthenticated, isFalse);
      expect(ApiService.accessToken, isNull);
    },
  );

  // --------------------------------------------------------------------
  // Regression tests: the automatic profile retry must fail fast (bounded
  // warm timeout) instead of inheriting ApiService's ~55s cold-start
  // budget on every attempt, which could otherwise stretch the retry
  // cascade to minutes. See ApiService.warmRequestTimeout / getProfile().
  // --------------------------------------------------------------------

  test(
    'E: warmRequestTimeout is the same 20s warm timeout the retry path relies on',
    () {
      expect(ApiService.warmRequestTimeout, const Duration(seconds: 20));
    },
  );

  test(
    'F: getProfile(timeout: ...) bounds the whole call instead of the '
    'adaptive (cold-start) timeout',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);

      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          // Simulate a slow/cold-starting backend far longer than our bound.
          await Future.delayed(const Duration(seconds: 2));
          return _jsonResponse(200, {'id': 1, 'username': 'testuser'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      await ApiService.setTokens(
        accessToken: 'bounded_token',
        refreshToken: 'bounded_refresh',
      );

      final stopwatch = Stopwatch()..start();
      await expectLater(
        ApiService.getProfile(timeout: const Duration(milliseconds: 300)),
        throwsA(isA<TimeoutException>()),
      );
      stopwatch.stop();

      // The explicit bound must win over the (much longer) real response —
      // proves this is not merely passed through to the adaptive timeout.
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));
    },
  );

  test(
    'G: a 401 whose refresh attempt fails outright still clears auth '
    'state and does NOT schedule a retry',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(milliseconds: 40),
      ];
      addTearDown(() => AuthService.debugProfileRetryDelaysOverride = null);

      var meCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCalls++;
          return _jsonResponse(401, {'message': 'Token has expired'});
        }
        // No explicit /api/auth/refresh handler: falls through to the
        // generic 200-with-empty-body stub below, so _refreshAccessToken()
        // finds no access_token in the response and fails — the realistic
        // "refresh token is also no longer valid" case already covered by
        // test D, extended here to also assert no retry gets scheduled.
        return _jsonResponse(200, <String, dynamic>{});
      });

      await ApiService.setTokens(
        accessToken: 'about_to_expire',
        refreshToken: 'no_longer_valid_refresh',
      );

      await AuthService().initialize();

      expect(AuthService().isAuthenticated, isFalse);
      expect(ApiService.isAuthenticated, isFalse);
      expect(ApiService.accessToken, isNull);
      expect(meCalls, 1);

      // No retry must have been scheduled for a 401 — wait past the
      // (overridden, tiny) retry delay and confirm /auth/me is never
      // called again.
      await Future.delayed(const Duration(milliseconds: 200));
      expect(meCalls, 1);
      expect(AuthService().isAuthenticated, isFalse);
    },
  );

  test(
    'H: automatic retry is bounded at exactly 3 attempts',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(milliseconds: 20),
        Duration(milliseconds: 20),
        Duration(milliseconds: 20),
      ];
      addTearDown(() => AuthService.debugProfileRetryDelaysOverride = null);

      var meCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCalls++;
          return _jsonResponse(500, {'message': 'always failing'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });

      await ApiService.setTokens(
        accessToken: 'always_failing_token',
        refreshToken: 'always_failing_refresh',
      );

      await AuthService().initialize();
      // Give every scheduled retry (20ms apart) plenty of time to fire,
      // plus extra margin to prove nothing further gets scheduled.
      await Future.delayed(const Duration(milliseconds: 400));

      // Initial attempt + exactly 3 retries = 4 total, then it must stop.
      expect(meCalls, 4);
      expect(AuthService().isAuthenticated, isFalse);
    },
  );

  test(
    'I: logout clears the pending-retry flag so a new session is never '
    'blocked by an old, still-pending retry timer',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(milliseconds: 300),
      ];
      addTearDown(() => AuthService.debugProfileRetryDelaysOverride = null);

      final meCallsByToken = <String>[];
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCallsByToken.add(ApiService.accessToken ?? '');
          return _jsonResponse(500, {'message': 'fail'});
        }
        if (request.url.path == '/api/auth/logout') {
          return _jsonResponse(200, {'message': 'logged out'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });

      // Old session fails once and schedules a retry ~300ms out.
      await ApiService.setTokens(
        accessToken: 'old_token',
        refreshToken: 'old_refresh',
      );
      await AuthService().refreshProfile();
      expect(AuthService().isAuthenticated, isFalse);

      // Log out well before that retry fires. This must reset
      // _profileRetryScheduled (in addition to clearing the token).
      await AuthService().logout();
      expect(ApiService.accessToken, isNull);

      // New session, different token, also fails once immediately after.
      // Because logout reset _profileRetryScheduled, this can schedule its
      // OWN retry right away instead of being blocked by the still-pending
      // old timer.
      await ApiService.setTokens(
        accessToken: 'new_token',
        refreshToken: 'new_refresh',
      );
      await AuthService().refreshProfile();
      expect(AuthService().isAuthenticated, isFalse);

      // Let both the stale old-session timer and the new session's own
      // retry fire.
      await Future.delayed(const Duration(milliseconds: 900));

      // The stale old-session retry must never re-run (token-identity
      // guard from the original fix) — only the one original call exists.
      expect(meCallsByToken.where((t) => t == 'old_token').length, 1);
      // The new session's own retry must have gotten a chance to run.
      expect(
        meCallsByToken.where((t) => t == 'new_token').length,
        greaterThanOrEqualTo(2),
      );
      expect(ApiService.accessToken, 'new_token');
      // Still failing (mock always 500) — no authentication bypass.
      expect(AuthService().isAuthenticated, isFalse);
    },
  );

  // --------------------------------------------------------------------
  // Regression tests: `Future.timeout()` does not cancel the underlying
  // `/auth/me` HTTP request it wraps, so without a single-flight guard a
  // slow/hanging backend could let the bounded retry fire additional,
  // genuinely overlapping `/auth/me` requests while an earlier one is
  // still in flight. These use a manually-controlled `Completer` (never
  // an instantly-resolving mock) to actually hold a request pending, so
  // the tests prove real concurrency behavior rather than timing luck.
  // --------------------------------------------------------------------

  test(
    'J: two profile-load attempts while a real request is still pending '
    'share the same underlying request instead of issuing a second one',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);

      final gate = Completer<void>();
      var meCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCalls++;
          await gate.future; // stays pending until the test releases it.
          return _jsonResponse(200, {
            'id': 1,
            'username': 'shared_user',
          });
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await ApiService.setTokens(
        accessToken: 'shared_token',
        refreshToken: 'shared_refresh',
      );

      // Two logically-independent callers (e.g. the initial load racing a
      // manual pull-to-refresh, or two overlapping retry attempts) start
      // "at the same time" while the real HTTP response is still pending.
      final f1 = AuthService().refreshProfile();
      final f2 = AuthService().refreshProfile();

      // Give both calls a chance to reach (and block on) the gated mock.
      await Future.delayed(const Duration(milliseconds: 50));
      expect(
        meCalls,
        1,
        reason:
            'a second concurrent profile load must not start a second '
            'real HTTP request while the first is still pending',
      );

      gate.complete();
      await Future.wait([f1, f2]);

      // Still exactly one real call after both callers observed the result.
      expect(meCalls, 1);
      expect(AuthService().isAuthenticated, isTrue);
      expect(AuthService().currentUser?['username'], 'shared_user');
    },
  );

  test(
    'K: after the shared in-flight request completes, a later profile '
    'load starts a brand-new request normally',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);

      var gate = Completer<void>();
      var meCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCalls++;
          await gate.future;
          return _jsonResponse(200, {
            'id': 1,
            'username': 'sequential_user',
          });
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await ApiService.setTokens(
        accessToken: 'sequential_token',
        refreshToken: 'sequential_refresh',
      );

      final f1 = AuthService().refreshProfile();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(meCalls, 1);
      gate.complete();
      await f1;
      expect(meCalls, 1);

      // The in-flight slot must now be clear: a later call issues its OWN
      // new HTTP request rather than reusing the finished one forever.
      gate = Completer<void>();
      final f2 = AuthService().refreshProfile();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(
        meCalls,
        2,
        reason: 'a call after the shared request finished must start a '
            'fresh HTTP request, not reuse the completed one indefinitely',
      );
      gate.complete();
      await f2;
      expect(meCalls, 2);
    },
  );

  test(
    'L: an error completion clears the in-flight slot so the next '
    'attempt can retry with a brand-new request',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);
      // Keep the automatic retry from interfering with this test's own
      // manual follow-up call.
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(seconds: 10),
      ];
      addTearDown(() => AuthService.debugProfileRetryDelaysOverride = null);

      var gate = Completer<void>();
      var meCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCalls++;
          await gate.future;
          return _jsonResponse(500, {'message': 'boom'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await ApiService.setTokens(
        accessToken: 'error_slot_token',
        refreshToken: 'error_slot_refresh',
      );

      // Two concurrent callers share the one pending (doomed) request.
      final f1 = AuthService().refreshProfile();
      final f2 = AuthService().refreshProfile();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(meCalls, 1);

      gate.complete();
      await Future.wait([f1, f2]);

      // The shared request failed, but only ONE real call was ever made
      // for both callers, and the failure did not authenticate anyone.
      expect(meCalls, 1);
      expect(AuthService().isAuthenticated, isFalse);

      // The slot must be cleared even though the shared request ended in
      // an error: a subsequent attempt must issue its own new request
      // rather than being permanently stuck reusing (or blocked behind) a
      // completed, failed Future.
      gate = Completer<void>();
      final f3 = AuthService().refreshProfile();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(
        meCalls,
        2,
        reason:
            'an error completion must clear the in-flight slot so the '
            'next attempt can retry normally',
      );
      gate.complete();
      await f3;
      expect(meCalls, 2);
      expect(AuthService().isAuthenticated, isFalse);
    },
  );

  test(
    'M: a still-pending request started under a replaced token is never '
    'adopted after the token changes without a logout — the new call '
    'always issues and gets its own response, never the stale one',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);

      final oldGate = Completer<void>();
      var meCallsOld = 0;
      var meCallsNew = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          final authHeader = request.headers['Authorization'] ?? '';
          if (authHeader.contains('old_switch_token')) {
            meCallsOld++;
            await oldGate.future;
            // If this were ever wrongly adopted by the new session, it
            // would surface as the wrong user below.
            return _jsonResponse(200, {'id': 999, 'username': 'old_user'});
          }
          meCallsNew++;
          return _jsonResponse(200, {'id': 1, 'username': 'new_user'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      addTearDown(() {
        if (!oldGate.isCompleted) oldGate.complete();
      });

      // Old session starts a real fetch that stays pending — the exact
      // "abandoned but still running in the background" shape the review
      // identified (a caller elsewhere may have already given up on it
      // via its own `.timeout()`, but the real request keeps going).
      await ApiService.setTokens(
        accessToken: 'old_switch_token',
        refreshToken: 'old_switch_refresh',
      );
      final staleFuture = AuthService().refreshProfile();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(meCallsOld, 1);

      // Simulate an out-of-band token replacement (e.g. a token refresh
      // elsewhere) *without* a full logout/_clearAuthState cycle, so the
      // stale old request is still genuinely tracked as "in flight" when
      // the new call starts — this is the exact condition the token-scoped
      // single-flight guard (not just logout's own state reset) must handle.
      await ApiService.setTokens(
        accessToken: 'new_switch_token',
        refreshToken: 'new_switch_refresh',
      );
      await AuthService().refreshProfile();

      // The new call must have made its OWN real request — never adopted
      // the still-pending old one.
      expect(meCallsNew, 1);
      expect(AuthService().isAuthenticated, isTrue);
      expect(AuthService().currentUser?['username'], 'new_user');

      // Now let the stale old request finally resolve. It must not be
      // able to retroactively touch the current (new) session's state.
      oldGate.complete();
      await staleFuture;
      expect(AuthService().isAuthenticated, isTrue);
      expect(AuthService().currentUser?['username'], 'new_user');
    },
  );

  // --------------------------------------------------------------------
  // Regression tests: startup-ordering fix. `AuthService.initialize()`
  // (and therefore `AuthGuard`, gated on `isLoading`/`isAuthenticated`)
  // must not wait for WebSocket connect or push-token sync — those run in
  // the background after the authentication decision is already final.
  // Firebase/PushNotificationService.initialize() and connectivity/locale
  // setup are not referenced by `AuthService` at all (see bootstrap.dart
  // for the ordering change), which every test in this file already
  // demonstrates implicitly: none of them ever initialize Firebase, yet
  // `AuthService().initialize()` still completes and authenticates.
  // --------------------------------------------------------------------

  test(
    'N: isLoading/isAuthenticated are decided as soon as the profile fetch '
    'resolves, without waiting for the background push-token sync it '
    'kicks off next',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);

      SharedPreferences.setMockInitialValues({'push_enabled': true});
      await TokenStore.savePushToken('gated_push_token');
      addTearDown(() => TokenStore.savePushToken(null));

      final pushGate = Completer<void>();
      var meCalls = 0;
      var pushCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCalls++;
          return _jsonResponse(200, {'id': 1, 'username': 'testuser'});
        }
        if (request.url.path == '/api/users/push_token') {
          pushCalls++;
          // Simulate a slow backend for push-token registration — this
          // must never be able to delay the auth decision above it.
          await pushGate.future;
          return _jsonResponse(200, {'message': 'ok'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      addTearDown(() {
        if (!pushGate.isCompleted) pushGate.complete();
      });

      await ApiService.setTokens(
        accessToken: 'startup_token',
        refreshToken: 'startup_refresh',
      );

      // initialize() must return promptly: it must NOT be waiting on the
      // still-pending (gated) push-token sync it triggers in the
      // background. A regression here would hang until pushGate resolves.
      await AuthService().initialize().timeout(const Duration(seconds: 5));

      expect(AuthService().isLoading, isFalse);
      expect(AuthService().isAuthenticated, isTrue);
      expect(AuthService().currentUser?['username'], 'testuser');
      expect(meCalls, 1);

      // The background push-token sync starts shortly after (proving it
      // still runs for an authenticated session), but reaching the mock
      // HTTP layer takes a few more microtask turns (SharedPreferences,
      // TokenStore reads) than `initialize()` itself waited for above —
      // which is exactly the point: those turns happened *after*
      // `initialize()` had already returned, not before.
      await Future.delayed(const Duration(milliseconds: 50));
      expect(pushCalls, 1);
      // Still gated/pending; still hasn't disturbed the auth decision.
      expect(AuthService().isAuthenticated, isTrue);

      pushGate.complete();
      await Future.delayed(const Duration(milliseconds: 50));
    },
  );

  test(
    'O: the background WebSocket connect + push-token sync run to '
    'completion after auth succeeds, and a failure there is swallowed '
    '(no unhandled Future error) without disturbing authentication state',
    () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);

      SharedPreferences.setMockInitialValues({'push_enabled': true});
      await TokenStore.savePushToken('failing_push_token');
      addTearDown(() => TokenStore.savePushToken(null));

      var meCalls = 0;
      var pushCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCalls++;
          return _jsonResponse(200, {'id': 1, 'username': 'testuser'});
        }
        if (request.url.path == '/api/users/push_token') {
          pushCalls++;
          return _jsonResponse(500, {'message': 'push backend down'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });

      await ApiService.setTokens(
        accessToken: 'bg_failure_token',
        refreshToken: 'bg_failure_refresh',
      );

      await AuthService().initialize();

      expect(AuthService().isLoading, isFalse);
      expect(AuthService().isAuthenticated, isTrue);
      expect(meCalls, 1);

      // Give the background follow-up (deliberately not awaited by
      // initialize()) a moment to run — and fail.
      await Future.delayed(const Duration(milliseconds: 50));

      expect(pushCalls, 1);
      // A failed background push-token sync must not clear/disturb the
      // already-decided authentication state, and must not surface as an
      // unhandled Future error (a regression here would fail this test via
      // the test framework's uncaught-error reporting, not an assertion).
      expect(AuthService().isAuthenticated, isTrue);
    },
  );
}
