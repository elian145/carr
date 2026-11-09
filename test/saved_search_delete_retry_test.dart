// F-43: a saved-search delete whose server call fails must not be undone by
// the next sync; the delete is retried until the server confirms it.
import 'dart:convert';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/services/saved_search_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_jwt.dart';

const _idA = '11111111-1111-1111-1111-111111111111';
const _idB = '22222222-2222-2222-2222-222222222222';
const _owner = 'owner_f43';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> server;
  late int deleteStatus;
  late List<String> deleteCalls;

  Map<String, dynamic> row(String id, String brand) => {
    'id': id,
    'name': brand,
    'filters': {'brand': brand},
    'notify': true,
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = [row(_idA, 'toyota'), row(_idB, 'kia')];
    deleteStatus = 200;
    deleteCalls = [];
    TokenStore.testMode = true;
    ApiService.debugResetSessionForTests();
    SavedSearchService.debugResetLegacyPurgeFlag();
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    ApiService.testHttpClient = MockClient((request) async {
      final path = request.url.path;
      final method = request.method.toUpperCase();
      http.Response j(Object b, [int c = 200]) => http.Response(
        json.encode(b),
        c,
        headers: {'content-type': 'application/json'},
      );
      if (path.endsWith('/auth/me')) return j({'id': _owner});
      if (method == 'DELETE' && path.startsWith('/api/saved-searches/')) {
        final id = path.split('/').last;
        deleteCalls.add(id);
        if (deleteStatus != 200) return j({'message': 'x'}, deleteStatus);
        server.removeWhere((r) => r['id'] == id);
        return j({'ok': true});
      }
      // GET list and POST sync both echo the server's current list, i.e. a
      // not-yet-deleted search "comes back" exactly like in production.
      if (path.startsWith('/api/saved-searches')) {
        return j({'saved_searches': server});
      }
      return j({});
    });
    await ApiService.setTokens(
      accessToken: testJwt(_owner, nonce: 1),
      refreshToken: testJwt(_owner, nonce: 2, type: 'refresh'),
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    ApiService.testHttpClient = null;
    setRuntimeApiBaseOverride(null);
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  test('failed server delete does not resurrect the search on next sync', () async {
    expect(await SavedSearchService.loadMerged(), hasLength(2));
    // User deletes A locally, server call fails (network/5xx).
    deleteStatus = 503;
    await SavedSearchService.persistLocal([
      (await SavedSearchService.loadLocal()).firstWhere((i) => i['id'] == _idB),
    ], ownerId: _owner);
    await SavedSearchService.deleteOnServer(_idA);
    expect(await SavedSearchService.pendingDeletes(_owner), {_idA});

    // Next sync: server still holds A, but it must stay hidden.
    final merged = await SavedSearchService.loadMerged();
    expect(merged.map((i) => i['id']), [_idB]);
    expect(deleteCalls.where((i) => i == _idA).length, 2,
        reason: 'delete is retried during the next load');

    // Server recovers: retry succeeds and the tombstone is cleared.
    deleteStatus = 200;
    final after = await SavedSearchService.loadMerged();
    expect(after.map((i) => i['id']), [_idB]);
    expect(server.map((r) => r['id']), [_idB]);
    expect(await SavedSearchService.pendingDeletes(_owner), isEmpty);
  });

  test('404 on delete counts as already gone', () async {
    deleteStatus = 404;
    await SavedSearchService.deleteOnServer(_idA);
    expect(await SavedSearchService.pendingDeletes(_owner), isEmpty);
  });

  test('negative control: a successful delete leaves no tombstone', () async {
    await SavedSearchService.deleteOnServer(_idA);
    expect(await SavedSearchService.pendingDeletes(_owner), isEmpty);
    expect(server.map((r) => r['id']), [_idB]);
  });

  test('negative control: searches never deleted still load normally', () async {
    final merged = await SavedSearchService.loadMerged();
    expect(merged.map((i) => i['id']).toSet(), {_idA, _idB});
  });
}
