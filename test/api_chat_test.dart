import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/outgoing_chat_send_service.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  test('getChats returns array rows from mock API', () async {
    final chats = await ApiService.getChats();
    expect(chats, isA<List<Map<String, dynamic>>>());
    expect(chats.length, 1);
    expect(chats.first['car_id'], 'list_car_1');
    expect(chats.first['last_message'], isA<Map>());
  });

  test('getUnreadChatCount reads unread_count envelope', () async {
    final count = await ApiService.getUnreadChatCount();
    expect(count, 0);
  });

  test('sendChatMessageByConversation POST returns message envelope', () async {
    final result = await ApiService.sendChatMessageByConversation(
      conversationId: '1',
      content: 'Hello',
      receiverId: 'buyer_1',
    );
    expect(result['message'], isA<Map<String, dynamic>>());
    expect(result['message']['content'], 'Hello');
  });

  test('getChatMessagesByConversation returns messages envelope', () async {
    final result = await ApiService.getChatMessagesByConversation('1');
    expect(result['messages'], isA<List>());
  });

  // BE-18: idempotency-key propagation (client -> HTTP layer).
  group('BE-18 chat send idempotency key propagation', () {
    setUp(() {
      FakeApiServer.chatSendIdempotencyKeys.clear();
    });

    test(
      'sendChatMessageByConversation forwards the given Idempotency-Key '
      'header verbatim, so an automatic timeout/401 retry of the same '
      '_makeAuthenticatedRequest call (which reuses the same header map) '
      'reuses the same key',
      () async {
        await ApiService.sendChatMessageByConversation(
          conversationId: '1',
          content: 'hello',
          receiverId: 'buyer_1',
          idempotencyKey: 'fixed-retry-key-123',
        );
        expect(FakeApiServer.chatSendIdempotencyKeys, ['fixed-retry-key-123']);
      },
    );

    test(
      'omitting idempotencyKey sends no Idempotency-Key header '
      '(backward compatible with existing callers)',
      () async {
        await ApiService.sendChatMessageByConversation(
          conversationId: '1',
          content: 'hello',
          receiverId: 'buyer_1',
        );
        expect(FakeApiServer.chatSendIdempotencyKeys, [null]);
      },
    );

    test(
      'two distinct logical sends via OutgoingChatSendService.startTextMessageSend '
      'each get their own freshly-generated key (a new user action must never '
      'reuse a previous send\'s key)',
      () async {
        final events = <OutgoingChatSendEvent>[];
        final sub = OutgoingChatSendService.instance.events.listen(events.add);
        addTearDown(() => sub.cancel());

        OutgoingChatSendService.instance.startTextMessageSend(
          conversationId: '1',
          content: 'first message',
        );
        await pumpEventQueue();

        OutgoingChatSendService.instance.startTextMessageSend(
          conversationId: '1',
          content: 'second message',
        );
        await pumpEventQueue();

        expect(events.length, 2);
        expect(events.every((e) => e.success), isTrue, reason: '$events');
        expect(FakeApiServer.chatSendIdempotencyKeys.length, 2);
        final key1 = FakeApiServer.chatSendIdempotencyKeys[0];
        final key2 = FakeApiServer.chatSendIdempotencyKeys[1];
        expect(key1, isNotNull);
        expect(key2, isNotNull);
        expect(key1, isNot(equals(key2)));
      },
    );
  });
}
