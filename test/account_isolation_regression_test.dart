// Regression suite for CarNet findings F-34 (saved searches), F-35 (pending
// chat sends) and F-34b/F-39 (authenticated GET cache / session races):
// private on-device data and in-flight work must never cross from one account
// to another across logout, account switch, restart, in-flight responses, 401
// retries, media sends and account deletion.
//
// Synthetic accounts "A" and "B" only. The "server" is an in-process
// MockClient with per-user state; no network, no production services.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/features/comparison/state/car_comparison_store.dart';
import 'package:car_listing_app/services/account_data_purge.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/services/outgoing_chat_send_service.dart';
import 'package:car_listing_app/services/saved_search_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/prefs/account_local_data.dart';
import 'package:car_listing_app/shared/prefs/chat_pending_send_prefs.dart';
import 'package:car_listing_app/shared/prefs/favorites_cache_prefs.dart';
import 'package:car_listing_app/shared/prefs/sell_pending_media_prefs.dart';

import 'support/test_jwt.dart';

class Backend {
  final Map<String, List<Map<String, dynamic>>> saved = {'A': [], 'B': []};
  final List<Map<String, dynamic>> sends = []; // what the server accepted
  final List<String> refreshedBy = []; // account whose refresh token was used
  int _n = 0;
  int _tok = 0;
  bool deleteFails = false;
  final List<String> deleted = [];

  /// Return non-null to override the response of a chat send endpoint.
  Future<http.Response?> Function(http.Request r, String? account)? sendHook;

  /// Gate for GET /api/saved-searches.
  Completer<void>? savedGetGate;

  String _acct(http.Request r) {
    final a = (r.headers['authorization'] ?? '').replaceFirst('Bearer ', '');
    final s = testJwtSubject(a);
    return (s == 'A' || s == 'B') ? s! : '';
  }

  http.Response _j(int code, Object body) => http.Response(
        json.encode(body),
        code,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic> row(String acct, Map item) => {
        'id': 'ss-${(++_n).toString().padLeft(32, '0')}',
        'name': item['name'] ?? 'x',
        'filters': item['filters'] ?? {},
        'notify': item['notify'] != false,
        'auto_saved': false,
        'created_at': DateTime.now().toIso8601String(),
      };

  Map<String, dynamic>? _tryJson(String s) {
    try {
      final d = json.decode(s);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    final acct = _acct(r);
    if (path.endsWith('/auth/logout')) return _j(200, {'message': 'ok'});
    if (path.endsWith('/auth/refresh')) {
      if (acct.isEmpty) return _j(401, {'message': 'bad refresh'});
      refreshedBy.add(acct);
      return _j(200, {
        'access_token': testJwt(acct, nonce: ++_tok),
        'refresh_token': testJwt(acct, nonce: ++_tok, type: 'refresh'),
      });
    }
    if (acct.isEmpty) return _j(401, {'message': 'Invalid token'});

    if (path.endsWith('/auth/me')) {
      return _j(200, {'id': acct, 'name': 'User $acct'});
    }
    if (path.endsWith('/auth/delete-account') && r.method == 'POST') {
      if (deleteFails) return _j(500, {'message': 'boom'});
      deleted.add(acct);
      return _j(200, {'message': 'deleted'});
    }
    if (path.endsWith('/saved-searches') && r.method == 'GET') {
      final g = savedGetGate;
      if (g != null) await g.future;
      return _j(200, {'saved_searches': saved[acct]});
    }
    if (path.endsWith('/saved-searches/sync') && r.method == 'POST') {
      final items = (json.decode(r.body)['items'] as List).cast<Map>();
      for (final it in items) {
        final fp = json.encode(it['filters']);
        final has = saved[acct]!.any((s) => json.encode(s['filters']) == fp);
        if (!has) saved[acct]!.add(row(acct, it));
      }
      return _j(200, {'saved_searches': saved[acct]});
    }
    if (path.endsWith('/saved-searches') && r.method == 'POST') {
      final b = json.decode(r.body) as Map;
      final rw = row(acct, b);
      saved[acct]!.add(rw);
      return _j(201, {'saved_search': rw});
    }
    final m = RegExp(r'/chat/([^/]+)/(send|send_media_group|send_audio)$')
        .firstMatch(path);
    if (m != null && r.method == 'POST') {
      final hook = sendHook;
      if (hook != null) {
        final o = await hook(r, acct);
        if (o != null) return o;
      }
      final idem = r.headers['idempotency-key'];
      final body = _tryJson(r.body);
      final dup = sends.any((s) => s['actor'] == acct && s['idem'] == idem);
      if (!dup) {
        sends.add({
          'actor': acct,
          'car': m.group(1),
          'endpoint': m.group(2),
          'content': body?['content'],
          'idem': idem,
        });
      }
      return _j(201, {
        'success': true,
        'message': {
          'id': 'srv-${sends.length}',
          'sender_id': acct,
          'content': body?['content'],
        },
      });
    }
    return _j(404, {'message': 'nf $path'});
  }
}

late Backend be;
int _loginN = 0;

Future<void> login(String a) => ApiService.setTokens(
      accessToken: testJwt(a, nonce: ++_loginN),
      refreshToken: testJwt(a, nonce: ++_loginN, type: 'refresh'),
    );
Future<void> logout() => ApiService.logout();

Future<void> ageRecords() async {
  for (final r in await ChatPendingSendPrefs.loadAll()) {
    await ChatPendingSendPrefs.upsert(r.copyWith(
      lastAttemptAt: DateTime.now()
          .subtract(const Duration(seconds: 60))
          .millisecondsSinceEpoch,
    ));
  }
}

List<String> sentBy(String actor) => be.sends
    .where((s) => s['actor'] == actor)
    .map((s) => (s['content'] ?? s['endpoint']).toString())
    .toList();

const aFilters = {'brand': 'Toyota', 'max_price': '20000'};
const bFilters = {'brand': 'Kia', 'max_price': '9000'};

Future<Set<String>> prefKeys() async =>
    (await SharedPreferences.getInstance()).getKeys();

void main() {
  setUp(() async {
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    be = Backend();
    ApiService.testHttpClient = MockClient(be.handle);
    SharedPreferences.setMockInitialValues({});
    ApiService.debugResetSessionForTests();
    SavedSearchService.debugResetLegacyPurgeFlag();
    ChatPendingSendPrefs.debugResetLegacyPurgeFlag();
    await ApiService.clearTokens();
  });
  tearDown(() async {
    ApiService.testHttpClient = null;
    await ApiService.clearTokens();
  });

  // --------------------------------------------------------------- F-34 --
  group('F-34 saved searches', () {
    test("1) A -> logout -> B: B must not see or inherit A's searches",
        () async {
      be.saved['A']!
          .add(be.row('A', {'name': 'A-search', 'filters': aFilters}));
      await login('A');
      expect((await SavedSearchService.loadMerged()).length, 1);
      await logout();
      await login('B');
      final seenByB = await SavedSearchService.loadMerged();
      expect(seenByB, isEmpty, reason: "B sees A's saved search");
      expect(be.saved['B'], isEmpty,
          reason: "A's search was uploaded into B's server account");
    });

    test('2) A -> B -> A: no cross-contamination in either direction',
        () async {
      be.saved['A']!
          .add(be.row('A', {'name': 'A-search', 'filters': aFilters}));
      be.saved['B']!
          .add(be.row('B', {'name': 'B-search', 'filters': bFilters}));
      await login('A');
      await SavedSearchService.loadMerged();
      await logout();
      await login('B');
      await SavedSearchService.loadMerged();
      await logout();
      await login('A');
      final backToA = await SavedSearchService.loadMerged();
      expect(backToA.map((e) => e['name']).toList(), ['A-search']);
      expect(be.saved['A']!.map((e) => e['name']), ['A-search']);
      expect(be.saved['B']!.map((e) => e['name']), ['B-search']);
    });

    test('3) after logout (no token) the service returns nothing', () async {
      be.saved['A']!
          .add(be.row('A', {'name': 'A-search', 'filters': aFilters}));
      await login('A');
      await SavedSearchService.loadMerged();
      await logout();
      expect(await SavedSearchService.loadMerged(), isEmpty,
          reason: "guest state still reads A's on-disk list");
      expect(await SavedSearchService.loadLocal(), isEmpty);
    });

    test(
        "4) restart: legacy global list from A's last session is DISCARDED, "
        'never adopted or synced by B (or by A)', () async {
      SharedPreferences.setMockInitialValues({
        SavedSearchService.legacyLocalKey: json.encode([
          {
            'id': '1700000000000',
            'name': 'A-local',
            'filters': aFilters,
            'notify': true,
            'created_at': '2026-10-01T00:00:00',
          },
        ]),
      });
      await login('B');
      expect(await SavedSearchService.loadMerged(), isEmpty);
      expect(be.saved['B'], isEmpty);
      expect(
        (await SharedPreferences.getInstance())
            .containsKey(SavedSearchService.legacyLocalKey),
        isFalse,
        reason: 'legacy unowned key must be deleted',
      );
      await logout();
      await login('A');
      expect(await SavedSearchService.loadMerged(), isEmpty,
          reason: 'unowned legacy data must not be adopted by A either');
      expect(be.saved['A'], isEmpty);
    });

    test("5) in-flight: A's load completes AFTER logout + B login", () async {
      be.saved['A']!
          .add(be.row('A', {'name': 'A-search', 'filters': aFilters}));
      be.savedGetGate = Completer<void>();
      await login('A');
      final inFlight = SavedSearchService.loadMerged();
      await pumpEventQueue();
      await logout();
      await login('B');
      be.savedGetGate!.complete();
      expect(await inFlight, isEmpty,
          reason: "A's late response must not be delivered to B's session");
      await pumpEventQueue();
      final sp = await SharedPreferences.getInstance();
      for (final k in sp.getKeys()) {
        expect(sp.get(k).toString(), isNot(contains('A-search')),
            reason: "late A response written to storage under key $k");
      }
    });

    test("6) legit data kept: A's own list survives A -> B -> A offline",
        () async {
      be.saved['A']!
          .add(be.row('A', {'name': 'A-search', 'filters': aFilters}));
      await login('A');
      await SavedSearchService.loadMerged();
      await logout();
      await login('B');
      await SavedSearchService.loadMerged();
      await logout();
      // A's per-account local copy is still on disk for A...
      final sp = await SharedPreferences.getInstance();
      expect(
        sp.getString(SavedSearchService.localKeyForOwner('A')),
        contains('A-search'),
      );
      // ...and is returned when A logs back in, even if the server is down.
      ApiService.testHttpClient =
          MockClient((r) async => throw const SocketException('offline'));
      await login('A');
      final backToA = await SavedSearchService.loadMerged();
      expect(backToA.any((e) => e['name'] == 'A-search'), isTrue);
    });

    test('7) upsertFromFilters stores under the signed-in account only',
        () async {
      await login('A');
      await SavedSearchService.upsertFromFilters(
        filters: aFilters,
        name: 'Toyota <= 20k',
        forceNotify: true,
      );
      await pumpEventQueue();
      final keys = await prefKeys();
      expect(keys, contains(SavedSearchService.localKeyForOwner('A')));
      expect(keys, isNot(contains(SavedSearchService.legacyLocalKey)));
      expect(be.saved['A']!.map((e) => e['name']), ['Toyota <= 20k']);
      await logout();
      await login('B');
      expect(await SavedSearchService.loadLocal(), isEmpty);
      expect(await SavedSearchService.loadMerged(), isEmpty);
      expect(be.saved['B'], isEmpty);
    });

    test('8) logged-out / unverified-owner saves never touch storage',
        () async {
      await SavedSearchService.persistLocal([
        {'id': '1', 'name': 'x', 'filters': aFilters},
      ]);
      expect(
        (await prefKeys()).where((k) => k.startsWith('saved_searches')),
        isEmpty,
      );
    });
  });

  // --------------------------------------------------------------- F-35 --
  group('F-35 pending chat sends', () {
    Future<void> aFailsToSend(String content) async {
      be.sendHook = (r, acct) async =>
          acct == 'A' && be.sends.isEmpty ? http.Response('', 503) : null;
      await login('A');
      OutgoingChatSendService.instance.startTextMessageSend(
        conversationId: 'car_X',
        content: content,
        receiverId: 'seller_S',
        tempMessageId: 'temp_A1',
      );
      await pumpEventQueue();
      expect(await ChatPendingSendPrefs.loadAll(), hasLength(1));
      be.sendHook = null;
    }

    test("1) B opening the same conversation must not see A's pending item",
        () async {
      await aFailsToSend('A private offer: 12k cash');
      await logout();
      await login('B');
      final shownToB = await ChatPendingSendPrefs.loadForConversation(
        'car_X',
        ownerUserId: ApiService.currentAccountId,
      );
      expect(shownToB, isEmpty, reason: "B sees A's pending bubble/content");
      expect(
        await ChatPendingSendPrefs.loadForConversation('car_X',
            ownerUserId: null),
        isEmpty,
      );
      final shownToA = await ChatPendingSendPrefs.loadForConversation('car_X',
          ownerUserId: 'A');
      expect(shownToA.single.ownerUserId, 'A');
    });

    test("2) B's recovery must not send A's message", () async {
      await aFailsToSend('A private offer: 12k cash');
      await logout();
      await login('B');
      await ageRecords();
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      expect(sentBy('B'), isEmpty, reason: "A's message was delivered AS B");
      expect(sentBy('A'), isEmpty);
    });

    test("3) A -> B -> A: A's message is kept and delivered by A exactly once",
        () async {
      await aFailsToSend('A private offer: 12k cash');
      await logout();
      await login('B');
      await ageRecords();
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      await logout();
      await login('A');
      await ageRecords();
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      expect(
        be.sends.map((s) => '${s['actor']}:${s['content']}').toList(),
        ['A:A private offer: 12k cash'],
      );
      expect(await ChatPendingSendPrefs.loadAll(), isEmpty);
    });

    test("3b) restart: A's owner-stamped record survives and resumes under A",
        () async {
      await aFailsToSend('survives restart');
      await logout();
      // Cold start: all in-memory state is gone, only SharedPreferences stays.
      ApiService.debugResetSessionForTests();
      ChatPendingSendPrefs.debugResetLegacyPurgeFlag();
      expect(await ChatPendingSendPrefs.loadAll(), hasLength(1));
      await login('A');
      await ageRecords();
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      expect(sentBy('A'), ['survives restart']);
    });

    test("4) in-flight: A's send fails (503) AFTER logout + B login", () async {
      final gate = Completer<void>();
      be.sendHook = (r, acct) async {
        if (acct == 'A') {
          await gate.future;
          return http.Response('', 503);
        }
        return null;
      };
      await login('A');
      OutgoingChatSendService.instance.startTextMessageSend(
        conversationId: 'car_X',
        content: 'A in-flight text',
        receiverId: 'seller_S',
        tempMessageId: 'temp_A2',
      );
      await pumpEventQueue();
      await logout();
      await login('B');
      gate.complete();
      await pumpEventQueue();
      expect(
        await ChatPendingSendPrefs.loadForConversation('car_X',
            ownerUserId: ApiService.currentAccountId),
        isEmpty,
        reason: "A's late failure is visible to B",
      );
      await ageRecords();
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      expect(sentBy('B'), isEmpty, reason: "A's message re-sent AS B");
      // The record is A's and is kept for A.
      expect(
        (await ChatPendingSendPrefs.loadForOwner('A')).map((r) => r.id),
        ['temp_A2'],
      );
    });

    test("5) in-flight 401: A's request is NOT retried with B's token",
        () async {
      final gate = Completer<void>();
      var first = true;
      be.sendHook = (r, acct) async {
        if (first && acct == 'A') {
          first = false;
          await gate.future;
          return http.Response('{"message":"expired"}', 401);
        }
        return null;
      };
      await login('A');
      OutgoingChatSendService.instance.startTextMessageSend(
        conversationId: 'car_X',
        content: 'A text racing a token expiry',
        receiverId: 'seller_S',
        tempMessageId: 'temp_A3',
      );
      await pumpEventQueue();
      await logout();
      await login('B');
      final bToken = ApiService.accessToken;
      gate.complete();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(sentBy('B'), isEmpty,
          reason: "A's text was sent as B via 401-refresh retry");
      expect(be.refreshedBy, isNot(contains('B')),
          reason: "B's refresh token was spent on A's request");
      expect(ApiService.accessToken, bToken,
          reason: "A's 401 handling clobbered or cleared B's tokens");
      expect(ApiService.currentAccountId, 'B');
    });

    test("6) A's late SUCCESS event is labelled with A (consumers filter)",
        () async {
      final gate = Completer<void>();
      be.sendHook = (r, acct) async {
        if (acct == 'A') await gate.future;
        return null;
      };
      await login('A');
      OutgoingChatSendService.instance.startTextMessageSend(
        conversationId: 'car_X',
        content: 'A late success',
        receiverId: 'seller_S',
        tempMessageId: 'temp_A4',
      );
      await pumpEventQueue();
      await logout();
      await login('B');
      final seen = <OutgoingChatSendEvent>[];
      final sub = OutgoingChatSendService.instance.events.listen(seen.add);
      gate.complete();
      await pumpEventQueue();
      await sub.cancel();
      // The request started under A is abandoned once the session changed, so
      // no message payload can ever reach B...
      expect(seen.where((e) => e.messageJson != null), isEmpty);
      expect(sentBy('B'), isEmpty);
      // ...and whatever is emitted is owned by A, never by the signed-in B.
      expect(seen.where((e) => e.ownerUserId == 'B'), isEmpty);
      expect(seen.every((e) => e.ownerUserId == 'A'), isTrue);
      // The request was already on the wire as A when the account switched, so
      // the server may have accepted it as A; the interrupted send is kept for
      // A and replayed through its idempotency key -- delivered exactly once.
      await logout();
      await login('A');
      await ageRecords();
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      expect(sentBy('A'), ['A late success']);
    });

    test('7) legacy ownerless pending records are discarded, never sent',
        () async {
      SharedPreferences.setMockInitialValues({
        ChatPendingSendPrefs.legacyPrefsKey: json.encode([
          {
            'id': 'temp_old',
            'conversationId': 'car_X',
            'kind': 'text',
            'idempotencyKey': 'chat-send-old',
            'content': 'legacy unowned',
            'receiverId': 'seller_S',
            'createdAt': 1,
            'attempts': 1,
          },
        ]),
      });
      await login('A');
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      expect(be.sends, isEmpty);
      expect(await ChatPendingSendPrefs.loadAll(), isEmpty);
      expect(
        (await prefKeys()).contains(ChatPendingSendPrefs.legacyPrefsKey),
        isFalse,
      );
    });

    test('7b) a v2 record without an owner is dropped on load', () async {
      SharedPreferences.setMockInitialValues({
        ChatPendingSendPrefs.prefsKey: json.encode([
          {
            'id': 'temp_x',
            'conversationId': 'car_X',
            'kind': 'text',
            'idempotencyKey': 'k',
            'content': 'no owner',
          },
        ]),
      });
      expect(await ChatPendingSendPrefs.loadAll(), isEmpty);
    });

    test('8) a send begun under A is never dispatched under B (pre-dispatch)',
        () async {
      await login('A');
      OutgoingChatSendService.instance.startTextMessageSend(
        conversationId: 'car_X',
        content: 'A text, account switches immediately',
        receiverId: 'seller_S',
        tempMessageId: 'temp_A5',
      );
      // Account switches before the request is dispatched.
      unawaited(login('B'));
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sentBy('B'), isEmpty, reason: "A's text went out as B");
      expect(sentBy('A'), isEmpty);
      expect(
        (await ChatPendingSendPrefs.loadForOwner('A')).map((r) => r.id),
        ['temp_A5'],
        reason: 'interrupted send must be kept for A',
      );
    });

    test('9) UI-expected owner mismatch / signed-out: nothing is sent',
        () async {
      final events = <OutgoingChatSendEvent>[];
      final sub = OutgoingChatSendService.instance.events.listen(events.add);
      addTearDown(sub.cancel);

      await login('B');
      OutgoingChatSendService.instance.startTextMessageSend(
        conversationId: 'car_X',
        content: 'composed on A screen',
        tempMessageId: 'temp_m1',
        expectedOwnerUserId: 'A',
      );
      await logout();
      OutgoingChatSendService.instance.startTextMessageSend(
        conversationId: 'car_X',
        content: 'composed while signed out',
        tempMessageId: 'temp_m2',
      );
      await pumpEventQueue();
      expect(be.sends, isEmpty);
      expect(await ChatPendingSendPrefs.loadAll(), isEmpty);
      expect(events, hasLength(2));
      expect(events.every((e) => !e.success && !e.pendingRetry), isTrue);
      expect(events.first.ownerUserId, 'A');
      expect(events.first.restoredPlainText, 'composed on A screen');
    });
  });

  group('F-35 media / audio sends', () {
    late Directory dir;
    late XFile photo;
    late XFile voice;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('acct_iso_');
      final p = File('${dir.path}/photo.jpg')..writeAsBytesSync([1, 2, 3, 4]);
      final v = File('${dir.path}/voice.m4a')..writeAsBytesSync([5, 6, 7, 8]);
      photo = XFile(p.path);
      voice = XFile(v.path);
    });
    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test(
        "media: A's in-flight upload is invisible to B, never re-sent as B, "
        'and resumes for A', () async {
      final gate = Completer<void>();
      final arrived = Completer<void>();
      be.sendHook = (r, acct) async {
        if (acct == 'A' && be.sends.isEmpty && !gate.isCompleted) {
          if (!arrived.isCompleted) arrived.complete();
          await gate.future;
          return http.Response('', 503);
        }
        return null;
      };
      await login('A');
      OutgoingChatSendService.instance.startMediaGroupSend(
        conversationId: 'car_X',
        files: [photo],
        tempMessageId: 'temp_media',
        startedAt: DateTime.now(),
        receiverId: 'seller_S',
        carId: 'car_X',
        restoreFiles: [photo],
        expectedOwnerUserId: 'A',
      );
      await pumpEventQueue();
      expect(
        OutgoingChatSendService.instance
            .inFlightMediaForConversation('car_X', ownerUserId: 'A'),
        hasLength(1),
      );
      // The multipart body is streamed from disk (real IO), so on a cold or
      // loaded machine the mock server may not have received A's request yet.
      // Wait for it to be in flight before switching accounts; otherwise the
      // late arrival would be (wrongly) read as "dispatched after the switch".
      await arrived.future.timeout(const Duration(seconds: 20));
      await logout();
      await login('B');
      expect(
        OutgoingChatSendService.instance.inFlightMediaForConversation('car_X',
            ownerUserId: ApiService.currentAccountId),
        isEmpty,
        reason: "B sees A's in-flight upload",
      );
      gate.complete();
      await pumpEventQueue();
      await ageRecords();
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      expect(be.sends, isEmpty, reason: "A's upload was sent as B");
      final rec = (await ChatPendingSendPrefs.loadForOwner('A')).single;
      expect(rec.kind, 'mediaGroup');
      expect(rec.ownerUserId, 'A');

      await logout();
      await login('A');
      await ageRecords();
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sentBy('A'), hasLength(1));
      expect(sentBy('B'), isEmpty);
    });

    test('audio: pending voice note only resumes under its owner', () async {
      be.sendHook = (r, acct) async =>
          acct == 'A' && be.sends.isEmpty ? http.Response('', 503) : null;
      await login('A');
      OutgoingChatSendService.instance.startAudioSend(
        conversationId: 'car_X',
        audioFile: voice,
        tempMessageId: 'temp_voice',
        startedAt: DateTime.now(),
        receiverId: 'seller_S',
        restoreFile: voice,
        expectedOwnerUserId: 'A',
      );
      await pumpEventQueue();
      expect((await ChatPendingSendPrefs.loadForOwner('A')), hasLength(1));
      be.sendHook = null;
      await logout();
      await login('B');
      await ageRecords();
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      expect(be.sends, isEmpty);
      await logout();
      await login('A');
      await ageRecords();
      await OutgoingChatSendService.instance.recoverPendingSends();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sentBy('A'), hasLength(1));
      expect(sentBy('B'), isEmpty);
    });
  });

  // ------------------------------------------------------- F-34b / F-39 --
  group('F-34b/F-39 session scoping', () {
    test("GET cache: B's timed-out GET is not answered from A's cache",
        () async {
      be.saved['A']!
          .add(be.row('A', {'name': 'A-search', 'filters': aFilters}));
      await login('A');
      await ApiService.getSavedSearches();
      await logout();
      await login('B');
      ApiService.testHttpClient = MockClient(
          (r) async => throw TimeoutException('B request timed out'));
      Map<String, dynamic>? res;
      try {
        res = await ApiService.getSavedSearches();
      } catch (_) {}
      expect(res, isNull, reason: "B was served A's cached response: $res");
    });

    test('GET cache: not reused across logout + login as the SAME account',
        () async {
      await login('A');
      await ApiService.getSavedSearches();
      await logout();
      await login('A');
      ApiService.testHttpClient = MockClient(
          (r) async => throw TimeoutException('request timed out'));
      Map<String, dynamic>? res;
      try {
        res = await ApiService.getSavedSearches();
      } catch (_) {}
      expect(res, isNull,
          reason: "an earlier session's cached response was reused: $res");
    });

    test("logout then login again as A: the old session's response is dropped",
        () async {
      be.savedGetGate = Completer<void>();
      await login('A');
      final pending = ApiService.getSavedSearches().then<Object?>(
        (v) => v,
        onError: (Object e) => e,
      );
      await pumpEventQueue();
      await logout();
      await login('A');
      be.savedGetGate!.complete();
      expect(await pending, isA<ApiSessionChangedException>());
    });

    test('identity: JWT subject must agree with /auth/me or fail closed',
        () async {
      {
        await login('A');
        expect(ApiService.currentAccountId, 'A');
        final session = ApiService.captureSession();
        expect(ApiService.confirmAccountIdentity('A', session), isTrue);
        expect(ApiService.currentAccountId, 'A');

        expect(ApiService.confirmAccountIdentity('B', session), isFalse);
        expect(ApiService.currentAccountId, isNull,
            reason: 'mismatch must fail closed');
        // No owner => nothing persists locally and nothing is uploaded.
        be.saved['A']!
            .add(be.row('A', {'name': 'A-search', 'filters': aFilters}));
        final list = await SavedSearchService.loadMerged();
        expect(list.map((e) => e['name']), ['A-search']);
        expect(
          (await prefKeys()).where((k) => k.startsWith('saved_searches')),
          isEmpty,
        );
      }
    });

    test('identity: missing/empty profile id fails closed', () async {
      await login('A');
      expect(
        ApiService.confirmAccountIdentity(null, ApiService.captureSession()),
        isFalse,
      );
      expect(ApiService.currentAccountId, isNull);
      await logout();
      await login('A');
      expect(ApiService.currentAccountId, 'A',
          reason: 'a fresh login resets the rejected state');
      expect(
        ApiService.confirmAccountIdentity('', ApiService.captureSession()),
        isFalse,
      );
    });

    test('identity: opaque (non-JWT) tokens have no owner', () async {
      await ApiService.setTokens(
        accessToken: 'opaque_access',
        refreshToken: 'opaque_refresh',
      );
      expect(ApiService.currentAccountId, isNull);
      expect(await SavedSearchService.loadLocal(), isEmpty);
    });

    test('identity: /auth/me mismatch ends the session (AuthService)',
        () async {
      // Server answers /auth/me with a different account than the token's sub.
      final inner = MockClient(be.handle);
      ApiService.testHttpClient = MockClient((r) async {
        if (r.url.path.endsWith('/auth/me')) {
          return http.Response(json.encode({'id': 'B', 'name': 'B'}), 200,
              headers: {'content-type': 'application/json'});
        }
        return inner.send(r).then(http.Response.fromStream);
      });
      await login('A');
      await AuthService().refreshProfile();
      expect(ApiService.isAuthenticated, isFalse,
          reason: 'unverifiable identity must end the session');
      expect(ApiService.currentAccountId, isNull);
    });
  });

  // ------------------------------------------------ other global keys --
  group('account-scoped global keys', () {
    Future<List<String>> cars() async =>
        (await SharedPreferences.getInstance())
            .getStringList('comparison_cars') ??
        const <String>[];

    test('A -> logout -> B -> A: values follow their owner', () async {
      await login('A');
      var sp = await SharedPreferences.getInstance();
      await sp.setStringList('comparison_cars', ['{"id":"a1"}']);
      await sp.setString('recently_viewed_local_v1', '[{"id":"a1"}]');
      await sp.setString('legacy_sell_draft_snapshot_v1', 'A-draft');
      await sp.setString('owner_optimistic_media_v1', 'A-media');
      await sp.setString('home_apply_filters_once_v1', '{"brand":"Toyota"}');
      await sp.setBool('home_pending_saved_search_fetch_v1', true);
      await logout();
      sp = await SharedPreferences.getInstance();
      for (final k in AccountLocalData.scopedKeys) {
        expect(sp.containsKey(k), isFalse, reason: 'guest sees $k');
      }
      await login('B');
      sp = await SharedPreferences.getInstance();
      for (final k in AccountLocalData.scopedKeys) {
        expect(sp.containsKey(k), isFalse, reason: 'B sees A value for $k');
      }
      await sp.setStringList('comparison_cars', ['{"id":"b1"}']);
      await logout();
      await login('A');
      expect(await cars(), ['{"id":"a1"}']);
      sp = await SharedPreferences.getInstance();
      expect(sp.getString('legacy_sell_draft_snapshot_v1'), 'A-draft');
      expect(sp.getString('owner_optimistic_media_v1'), 'A-media');
      expect(sp.getString('home_apply_filters_once_v1'), '{"brand":"Toyota"}');
      expect(sp.getBool('home_pending_saved_search_fetch_v1'), isTrue);
      await logout();
      await login('B');
      expect(await cars(), ['{"id":"b1"}']);
    });

    test('legacy unowned values are quarantined, not adopted', () async {
      SharedPreferences.setMockInitialValues({
        'comparison_cars': ['{"id":"old"}'],
        'legacy_sell_draft_snapshot_v1': 'old-draft',
        'legacy_sell_pending_media_v1':
            '{"carId":"old_car","draftId":"d","carData":{"images":["/x.jpg"]}}',
      });
      await login('A');
      expect(await cars(), isEmpty);
      final sp = await SharedPreferences.getInstance();
      expect(sp.containsKey('legacy_sell_draft_snapshot_v1'), isFalse);
      expect(sp.containsKey('legacy_sell_pending_media_v1'), isFalse);
      expect(await SellPendingMediaPrefs.load(), isNull,
          reason: 'an unowned pending upload must not reach any account');
      await logout();
      await login('B');
      expect(await cars(), isEmpty);
      expect(await SellPendingMediaPrefs.load(), isNull);
    });

    test('guest-created values are never adopted by an account', () async {
      await AccountLocalData.activate(null);
      var sp = await SharedPreferences.getInstance();
      await sp.setStringList('comparison_cars', ['{"id":"g1"}']);
      await sp.setString('recently_viewed_local_v1', '[{"id":"g1"}]');
      await login('A');
      expect(await cars(), isEmpty, reason: "guest data must not reach A");
      sp = await SharedPreferences.getInstance();
      expect(sp.containsKey('recently_viewed_local_v1'), isFalse);
      await sp.setStringList('comparison_cars', ['{"id":"a1"}']);
      await logout();
      // Signed out again: the guest bucket (and only it) comes back.
      expect(await cars(), ['{"id":"g1"}']);
      await login('B');
      expect(await cars(), isEmpty, reason: "guest data must not reach B");
      await logout();
      await login('A');
      expect(await cars(), ['{"id":"a1"}']);
    });

    test('comparison store follows the signed-in account', () async {
      final store = CarComparisonStore();
      addTearDown(store.dispose);
      await login('A');
      await pumpEventQueue();
      store.addCarToComparison({'id': 'a1', 'title': 'A car'});
      await pumpEventQueue();
      expect(store.comparisonCount, 1);
      await logout();
      expect(store.comparisonCount, 0,
          reason: 'logout must clear the in-memory list immediately');
      await login('B');
      await pumpEventQueue();
      expect(store.comparisonCount, 0);
      await logout();
      await login('A');
      await pumpEventQueue();
      expect(store.comparisonCars.map((c) => c['id']), ['a1']);
    });

    test('favorites cache is per account; legacy global key is deleted',
        () async {
      SharedPreferences.setMockInitialValues({
        FavoritesCachePrefs.legacyKey: '[{"id":"old"}]',
      });
      await FavoritesCachePrefs.write('A', '[{"id":"a"}]');
      expect(await FavoritesCachePrefs.read('B'), isNull);
      expect(await FavoritesCachePrefs.read(null), isNull);
      expect(await FavoritesCachePrefs.read('A'), '[{"id":"a"}]');
      expect(
        (await prefKeys()).contains(FavoritesCachePrefs.legacyKey),
        isFalse,
      );
    });
  });

  // ------------------------------------------------- account deletion --
  group('account deletion', () {
    Future<void> seed() async {
      be.saved['A']!
          .add(be.row('A', {'name': 'A-search', 'filters': aFilters}));
      be.saved['B']!
          .add(be.row('B', {'name': 'B-search', 'filters': bFilters}));
      be.sendHook = (r, acct) async =>
          be.sends.isEmpty ? http.Response('', 503) : null;
      await login('B');
      await SavedSearchService.loadMerged();
      OutgoingChatSendService.instance.startTextMessageSend(
        conversationId: 'car_X',
        content: 'B pending',
        tempMessageId: 'temp_B',
      );
      await pumpEventQueue();
      await FavoritesCachePrefs.write('B', '[{"id":"b"}]');
      var sp = await SharedPreferences.getInstance();
      await sp.setStringList('comparison_cars', ['{"id":"b1"}']);
      await logout();

      await login('A');
      await SavedSearchService.loadMerged();
      OutgoingChatSendService.instance.startTextMessageSend(
        conversationId: 'car_X',
        content: 'A pending',
        tempMessageId: 'temp_A',
      );
      await pumpEventQueue();
      await FavoritesCachePrefs.write('A', '[{"id":"a"}]');
      sp = await SharedPreferences.getInstance();
      await sp.setStringList('comparison_cars', ['{"id":"a1"}']);
      be.sendHook = null;
    }

    test('failed deletion keeps all local data', () async {
      await seed();
      be.deleteFails = true;
      await expectLater(
        AuthService().deleteAccount(code: '123456'),
        throwsA(isA<ApiException>()),
      );
      final sp = await SharedPreferences.getInstance();
      expect(sp.containsKey(SavedSearchService.localKeyForOwner('A')), isTrue);
      expect(sp.containsKey(FavoritesCachePrefs.keyForOwner('A')), isTrue);
      expect(sp.getStringList('comparison_cars'), ['{"id":"a1"}']);
      expect(
        (await ChatPendingSendPrefs.loadForOwner('A')).map((r) => r.id),
        ['temp_A'],
      );
    });

    test("confirmed deletion purges A's data and leaves B's untouched",
        () async {
      await seed();
      await AuthService().deleteAccount(code: '123456');
      expect(be.deleted, ['A']);
      final sp = await SharedPreferences.getInstance();
      expect(sp.containsKey(SavedSearchService.localKeyForOwner('A')), isFalse);
      expect(sp.containsKey(FavoritesCachePrefs.keyForOwner('A')), isFalse);
      expect(await ChatPendingSendPrefs.loadForOwner('A'), isEmpty);
      expect(
        sp.getKeys().where((k) =>
            k.startsWith('acct_stash_v1:A:') ||
            k == 'comparison_cars' && sp.getStringList(k)!.contains('{"id":"a1"}')),
        isEmpty,
        reason: "A's scoped values must be gone",
      );
      // B is unaffected.
      expect(sp.containsKey(SavedSearchService.localKeyForOwner('B')), isTrue);
      expect(sp.containsKey(FavoritesCachePrefs.keyForOwner('B')), isTrue);
      expect(
        (await ChatPendingSendPrefs.loadForOwner('B')).map((r) => r.id),
        ['temp_B'],
      );
      await login('B');
      expect(
        (await SharedPreferences.getInstance())
            .getStringList('comparison_cars'),
        ['{"id":"b1"}'],
      );
    });

    test('AccountDataPurge is idempotent for unknown owners', () async {
      await AccountDataPurge.purgeOwner('nobody');
      await AccountDataPurge.purgeOwner('');
    });
  });
}
