import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/websocket_service.dart';

import 'fake_api_server.dart';
import 'support/fake_ws_socket.dart';
import 'support/test_jwt.dart';

/// Real-device regression (Samsung A17): a buyer's typing indicator never
/// reached the seller's screen although the backend delivered it to the right
/// conversation room.
///
/// Cause: the client asked for `transports: ['polling', 'websocket']`. On
/// dart:io `socket_io_client` has ONE transport implementation (a WebSocket);
/// for `polling` it opens a WebSocket handshake labelled `transport=polling`,
/// which the Engine.IO server answers as ordinary polling (HTTP 200, no
/// upgrade). The socket therefore never connected, `join_chat` never reached
/// the server, and room-scoped events (typing, read receipts) were never
/// delivered. Plain `new_message` still "worked" through the 12 s HTTP poll.
///
/// The only transport that can connect on native is `websocket`.
void main() {
  late List<FakeWsSocket> sockets;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
    sockets = [];
    WebSocketService.debugSocketFactory = (base, options) {
      final s = FakeWsSocket(options);
      sockets.add(s);
      return s;
    };
    await AuthService().adoptTestSession(
      user: {
        'id': 'seller_1',
        'username': 'seller_1',
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
    await ApiService.setTokens(
      accessToken: testJwt('seller_1', nonce: 't1'),
      refreshToken: testJwt('seller_1', type: 'refresh'),
    );
  });

  tearDown(() async {
    WebSocketService.debugReset();
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  test('the socket asks for the websocket transport only', () async {
    await WebSocketService.connect();

    expect(sockets, hasLength(1));
    final options = sockets.single.options;
    expect(
      options['transports'],
      <String>['websocket'],
      reason: 'dart:io socket_io_client cannot do HTTP long-polling; a '
          '"polling" first transport is a mislabelled WebSocket handshake '
          'the server rejects, so the socket never connects',
    );
    // Every socket gets a fresh Manager: the cached one would keep the
    // previous account's bearer token after an account switch.
    expect(options['forceNew'], isTrue);
    // Authentication still travels in the handshake headers, never the URL.
    expect(sockets.single.token, isNotEmpty);
    expect(options['query'], isNull);
    expect(options['path'], '/socket.io/');
  });

  test('a connected seller socket delivers buyer typing to the chat stream',
      () async {
    final typing = <Map<String, dynamic>>[];
    final sub = WebSocketService.typingEvents.listen(typing.add);

    WebSocketService.joinChat('car_x', peerId: 'buyer_a');
    final socket = sockets.last;
    socket.fire('connect');
    socket.fire('connected', {'authenticated': true, 'user_id': 'seller_1'});

    expect(socket.emits('join_chat'), [
      {'car_id': 'car_x', 'peer_id': 'buyer_a'},
    ]);

    socket.fire('typing', {
      'car_id': 'car_x',
      'user_id': 'buyer_a',
      'peer_id': 'seller_1',
      'user_name': 'Alice BuyerA',
      'typing': true,
    });
    await Future<void>.delayed(Duration.zero);
    expect(typing.single['user_id'], 'buyer_a');

    await sub.cancel();
  });
}
