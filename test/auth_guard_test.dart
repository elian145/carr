// F-05 regression coverage: AuthGuard used to spin a bare
// CircularProgressIndicator forever once a token was held in memory
// (ApiService.isAuthenticated) but AuthService never became authenticated
// (the initial /auth/me attempt and AuthService's own bounded automatic
// retries all failed with something other than a 401). These tests prove
// AuthGuard now:
//   1. renders `child` normally on a successful profile load,
//   2. never shows the terminal error while AuthService's existing bounded
//      retry could still legitimately recover,
//   3. eventually replaces the child with a recoverable error once its own
//      terminal timeout elapses after the stranded state is reached,
//   4. recovers via a tap on Retry, which calls the existing
//      AuthService().refreshProfile() (no new profile-loading mechanism),
//   5. never shows the terminal error on a definitive 401 (existing login
//      redirect behavior is untouched), and
//   6. never creates a duplicate terminal timer across repeated rebuilds.
//
// All timing is deterministic: `testWidgets` runs inside a FakeAsync zone,
// so `tester.pump(duration)` advances Timers (both AuthService's own
// retry-delay Timers and AuthGuard's terminal Timer) without any real
// wall-clock wait. AuthService.debugProfileRetryDelaysOverride and the new
// AuthGuard.debugTerminalTimeoutOverride (mirroring the same existing
// testing convention) keep the simulated cascade short.
//
// RC smoke-test follow-up round 1 (superseded by round 2 below): while the
// initial `/auth/me` check is genuinely pending, AuthGuard's pending-state
// UI must be a real loading shell (Scaffold + AppBar), not a bare spinner
// on an otherwise blank page, which real-device testing found reads as
// "the tap did nothing".
//
// RC smoke-test follow-up round 2 (tests 7-10 below): round 1 only
// improved the *look* of the pending state — it did not remove the
// underlying serialization. A locally-stored token
// (`ApiService.isAuthenticated`) means this session *was* authenticated
// last time the app ran, so AuthGuard now mounts the real protected
// `child` IMMEDIATELY whenever that local token exists, instead of making
// every protected route (Sell, Chat, My Listings, ...) wait for `/auth/me`
// to confirm it first. `/auth/me` keeps validating in the background —
// the child's own data/local-init work now starts in parallel with it
// instead of after it. The loading-shell UI from round 1 is only shown
// now during the brief window at a genuinely fresh (logged-out-or-unknown)
// launch, before even the presence of a local token is known, and while
// redirecting a confirmed-unauthenticated session to `/login`.
//
// This changes tests 2, 3 and 6 below too: a "stranded" session (local
// token present, `/auth/me` failing/retrying) now shows the real `child`
// instead of a spinner throughout that window — the terminal-timeout
// error UI (test 3) still eventually replaces it exactly as before once
// the terminal timeout elapses, proving AuthService's bounded-retry and
// AuthGuard's own terminal-timeout semantics are both fully intact; only
// what is shown *while* still within that budget has changed.
import 'dart:async';
import 'dart:convert';

import 'package:car_listing_app/app/carzo_shared.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api_server.dart';

http.Response _jsonResponse(int status, Object body) => http.Response(
  json.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Minimal host app: Provider + localization + a `/login` stub route, with
/// [guardedChild] behind a real [AuthGuard] — no test-only fakes of
/// AuthGuard itself.
Widget _appWithGuard(Widget guardedChild, {bool allowWhenLoggedOut = false}) {
  return ChangeNotifierProvider<AuthService>.value(
    value: AuthService(),
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      routes: {'/login': (context) => const Scaffold(body: Text('Login stub'))},
      home: AuthGuard(
        allowWhenLoggedOut: allowWhenLoggedOut,
        child: guardedChild,
      ),
    ),
  );
}

// Matches the localized copy AuthGuard's terminal error state reuses
// (AppLocalizations.of(context)!.failedToLoadUserData, en locale) — see
// lib/l10n/app_en.arb.
const _terminalErrorText = 'Failed to load user data';

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

  tearDown(() {
    AuthService.debugProfileRetryDelaysOverride = null;
    AuthGuard.debugTerminalTimeoutOverride = null;
  });

  testWidgets('1: successful profile load renders child, no error UI', (
    tester,
  ) async {
    ApiService.testHttpClient = MockClient((request) async {
      if (request.url.path == '/api/auth/me') {
        return _jsonResponse(200, {'id': 1, 'username': 'testuser'});
      }
      return _jsonResponse(200, <String, dynamic>{});
    });
    await ApiService.setTokens(
      accessToken: 'good_token',
      refreshToken: 'good_refresh',
    );
    await AuthService().initialize();

    await tester.pumpWidget(_appWithGuard(const Text('Protected Content')));
    await tester.pump();

    expect(find.text('Protected Content'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(_terminalErrorText), findsNothing);
  });

  testWidgets(
    '2: a transient failure recovered by the existing bounded retry never '
    'shows the terminal error UI',
    (tester) async {
      // Retry recovers well inside AuthGuard's own (generous) terminal
      // window — proves the terminal timer does not preempt a legitimate,
      // still-recoverable AuthService retry.
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(milliseconds: 50),
      ];
      AuthGuard.debugTerminalTimeoutOverride = const Duration(
        milliseconds: 500,
      );

      var meCalls = 0;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCalls++;
          if (meCalls == 1) {
            return _jsonResponse(500, {'message': 'temporary failure'});
          }
          return _jsonResponse(200, {'id': 1, 'username': 'testuser'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      await ApiService.setTokens(
        accessToken: 'flaky_token',
        refreshToken: 'flaky_refresh',
      );
      await AuthService().initialize();

      // Right after the first failed attempt: stranded by definition, but
      // a local token is present, so AuthGuard now mounts the real child
      // immediately (RC parallelization fix) instead of showing a spinner
      // while the bounded retry is still in flight.
      await tester.pumpWidget(_appWithGuard(const Text('Protected Content')));
      await tester.pump();
      expect(find.text('Protected Content'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_terminalErrorText), findsNothing);

      // Let the bounded retry (50ms) fire and succeed.
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Protected Content'), findsOneWidget);
      expect(find.text(_terminalErrorText), findsNothing);

      // Advance well past the *original* terminal deadline too — recovery
      // must be permanent, never regressing to the error state.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Protected Content'), findsOneWidget);
      expect(find.text(_terminalErrorText), findsNothing);
    },
  );

  testWidgets(
    '3: persistent /auth/me failures exhaust the existing bounded retry — '
    'the local-token child stays mounted throughout, and AuthGuard only '
    'eventually replaces it with a recoverable error once its own terminal '
    'timeout elapses',
    (tester) async {
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 10),
        Duration(milliseconds: 10),
      ];
      AuthGuard.debugTerminalTimeoutOverride = const Duration(
        milliseconds: 300,
      );

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

      await tester.pumpWidget(_appWithGuard(const Text('Protected Content')));
      await tester.pump();
      // A local token is present, so the real child is already mounted —
      // not a spinner — even on this very first (already-failed-once)
      // attempt.
      expect(find.text('Protected Content'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Let AuthService's existing bounded retry mechanism fully exhaust
      // (initial + 3 retries = 4 calls, exactly like the existing
      // auth_service_test.dart test H) — the exact stranded combination
      // this finding describes. AuthService's retry budget is completely
      // unaffected by the RC parallelization fix: same call count, same
      // isAuthenticated/isLoading/ApiService.isAuthenticated combination.
      await tester.pump(const Duration(milliseconds: 100));
      expect(meCalls, 4);
      expect(AuthService().isAuthenticated, isFalse);
      expect(AuthService().isLoading, isFalse);
      expect(ApiService.isAuthenticated, isTrue);
      // Still optimistically mounted — the child's own data/local-init
      // work has had this entire retry-cascade window to run in parallel
      // with `/auth/me`, instead of only starting once (if ever) this
      // finally gave up.
      expect(find.text('Protected Content'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_terminalErrorText), findsNothing);

      // Advance past AuthGuard's own terminal timeout: only *now* — once
      // recovery is truly hopeless — does the optimistically-mounted child
      // get replaced by a recoverable, non-technical error with a retry
      // action. This proves the terminal-timeout mechanism itself (not
      // just AuthService's retry budget) is fully intact under the new
      // optimistic-mount behavior.
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Protected Content'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_terminalErrorText), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    },
  );

  testWidgets(
    '4: tapping retry calls the existing AuthService.refreshProfile() and '
    'recovers to child on success',
    (tester) async {
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 10),
        Duration(milliseconds: 10),
      ];
      AuthGuard.debugTerminalTimeoutOverride = const Duration(
        milliseconds: 200,
      );

      var meCalls = 0;
      var succeedFromNowOn = false;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          meCalls++;
          if (succeedFromNowOn) {
            return _jsonResponse(200, {'id': 1, 'username': 'testuser'});
          }
          return _jsonResponse(500, {'message': 'always failing'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      await ApiService.setTokens(
        accessToken: 'retry_token',
        refreshToken: 'retry_refresh',
      );
      await AuthService().initialize();

      await tester.pumpWidget(_appWithGuard(const Text('Protected Content')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50)); // exhaust retries
      await tester.pump(
        const Duration(milliseconds: 200),
      ); // cross terminal timeout

      expect(find.text(_terminalErrorText), findsOneWidget);
      final callsBeforeRetry = meCalls;

      succeedFromNowOn = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Behavioral proof that AuthService.refreshProfile() (its existing
      // single-flight /auth/me fetch) was actually invoked by the tap.
      expect(meCalls, greaterThan(callsBeforeRetry));
      expect(find.text('Protected Content'), findsOneWidget);
      expect(find.text(_terminalErrorText), findsNothing);
    },
  );

  testWidgets(
    '5: a definitive 401 clears tokens and preserves the existing login '
    'redirect — the terminal error must never appear',
    (tester) async {
      AuthGuard.debugTerminalTimeoutOverride = const Duration(
        milliseconds: 50,
      );
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return _jsonResponse(401, {'message': 'Token has expired'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      await ApiService.setTokens(
        accessToken: 'expired_token',
        refreshToken: 'expired_refresh_invalid',
      );
      await AuthService().initialize();

      // A real 401 clears the session immediately — no retry, no lingering
      // token (existing behavior, untouched by this fix).
      expect(AuthService().isAuthenticated, isFalse);
      expect(ApiService.isAuthenticated, isFalse);

      await tester.pumpWidget(_appWithGuard(const Text('Protected Content')));
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 50),
      ); // let the post-frame redirect run

      expect(find.text('Login stub'), findsOneWidget);
      expect(find.text(_terminalErrorText), findsNothing);

      // Advance well past AuthGuard's own (tiny) terminal timeout too — it
      // must never fire once ApiService.isAuthenticated is false.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(_terminalErrorText), findsNothing);
      expect(find.text('Login stub'), findsOneWidget);
    },
  );

  testWidgets(
    '6: repeated widget rebuilds while stranded do not create a duplicate '
    'terminal timer',
    (tester) async {
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(milliseconds: 10),
      ];
      AuthGuard.debugTerminalTimeoutOverride = const Duration(
        milliseconds: 300,
      );

      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return _jsonResponse(500, {'message': 'always failing'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      await ApiService.setTokens(
        accessToken: 'rebuild_token',
        refreshToken: 'rebuild_refresh',
      );
      await AuthService().initialize();

      await tester.pumpWidget(_appWithGuard(const Text('Protected Content')));
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 30),
      ); // exhaust the single retry, still stranded

      // Force several rebuilds of the SAME AuthGuard element (same
      // StatefulElement/State — no key change) while stranded and before
      // the terminal timeout fires. If a bug created a new Timer on every
      // build(), this would leave multiple pending Timers: the
      // flutter_test framework fails a test at teardown if any Timer is
      // still pending, so this loop plus the final pump below would catch
      // that regression even without inspecting private state directly.
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(_appWithGuard(Text('Protected Content $i')));
        await tester.pump();
      }
      // Local token present + stranded: the (latest) real child is mounted
      // throughout, not a spinner — see test 3.
      expect(find.text('Protected Content 4'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_terminalErrorText), findsNothing);

      // Only one terminal timer should be pending: crossing its deadline
      // now produces exactly one error transition (findsOneWidget, not
      // multiple/duplicated).
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_terminalErrorText), findsOneWidget);
    },
  );

  testWidgets(
    '7: with NO local token at all, AuthGuard still shows the loading shell '
    '(Scaffold + AppBar) — not the child — while auth initialization is '
    'still determining whether a session even exists',
    (tester) async {
      ApiService.testHttpClient = MockClient(
        (request) async => _jsonResponse(200, <String, dynamic>{}),
      );
      // No token was ever set (setUp() already cleared it) — this is a
      // genuinely fresh/logged-out launch, the one case the RC
      // parallelization fix must NOT optimistically mount for.
      expect(ApiService.isAuthenticated, isFalse);

      // `AuthService._initializeOnce()` calls `_setLoading(true)`
      // synchronously as its very first statement, then suspends on
      // `await ApiService.initializeTokens()` — so right after this call
      // (still in the same synchronous stretch of code, before any
      // `pump`), `isLoading` is already `true` and no token has been
      // found yet. Deliberately not awaited, mirroring how a real cold
      // app session looks at the moment a protected route is first opened.
      unawaited(AuthService().initialize());
      expect(AuthService().isLoading, isTrue);
      expect(ApiService.isAuthenticated, isFalse);

      // `pumpWidget` builds the widget tree synchronously (before any of
      // its own internal awaits let the microtask above continue), so
      // AuthGuard's very first build still observes exactly the state
      // just asserted above.
      await tester.pumpWidget(_appWithGuard(const Text('Protected Content')));

      expect(
        find.text('Protected Content'),
        findsNothing,
        reason:
            'No local session exists yet — the real destination must not '
            'render.',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.byType(AppBar),
        findsOneWidget,
        reason:
            'The pending state must render a proper loading shell (a real '
            'Scaffold + AppBar), not a bare/blank spinner-only page.',
      );
      expect(find.text(_terminalErrorText), findsNothing);
    },
  );

  testWidgets(
    '8: with a local token present, AuthGuard mounts the protected child '
    'IMMEDIATELY while /auth/me is still pending — no more waiting for it '
    'before the destination can even begin its own loading',
    (tester) async {
      final pendingProfileResponse = Completer<http.Response>();
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return pendingProfileResponse.future;
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      await ApiService.setTokens(
        accessToken: 'pending_token',
        refreshToken: 'pending_refresh',
      );
      // Deliberately not awaited: this leaves AuthService.isLoading true
      // and the (mocked) /auth/me request in flight, exactly like a real
      // cold app session at the moment a protected route is first opened.
      unawaited(AuthService().initialize());

      await tester.pumpWidget(_appWithGuard(const Text('Protected Content')));
      await tester.pump();

      expect(AuthService().isLoading, isTrue);
      expect(ApiService.isAuthenticated, isTrue);
      expect(
        find.text('Protected Content'),
        findsOneWidget,
        reason:
            'RC parallelization fix: a locally-stored token is enough to '
            'mount the real destination immediately — its own data/'
            'local-init work can now start in parallel with /auth/me '
            'instead of waiting for it to finish first.',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_terminalErrorText), findsNothing);

      // Resolve the in-flight /auth/me request to keep the test's own
      // MockClient/session state tidy for tearDown — behavior on success
      // is already covered by test 9 below.
      pendingProfileResponse.complete(
        _jsonResponse(200, {'id': 1, 'username': 'testuser'}),
      );
      await tester.pump();
      await tester.pump();
    },
  );

  testWidgets(
    '9: while a local-token child is optimistically mounted, /auth/me '
    'finishing successfully in the background changes nothing disruptive '
    '— the same child instance remains, now backed by a confirmed session',
    (tester) async {
      final pendingProfileResponse = Completer<http.Response>();
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return pendingProfileResponse.future;
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      await ApiService.setTokens(
        accessToken: 'pending_token',
        refreshToken: 'pending_refresh',
      );
      unawaited(AuthService().initialize());

      final childKey = GlobalKey();
      await tester.pumpWidget(
        _appWithGuard(Text('Protected Content', key: childKey)),
      );
      await tester.pump();

      expect(find.text('Protected Content'), findsOneWidget);
      final elementBeforeResolve = tester.element(find.byKey(childKey));

      // /auth/me resolves successfully in the background.
      pendingProfileResponse.complete(
        _jsonResponse(200, {'id': 1, 'username': 'testuser'}),
      );
      await tester.pump();
      await tester.pump();

      expect(AuthService().isAuthenticated, isTrue);
      expect(find.text('Protected Content'), findsOneWidget);
      expect(
        tester.element(find.byKey(childKey)),
        same(elementBeforeResolve),
        reason:
            'The child must not be torn down and remounted when /auth/me '
            'catches up — AuthGuard.build returns the exact same '
            '`widget.child` instance from both the optimistic-mount branch '
            'and the confirmed-authenticated branch, so Flutter keeps the '
            'same element/state (no lost scroll position, no restarted '
            'in-flight requests, no flicker).',
      );
      expect(find.text(_terminalErrorText), findsNothing);
    },
  );

  testWidgets(
    '10: a local-token child that was optimistically mounted is correctly '
    'swapped for the existing unauthenticated/login-redirect behavior once '
    '/auth/me comes back unauthorized — the backend remains the security '
    'authority even after an optimistic mount',
    (tester) async {
      final pendingProfileResponse = Completer<http.Response>();
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return pendingProfileResponse.future;
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      await ApiService.setTokens(
        accessToken: 'will_be_rejected_token',
        refreshToken: 'will_be_rejected_refresh',
      );
      unawaited(AuthService().initialize());

      await tester.pumpWidget(_appWithGuard(const Text('Protected Content')));
      await tester.pump();

      // Optimistically mounted while /auth/me is still pending — same as
      // test 8.
      expect(find.text('Protected Content'), findsOneWidget);
      expect(ApiService.isAuthenticated, isTrue);

      // The backend now rejects the token: a definitive 401. This still
      // runs the pre-existing `AuthService.onApiTokensCleared()` path
      // (clears ApiService's tokens, notifies listeners) exactly as if the
      // optimistic mount had never happened.
      pendingProfileResponse.complete(
        _jsonResponse(401, {'message': 'Token has expired'}),
      );
      // Unlike test 5 (where AuthService.initialize() fully resolves
      // *before* AuthGuard ever mounts, so its very first build already
      // lands in the redirect branch), here the 401 arrives while AuthGuard
      // is already mounted and optimistically showing the child. That
      // takes one extra pump for Provider's own rebuild to pick up the
      // now-resolved AuthService state, plus the redirected `/login`
      // route's own (real) push-replacement transition — so settle fully
      // instead of guessing a fixed number of frames/milliseconds.
      await tester.pumpAndSettle();

      expect(AuthService().isAuthenticated, isFalse);
      expect(ApiService.isAuthenticated, isFalse);
      expect(find.text('Login stub'), findsOneWidget);
      expect(find.text('Protected Content'), findsNothing);
      expect(find.text(_terminalErrorText), findsNothing);
    },
  );
}
