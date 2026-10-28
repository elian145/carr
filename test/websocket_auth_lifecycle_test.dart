// F-36 / F-25 / F-05 client side: the realtime socket's authentication
// lifecycle and conversation addressing.
//
//  * an expired token is never used to open a socket (fail closed),
//  * an expiring / rejected token is refreshed for the SAME session and the
//    socket is rebuilt with the new token, resuming the conversation,
//  * a logout / account switch while a refresh is in flight never revives a
//    socket (and never uses another account's credentials),
//  * the socket must be authenticated as the account the app is signed in as,
//  * typing / join payloads name the counterpart (one seller, many buyers).
//
// Synthetic accounts, a fake Socket.IO socket and an in-memory HTTP client
// only -- no network.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/services/websocket_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';

import 'support/fake_ws_socket.dart';
import 'support/test_jwt.dart';

class _Backend {
  int refreshCalls = 0;
  int status = 200;
  Completer<void>? gate;
  int _n = 0;
  final List<String> issued = [];

  Future<http.Response> handle(http.Request r) async {
    if (r.url.path.endsWith('/auth/refresh')) {
      refreshCalls++;
      final g = gate;
      if (g != null) await g.future;
      if (status != 200) {
        return http.Response(json.encode({'message': 'no'}), status,
            headers: {'content-type': 'application/json'});
      }
      final auth = r.headers['Authorization'] ?? r.headers['authorization'];
      final sub = testJwtSubject(auth?.substring(7));
      final access = testJwt(sub ?? 'unknown', nonce: 'srv${++_n}');
      issued.add(access);
      return http.Response(
        json.encode({
          'access_token': access,
          'refresh_token': testJwt(sub ?? 'unknown', nonce: 'rr$_n', type: 'refresh'),
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404,
        headers: {'content-type': 'application/json'});
  }
}

void main() {
  late _Backend backend;
  late List<FakeWsSocket> sockets;
  late List<String> errors;
  StreamSubscription<String>? errSub;
  var loginN = 0;

  Future<void> login(
    String acct, {
    Duration expiresIn = const Duration(hours: 1),
  }) =>
      ApiService.setTokens(
        accessToken: testJwt(acct, nonce: 'l${++loginN}', expiresIn: expiresIn),
        refreshToken: testJwt(acct, nonce: 'lr$loginN', type: 'refresh'),
      );

  /// Lets broadcast-stream deliveries (error events) reach the listeners.
  Future<void> settleEvents() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  Future<void> until(bool Function() cond, {String? what}) async {
    for (var i = 0; i < 300; i++) {
      if (cond()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('timed out waiting for ${what ?? 'condition'}');
  }

  /// A socket the server accepted: `connect` + `connected(authenticated)`.
  void accept(FakeWsSocket s, String userId, {num? expiresAt}) {
    s.fire('connect');
    s.fire('connected', {
      'authenticated': true,
      'user_id': userId,
      if (expiresAt != null) 'expires_at': expiresAt,
    });
  }

  setUp(() async {
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    backend = _Backend();
    ApiService.testHttpClient = MockClient(backend.handle);
    SharedPreferences.setMockInitialValues({});
    ApiService.debugResetSessionForTests();
    await ApiService.clearTokens();
    sockets = [];
    errors = [];
    errSub = WebSocketService.errors.listen(errors.add);
    WebSocketService.debugSocketFactory = (base, options) {
      final s = FakeWsSocket(options);
      sockets.add(s);
      return s;
    };
  });

  tearDown(() async {
    await errSub?.cancel();
    WebSocketService.debugReset();
    WebSocketService.debugClock = null;
    ApiService.testHttpClient = null;
    await ApiService.clearTokens();
  });

  group('conversation addressing (F-05 / F-25)', () {
    test('join and typing name the counterpart; resumed on reconnect',
        () async {
      await login('seller');
      WebSocketService.joinChat('car_1', peerId: 'buyer_1');
      await until(() => sockets.isNotEmpty, what: 'socket');
      final s = sockets.single;
      expect(s.token, isNotEmpty);
      accept(s, 'seller');

      expect(s.emits('join_chat'), [
        {'car_id': 'car_1', 'peer_id': 'buyer_1'},
      ], reason: 'the seller joins THE thread with buyer_1, not "car_1"');

      WebSocketService.sendTypingStart('car_1', peerId: 'buyer_1');
      WebSocketService.sendTypingStop('car_1', peerId: 'buyer_1');
      expect(s.emits('typing_start'), [
        {'car_id': 'car_1', 'peer_id': 'buyer_1'},
      ]);
      expect(s.emits('typing_stop'), [
        {'car_id': 'car_1', 'peer_id': 'buyer_1'},
      ]);

      // Server reports the per-conversation room; leaving names exactly it.
      s.fire('joined_chat', {
        'ok': true,
        'car_id': 'car_1',
        'peer_id': 'buyer_1',
        'room': 'chat:car_1:buyer_1:seller',
      });
      WebSocketService.leaveChat();
      expect(s.emits('leave_chat'), [
        {'room': 'chat:car_1:buyer_1:seller'},
      ]);
    });

    test('switching from buyer 1 to buyer 2 rejoins with the new counterpart',
        () async {
      await login('seller');
      WebSocketService.joinChat('car_1', peerId: 'buyer_1');
      await until(() => sockets.isNotEmpty);
      final s = sockets.single;
      accept(s, 'seller');
      WebSocketService.joinChat('car_1', peerId: 'buyer_2');
      expect(s.emits('join_chat').map((e) => e['peer_id']),
          ['buyer_1', 'buyer_2']);
    });

    test('a buyer omits the counterpart (the seller is implicit)', () async {
      await login('buyer_1');
      WebSocketService.joinChat('car_1');
      await until(() => sockets.isNotEmpty);
      accept(sockets.single, 'buyer_1');
      expect(sockets.single.emits('join_chat'), [
        {'car_id': 'car_1'},
      ]);
    });
  });

  group('token lifetime (F-36)', () {
    test('an already expired token is refreshed BEFORE the socket opens',
        () async {
      await login('seller', expiresIn: const Duration(minutes: -5));
      final stale = ApiService.accessToken;
      await WebSocketService.connect();
      expect(backend.refreshCalls, 1);
      expect(sockets, hasLength(1));
      expect(sockets.single.token, isNot(stale));
      expect(sockets.single.token, backend.issued.single);
      expect(testJwtSubject(sockets.single.token), 'seller');
    });

    test('expired token and refresh refused: NO socket is opened', () async {
      await login('seller', expiresIn: const Duration(minutes: -5));
      backend.status = 401;
      await WebSocketService.connect();
      expect(sockets, isEmpty,
          reason: 'must not connect with a token known to be expired');
      expect(WebSocketService.isConnected, isFalse);
      await settleEvents();
      expect(errors, contains('Session expired'));
    });

    test('server auth_expired -> refresh -> rebuilt socket, same account, '
        'conversation resumed, queued emit kept', () async {
      await login('seller');
      WebSocketService.joinChat('car_1', peerId: 'buyer_2');
      await until(() => sockets.isNotEmpty);
      final first = sockets.single;
      accept(first, 'seller');
      final firstToken = first.token;

      first.fire('auth_expired', {'error': 'token_expired'});
      // A message the user sends while the token is being replaced.
      await until(() => backend.refreshCalls == 1, what: 'refresh');
      WebSocketService.sendTypingStart('car_1', peerId: 'buyer_2');
      await until(() => sockets.length == 2, what: 'rebuilt socket');

      final second = sockets.last;
      expect(first.disposed, isTrue, reason: 'the stale socket is discarded');
      expect(second.token, isNot(firstToken));
      expect(testJwtSubject(second.token), 'seller');
      accept(second, 'seller');
      expect(second.emits('join_chat'), [
        {'car_id': 'car_1', 'peer_id': 'buyer_2'},
      ], reason: 'the SAME conversation (buyer_2) is resumed');
      expect(second.emits('typing_start'), [
        {'car_id': 'car_1', 'peer_id': 'buyer_2'},
      ]);
    });

    test('an already non-empty queue survives auth recovery EXACTLY once '
        '(join_chat + send_message, in order)', () async {
      await login('seller');
      await WebSocketService.connect();
      final first = sockets.single; // created, NOT yet connected
      WebSocketService.joinChat('car_1', peerId: 'buyer_1');
      WebSocketService.sendMessage('send_message', {'car_id': 'car_1', 'content': 'one'});
      WebSocketService.sendMessage('send_message', {'car_id': 'car_1', 'content': 'two'});
      expect(WebSocketService.debugPendingEmitCount, 3);

      // Hold the refresh open so the queue can be inspected mid-recovery.
      backend.gate = Completer<void>();
      first.fire('auth_expired');
      await until(() => backend.refreshCalls == 1, what: 'refresh started');
      expect(WebSocketService.debugPendingEmitCount, 3,
          reason: 'nothing duplicated or dropped while refreshing');
      backend.gate!.complete();
      await until(() => sockets.length == 2, what: 'rebuilt socket');
      expect(WebSocketService.debugPendingEmitCount, 3,
          reason: 'the queue is carried over, not doubled');

      final second = sockets.last;
      accept(second, 'seller');
      expect(WebSocketService.debugPendingEmitCount, 0);
      expect(second.emits('join_chat'), [
        {'car_id': 'car_1', 'peer_id': 'buyer_1'},
      ], reason: 'exactly one join_chat');
      expect(second.emits('send_message').map((e) => e['content']),
          ['one', 'two'],
          reason: 'each send_message exactly once, original order');
      expect(first.emits('send_message'), isEmpty,
          reason: 'the stale socket never emitted queued events');
    });

    test('connect_error caused by an expired token recovers; other errors '
        'do not refresh', () async {
      await login('seller');
      await WebSocketService.connect();
      final s = sockets.single;
      s.fire('connect_error', 'network down');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(backend.refreshCalls, 0);
      expect(errors.single, contains('Socket connect error'));

      s.fire('connect_error', {'message': 'token_expired'});
      await until(() => sockets.length == 2, what: 'rebuild');
      expect(backend.refreshCalls, 1);
    });

    test('connected(authenticated:false) while holding a token recovers',
        () async {
      await login('seller');
      await WebSocketService.connect();
      sockets.single.fire('connect');
      sockets.single.fire('connected', {'authenticated': false});
      await until(() => sockets.length == 2, what: 'rebuild');
      expect(backend.refreshCalls, 1);
    });

    test('refresh refused during recovery: socket is closed, not retried',
        () async {
      await login('seller');
      await WebSocketService.connect();
      accept(sockets.single, 'seller');
      backend.status = 401;
      sockets.single.fire('auth_expired');
      await until(() => errors.contains('Session expired'));
      expect(sockets, hasLength(1));
      expect(WebSocketService.isConnected, isFalse);
    });

    test('recovery is bounded: a server that keeps refusing is not hammered',
        () async {
      await login('seller');
      await WebSocketService.connect();
      for (var i = 1; i <= 3; i++) {
        sockets.last.fire('auth_expired');
        await until(() => sockets.length == i + 1, what: 'rebuild $i');
      }
      sockets.last.fire('auth_expired');
      await until(() => errors.contains('Authentication failed'));
      expect(sockets, hasLength(4));
      expect(backend.refreshCalls, 3);
    });

    test('socket authenticated as ANOTHER account is dropped', () async {
      await login('seller');
      await WebSocketService.connect();
      sockets.single.fire('connect');
      sockets.single.fire('connected', {
        'authenticated': true,
        'user_id': 'someone_else',
      });
      await settleEvents();
      expect(errors, contains('Socket account mismatch'));
      expect(WebSocketService.isConnected, isFalse);
      expect(sockets.single.disposed, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(backend.refreshCalls, 0, reason: 'a mismatch is not retried');
    });
  });

  group('account switching while the token is refreshed (F-36 / F-35)', () {
    test('switch A -> B mid-refresh: nothing is rebuilt, B is never '
        'connected under A, A\'s events are dropped', () async {
      await login('acct_A');
      WebSocketService.joinChat('car_1', peerId: 'buyer_1');
      await until(() => sockets.isNotEmpty);
      final aSocket = sockets.single;
      accept(aSocket, 'acct_A');

      backend.gate = Completer<void>();
      aSocket.fire('auth_expired');
      await until(() => backend.refreshCalls == 1);

      // The user switches account while A's refresh is still in flight.
      await ApiService.logout();
      await login('acct_B');
      backend.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(sockets, hasLength(1),
          reason: 'the refresh for A must not build a socket for anyone');
      expect(WebSocketService.isConnected, isFalse);
      expect(WebSocketService.debugPendingEmitCount, 0);
      expect(testJwtSubject(ApiService.accessToken), 'acct_B');

      // B opens its own conversation: a brand new socket with B's token only.
      WebSocketService.joinChat('car_9', peerId: 'x');
      await until(() => sockets.length == 2);
      expect(testJwtSubject(sockets.last.token), 'acct_B');
      expect(sockets.last.token, isNot(aSocket.token));

      // A late event on A's discarded socket must not reach the app.
      final seen = <Map<String, dynamic>>[];
      final sub = WebSocketService.messages.listen(seen.add);
      aSocket.fire('new_message', {'id': 'leak', 'car_id': 'car_1'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(seen, isEmpty);
    });

    test('plain logout mid-refresh never revives a socket', () async {
      await login('acct_A');
      await WebSocketService.connect();
      accept(sockets.single, 'acct_A');
      backend.gate = Completer<void>();
      sockets.single.fire('auth_expired');
      await until(() => backend.refreshCalls == 1);
      await ApiService.logout();
      backend.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sockets, hasLength(1));
      expect(WebSocketService.isConnected, isFalse);
    });

    test('reconnect after logout with no token fails closed', () async {
      await login('acct_A');
      await WebSocketService.connect();
      await ApiService.logout();
      await WebSocketService.connect();
      expect(sockets, hasLength(1));
      await settleEvents();
      expect(errors, contains('No access token found'));
    });
  });

  group('proactive refresh before expiry (F-36)', () {
    testWidgets('refreshes ahead of the server-reported expiry and rebuilds',
        (tester) async {
      // Frozen "now" (the real now, so the freshly issued token is valid).
      final t0 = DateTime.now().toUtc();
      WebSocketService.debugClock = () => t0;
      await tester.runAsync(() => login('seller'));
      WebSocketService.joinChat('car_1', peerId: 'buyer_1');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => until(() => sockets.isNotEmpty));
      final first = sockets.single;
      // The server says the token lives for 10 more minutes.
      accept(first, 'seller',
          expiresAt: t0.millisecondsSinceEpoch ~/ 1000 + 600);

      await tester.pump(const Duration(minutes: 7));
      expect(backend.refreshCalls, 0, reason: 'too early: lead time not hit');

      await tester.pump(const Duration(minutes: 2));
      await tester.runAsync(() => until(() => backend.refreshCalls == 1));
      await tester.runAsync(() => until(() => sockets.length == 2));
      expect(sockets.last.token, isNot(first.token));
      accept(sockets.last, 'seller');
      expect(sockets.last.emits('join_chat'), [
        {'car_id': 'car_1', 'peer_id': 'buyer_1'},
      ]);
      WebSocketService.disconnect();
    });
  });
}
