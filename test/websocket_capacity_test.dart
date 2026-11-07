// C-1 client side: the server spends its limited socket capacity on
// conversations, so a socket it RELEASES (idle) or REFUSES (out of capacity)
// must never turn into a reconnect storm. The socket is dropped, the
// conversation and queued emits are kept, and it comes back lazily (the next
// join/typing emit) or -- when a conversation is open -- after ONE delayed retry.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/services/websocket_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';

import 'support/fake_ws_socket.dart';
import 'support/test_jwt.dart';

void main() {
  late List<FakeWsSocket> sockets;
  late List<bool> states;
  StreamSubscription<bool>? stateSub;

  Future<void> until(bool Function() cond, {String? what}) async {
    for (var i = 0; i < 300; i++) {
      if (cond()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('timed out waiting for ${what ?? 'condition'}');
  }

  void accept(FakeWsSocket s, String userId) {
    s.fire('connect');
    s.fire('connected', {'authenticated': true, 'user_id': userId});
  }

  setUp(() async {
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    SharedPreferences.setMockInitialValues({});
    ApiService.debugResetSessionForTests();
    await ApiService.clearTokens();
    await ApiService.setTokens(
      accessToken: testJwt('seller', nonce: 'c1', expiresIn: const Duration(hours: 1)),
      refreshToken: testJwt('seller', nonce: 'c1r', type: 'refresh'),
    );
    sockets = [];
    states = [];
    stateSub = WebSocketService.connectionState.listen(states.add);
    WebSocketService.debugSocketFactory = (base, options) {
      final s = FakeWsSocket(options);
      sockets.add(s);
      return s;
    };
  });

  tearDown(() async {
    await stateSub?.cancel();
    WebSocketService.debugCapacityRetryDelay = null;
    WebSocketService.debugReset();
    await ApiService.clearTokens();
  });

  for (final event in ['connection_released', 'connection_replaced']) {
    test('$event drops the socket and does NOT reconnect by itself', () async {
      WebSocketService.joinChat('car_1', peerId: 'buyer_1');
      await until(() => sockets.isNotEmpty, what: 'first socket');
      final first = sockets.single;
      accept(first, 'seller');

      first.fire(event, {'code': 'idle'});
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(first.disposed, isTrue);
      expect(sockets, hasLength(1), reason: 'no automatic reconnect');
      expect(states.isNotEmpty && states.last == false, isTrue,
          reason: 'listeners (REST fallback poll) are told the socket is down');
    });
  }

  test('after a release, opening a conversation reconnects and rejoins', () async {
    WebSocketService.joinChat('car_1', peerId: 'buyer_1');
    await until(() => sockets.isNotEmpty);
    accept(sockets.single, 'seller');
    sockets.single.fire('connection_released', {'code': 'idle'});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sockets, hasLength(1));

    // The user opens (another) conversation: the lazy path reconnects.
    WebSocketService.joinChat('car_2', peerId: 'buyer_2');
    await until(() => sockets.length == 2, what: 'second socket');
    accept(sockets[1], 'seller');
    expect(sockets[1].emits('join_chat').map((e) => e['car_id']), contains('car_2'));
  });

  test('server_busy stops the transport retry loop (no storm)', () async {
    WebSocketService.joinChat('car_1', peerId: 'buyer_1');
    await until(() => sockets.isNotEmpty);
    final s = sockets.single;
    s.fire('connect_error', {'message': 'server_busy'});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.disconnected, isTrue);
    expect(s.disposed, isTrue);
    expect(sockets, hasLength(1));
  });

  test('too_many_connections is treated like server_busy', () async {
    WebSocketService.joinChat('car_1', peerId: 'buyer_1');
    await until(() => sockets.isNotEmpty);
    sockets.single.fire('connect_error', 'too_many_connections');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(sockets.single.disposed, isTrue);
  });

  test('another transport error keeps the existing retry behaviour', () async {
    WebSocketService.joinChat('car_1', peerId: 'buyer_1');
    await until(() => sockets.isNotEmpty);
    final s = sockets.single;
    s.fire('connect_error', 'xhr poll error');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.disposed, isFalse, reason: 'transient errors are retried by the transport');
  });

  test('with a conversation open, ONE delayed retry follows a capacity refusal',
      () async {
    WebSocketService.debugCapacityRetryDelay = const Duration(milliseconds: 80);
    WebSocketService.joinChat('car_1', peerId: 'buyer_1');
    await until(() => sockets.isNotEmpty);
    sockets.single.fire('connect_error', {'message': 'server_busy'});
    await until(() => sockets.length == 2, what: 'delayed retry');
    // Still refused: it schedules the next single retry, never a burst.
    sockets[1].fire('connect_error', {'message': 'server_busy'});
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(sockets, hasLength(2), reason: 'not before the next delay elapses');
  });

  test('with no conversation open there is no retry at all', () async {
    WebSocketService.debugCapacityRetryDelay = const Duration(milliseconds: 40);
    await WebSocketService.connect();
    await until(() => sockets.isNotEmpty);
    sockets.single.fire('connect_error', {'message': 'server_busy'});
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(sockets, hasLength(1));
  });

  test('logout cancels a pending capacity retry', () async {
    WebSocketService.debugCapacityRetryDelay = const Duration(milliseconds: 80);
    WebSocketService.joinChat('car_1', peerId: 'buyer_1');
    await until(() => sockets.isNotEmpty);
    sockets.single.fire('connect_error', {'message': 'server_busy'});
    WebSocketService.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(sockets, hasLength(1));
  });
}