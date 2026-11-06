// Focused session-race regressions for the account-isolation integration.
//
// Every test forces the race with CONTROLLED BARRIERS (completers) -- never
// sleeps:
//   * `TokenStore.debugIoGate` holds one credential load/save/clear half-way,
//   * `SavedSearchService.debugAfterLocalPersist` holds a local save,
//   * a mock HTTP server holds one response,
//   * `AccountLocalData.runForOwner` holds the on-device re-scoping queue.
//
// 1. SavedSearchService.upsertFromFilters never syncs account A's data with
//    account B's credentials.
// 2. A request started WITHOUT credentials never adopts an unrelated account
//    that signs in meanwhile -- while cold-start restoration still works.
// 3. Overlapping login / logout / refresh / initialisation can never leave a
//    stale session's tokens in memory or storage, run its cleanup, or
//    activate the wrong account's local data.
// 4. loadMerged and the Saved Searches page never show another session's
//    results, and reload on account change.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/saved_searches_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/services/saved_search_service.dart';
import 'package:car_listing_app/shared/auth/account_scope.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/prefs/account_local_data.dart';

import 'support/test_jwt.dart';

// ---------------------------------------------------------------------------
// Controlled barrier.
// ---------------------------------------------------------------------------
class _Gate {
  final Completer<void> _reached = Completer<void>();
  final Completer<void> _release = Completer<void>();
  bool _armed = true;

  Future<void> get reached => _reached.future;
  bool get hasBeenReached => _reached.isCompleted;

  /// Called by the code under test: the FIRST call parks until [open].
  Future<void> hit() async {
    if (!_armed) return;
    _armed = false;
    _reached.complete();
    await _release.future;
  }

  void open() {
    if (!_release.isCompleted) _release.complete();
  }
}

class _Call {
  _Call(this.method, this.path, this.actor);
  final String method;
  final String path;
  final String? actor;
}

class _Srv {
  final List<_Call> calls = <_Call>[];
  final Set<String> validAccess = <String>{};
  int _n = 0;

  /// Parks the saved-search LIST response of this actor until opened.
  final Map<String, _Gate> listGate = <String, _Gate>{};

  List<_Call> to(String method, String suffix) => calls
      .where((c) => c.method == method && c.path.endsWith(suffix))
      .toList();

  http.Response _j(int code, Object body) => http.Response(
        json.encode(body),
        code,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic> _row(String actor) => {
        'id': '00000000-0000-4000-8000-${actor.padRight(12, '0')}',
        'name': '$actor search',
        'filters': {'min_price': actor == 'A' ? '1000' : '2000'},
        'notify': true,
        'auto_saved': false,
        'created_at': '2026-01-01T00:00:00',
      };

  Future<http.Response> handle(http.Request r) async {
    final h = r.headers['Authorization'] ?? r.headers['authorization'];
    final token =
        (h != null && h.startsWith('Bearer ')) ? h.substring(7) : null;
    final actor = testJwtSubject(token);
    final path = r.url.path;
    calls.add(_Call(r.method, path, actor));

    if (path.endsWith('/auth/refresh')) {
      if (actor == null) return _j(401, {'message': 'bad'});
      final access = testJwt(actor, nonce: 'rot${++_n}');
      validAccess.add(access);
      return _j(200, {
        'access_token': access,
        'refresh_token': testJwt(actor, nonce: 'rrot$_n', type: 'refresh'),
      });
    }
    if (token == null || !validAccess.contains(token)) {
      return _j(401, {'message': 'unauthorized'});
    }
    if (path.endsWith('/auth/me')) return _j(200, {'id': actor});
    if (path.endsWith('/ping')) return _j(200, {'ok': true, 'actor': actor});
    if (path.endsWith('/saved-searches/sync')) {
      return _j(200, {
        'saved_searches': [_row(actor!)],
      });
    }
    if (path.endsWith('/saved-searches')) {
      if (r.method == 'GET') {
        final gate = listGate[actor];
        if (gate != null) await gate.hit();
        return _j(200, {
          'saved_searches': [_row(actor!)],
        });
      }
      return _j(201, {
        'saved_search': {'id': '11111111-1111-4111-8111-111111111111'},
      });
    }
    return _j(404, {'message': 'nf $path'});
  }
}

late _Srv _srv;
int _loginN = 0;
String? _lastAccess;
String? _lastRefresh;

Future<void> login(String acct, {bool validNow = true}) {
  final access = testJwt(acct, nonce: 'l${++_loginN}');
  final refresh = testJwt(acct, nonce: 'lr$_loginN', type: 'refresh');
  _lastAccess = access;
  _lastRefresh = refresh;
  if (validNow) _srv.validAccess.add(access);
  return ApiService.setTokens(accessToken: access, refreshToken: refresh);
}

Future<Object?> outcome(Future<Object?> f) =>
    f.then<Object?>((v) => v, onError: (Object e) => e);

Future<String?> marker() async =>
    (await SharedPreferences.getInstance()).getString(
      AccountLocalData.markerKey,
    );

void main() {
  void Function()? previousOnCleared;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    previousOnCleared = ApiService.onTokensCleared;
  });

  setUp(() async {
    TokenStore.testMode = true;
    TokenStore.resetForTests();
    TokenStore.debugIoGate = null;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    SharedPreferences.setMockInitialValues({});
    _srv = _Srv();
    ApiService.testHttpClient = MockClient(_srv.handle);
    ApiService.debugResetSessionForTests();
    SavedSearchService.debugResetLegacyPurgeFlag();
    SavedSearchService.debugAfterLocalPersist = null;
    await ApiService.clearTokens();
    _srv.calls.clear();
  });

  tearDown(() async {
    TokenStore.debugIoGate = null;
    SavedSearchService.debugAfterLocalPersist = null;
    ApiService.onTokensCleared = previousOnCleared;
    await ApiService.clearTokens();
    ApiService.testHttpClient = null;
    // ignore: invalid_use_of_visible_for_testing_member
    AccountLocalData.debugReset();
    TokenStore.resetForTests();
  });

  // =========================================================================
  group('1. SavedSearchService.upsertFromFilters', () {
    test('control: an untouched session pushes the search as the SAME account',
        () async {
      await login('A');
      await SavedSearchService.upsertFromFilters(
        filters: {'min_price': '1000'},
        name: 'A search',
      );
      await pumpEventQueue();
      final posts = _srv.to('POST', '/saved-searches');
      expect(posts, hasLength(1));
      expect(posts.single.actor, 'A');
    });

    test('account A switching to B during the async save: A\'s search is '
        'never pushed with B\'s credentials', () async {
      await login('A');
      final gate = _Gate();
      SavedSearchService.debugAfterLocalPersist = gate.hit;

      final save = SavedSearchService.upsertFromFilters(
        filters: {'min_price': '1000'},
        name: 'A search',
      );
      await gate.reached; // A's local write is done; the push is next
      await login('B'); // account switch in the middle of the save
      gate.open();
      await save;
      await pumpEventQueue();

      expect(_srv.to('POST', '/saved-searches'), isEmpty,
          reason: "no create/update may leave the device for A's data");
      expect(_srv.to('PUT', ''), isEmpty);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(SavedSearchService.localKeyForOwner('A')),
          contains('A search'),
          reason: "A's own local copy is kept (legitimate data preserved)");
      expect(sp.getString(SavedSearchService.localKeyForOwner('B')), isNull,
          reason: 'nothing leaks into B');
    });

    test('a save started as a GUEST is never pushed into the account that '
        'signs in meanwhile', () async {
      expect(ApiService.isAuthenticated, isFalse);
      final save = SavedSearchService.upsertFromFilters(
        filters: {'min_price': '1000'},
        name: 'guest search',
      );
      final signIn = login('B'); // signs in while the save is in flight
      await Future.wait<Object?>([save, signIn]);
      await pumpEventQueue();

      expect(_srv.to('POST', '/saved-searches'), isEmpty);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(SavedSearchService.localKeyForOwner('B')), isNull);
    });
  });

  // =========================================================================
  group('2. a request started without credentials', () {
    Future<void> persistedSessionOf(String acct) async {
      await TokenStore.save(testJwt(acct, nonce: 'persisted'));
      await TokenStore.saveRefresh(
        testJwt(acct, nonce: 'persistedR', type: 'refresh'),
      );
      _srv.validAccess.add(TokenStore.token!);
    }

    test('does NOT adopt an unrelated account that signs in while the '
        'persisted session is being read', () async {
      await persistedSessionOf('A');
      final gate = _Gate();
      TokenStore.debugIoGate = (op) async {
        if (op == 'load') await gate.hit();
      };

      final request = outcome(
        ApiService.makeAuthenticatedRequest('GET', '/ping'),
      );
      await gate.reached;
      final signIn = login('B');
      await pumpEventQueue();
      expect(ApiService.currentAccountId, 'B');
      gate.open();
      await signIn;

      expect(await request, isA<ApiSessionChangedException>());
      expect(_srv.to('GET', '/ping'), isEmpty,
          reason: 'the call began without credentials: it must not be sent '
              "under B's (or A's persisted) credentials");
      expect(ApiService.currentAccountId, 'B');
      expect(testJwtSubject(TokenStore.token), 'B',
          reason: "B's persisted session is not overwritten by the stale "
              'read');
    });

    test('does NOT resurrect a session that was signed out while the '
        'persisted session was being read', () async {
      await persistedSessionOf('A');
      final gate = _Gate();
      TokenStore.debugIoGate = (op) async {
        if (op == 'load') await gate.hit();
      };

      final request = outcome(
        ApiService.makeAuthenticatedRequest('GET', '/ping'),
      );
      await gate.reached;
      final clearing = ApiService.clearTokens();
      await pumpEventQueue();
      gate.open();
      await clearing;

      expect(await request, isA<ApiSessionChangedException>());
      expect(_srv.calls.where((c) => c.path.endsWith('/ping')), isEmpty);
      expect(ApiService.isAuthenticated, isFalse);
      expect(TokenStore.token, isNull);
    });

    test('control: legitimate cold-start restoration still works, for '
        'concurrent callers too', () async {
      await persistedSessionOf('A');
      final gate = _Gate();
      TokenStore.debugIoGate = (op) async {
        if (op == 'load') await gate.hit();
      };

      final first = ApiService.makeAuthenticatedRequest('GET', '/ping');
      final second = ApiService.makeAuthenticatedRequest('GET', '/ping');
      await gate.reached;
      gate.open();
      final results = await Future.wait([first, second]);

      expect(results.map((r) => r['actor']), ['A', 'A']);
      expect(ApiService.currentAccountId, 'A');
      expect(ApiService.isAuthenticated, isTrue);
    });
  });

  // =========================================================================
  group('3. overlapping token persistence', () {
    test('a refresh rotation still being persisted cannot resurrect a '
        'session that was signed out meanwhile', () async {
      await login('A', validNow: false); // server rejects it -> refresh path
      final gate = _Gate();
      TokenStore.debugIoGate = (op) async {
        if (op == 'save') await gate.hit();
      };

      final request = outcome(
        ApiService.makeAuthenticatedRequest('GET', '/ping'),
      );
      await gate.reached; // the rotated token is being persisted
      final clearing = ApiService.clearTokens();
      await pumpEventQueue();
      gate.open();
      await clearing;

      expect(await request, isA<ApiSessionChangedException>());
      expect(ApiService.isAuthenticated, isFalse);
      expect(ApiService.accessToken, isNull);
      expect(ApiService.refreshToken, isNull);
      expect(ApiService.currentAccountId, isNull);
      expect(TokenStore.token, isNull, reason: 'persisted token resurrected');
      expect(TokenStore.refreshToken, isNull);
      expect(await marker(), AccountLocalData.guestOwner);
    });

    test('a rotation still being persisted for A cannot overwrite the '
        'access OR refresh token of the account that logged in meanwhile',
        () async {
      await login('A', validNow: false);
      final gate = _Gate();
      TokenStore.debugIoGate = (op) async {
        if (op == 'save') await gate.hit();
      };

      final request = outcome(
        ApiService.makeAuthenticatedRequest('GET', '/ping'),
      );
      await gate.reached;
      final signIn = login('B');
      final bAccess = _lastAccess!;
      final bRefresh = _lastRefresh!;
      await pumpEventQueue();
      gate.open();
      await signIn;

      expect(await request, isA<ApiSessionChangedException>());
      expect(ApiService.accessToken, bAccess);
      expect(ApiService.refreshToken, bRefresh);
      expect(ApiService.currentAccountId, 'B');
      expect(TokenStore.token, bAccess);
      expect(TokenStore.refreshToken, bRefresh);
      expect(await marker(), 'B');
    });

    test('a slow login persist for A cannot overwrite B\'s memory, B\'s '
        'persisted credentials, or leave A\'s data active', () async {
      final gate = _Gate();
      TokenStore.debugIoGate = (op) async {
        if (op == 'save') await gate.hit();
      };

      final a = login('A');
      await gate.reached; // A's credentials are half-way to storage
      final b = login('B');
      final bAccess = _lastAccess!;
      final bRefresh = _lastRefresh!;
      await pumpEventQueue();
      gate.open();
      await Future.wait<Object?>([a, b]);

      expect(ApiService.accessToken, bAccess);
      expect(ApiService.refreshToken, bRefresh);
      expect(ApiService.currentAccountId, 'B');
      expect(TokenStore.token, bAccess);
      expect(TokenStore.refreshToken, bRefresh);
      expect(await marker(), 'B', reason: "A's activation must not win");
    });

    test('a slow sign-out of A cannot wipe B\'s session, run B\'s '
        'cleanup, or activate the guest scope', () async {
      await login('A');
      var cleaned = 0;
      ApiService.onTokensCleared = () => cleaned++;
      final gate = _Gate();
      TokenStore.debugIoGate = (op) async {
        if (op == 'clear') await gate.hit();
      };

      final clearing = ApiService.clearTokens();
      await gate.reached;
      final signIn = login('B');
      final bAccess = _lastAccess!;
      await pumpEventQueue();
      gate.open();
      await Future.wait<Object?>([clearing, signIn]);

      expect(cleaned, 0, reason: "B must not be cleaned up by A's sign-out");
      expect(ApiService.accessToken, bAccess);
      expect(ApiService.currentAccountId, 'B');
      expect(TokenStore.token, bAccess,
          reason: "A's slow clear wiped B's persisted credentials");
      expect(await marker(), 'B');
    });

    test('an ordinary sign-out still runs its cleanup exactly once',
        () async {
      await login('A');
      var cleaned = 0;
      ApiService.onTokensCleared = () => cleaned++;
      await ApiService.clearTokens();
      expect(cleaned, 1);
      expect(ApiService.isAuthenticated, isFalse);
      expect(await marker(), AccountLocalData.guestOwner);
    });

    test('two overlapping sign-outs run the cleanup once, not per call',
        () async {
      await login('A');
      var cleaned = 0;
      ApiService.onTokensCleared = () => cleaned++;
      await Future.wait([ApiService.clearTokens(), ApiService.clearTokens()]);
      expect(cleaned, 1);
      expect(ApiService.isAuthenticated, isFalse);
    });

    test('initializeTokens with a slow storage read cannot overwrite a '
        'session that was installed meanwhile', () async {
      await TokenStore.save(testJwt('A', nonce: 'old'));
      await TokenStore.saveRefresh(testJwt('A', nonce: 'oldR', type: 'refresh'));
      final gate = _Gate();
      TokenStore.debugIoGate = (op) async {
        if (op == 'load') await gate.hit();
      };

      final init = ApiService.initializeTokens();
      await gate.reached;
      final signIn = login('B');
      final bAccess = _lastAccess!;
      await pumpEventQueue();
      gate.open();
      await Future.wait<Object?>([init, signIn]);

      expect(ApiService.accessToken, bAccess);
      expect(ApiService.currentAccountId, 'B');
      expect(TokenStore.token, bAccess);
      expect(await marker(), 'B');
    });

    test('control: ordinary same-account rotation persists and keeps the '
        'session', () async {
      await login('A', validNow: false);
      final epoch = ApiService.sessionEpoch;
      final res = await ApiService.makeAuthenticatedRequest('GET', '/ping');
      expect(res['actor'], 'A');
      expect(ApiService.sessionEpoch, epoch);
      expect(TokenStore.token, ApiService.accessToken);
      expect(ApiService.currentAccountId, 'A');
    });

    test('AccountScope activation never delivers a stale owner after a '
        'newer authentication transition', () async {
      final delivered = <String?>[];
      void listener(String? owner) => delivered.add(owner);
      AccountScope.addActivatedListener(listener);
      addTearDown(() => AccountScope.removeActivatedListener(listener));

      // Park the on-device re-scoping queue so A's and B's activations both
      // wait in line behind it.
      final held = Completer<void>();
      unawaited(AccountLocalData.runForOwner(null, (_) => held.future));
      await pumpEventQueue();

      final a = login('A');
      final b = login('B');
      await pumpEventQueue();
      held.complete();
      await Future.wait<Object?>([a, b]);

      expect(delivered, ['B'], reason: 'A\'s superseded activation leaked');
      expect(await marker(), 'B');
    });
  });

  // =========================================================================
  group('4. saved searches display', () {
    test('loadMerged: a response that arrives after A -> B is never '
        'returned to the caller', () async {
      await login('A');
      final gate = _Gate();
      SavedSearchService.debugAfterLocalPersist = gate.hit;

      final result = SavedSearchService.loadMerged();
      await gate.reached; // A's list was fetched and cached; return is next
      await login('B');
      gate.open();

      expect(await result, isEmpty,
          reason: "A's list must not be handed to a caller that is now B's");
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SavedSearchesPage(),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('a late response for A after A -> B is never displayed and '
        'the page reloads for B', (tester) async {
      await login('A');
      final gateA = _Gate();
      _srv.listGate['A'] = gateA;

      await pumpPage(tester);
      expect(gateA.hasBeenReached, isTrue,
          reason: "A's list request must be in flight");

      await login('B'); // account switch while A's response is outstanding
      gateA.open();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text('A search'), findsNothing);
      expect(find.text('B search'), findsOneWidget,
          reason: "the page must reload for the new account's list");
    });

    testWidgets('A\'s displayed list is cleared the moment the account '
        'changes, then B\'s list is loaded', (tester) async {
      await login('A');
      await pumpPage(tester);
      expect(find.text('A search'), findsOneWidget);

      final bGate = _Gate();
      _srv.listGate['B'] = bGate; // hold B's list so the interim is visible
      await login('B');
      await tester.pump();
      expect(find.text('A search'), findsNothing,
          reason: "A's rows must not stay on screen under B");

      bGate.open();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('B search'), findsOneWidget);
      expect(find.text('A search'), findsNothing);
    });
  });
}
