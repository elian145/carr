// Regression tests: Edit / Delete / Analytics on Listing Details opened from
// My Listings must be there on the FIRST render of a cold start.
//
// Root cause pinned here: the signed-in account's id used to come only from
// `/auth/me`, but `AuthGuard` mounts My Listings as soon as a stored token
// exists -- BEFORE `/auth/me` returns -- so My Listings -> My Car -> Listing
// Details could be fully built while `AuthService.userId` was still null, and
// `CarDetailsPage` (which read it once with `listen: false`) stayed "not the
// owner" until the app was restarted.
//
// The fix restores the account id from the persisted session's own tokens
// (`SessionIdentity`) so ownership is known immediately, keeps verifying the
// profile in the background, and follows the account reactively. These tests
// drive the real pages with a scripted MockClient + Completers (no real
// network or timing) and assert -- on EVERY frame -- that no ownership
// spinner or Retry button ever stands in for the buttons.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/comparison/state/car_comparison_store.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/car_details_page.dart';
import 'package:car_listing_app/pages/my_listings_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/connectivity_service.dart';
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

import 'support/fake_session_jwt.dart';

// Backend public ids are UUIDs; the JWT `sub` carries exactly this value.
const _ownerId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const _otherId = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';

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

/// Persists a session the way a cold start finds it: both tokens issued for
/// [accountId] (the backend's `identity=public_id`).
Future<void> _storeSessionFor(String accountId) => ApiService.setTokens(
  accessToken: fakeSessionJwt(accountId),
  refreshToken: fakeSessionJwt(accountId, type: 'refresh'),
);

/// Scripted backend. Every gate is optional; ungated endpoints answer
/// immediately.
class _Backend {
  final Map<String, Map<String, dynamic>> listings = {};

  /// When set, `/auth/me` waits for it (simulates a slow cold backend).
  Completer<void>? meGate;

  /// When true `/auth/me` fails with a transient network error.
  bool meDown = false;
  String meUserId = _ownerId;

  /// When set, `POST /auth/logout` waits for it (slow server revocation).
  Completer<void>? logoutGate;

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
    if (path.endsWith('/auth/logout')) {
      final gate = logoutGate;
      if (gate != null) await gate.future;
      return _json(200, {});
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
    // What a cold start restores: a stored session for the owner, and NO
    // profile yet (AuthService has not loaded /auth/me).
    await _storeSessionFor(_ownerId);
  });

  tearDown(() async {
    ApiService.testHttpClient = null;
    debugTransientGetRetryDelays = null;
    AuthService().resetTestSession();
    await ApiService.clearTokens();
    ConnectivityService.instance.isOnline.value = true;
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  // The three controls from the bug report.
  final edit = find.byTooltip('Edit');
  final delete = find.byTooltip('Delete');
  final analytics = find.byTooltip('Analytics');
  final report = find.byType(PopupMenuButton<String>);

  void expectOwnerControls({required bool visible, String? reason}) {
    final matcher = visible ? findsOneWidget : findsNothing;
    expect(edit, matcher, reason: reason ?? 'Edit');
    expect(delete, matcher, reason: reason ?? 'Delete');
    expect(analytics, matcher, reason: reason ?? 'Analytics');
  }

  /// UX contract: no ownership spinner, no Retry (tooltip or refresh icon)
  /// may ever stand in for / sit beside the owner buttons in the app bar.
  void expectNoOwnerPlaceholders() {
    final bar = find.byType(SliverAppBar);
    for (final f in [
      find.descendant(of: bar, matching: find.byType(CircularProgressIndicator)),
      find.descendant(of: bar, matching: find.byTooltip('Retry')),
      find.descendant(of: bar, matching: find.byIcon(Icons.refresh)),
      find.byKey(const ValueKey<String>('owner-controls-resolving')),
      find.byKey(const ValueKey<String>('owner-controls-retry')),
    ]) {
      expect(f, findsNothing, reason: 'ownership placeholder in app bar');
    }
  }

  /// Pumps frames, asserting EVERY frame: no placeholders, and -- from the
  /// frame the listing first appears -- the owner controls are exactly
  /// [ownerVisible] (so a flicker, or a late appearance, fails the test).
  Future<void> settle(
    WidgetTester tester, {
    int frames = 20,
    bool? ownerVisible,
    String model = 'Camry',
  }) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expectNoOwnerPlaceholders();
      if (ownerVisible != null &&
          find.byType(CarDetailsPage).evaluate().isNotEmpty &&
          find.textContaining(model).evaluate().isNotEmpty) {
        expectOwnerControls(
          visible: ownerVisible,
          reason: 'frame $i (listing rendered)',
        );
      }
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
    bool? ownerVisible,
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
    await settle(tester, ownerVisible: ownerVisible);
  }

  /// Starts the (gated) `/auth/me` that a cold start kicks off.
  void startProfileLoad() => unawaited(AuthService().refreshProfile());

  testWidgets(
    'A. cold start, /auth/me still pending: the owner sees Edit/Delete/'
    'Analytics on the first render of the listing -- no profile round trip, '
    'no spinner, no Retry -- and they do not flicker when the profile lands',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>(); // /auth/me never answers (yet)
      startProfileLoad();

      await pumpDetail(tester, 'car_1', ownerVisible: true);
      expect(find.textContaining('Camry'), findsWidgets);
      expect(AuthService().currentUser, isNull, reason: 'profile NOT loaded');
      expectOwnerControls(visible: true, reason: 'with /auth/me pending');
      expect(report, findsNothing, reason: 'owner never sees Report');

      backend.meGate!.complete(); // verification finishes in the background
      await settle(tester, ownerVisible: true);
      expect(AuthService().currentUser, isNotNull);
      expect(AuthService().userId, _ownerId);
      expectOwnerControls(visible: true);
      expect(report, findsNothing);
    },
  );

  testWidgets(
    'A2. normal authenticated flow: no ownership spinner and no Retry button '
    'anywhere in the app bar, before, during and after profile verification',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      startProfileLoad();

      await pumpDetail(tester, 'car_1', ownerVisible: true);
      expectNoOwnerPlaceholders();
      expect(find.byTooltip('Retry'), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SliverAppBar),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );

      backend.meGate!.complete();
      await settle(tester, ownerVisible: true);
      expectNoOwnerPlaceholders();
      expect(find.byTooltip('Retry'), findsNothing);
    },
  );

  testWidgets(
    'B. profile already loaded, listing slow: controls show the moment the '
    'listing arrives',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.carGates['car_1'] = Completer<void>();
      await AuthService().refreshProfile();
      expect(AuthService().userId, _ownerId);

      await pumpDetail(tester, 'car_1');
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expectOwnerControls(visible: false, reason: 'listing not loaded yet');

      backend.carGates['car_1']!.complete();
      await settle(tester, ownerVisible: true);
      expectOwnerControls(visible: true);
    },
  );

  testWidgets(
    'C. everything slow (profile AND listing): the controls appear with the '
    'listing, whichever finishes first, and the listing is fetched ONCE',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      backend.carGates['car_1'] = Completer<void>();
      startProfileLoad();

      await pumpDetail(tester, 'car_1');
      backend.meGate!.complete();
      await settle(tester);
      expectOwnerControls(visible: false, reason: 'listing still loading');

      backend.carGates['car_1']!.complete();
      await settle(tester, ownerVisible: true);
      expectOwnerControls(visible: true);
      expect(backend.carCalls['car_1'], 1, reason: 'no duplicate request');
    },
  );

  testWidgets(
    "D. another user's listing: owner controls are NEVER exposed -- not "
    'before the profile lands, not after -- and the Report menu stays',
    (tester) async {
      backend.listings['car_x'] = _listing('car_x', sellerId: _otherId);
      backend.meGate = Completer<void>();
      startProfileLoad();

      await pumpDetail(tester, 'car_x', ownerVisible: false);
      expectOwnerControls(visible: false);

      backend.meGate!.complete();
      await settle(tester, ownerVisible: false);
      expect(AuthService().userId, _ownerId);
      expectOwnerControls(visible: false, reason: 'not the owner');
      expect(report, findsOneWidget, reason: 'non-owner may report');
      expect(backend.carCalls['car_x'], 1);
    },
  );

  testWidgets(
    'E. Search / Home entry points (allowOwnerManagement=false) never show '
    'owner controls, even to the real owner with a fully restored session',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      await AuthService().refreshProfile();

      await pumpDetail(tester, 'car_1', allowOwnerManagement: false);
      expect(AuthService().userId, _ownerId);
      expectOwnerControls(visible: false, reason: 'navigation origin');
      await settle(tester, ownerVisible: false);
    },
  );

  testWidgets(
    'F. forged / foreign session: tokens that name ANOTHER account never '
    "unlock someone else's listing controls",
    (tester) async {
      await _storeSessionFor(_otherId); // device is signed in as "other"
      backend.meUserId = _otherId;
      backend.listings['car_1'] = _listing('car_1'); // owned by _ownerId
      startProfileLoad();

      await pumpDetail(tester, 'car_1', ownerVisible: false);
      await settle(tester, ownerVisible: false);
      expect(AuthService().userId, _otherId);
      expectOwnerControls(visible: false);
    },
  );

  testWidgets(
    'G. temporary /auth/me network failure: controls stay, no Retry button, '
    'and the profile recovers automatically (bounded backoff)',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meDown = true;
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(seconds: 1),
        Duration(seconds: 1),
      ];
      startProfileLoad();

      await pumpDetail(tester, 'car_1', ownerVisible: true);
      expect(AuthService().currentUser, isNull, reason: '/auth/me is down');
      expectOwnerControls(visible: true, reason: 'despite the failure');
      expect(find.byTooltip('Retry'), findsNothing);

      backend.meDown = false; // network back; the automatic retry succeeds
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
        expectNoOwnerPlaceholders();
        expectOwnerControls(visible: true, reason: 'retry tick $i');
      }
      await settle(tester, ownerVisible: true);
      expect(AuthService().currentUser, isNotNull, reason: 'auto recovered');
      expect(AuthService().userId, _ownerId);
    },
  );

  testWidgets(
    'G2. /auth/me failure with the retry budget spent: connectivity coming '
    'back (offline -> online) recovers the profile by itself; controls never '
    'depend on it',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meDown = true;
      AuthService.debugProfileRetryDelaysOverride = const [
        Duration(minutes: 30),
      ];
      AuthService().hookConnectivityRecovery();
      ConnectivityService.instance.isOnline.value = false;
      await AuthService().refreshProfile();
      expect(AuthService().isProfileStranded, isTrue);

      await pumpDetail(tester, 'car_1', ownerVisible: true);
      expectOwnerControls(visible: true, reason: 'offline');

      backend.meDown = false;
      ConnectivityService.instance.isOnline.value = true;
      await settle(tester, ownerVisible: true);
      expect(AuthService().currentUser, isNotNull);
      expectOwnerControls(visible: true);
      await tester.pump(const Duration(minutes: 31)); // drain stale timer
    },
  );

  testWidgets(
    'H. app backgrounded while /auth/me is outstanding and resumed (several '
    'cycles): the controls are present throughout',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      startProfileLoad();
      await pumpDetail(tester, 'car_1', ownerVisible: true);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      backend.meGate!.complete();
      await settle(tester, ownerVisible: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester, ownerVisible: true);

      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester, ownerVisible: true);
        expectOwnerControls(visible: true, reason: 'cycle $i');
      }
    },
  );

  testWidgets(
    'H2. access-token refresh / rotation (new tokens, same account) while '
    'the page is shown and while /auth/me is outstanding: the controls never '
    'flicker, and nothing is re-fetched',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      startProfileLoad();
      await pumpDetail(tester, 'car_1', ownerVisible: true);

      for (var i = 0; i < 3; i++) {
        await _storeSessionFor(_ownerId); // rotated tokens, same account
        await settle(tester, frames: 3, ownerVisible: true);
        expectOwnerControls(visible: true, reason: 'rotation $i');
      }
      backend.meGate!.complete();
      await settle(tester, ownerVisible: true);
      expect(AuthService().currentUser, isNotNull, reason: 'profile kept');
      await _storeSessionFor(_ownerId);
      await settle(tester, ownerVisible: true);
      expect(backend.carCalls['car_1'], 1);
      expect(backend.meCalls, 1);
    },
  );

  testWidgets(
    'I. session ends: the previous owner\'s controls disappear IMMEDIATELY '
    '(token loss with no profile ever loaded, and logout before the server '
    'call returns)',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      startProfileLoad(); // profile never loads in this scenario
      await pumpDetail(tester, 'car_1', ownerVisible: true);

      // Session rejected / cleared out of band.
      await ApiService.clearTokens();
      await tester.pump();
      expectOwnerControls(visible: false, reason: 'session lost');
      expectNoOwnerPlaceholders();
      backend.meGate!.complete();
      await settle(tester);

      // Fresh app: owner signs in again, then logs out with a SLOW server.
      await tester.pumpWidget(const SizedBox.shrink());
      AuthService().resetTestSession();
      await _storeSessionFor(_ownerId);
      backend.meGate = null;
      await AuthService().refreshProfile();
      await pumpDetail(tester, 'car_1', ownerVisible: true);

      backend.logoutGate = Completer<void>();
      final loggingOut = AuthService().logout();
      await tester.pump(); // server has NOT answered
      expectOwnerControls(visible: false, reason: 'logout in progress');
      expectNoOwnerPlaceholders();
      backend.logoutGate!.complete();
      await loggingOut;
      await settle(tester);
      expectOwnerControls(visible: false, reason: 'logged out');
    },
  );

  testWidgets(
    'I2. account switch: a DIFFERENT account on the same device never gets '
    "the previous owner's controls; the owner gets them back on return",
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      await AuthService().refreshProfile();
      await pumpDetail(tester, 'car_1', ownerVisible: true);

      // Another account logs in: its tokens replace the owner's.
      await _storeSessionFor(_otherId);
      backend.meUserId = _otherId;
      await AuthService().refreshProfile();
      await settle(tester, ownerVisible: false);
      expectOwnerControls(visible: false, reason: 'different account');
      expect(AuthService().userId, _otherId);

      // The owner logs back in.
      await _storeSessionFor(_ownerId);
      backend.meUserId = _ownerId;
      await AuthService().refreshProfile();
      await settle(tester, ownerVisible: true);
      expectOwnerControls(visible: true, reason: 'owner back');
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
    'K. listing load failure then Retry (the LISTING\'s own retry): the '
    'controls appear after the successful retry',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.carFailuresLeft = 1;
      await AuthService().refreshProfile();

      await pumpDetail(tester, 'car_1');
      expectOwnerControls(visible: false, reason: 'load failed');
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await settle(tester, ownerVisible: true);
      expectOwnerControls(visible: true);
    },
  );

  testWidgets(
    'L. returning from Edit Listing keeps the controls, even when the edit '
    'result carries no (or a blank) seller',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');

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
        await settle(tester, ownerVisible: true);
        expectOwnerControls(visible: true);

        await tester.tap(edit);
        await settle(tester);
        expect(find.text('FINISH EDIT'), findsOneWidget);
        await tester.tap(find.text('FINISH EDIT'));
        await settle(tester, ownerVisible: true);

        expect(find.text('FINISH EDIT'), findsNothing);
        expectOwnerControls(visible: true, reason: 'after edit $editResult');
      }
    },
  );

  testWidgets(
    'M. cold launch -> My Listings -> My Car -> details, repeatedly, while '
    '/auth/me is slow: the controls are there on the FIRST open and on every '
    'later visit',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.meGate = Completer<void>();
      startProfileLoad(); // cold start: /auth/me in flight

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
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.textContaining('Camry'), findsWidgets);

      Future<void> openAndClose() async {
        await tester.tap(find.textContaining('Camry').first);
        await settle(tester, ownerVisible: true);
        expect(find.byType(CarDetailsPage), findsOneWidget);
        expectOwnerControls(visible: true, reason: 'owner on details');
        Navigator.of(tester.element(find.byType(CarDetailsPage))).pop();
        await settle(tester);
        expect(find.byType(CarDetailsPage), findsNothing);
      }

      await openAndClose(); // profile STILL not loaded
      expect(AuthService().currentUser, isNull);
      backend.meGate!.complete();
      await settle(tester);
      for (var i = 0; i < 3; i++) {
        await openAndClose();
      }
      expect(backend.meCalls, 1, reason: 'one background verification only');
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

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpDetail(tester, 'car_1', allowOwnerManagement: false);
      expectOwnerControls(visible: false);
    },
  );

  testWidgets(
    'P. no request storm: the owner listing and /auth/me are each requested '
    'exactly once on a cold start, a foreign listing once, and lifecycle '
    'cycles / same-user refreshes add no listing requests',
    (tester) async {
      backend.listings['car_1'] = _listing('car_1');
      backend.listings['car_x'] = _listing('car_x', sellerId: _otherId);
      backend.meGate = Completer<void>();
      startProfileLoad();

      await pumpDetail(tester, 'car_1', ownerVisible: true);
      expect(backend.carCalls['car_1'], 1);
      backend.meGate!.complete();
      await settle(tester, ownerVisible: true);
      expect(backend.carCalls['car_1'], 1, reason: 'profile landing: no reload');
      expect(backend.meCalls, 1, reason: 'page adds no /auth/me request');

      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await AuthService().refreshProfile(); // same user again
        await settle(tester, ownerVisible: true);
      }
      expect(backend.carCalls['car_1'], 1, reason: 'same user: no reload');

      await tester.pumpWidget(const SizedBox.shrink());
      AuthService().resetTestSession();
      await _storeSessionFor(_ownerId);
      backend.meGate = Completer<void>();
      startProfileLoad();
      await pumpDetail(tester, 'car_x', ownerVisible: false);
      backend.meGate!.complete();
      await settle(tester, ownerVisible: false);
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

      await pumpDetail(tester, 'car_1', ownerVisible: true);
      expectOwnerControls(visible: true);
      expect(find.byTooltip('Mark as available'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpDetail(tester, 'car_2', ownerVisible: false);
      expectOwnerControls(visible: false);
    },
  );

  group('existing installs / sessions whose account id cannot be read '
      'from the tokens', () {
    testWidgets(
      'Q. opaque (legacy) tokens: nothing is granted from the unknown '
      'session, the page itself triggers profile recovery automatically, and '
      'the owner then gets the controls -- never a spinner or Retry',
      (tester) async {
        await ApiService.setTokens(
          accessToken: 'opaque-legacy-access',
          refreshToken: 'opaque-legacy-refresh',
        );
        backend.listings['car_1'] = _listing('car_1');
        backend.meGate = Completer<void>();

        await pumpDetail(tester, 'car_1', ownerVisible: null);
        expect(AuthService().userId, isNull, reason: 'cannot be known yet');
        expectOwnerControls(visible: false, reason: 'unverified: no controls');
        expectNoOwnerPlaceholders();
        expect(backend.meCalls, 1, reason: 'recovery started automatically');

        backend.meGate!.complete();
        await settle(tester, ownerVisible: true);
        expect(AuthService().userId, _ownerId);
        expectOwnerControls(visible: true);
        expect(backend.meCalls, 1, reason: 'single-flight, no duplicates');
      },
    );

    testWidgets(
      'Q2. legacy numeric-subject token (not a public id): treated as '
      'unknown, never matched against listings; recovers via the profile',
      (tester) async {
        await ApiService.setTokens(
          accessToken: fakeSessionJwt('42'),
          refreshToken: fakeSessionJwt('42', type: 'refresh'),
        );
        backend.listings['car_1'] = _listing('car_1');

        await pumpDetail(tester, 'car_1');
        await settle(tester, ownerVisible: true);
        expect(AuthService().userId, _ownerId);
        expectOwnerControls(visible: true);
      },
    );

    testWidgets(
      'Q3. expired access token but valid refresh token (cold start after '
      '>30 minutes): the identity still restores immediately',
      (tester) async {
        await ApiService.setTokens(
          accessToken: fakeSessionJwt(
            _ownerId,
            expiresIn: const Duration(hours: -3),
          ),
          refreshToken: fakeSessionJwt(
            _ownerId,
            type: 'refresh',
            expiresIn: const Duration(days: 20),
          ),
        );
        backend.listings['car_1'] = _listing('car_1');
        backend.meGate = Completer<void>();
        startProfileLoad();

        await pumpDetail(tester, 'car_1', ownerVisible: true);
        expectOwnerControls(visible: true, reason: 'profile pending');
        backend.meGate!.complete();
        await settle(tester, ownerVisible: true);
      },
    );

    testWidgets(
      'Q4. a dead session (both tokens expired) restores NO identity, so '
      'no controls are granted from it',
      (tester) async {
        await ApiService.setTokens(
          accessToken: fakeSessionJwt(
            _ownerId,
            expiresIn: const Duration(hours: -3),
          ),
          refreshToken: fakeSessionJwt(
            _ownerId,
            type: 'refresh',
            expiresIn: const Duration(days: -1),
          ),
        );
        backend.listings['car_1'] = _listing('car_1');
        backend.meGate = Completer<void>(); // never answers

        await pumpDetail(tester, 'car_1');
        expect(AuthService().userId, isNull);
        expectOwnerControls(visible: false);
        expectNoOwnerPlaceholders();
        backend.meGate!.complete();
        await settle(tester);
      },
    );
  });
}
