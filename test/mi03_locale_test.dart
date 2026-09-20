// MI-03/U-01 targeted Flutter regression tests.
//
// Covers (see PRODUCTION_AUDIT.md MI-03/U-01):
//  - central request headers always include Accept-Language (en/ar/ku)
//  - an explicit in-app language change still persists locally
//  - an authenticated language change syncs `User.locale` to the backend
//  - a failed backend sync never undoes the local language change
//  - the post-profile-load sync only PATCHes when backend locale is
//    missing or different from the current device/app language
//  - ForceUpdateGate's own chrome (title/buttons) is localized
//  - production_routes.dart's missing-argument fallbacks use l10n
//  - bootstrap.dart's release crash message is localized (source check --
//    the widget itself is a private class with no reachable BuildContext
//    path in a unit test; see the crash section below for why).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_routes.dart';
import 'package:car_listing_app/app/widgets/force_update_gate.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/app_version_gate.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/state/locale_controller.dart';

http.Response _jsonResponse(int status, Object body) => http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Records every `PUT /api/user/profile` this client sees (MI-03 backend
/// locale sync) and echoes back whatever `locale` was sent, exactly like
/// the real endpoint's response shape.
class _ProfileUpdateRecorder {
  int calls = 0;
  Map<String, dynamic>? lastBody;

  MockClient client() {
    return MockClient((request) async {
      if (request.method == 'PUT' && request.url.path == '/api/user/profile') {
        calls++;
        final decoded = request.body.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(json.decode(request.body) as Map);
        lastBody = decoded;
        return _jsonResponse(200, {
          'message': 'Profile updated successfully',
          'user': {
            'id': 1,
            'username': 'test',
            'account_type': 'individual',
            'locale': decoded['locale'],
          },
        });
      }
      return _jsonResponse(200, <String, dynamic>{});
    });
  }
}

Widget _localizedApp(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Matches FakeApiServer's own setup: avoids real
    // flutter_secure_storage platform-channel calls (unavailable under
    // `flutter test`) for the token read/writes these tests trigger.
    TokenStore.testMode = true;
  });
  tearDownAll(() {
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  // ------------------------------------------------------------------
  // LocaleController.resolveCode() / supportedCodes
  // ------------------------------------------------------------------
  group('LocaleController.resolveCode', () {
    setUp(() {
      LocaleController.currentLocale.value = null;
    });
    tearDown(() {
      LocaleController.currentLocale.value = null;
    });

    test('an explicit supported selection wins', () {
      LocaleController.currentLocale.value = const Locale('ar');
      expect(LocaleController.resolveCode(), 'ar');
      LocaleController.currentLocale.value = const Locale('ku');
      expect(LocaleController.resolveCode(), 'ku');
    });

    test('an explicit unsupported selection falls back to device/en', () {
      LocaleController.currentLocale.value = const Locale('fr');
      // The flutter test harness's platform locale is en_US, which is
      // supported, so this exercises the device-locale fallback branch.
      expect(LocaleController.resolveCode(), 'en');
    });

    test('supportedCodes is exactly en/ar/ku -- ckb is NOT included', () {
      expect(LocaleController.supportedCodes, ['en', 'ar', 'ku']);
      expect(LocaleController.supportedCodes.contains('ckb'), isFalse);
    });
  });

  // ------------------------------------------------------------------
  // Accept-Language header (central api_http.dart header construction)
  // ------------------------------------------------------------------
  group('Accept-Language header', () {
    setUp(() {
      LocaleController.currentLocale.value = null;
    });
    tearDown(() {
      LocaleController.currentLocale.value = null;
    });

    test('ApiService.defaultHeaders() follows the resolved locale for en/ar/ku', () {
      for (final code in ['en', 'ar', 'ku']) {
        LocaleController.currentLocale.value = Locale(code);
        expect(ApiService.defaultHeaders()['Accept-Language'], code);
      }
    });

    test('AppVersionGate.load() sends Accept-Language on GET /api/config/app', () async {
      final originalClient = ApiService.boundTestHttpClient;
      addTearDown(() => ApiService.testHttpClient = originalClient);
      addTearDown(AppVersionGate.resetCacheForTests);

      String? captured;
      ApiService.testHttpClient = MockClient((request) async {
        if (request.url.path == '/api/config/app') {
          captured = request.headers['Accept-Language'];
        }
        return _jsonResponse(200, {
          'min_app_version': '',
          'force_update_message': 'Please update CarNet to continue.',
          'soft_update_message': 'A newer version of CarNet is available.',
          'android_store_url': '',
          'ios_store_url': '',
        });
      });

      LocaleController.currentLocale.value = const Locale('ku');
      AppVersionGate.resetCacheForTests();
      await AppVersionGate.load(forceRefresh: true);

      expect(captured, 'ku');
    });
  });

  // ------------------------------------------------------------------
  // Flutter -> backend locale sync (AuthService + LocaleController)
  // ------------------------------------------------------------------
  group('MI-03(A): locale change while authenticated syncs to backend', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({'push_enabled': false});
      await ApiService.clearTokens();
      AuthService().resetTestSession();
      LocaleController.currentLocale.value = null;
    });
    tearDown(() async {
      LocaleController.onLocaleChanged = null;
      LocaleController.currentLocale.value = null;
      await ApiService.clearTokens();
      AuthService().resetTestSession();
    });

    test('an in-app language change still persists locally even with no sync hook', () async {
      LocaleController.onLocaleChanged = null;
      await LocaleController.setLocale(const Locale('ar'));
      expect(LocaleController.currentLocale.value?.languageCode, 'ar');

      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('app_locale'), 'ar');
    });

    test('wiring onLocaleChanged to AuthService PATCHes User.locale on change', () async {
      final recorder = _ProfileUpdateRecorder();
      ApiService.testHttpClient = recorder.client();
      await ApiService.setTokens(accessToken: 'sync_token', refreshToken: 'sync_refresh');
      await AuthService().adoptTestSession();
      LocaleController.onLocaleChanged = AuthService().syncLocaleIfAuthenticated;

      await LocaleController.setLocale(const Locale('ku'));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(recorder.calls, 1);
      expect(recorder.lastBody?['locale'], 'ku');
      // Local selection remains authoritative regardless of the backend call.
      expect(LocaleController.resolveCode(), 'ku');
    });

    test('a failing backend sync does not undo the local language change', () async {
      ApiService.testHttpClient = MockClient((request) async {
        if (request.method == 'PUT' && request.url.path == '/api/user/profile') {
          return _jsonResponse(500, {'message': 'boom'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      });
      await ApiService.setTokens(accessToken: 'fail_token', refreshToken: 'fail_refresh');
      await AuthService().adoptTestSession();
      LocaleController.onLocaleChanged = AuthService().syncLocaleIfAuthenticated;

      await LocaleController.setLocale(const Locale('ar'));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(LocaleController.currentLocale.value?.languageCode, 'ar');
      expect(LocaleController.resolveCode(), 'ar');
    });

    test('syncLocaleIfAuthenticated is a no-op (never throws) when logged out', () async {
      expect(ApiService.isAuthenticated, isFalse);
      await AuthService().syncLocaleIfAuthenticated('ar');
    });
  });

  // ------------------------------------------------------------------
  // MI-03(B): post-profile-load sync only when backend locale is
  // missing/different -- never spams the API when it already matches.
  // ------------------------------------------------------------------
  group('MI-03(B): profile-load locale sync', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({'push_enabled': false});
      await ApiService.clearTokens();
      AuthService().resetTestSession();
    });
    tearDown(() async {
      LocaleController.currentLocale.value = null;
      await ApiService.clearTokens();
      AuthService().resetTestSession();
    });

    test('syncs when the backend locale is null', () async {
      final recorder = _ProfileUpdateRecorder();
      ApiService.testHttpClient = recorder.client();
      await ApiService.setTokens(accessToken: 't1', refreshToken: 'r1');
      LocaleController.currentLocale.value = const Locale('ar');

      await AuthService().activateSession(user: {
        'id': 1,
        'username': 'test',
        'account_type': 'individual',
        'locale': null,
      });
      await Future.delayed(const Duration(milliseconds: 30));

      expect(recorder.calls, 1);
      expect(recorder.lastBody?['locale'], 'ar');
    });

    test('does not sync when the backend locale already matches', () async {
      final recorder = _ProfileUpdateRecorder();
      ApiService.testHttpClient = recorder.client();
      await ApiService.setTokens(accessToken: 't2', refreshToken: 'r2');
      LocaleController.currentLocale.value = const Locale('ar');

      await AuthService().activateSession(user: {
        'id': 1,
        'username': 'test',
        'account_type': 'individual',
        'locale': 'ar',
      });
      await Future.delayed(const Duration(milliseconds: 30));

      expect(recorder.calls, 0);
    });

    test(
      'syncs the CURRENT local/device locale over a differing stored '
      'backend value -- login never silently changes the visible language',
      () async {
        final recorder = _ProfileUpdateRecorder();
        ApiService.testHttpClient = recorder.client();
        await ApiService.setTokens(accessToken: 't3', refreshToken: 'r3');
        LocaleController.currentLocale.value = const Locale('en');

        await AuthService().activateSession(user: {
          'id': 1,
          'username': 'test',
          'account_type': 'individual',
          'locale': 'ar',
        });
        await Future.delayed(const Duration(milliseconds: 30));

        expect(recorder.calls, 1);
        // The device/session language (en) wins and is pushed to the
        // backend -- the stale stored 'ar' never overrides the session.
        expect(recorder.lastBody?['locale'], 'en');
        expect(LocaleController.resolveCode(), 'en');
      },
    );
  });

  // ------------------------------------------------------------------
  // U-01: ForceUpdateGate's own chrome (title/buttons) is localized.
  // decision.message itself is expected to already arrive localized from
  // the backend (see kk.app_settings.get_localized_platform_message) and
  // is displayed verbatim.
  // ------------------------------------------------------------------
  group('U-01: ForceUpdateGate localized chrome', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppVersionGate.resetCacheForTests();
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: '1.0.0',
        buildNumber: '1',
      );
    });
    tearDown(AppVersionGate.resetCacheForTests);

    testWidgets('hard block shows localized title/message/try-again', (tester) async {
      AppVersionGate.setCachedForTests(
        const AppVersionRequirement(
          minAppVersion: '99.0.0',
          forceUpdateMessage: 'Please update now.',
        ),
      );

      await tester.pumpWidget(
        _localizedApp(const ForceUpdateGate(child: SizedBox.shrink())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Please update now.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // No store URL configured -> the "Update now" action is not shown.
      expect(find.text('Update now'), findsNothing);
    });

    testWidgets('soft prompt dialog shows localized title/buttons', (tester) async {
      AppVersionGate.setCachedForTests(
        const AppVersionRequirement(
          recommendedAppVersion: '99.0.0',
          softUpdateMessage: 'A newer version is available.',
          androidStoreUrl: 'https://example.com/app',
        ),
      );

      await tester.pumpWidget(
        _localizedApp(const ForceUpdateGate(child: SizedBox.shrink())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('A newer version is available.'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------
  // U-01: production_routes.dart missing-argument fallbacks use l10n.
  // Calls the exact WidgetBuilder functions from the real route table.
  // ------------------------------------------------------------------
  // ------------------------------------------------------------------
  // U-01: app_version_gate.dart's own malformed/legacy-response fallback
  // (backend returns an empty force/soft update message despite genuinely
  // requiring one) must not show English to an ar/ku user -- it now goes
  // through `lookupAppLocalizations` + the current app locale instead of a
  // hardcoded literal.
  // ------------------------------------------------------------------
  group('U-01: app_version_gate.dart malformed-response fallback is localized', () {
    setUp(() {
      AppVersionGate.resetCacheForTests();
      AppVersionGate.debugPackageInfo = PackageInfo(
        appName: 'CarNet',
        packageName: 'com.carnetiq.app',
        version: '1.0.0',
        buildNumber: '1',
      );
    });
    tearDown(() {
      AppVersionGate.resetCacheForTests();
      LocaleController.currentLocale.value = null;
    });

    test('force-update fallback follows the current app locale, not English', () async {
      LocaleController.currentLocale.value = const Locale('ar');
      // forceUpdateMessage deliberately left empty -- the malformed/legacy
      // response this fallback exists for.
      AppVersionGate.setCachedForTests(
        const AppVersionRequirement(minAppVersion: '99.0.0'),
      );

      final decision = await AppVersionGate.evaluate();

      expect(decision.required, isTrue);
      expect(
        decision.message,
        lookupAppLocalizations(const Locale('ar')).forceUpdateFallbackMessage,
      );
      expect(decision.message, isNot(contains('Please update CarNet')));
    });

    test('soft-update fallback follows the current app locale, not English', () async {
      LocaleController.currentLocale.value = const Locale('ku');
      AppVersionGate.setCachedForTests(
        const AppVersionRequirement(recommendedAppVersion: '99.0.0'),
      );

      final decision = await AppVersionGate.evaluate();

      expect(decision.softRecommended, isTrue);
      expect(
        decision.message,
        lookupAppLocalizations(const Locale('ku')).softUpdateFallbackMessage,
      );
      expect(decision.message, isNot(contains('A newer version of CarNet')));
    });
  });

  group('U-01: production_routes.dart navigation-error text uses l10n', () {
    late Map<String, WidgetBuilder> routes;

    setUp(() {
      routes = buildProductionRoutes();
    });

    testWidgets('/chat/conversation with no arguments', (tester) async {
      await tester.pumpWidget(
        _localizedApp(Builder(builder: routes['/chat/conversation']!)),
      );
      await tester.pump();

      expect(find.text('Navigation error'), findsOneWidget);
      expect(find.text('Missing chat conversation id'), findsOneWidget);
    });

    testWidgets('/edit with no car argument', (tester) async {
      await tester.pumpWidget(
        _localizedApp(Builder(builder: routes['/edit']!)),
      );
      await tester.pump();

      expect(find.text('Navigation error'), findsOneWidget);
      expect(find.text('Missing listing data'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------
  // U-01: bootstrap.dart release crash message is localized -- including
  // the no-Localizations-ancestor edge case (a build error inside
  // `MyApp.build()` itself, above `MaterialApp`; see production_app.dart).
  // That case is realistically reachable, so the old hardcoded-English
  // `??` fallback was replaced with `lookupAppLocalizations` (generated by
  // `flutter gen-l10n`) + `LocaleController.resolveCode()`, which needs no
  // `BuildContext` at all.
  //
  // `ErrorWidget.builder` is process-global, only assigned inside
  // `bootstrapAndRun()` (a full startup routine we can't exercise in a
  // unit test without also standing up Firebase/platform channels), and
  // the widget it hands off to (`_StartupCrashMessage`) is a private,
  // library-scoped class that this test file (a different library) has
  // no way to import/pump directly. A source check is the smallest way to
  // pin down the actual regression the audit cares about.
  // ------------------------------------------------------------------
  test('U-01: bootstrap.dart release crash text is fully l10n-driven, no hardcoded English', () {
    final source = File('lib/app/bootstrap.dart').readAsStringSync();

    // No hardcoded English crash literal anywhere -- not even as a "??" fallback.
    expect(
      source.contains('Something went wrong'),
      isFalse,
      reason: 'the crash message must not contain a hardcoded English literal',
    );

    // The no-Localizations-ancestor case must be handled by the generated
    // lookup (not `Localizations.of(context)`, which is exactly what
    // returns null in that case) driven by the already-resolved app locale.
    final fallbackLookup = RegExp(
      r'AppLocalizations\.of\(context\)\s*\?\?\s*\r?\n\s*'
      r'lookupAppLocalizations\(Locale\(LocaleController\.resolveCode\(\)\)\)',
    );
    expect(
      fallbackLookup.hasMatch(source),
      isTrue,
      reason:
          'a missing Localizations ancestor must fall back to '
          'lookupAppLocalizations(LocaleController.resolveCode()), not a literal',
    );

    expect(
      source.contains('l10n.somethingWentWrongRestart'),
      isTrue,
      reason: 'the crash text itself must come from AppLocalizations',
    );
  });
}
