// F-34: "recently viewed" lives under one global on-device key that is re-scoped
// on every account switch. An operation that STARTED under account A (a view
// being recorded, a list being hydrated from the network, a delete/clear) must
// never write under, read for, or report to account B when it finishes late.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/services/recently_viewed_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/prefs/account_local_data.dart';

import 'support/test_jwt.dart';

const _a = 'user_a_0001';
const _b = 'user_b_0001';

final List<String> _requests = []; // "<actor> <METHOD> <path>"
int _n = 0;
Completer<void>? _getCarGate;

String? _actorOf(http.BaseRequest r) {
  final h = r.headers['Authorization'] ?? r.headers['authorization'];
  if (h == null || !h.startsWith('Bearer ')) return 'guest';
  return testJwtSubject(h.substring(7));
}

Future<http.Response> _handle(http.Request r) async {
  _requests.add('${_actorOf(r)} ${r.method} ${r.url.path}');
  final path = r.url.path;
  if (r.method == 'GET' && RegExp(r'/cars/[^/]+$').hasMatch(path)) {
    final gate = _getCarGate;
    if (gate != null) await gate.future;
    final id = path.split('/').last;
    if (id.startsWith('gone')) {
      return http.Response('{"message":"nf"}', 404,
          headers: {'content-type': 'application/json'});
    }
    return http.Response(
      json.encode({
        'car': {'id': id, 'public_id': id, 'title': 'T $id', 'brand': 'B'},
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response('{}', 200,
      headers: {'content-type': 'application/json'});
}

Future<void> login(String acct) => ApiService.setTokens(
      accessToken: testJwt(acct, nonce: ++_n),
      refreshToken: testJwt(acct, nonce: ++_n, type: 'refresh'),
    );
Future<void> logout() => ApiService.logout();

Future<List<String>> storedIds() async {
  final raw = (await SharedPreferences.getInstance())
      .getString(RecentlyViewedService.localKey);
  if (raw == null || raw.isEmpty) return const [];
  return (json.decode(raw) as List)
      .map((e) => (e as Map)['id'].toString())
      .toList();
}

/// Keeps the on-device serialisation queue busy so the operation under test
/// runs LATE (after the account switch), like a slow write would.
Future<Completer<void>> holdQueue(String owner) async {
  final release = Completer<void>();
  final started = Completer<void>();
  unawaited(AccountLocalData.withOwner<void>(owner, (sp) async {
    started.complete();
    await release.future;
  }));
  await started.future;
  return release;
}

void main() {
  setUp(() async {
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    _requests.clear();
    _getCarGate = null;
    ApiService.testHttpClient = MockClient(_handle);
    SharedPreferences.setMockInitialValues({});
    ApiService.debugResetSessionForTests();
    await ApiService.clearTokens();
  });
  tearDown(() async {
    ApiService.testHttpClient = null;
    await ApiService.clearTokens();
  });

  test('ordinary: a view is stored under the signed-in account only',
      () async {
    await login(_a);
    await RecentlyViewedService.recordView('car_1', snapshot: {'id': 'car_1'});
    expect(await storedIds(), ['car_1']);
    await logout();
    await login(_b);
    expect(await storedIds(), isEmpty, reason: "B must not see A's views");
    await logout();
    await login(_a);
    expect(await storedIds(), ['car_1'], reason: 'A gets A\'s own list back');
  });

  test('a view recorded late (after A -> B) never lands in B\'s list and is '
      'not reported to the server as B', () async {
    await login(_a);
    final release = await holdQueue(_a);
    final pending = RecentlyViewedService.recordView(
      'car_late',
      snapshot: {'id': 'car_late'},
    );
    await pumpEventQueue();
    final loggedOut = logout();
    final loginB = login(_b);
    await pumpEventQueue();
    release.complete();
    await loggedOut;
    await loginB;
    await pending;
    await pumpEventQueue();

    expect(await storedIds(), isEmpty,
        reason: "A's late view must not be written under B");
    expect(_requests.where((r) => r.contains('car_late')), isEmpty,
        reason: "A's late view must not be reported as B (or anyone)");
    await logout();
    await login(_a);
    expect(await storedIds(), isNot(contains('car_late')));
  });

  test('a guest view that finishes after sign-in is not adopted by the '
      'account', () async {
    await AccountLocalData.activate(null);
    final release = await holdQueue('');
    final pending =
        RecentlyViewedService.recordView('car_guest', snapshot: {'id': 'car_guest'});
    await pumpEventQueue();
    final loginA = login(_a);
    release.complete();
    await loginA;
    await pending;
    expect(await storedIds(), isEmpty);
  });

  test('a list hydrated from the network for A is not handed to B',
      () async {
    await login(_a);
    // A stub with no snapshot: needs a network round trip to display.
    await (await SharedPreferences.getInstance()).setString(
      RecentlyViewedService.localKey,
      json.encode([
        {'id': 'stub_1', 'public_id': 'stub_1'},
      ]),
    );
    _getCarGate = Completer<void>();
    final pending = RecentlyViewedService.loadLocalDisplayList();
    await pumpEventQueue();
    await logout();
    await login(_b);
    _getCarGate!.complete();
    final result = await pending;
    expect(result, isEmpty, reason: "A's hydrated items must not reach B");
    expect(await storedIds(), isEmpty);
  });

  test('a 404 prune that finishes late cannot delete from B\'s list',
      () async {
    await login(_a);
    await (await SharedPreferences.getInstance()).setString(
      RecentlyViewedService.localKey,
      json.encode([
        {'id': 'gone_1', 'public_id': 'gone_1'},
      ]),
    );
    _getCarGate = Completer<void>();
    final pending = RecentlyViewedService.loadLocalDisplayList();
    await pumpEventQueue();
    await logout();
    await login(_b);
    await RecentlyViewedService.recordView('gone_1',
        snapshot: {'id': 'gone_1', 'title': 'B owns this view'});
    _getCarGate!.complete();
    await pending;
    expect(await storedIds(), ['gone_1'],
        reason: "A's late 404 prune must not remove B's own entry");
  });

  test('a clearAll / removeOne that runs late only affects the account that '
      'asked', () async {
    await login(_a);
    final release = await holdQueue(_a);
    final clearing = RecentlyViewedService.clearAll();
    final removing = RecentlyViewedService.removeOne('car_b1');
    await pumpEventQueue();
    final loggedOut = logout();
    final loginB = login(_b);
    await pumpEventQueue();
    release.complete();
    await loggedOut;
    await loginB;
    await clearing;
    await removing;
    // B now records something and A's earlier (late) operations must not have
    // touched it, nor have been sent to the server as B.
    await RecentlyViewedService.recordView('car_b1', snapshot: {'id': 'car_b1'});
    expect(await storedIds(), ['car_b1']);
    expect(
      _requests.where((r) => r.startsWith('$_b ') && r.contains('DELETE')),
      isEmpty,
      reason: "A's delete/clear must not be sent as B",
    );
  });

  test('ordinary authenticated traffic in the same session does not drop a view', () async {
    await login(_a);
    final epoch = ApiService.sessionEpoch;
    final release = await holdQueue(_a);
    final pending = RecentlyViewedService.recordView(
      'car_rot',
      snapshot: {'id': 'car_rot'},
    );
    await pumpEventQueue();
    // Unrelated traffic in the same session keeps it (and the pending view).
    await ApiService.makeAuthenticatedRequest('GET', '/ping');
    expect(ApiService.sessionEpoch, epoch);
    release.complete();
    await pending;
    expect(await storedIds(), ['car_rot']);
  });

  test('a session that is being signed out is never resurrected from the '
      'not-yet-cleared persisted token', () async {
    await login(_a);
    final stale = ApiService.accessToken!;
    final clearing = ApiService.clearTokens(); // memory empty, store wiping
    // Simulates the persisted copy a concurrent reader would still find.
    await TokenStore.save(stale);
    await ApiService.ensureSessionLoaded();
    await clearing;
    expect(ApiService.isAuthenticated, isFalse,
        reason: 'logout must not be undone by a concurrent restore');
    expect(ApiService.currentAccountId, isNull);
  });
}
