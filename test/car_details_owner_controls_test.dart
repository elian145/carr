// Regression tests: intermittent missing Edit / Delete / Analytics buttons on
// Listing Details opened from My Listings.
//
// Root cause pinned here: `AuthGuard` mounts My Listings as soon as a stored
// token exists -- BEFORE `/auth/me` has returned -- so My Listings -> My Car ->
// Listing Details can be fully built while `AuthService.userId` is still null.
// `CarDetailsPage` decided ownership once per build by reading
// `Provider.of<AuthService>(listen: false)` and never subscribed to
// AuthService, so when `/auth/me` finished a moment later nothing rebuilt the
// page: the owner stayed "not the owner" (controls missing) until the app was
// restarted. The same one-shot read also kept the controls visible after the
// session ended or switched to another account.
//
// Every test drives the real pages with a scripted MockClient + Completers;
// no real network and no real timing.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/comparison/state/car_comparison_store.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/car_details_page.dart';
import 'package:car_listing_app/pages/my_listings_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/net/transient_get_retry.dart';
import 'package:car_listing_app/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ownerId = 'user_owner';
const _otherId = 'user_other';

http.Response _json(int status, Object body) => http.Response(
  json.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _listing(
  String id, {
  String model = 'Camry',
  String sellerId = _ownerId,
  String status = 'active',
}) => {
  'id': id,
  'public_id': id,
  'brand': 'toyota',
  'model': model,
  'title': 'Toyota $model',
  'year': 2020,
  'price': 12000,
  'currency': 'USD',
  'mileage': 1000,
  'city': 'baghdad',
  'location': 'Baghdad',
  'status': status,
  'images': <dynamic>[],
  'videos': <dynamic>[],
  'seller': {'id': sellerId, 'username': 'seller_$sellerId'},
};

/// Scripted backend. Every gate is optional; ungated endpoints answer
/// immediately.
class _Backend {
  final Map<String, Map<String, dynamic>> listings = {};

  /// When set, `/auth/me` waits for it (simulates a slow cold backend).
  Completer<void>? meGate;

  /// When true `/auth/me` fails with a transient network error.
  bool meDown = false;
  String meUserId = _ownerId;

  /// Per-listing gate for `GET /api/cars/<id>`.
  final Map<String, Completer<void>> carGates = {};

  /// Number of upcoming `GET /api/cars/<id>` calls that answer HTTP 500.
  int carFailuresLeft = 0;

  int meCalls = 0;
  final Map<String, int> carCalls = {};

  http.Client client() => MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/auth/me')) {
      meCalls++;
      final gate = meGate;
      if (gate != null) await gate.future;
      if (meDown) throw const SocketException('Network is unreachable');
      return _json(200, {
        'user': {
          'id': meUserId,
          'username': 'u_$meUserId',
          'is_admin': false,
          'is_verified': true,
          'account_type': 'individual',
        },
      });
    }
    if (path.endsWith('/user/my-listings')) {
      return _json(200, {
        'cars': [for (final c in listings.values) c],
        'pagination': {'has_next': false},
      });
    }
    final carMatch = RegExp(r'/cars/([^/]+)$').firstMatch(path);
    if (carMatch != null && request.method == 'GET') {
      final id = carMatch.group(1)!;
      carCalls[id] = (carCalls[id] ?? 0) + 1;
      final gate = carGates[id];
      if (gate != null) await gate.future;
      if (carFailuresLeft > 0) {
        carFailuresLeft--;
        return _json(500, {'message': 'boom'});
      }
      final listing = listings[id];
      if (listing == null) return _json(404, {'message': 'Car not found'});
      return _json(200, {'car': listing});
    }
    return _json(200, {});
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Backend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    TokenStore.testMode = true;
    debugTransientGetRetryDelays = const [Duration.zero, Duration.zero];
    AuthService().resetTestSession();
    backend = _Backend();
    ApiService.testHttpClient = backend.client();
    // A stored token (what a cold start restores) but NO profile yet.
    await ApiService.setTokens(accessToken: 'access', refreshToken: 'refresh');
  });

  tearDown(() async {
    ApiService.testHttpClient = null;
    debugTransientGetRetryDelays = null;
    AuthService().resetTestSession();
    await ApiService.clearTokens();
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  Future<void> settle(WidgetTester tester, [int frames = 20]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget app({
    required Widget home,
    Map<String, WidgetBuilder>? routes,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AuthService>.value(value: AuthService()),
        ChangeNotifierProvider(create: (_) => CarComparisonStore()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
        routes: routes ?? const {},
      ),
    );
  }

  Future<void> pumpDetail(
    WidgetTester tester,
    String carId, {
    bool allowOwnerManagement = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        home: CarDetailsPage(
          carId: carId,
          allowOwnerManagement: allowOwnerManagement,
        ),
      ),
    );
    await settle(tester);
  }

  // The three controls from the bug report.
  final edit = find.byTooltip('Edit');
  final delete = find.byTooltip('Delete');
  final analytics = find.byTooltip('Analytics');
  final resolving = find.byKey(const ValueKey<String>('owner-controls-resolving'));
  final retry = find.byKey(const ValueKey<String>('owner-controls-retry'));
  final report = find.byType(PopupMenuButton<String>);

  void expectOwnerControls({required bool visible, String? reason}) {
    final matcher = visible ? findsOneWidget : findsNothing;
    expect(edit, matcher, reason: reason ?? 'Edit');
    expect(delete, matcher, reason: reason ?? 'Delete');
    expect(analytics, matcher, reason: reason ?? 'Analytics');
  }

  /// Starts the (gated) `/auth/me` that a cold start kicks off.
  Future<void> startProfileLoad() async {
    unawaited(AuthService().refreshProfile());
  }

  testWidgets(
    'A. cold start: details page builds BEFORE /auth/me returns; once the '
    'profile arrives the owner gets Edit/Delete/Analytics WITHOUT a restart',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      await startProfileLoad();

      await pumpDetail(tester, 'car_1');
      expect(find.textContaining('Camry'), findsWidgets);
      expect(AuthService().userId, isNull, reason: 'profile still loading');
      expectOwnerControls(visible: false, reason: 'unknown owner: no controls');

      backend.meGate!.complete(); // /auth/me finally answers
      await settle(tester);

      expect(AuthService().userId, _ownerId);
      expectOwnerControls(visible: true, reason: 'owner after profile load');
      expect(resolving, findsNothing);
      expect(report, findsNothing, reason: 'owner never sees Report');
    },
  );

  testWidgets(
    'A2. while ownership is unknown the app bar shows a "resolving" '
    'indicator (actions are not silently hidden) and no Report menu',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      await startProfileLoad();

      await pumpDetail(tester, 'car_1');
      expectOwnerControls(visible: false);
      expect(resolving, findsOneWidget);
      expect(report, findsNothing, reason: 'owner must not be offered Report');
      backend.meGate!.complete();
      await settle(tester);
    },
  );

  testWidgets(
    'B. profile already loaded before the listing: controls show once the '
    'listing arrives (delayed listing API, loading state in between)',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.carGates['car_1'] = Completer<void>();
      await AuthService().refreshProfile();
      expect(AuthService().userId, _ownerId);

      await pumpDetail(tester, 'car_1');
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expectOwnerControls(visible: false, reason: 'still loading the listing');

      backend.carGates['car_1']!.complete();
      await settle(tester);
      expectOwnerControls(visible: true);
    },
  );

  testWidgets(
    'C. profile resolves while the listing request is still in flight: '
    'ownership is evaluated against the NEW user when the listing lands',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      backend.carGates['car_1'] = Completer<void>();
      await startProfileLoad();

      await pumpDetail(tester, 'car_1');
      backend.meGate!.complete();
      await settle(tester);
      expect(AuthService().userId, _ownerId);

      backend.carGates['car_1']!.complete();
      await settle(tester);
      expectOwnerControls(visible: true);
    },
  );

  testWidgets(
    'D. listing lands first, profile arrives after BOTH similar-cars and '
    'favorites finished (no incidental rebuild left to mask the bug)',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      await startProfileLoad();
      await pumpDetail(tester, 'car_1');
      await tester.pump(const Duration(seconds: 5));
      expectOwnerControls(visible: false);

      backend.meGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expectOwnerControls(visible: true);
    },
  );

  testWidgets(
    "E. another user's listing: controls are never exposed, not even while "
    'the profile is still loading (spinner only) and not after it resolves',
    (tester) async {
      backend.listings['car_x'] = _listing('car_x', sellerId: _otherId);
      backend.meGate = Completer<void>();
      await startProfileLoad();

      await pumpDetail(tester, 'car_x');
      expectOwnerControls(visible: false);

      backend.meGate!.complete();
      await settle(tester);
      expect(AuthService().userId, _ownerId);
      expectOwnerControls(visible: false, reason: 'not the owner');
      expect(resolving, findsNothing, reason: 'resolution finished');
      expect(retry, findsNothing);
      expect(report, findsOneWidget, reason: 'non-owner may report');
    },
  );

  testWidgets(
    'F. other entry points (allowOwnerManagement=false, e.g. Home feed) never '
    'show owner controls, even for the real owner',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      await AuthService().refreshProfile();

      await pumpDetail(tester, 'car_1', allowOwnerManagement: false);
      expectOwnerControls(visible: false);
      expect(resolving, findsNothing);
    },
  );

  testWidgets(
    'G. profile load fails -> controls are not hidden forever: a retry '
    'affordance appears and tapping it brings the controls back',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meDown = true;
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(minutes: 30),
      ];
      await AuthService().refreshProfile(); // fails; retry far in the future
      expect(AuthService().userId, isNull);

      await pumpDetail(tester, 'car_1');
      expectOwnerControls(visible: false);
      expect(retry, findsOneWidget, reason: 'recoverable failure state');

      backend.meDown = false; // network is back
      await tester.tap(retry);
      await settle(tester);

      expect(AuthService().userId, _ownerId);
      expectOwnerControls(visible: true);
      expect(retry, findsNothing);
      // Drain the (now moot) scheduled auto-retry timer.
      await tester.pump(const Duration(minutes: 31));
    },
  );

  testWidgets(
    'H. app backgrounded while /auth/me is outstanding, profile lands while '
    'paused: controls are present on resume (and stay across more cycles)',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      await startProfileLoad();
      await pumpDetail(tester, 'car_1');
      expectOwnerControls(visible: false);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      backend.meGate!.complete();
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expectOwnerControls(visible: true);

      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester);
        expectOwnerControls(visible: true, reason: 'cycle $i');
      }
    },
  );

  testWidgets(
    'I. logout removes the controls immediately; logging back in as the same '
    'owner restores them; a DIFFERENT account never gets them',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      await AuthService().refreshProfile();
      await pumpDetail(tester, 'car_1');
      expectOwnerControls(visible: true);

      // Session ends (token cleared + auth state reset).
      await ApiService.clearTokens();
      AuthService().resetTestSession();
      await settle(tester);
      expectOwnerControls(visible: false, reason: 'logged out');
      expect(resolving, findsNothing, reason: 'no session -> nothing pending');

      // Same owner logs back in.
      await AuthService().adoptTestSession(
        user: {'id': _ownerId, 'username': 'owner'},
      );
      await settle(tester);
      expectOwnerControls(visible: true, reason: 'owner logged back in');

      // A different account on the same device.
      await AuthService().adoptTestSession(
        user: {'id': _otherId, 'username': 'other'},
      );
      await settle(tester);
      expectOwnerControls(visible: false, reason: 'different account');
    },
  );

  testWidgets(
    'J. switching between owned and foreign listings: every page evaluates '
    'ownership for ITS OWN listing, and the first page is intact on return',
    (tester) async {
      backend.listings['car_a'] = _listing('car_a', model: 'Alpha');
      backend.listings['car_b'] = _listing('car_b', model: 'Bravo');
      backend.listings['car_c'] = _listing(
        'car_c',
        model: 'Charlie',
        sellerId: _otherId,
      );
      await AuthService().refreshProfile();

      Widget details(String id) =>
          CarDetailsPage(carId: id, allowOwnerManagement: true);
      await tester.pumpWidget(app(home: details('car_a')));
      await settle(tester);
      expectOwnerControls(visible: true, reason: 'car_a');

      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => details('car_b')));
      await settle(tester);
      expect(find.textContaining('Bravo'), findsWidgets);
      expectOwnerControls(visible: true, reason: 'car_b');

      nav.push(MaterialPageRoute<void>(builder: (_) => details('car_c')));
      await settle(tester);
      expect(find.textContaining('Charlie'), findsWidgets);
      expectOwnerControls(visible: false, reason: 'car_c is foreign');

      nav.pop();
      await settle(tester);
      expectOwnerControls(visible: true, reason: 'back on car_b');
      nav.pop();
      await settle(tester);
      expectOwnerControls(visible: true, reason: 'back on car_a');
    },
  );

  testWidgets(
    'K. listing load failure then Retry: the controls appear after the '
    'successful retry',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.carFailuresLeft = 1;
      await AuthService().refreshProfile();

      await pumpDetail(tester, 'car_1');
      expectOwnerControls(visible: false, reason: 'load failed');
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await settle(tester);
      expectOwnerControls(visible: true);
    },
  );

  testWidgets(
    'L. returning from Edit Listing keeps the controls, even when the edit '
    'result carries no (or a blank) seller',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      await AuthService().refreshProfile();

      for (final editResult in <Map<String, dynamic>>[
        {'id': 'car_1', 'price': 13000}, // form payload: no seller at all
        {'id': 'car_1', 'price': 14000, 'seller': null, 'seller_id': ''},
      ]) {
        await tester.pumpWidget(
          app(
            home: const CarDetailsPage(
              carId: 'car_1',
              allowOwnerManagement: true,
            ),
            routes: {
              '/sell': (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, {'car': editResult}),
                    child: const Text('FINISH EDIT'),
                  ),
                ),
              ),
            },
          ),
        );
        await settle(tester);
        expectOwnerControls(visible: true);

        await tester.tap(edit);
        await settle(tester);
        expect(find.text('FINISH EDIT'), findsOneWidget);
        await tester.tap(find.text('FINISH EDIT'));
        await settle(tester);

        expect(find.text('FINISH EDIT'), findsNothing);
        expectOwnerControls(visible: true, reason: 'after edit $editResult');
      }
    },
  );

  testWidgets(
    'M. cold launch -> My Listings -> My Car -> details, repeatedly, with a '
    'slow /auth/me: controls appear once the profile lands and on every '
    'later visit',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      await startProfileLoad(); // cold start: /auth/me in flight

      await tester.pumpWidget(
        app(
          home: const MyListingsPage(),
          routes: {
            '/car_detail': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map;
              return CarDetailsPage(
                carId: args['carId'].toString(),
                allowOwnerManagement: args['allowOwnerManagement'] == true,
              );
            },
          },
        ),
      );
      await settle(tester);
      expect(find.textContaining('Camry'), findsWidgets);

      Future<void> openAndClose({required bool profileKnown}) async {
        await tester.tap(find.textContaining('Camry').first);
        await settle(tester);
        expect(find.byType(CarDetailsPage), findsOneWidget);
        if (!profileKnown) {
          expectOwnerControls(visible: false, reason: 'profile pending');
          backend.meGate!.complete();
          await settle(tester);
        }
        expectOwnerControls(visible: true, reason: 'owner on details');
        Navigator.of(tester.element(find.byType(CarDetailsPage))).pop();
        await settle(tester);
        expect(find.byType(CarDetailsPage), findsNothing);
      }

      await openAndClose(profileKnown: false);
      for (var i = 0; i < 4; i++) {
        await openAndClose(profileKnown: true);
      }
    },
  );

  testWidgets(
    'N. the same listing reached from My Listings (controls) and from a '
    'non-owner entry point (no controls) behaves per entry point',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      await AuthService().refreshProfile();

      await pumpDetail(tester, 'car_1', allowOwnerManagement: true);
      expectOwnerControls(visible: true);

      await pumpDetail(tester, 'car_1', allowOwnerManagement: false);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpDetail(tester, 'car_1', allowOwnerManagement: false);
      expectOwnerControls(visible: false);
    },
  );

  testWidgets(
    'P. no request storm: the owner listing is re-fetched exactly once when '
    'the profile lands, a foreign listing never, and lifecycle cycles / '
    'repeated profile refreshes add nothing',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.listings['car_x'] = _listing('car_x', sellerId: _otherId);
      backend.meGate = Completer<void>();
      await startProfileLoad();

      await pumpDetail(tester, 'car_1');
      expect(backend.carCalls['car_1'], 1);
      backend.meGate!.complete();
      await settle(tester);
      expectOwnerControls(visible: true);
      expect(backend.carCalls['car_1'], 2, reason: 'one quiet owner refresh');

      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await AuthService().refreshProfile(); // same user again
        await settle(tester);
      }
      expect(backend.carCalls['car_1'], 2, reason: 'same user: no reload');

      await tester.pumpWidget(const SizedBox.shrink());
      AuthService().resetTestSession();
      await ApiService.setTokens(accessToken: 'a2', refreshToken: 'r2');
      backend.meGate = Completer<void>();
      await startProfileLoad();
      await pumpDetail(tester, 'car_x');
      backend.meGate!.complete();
      await settle(tester);
      expectOwnerControls(visible: false);
      expect(backend.carCalls['car_x'], 1, reason: 'foreign: never reloaded');
    },
  );

  testWidgets(
    'O. listing-status restrictions are untouched: a sold listing still '
    'offers the controls to its owner (with the undo-sold action), and an '
    'unrelated viewer still gets nothing',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1', status: 'sold');
      backend.listings['car_2'] = _listing(
        'car_2',
        status: 'sold',
        sellerId: _otherId,
      );
      await AuthService().refreshProfile();

      await pumpDetail(tester, 'car_1');
      expectOwnerControls(visible: true);
      expect(find.byTooltip('Mark as available'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpDetail(tester, 'car_2');
      expectOwnerControls(visible: false);
    },
  );
}
