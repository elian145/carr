import 'package:car_listing_app/features/chat/chat_live_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTP poll only when socket is down (P-10)', () {
    expect(shouldHttpPollChatMessages(socketConnected: true), isFalse);
    expect(shouldHttpPollChatMessages(socketConnected: false), isTrue);
  });

  test('fallback poll interval is slower than former always-on 7s', () {
    expect(kChatHttpFallbackPollInterval.inSeconds, greaterThanOrEqualTo(10));
  });

  test('CHAT-2 text send never uses WebSocket emit', () {
    expect(chatTextSendUsesWebSocket(socketConnected: true), isFalse);
    expect(chatTextSendUsesWebSocket(socketConnected: false), isFalse);
  });
}
