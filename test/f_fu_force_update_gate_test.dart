// Force-update hardening: ForceUpdateGate widget tests inside a real
// `MaterialApp.builder` (exactly where production_app.dart mounts the gate).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/widgets/force_update_gate.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/app_version_gate.dart';

import 'f_fu_support.dart';

const _home = Key('f_fu_home');

Widget _app({
  GlobalKey<NavigatorState>? navKey,
  bool passNavigatorKeyToGate = true,
  StoreUrlLauncher? launcher,
}) {
  return MaterialApp(
    navigatorKey: navKey,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    // Same position as production_app.dart: ABOVE the Navigator.
    builder: (context, child) => ForceUpdateGate(
      navigatorKey: passNavigatorKeyToGate ? navKey : null,
      urlLauncher: launcher,
      child: child ?? const SizedBox.shrink(),
    ),
    home: const Scaffold(body: Center(child: Text('HOME', key: _home))),
  );
}

Future<void> _resume(WidgetTester tester) async {
  final binding = tester.binding;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late FakeConfigServer server;
  late FakeClock clock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = FakeConfigServer(oldShapeConfig());
    clock = setUpGateFakes(server);
  });
  tearDown(tearDownGateFakes);

  testWidgets('no floor: the app is shown, no blocking UI', (tester) async {
    await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
    await tester.pumpAndSettle();
    expect(find.byKey(_home), findsOneWidget);
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('malformed floors from the server never show the block screen', (tester) async {
    for (final bad in <Object?>['garbage', '999.0.0', '-1', 7, '']) {
      server.respond({...oldShapeConfig(), 'min_app_version': bad});
      AppVersionGate.resetCacheForTests();
      AppVersionGate.clock = clock.call;
      await tester.pumpWidget(Container());
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsNothing, reason: '$bad');
      expect(find.byKey(_home), findsOneWidget, reason: '$bad');
    }
  });

  testWidgets('a failed fetch at start fails open', (tester) async {
    server.status = 500;
    await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
    await tester.pumpAndSettle();
    expect(find.byKey(_home), findsOneWidget);
    expect(find.text('Update required'), findsNothing);
  });

  group('blocking UI', () {
    testWidgets('floor above the installed version blocks with Try again + Update now', (tester) async {
      server.respond(oldShapeConfig(minAppVersion: '1.0.1'));
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Please update CarNet to continue.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
    });

    testWidgets('floor equal to the installed version does not block', (tester) async {
      server.respond(oldShapeConfig(minAppVersion: '1.0.0'));
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsNothing);
      expect(find.byKey(_home), findsOneWidget);
    });

    testWidgets('Update now opens the (validated) store URL', (tester) async {
      final opened = <Uri>[];
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      await tester.pumpWidget(_app(
        navKey: GlobalKey<NavigatorState>(),
        launcher: (uri) async {
          opened.add(uri);
          return true;
        },
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(),
          'https://play.google.com/store/apps/details?id=com.carnetiq.app');
    });

    testWidgets('Update now survives a launcher failure (no crash, stays blocked)', (tester) async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      await tester.pumpWidget(_app(
        navKey: GlobalKey<NavigatorState>(),
        launcher: (uri) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Update required'), findsOneWidget);
    });

    for (final badUrl in <String>['', 'javascript:alert(1)', 'not a url', 'https://']) {
      testWidgets('malformed store URL "$badUrl" hides Update now and never launches', (tester) async {
        final opened = <Uri>[];
        server.respond(oldShapeConfig(minAppVersion: '2.0.0', androidStoreUrl: badUrl));
        await tester.pumpWidget(_app(
          navKey: GlobalKey<NavigatorState>(),
          launcher: (uri) async {
            opened.add(uri);
            return true;
          },
        ));
        await tester.pumpAndSettle();
        expect(find.text('Update required'), findsOneWidget);
        expect(find.text('Update now'), findsNothing);
        expect(find.text('Try again'), findsOneWidget);
        expect(opened, isEmpty);
      });
    }
  });

  group('Try again really refetches', () {
    testWidgets('still blocked while the floor is unchanged; unblocked once lowered', (tester) async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(server.calls, 1);

      // Still the same floor: a real refetch happens and it stays blocked.
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(server.calls, 2, reason: 'retry must hit the network, not the cache');
      expect(find.text('Update required'), findsOneWidget);

      // Admin fixes the typo; the user taps Try again (cache is still fresh!).
      server.respond(oldShapeConfig(minAppVersion: '1.0.0'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(server.calls, 3);
      expect(find.text('Update required'), findsNothing);
      expect(find.byKey(_home), findsOneWidget);
    });

    testWidgets('while retrying the app is not exposed and a spinner is shown', (tester) async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();

      final hold = Completer<void>();
      server.hold = hold;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.byKey(_home), findsNothing, reason: 'no fail-open flash while retrying');
      expect(find.text('Try again'), findsNothing, reason: 'no double-tap spam');

      hold.complete();
      await tester.pumpAndSettle();
      expect(server.calls, 2);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('retry while the network is down keeps the known-good block and can retry again', (tester) async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();

      server.failWith = TimeoutException('offline');
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(server.calls, 2);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget, reason: 'never a dead end');

      server.respond(oldShapeConfig(minAppVersion: '1.0.0'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(_home), findsOneWidget);
    });
  });

  group('app resume', () {
    testWidgets('a blocked user is released on resume after the floor was lowered', (tester) async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      expect(server.calls, 1);

      server.respond(oldShapeConfig(minAppVersion: '1.0.0'));
      clock.advance(AppVersionGate.minResumeGap + const Duration(seconds: 1));
      await _resume(tester);
      await tester.pumpAndSettle();
      expect(server.calls, 2, reason: 'resume re-checks while blocked (cache bypassed)');
      expect(find.text('Update required'), findsNothing);
      expect(find.byKey(_home), findsOneWidget);
    });

    testWidgets('resume storm while blocked is throttled (no refetch loop)', (tester) async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await _resume(tester); // clock did not advance
      }
      expect(server.calls, 1);
      clock.advance(AppVersionGate.minResumeGap + const Duration(seconds: 1));
      await _resume(tester);
      await tester.pumpAndSettle();
      expect(server.calls, 2);
    });

    testWidgets('not blocked: resume < 15 min after success does not refetch', (tester) async {
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(server.calls, 1);
      clock.advance(const Duration(minutes: 5));
      await _resume(tester);
      expect(server.calls, 1);
    });

    testWidgets('not blocked: resume >= 15 min later picks up a new floor and blocks', (tester) async {
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(find.byKey(_home), findsOneWidget);

      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      clock.advance(AppVersionGate.cacheTtl + const Duration(minutes: 1));
      await _resume(tester);
      await tester.pumpAndSettle();
      expect(server.calls, 2);
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('after a failed start fetch, a later resume retries and picks the config up', (tester) async {
      server.status = 500;
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(server.calls, 1);
      expect(find.byKey(_home), findsOneWidget);

      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      clock.advance(AppVersionGate.minResumeGap + const Duration(seconds: 1));
      await _resume(tester);
      await tester.pumpAndSettle();
      expect(server.calls, 2);
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('a resume failure while blocked keeps the block and does not loop', (tester) async {
      server.respond(oldShapeConfig(minAppVersion: '2.0.0'));
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      server.failWith = TimeoutException('offline');
      clock.advance(AppVersionGate.minResumeGap + const Duration(seconds: 1));
      await _resume(tester);
      await tester.pumpAndSettle();
      expect(server.calls, 2);
      expect(find.text('Update required'), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        await _resume(tester);
      }
      expect(server.calls, 2);
    });
  });

  group('latest-aware escape through the real UI', () {
    testWidgets('device on the latest version is not blocked by an unsatisfiable build floor', (tester) async {
      server.respond({
        ...oldShapeConfig(minAndroidBuild: 99999),
        'latest_app_version': '1.0.0',
      });
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsNothing);
      expect(find.byKey(_home), findsOneWidget);
    });
  });

  group('soft update dialog (Navigator context)', () {
    Map<String, dynamic> soft() => oldShapeConfig(recommended: '1.1.0');

    testWidgets('shows from the builder-level gate when given the app navigator key', (tester) async {
      server.respond(soft());
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);
      expect(find.byKey(_home), findsOneWidget);
    });

    testWidgets('without a navigator key it neither throws nor crashes the app', (tester) async {
      server.respond(soft());
      await tester.pumpWidget(_app(passNavigatorKeyToGate: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(_home), findsOneWidget);
    });

    testWidgets('Update button opens the store and closes the dialog', (tester) async {
      final opened = <Uri>[];
      server.respond(soft());
      await tester.pumpWidget(_app(
        navKey: GlobalKey<NavigatorState>(),
        launcher: (u) async {
          opened.add(u);
          return true;
        },
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('dismissal is remembered for that recommendation', (tester) async {
      server.respond(soft());
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(Container());
      AppVersionGate.resetCacheForTests();
      AppVersionGate.clock = clock.call;
      await tester.pumpWidget(_app(navKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);
    });
  });
}
