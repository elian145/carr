// F-05 regression coverage: AuthGuard used to spin a bare
// CircularProgressIndicator forever once a token was held in memory
// (ApiService.isAuthenticated) but AuthService never became authenticated
// (the initial /auth/me attempt and AuthService's own bounded automatic
// retries all failed with something other than a 401). These tests prove
// AuthGuard now:
//   1. renders `child` normally on a successful profile load,
//   2. never shows the terminal error while AuthService's existing bounded
//      retry could still legitimately recover,
//   3. eventually replaces the spinner with a recoverable error once its
//      own terminal timeout elapses after the stranded state is reached,
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
      // AuthGuard must still show the ordinary spinner, not an error.
      await tester.pumpWidget(_appWithGuard(const Text('Protected Content')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
    '3: persistent /auth/me failures exhaust the existing bounded retry and '
    'AuthGuard eventually replaces the spinner with a recoverable error',
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
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Let AuthService's existing bounded retry mechanism fully exhaust
      // (initial + 3 retries = 4 calls, exactly like the existing
      // auth_service_test.dart test H) — the exact stranded combination
      // this finding describes.
      await tester.pump(const Duration(milliseconds: 100));
      expect(meCalls, 4);
      expect(AuthService().isAuthenticated, isFalse);
      expect(AuthService().isLoading, isFalse);
      expect(ApiService.isAuthenticated, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_terminalErrorText), findsNothing);

      // Advance past AuthGuard's own terminal timeout: the spinner must be
      // replaced by a recoverable, non-technical error with a retry action.
      await tester.pump(const Duration(milliseconds: 250));

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
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_terminalErrorText), findsNothing);

      // Only one terminal timer should be pending: crossing its deadline
      // now produces exactly one error transition (findsOneWidget, not
      // multiple/duplicated).
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_terminalErrorText), findsOneWidget);
    },
  );
}
