import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/api_service.dart';

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

  test('sendChatMessageByConversation POST returns stub payload', () async {
    final result = await ApiService.sendChatMessageByConversation(
      conversationId: '1',
      content: 'Hello',
      receiverId: 'buyer_1',
    );
    expect(result['id'], 1);
    expect(result['content'], 'stub');
  });

  test('getChatMessagesByConversation returns messages envelope', () async {
    final result = await ApiService.getChatMessagesByConversation('1');
    expect(result['messages'], isA<List>());
  });
}
