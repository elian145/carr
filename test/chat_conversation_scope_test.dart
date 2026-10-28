// F-05 / F-25: which realtime events may appear in ONE open conversation.
//
// One seller (S) talks to several buyers (B1, B2) about the SAME listing. The
// listing id is shared, so without the counterpart a message, typing indicator
// or read receipt of buyer B2 would show up inside buyer B1's thread.
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/chat/chat_conversation_scope.dart';

void main() {
  const car = 'car_1';
  const s = 'seller';
  const b1 = 'buyer_1';
  const b2 = 'buyer_2';

  // The seller looking at the thread with B1.
  const sellerWithB1 = ChatConversationScope(carId: car, myId: s, peerId: b1);

  Map<String, dynamic> msg(String from, String to, {String carId = car}) =>
      <String, dynamic>{'car_id': carId, 'sender_id': from, 'receiver_id': to};

  group('messages (new / updated / deleted)', () {
    test('seller sees only the open buyer\'s messages', () {
      expect(sellerWithB1.matchesMessage(msg(b1, s)), isTrue);
      expect(sellerWithB1.matchesMessage(msg(s, b1)), isTrue);
      expect(sellerWithB1.matchesMessage(msg(b2, s)), isFalse);
      expect(sellerWithB1.matchesMessage(msg(s, b2)), isFalse);
    });

    test('another listing is never shown', () {
      expect(sellerWithB1.matchesMessage(msg(b1, s, carId: 'car_2')), isFalse);
    });

    test('a message between two OTHER people is never shown', () {
      expect(sellerWithB1.matchesMessage(msg(b1, b2)), isFalse);
    });

    test('a buyer (counterpart unnamed) keeps seeing the listing\'s messages',
        () {
      const buyer = ChatConversationScope(carId: car, myId: b1);
      expect(buyer.matchesMessage(msg(s, b1)), isTrue);
      expect(buyer.matchesMessage(msg(b1, s)), isTrue);
      expect(buyer.matchesMessage(msg(s, b1, carId: 'car_2')), isFalse);
    });

    test('payloads without car / participants are handled conservatively', () {
      expect(sellerWithB1.matchesMessage(<String, dynamic>{}), isTrue,
          reason: 'legacy payload: unchanged behaviour');
      expect(
        sellerWithB1.matchesMessage(<String, dynamic>{'sender_id': b2}),
        isFalse,
      );
    });
  });

  group('typing indicators', () {
    Map<String, dynamic> typing(String from, {String? to, String carId = car}) =>
        <String, dynamic>{
          'car_id': carId,
          'user_id': from,
          if (to != null) 'peer_id': to,
          'typing': true,
        };

    test('only the open counterpart, addressed to me, drives the indicator',
        () {
      expect(sellerWithB1.matchesTyping(typing(b1, to: s)), isTrue);
      expect(sellerWithB1.matchesTyping(typing(b2, to: s)), isFalse,
          reason: 'buyer 2 typing must not show in buyer 1\'s thread');
    });

    test('typing addressed to someone else is ignored', () {
      expect(sellerWithB1.matchesTyping(typing(b1, to: b2)), isFalse);
    });

    test('my own typing is never shown back to me', () {
      expect(sellerWithB1.matchesTyping(typing(s, to: b1)), isFalse);
    });

    test('another listing is ignored', () {
      expect(
        sellerWithB1.matchesTyping(typing(b1, to: s, carId: 'car_2')),
        isFalse,
      );
    });

    test('buyer: the seller\'s typing shows, a stranger\'s does not', () {
      const buyer = ChatConversationScope(carId: car, myId: b1, peerId: s);
      expect(buyer.matchesTyping(typing(s, to: b1)), isTrue);
      expect(buyer.matchesTyping(typing(b2, to: b1)), isFalse);
    });

    test('legacy payload without peer_id still works for a known counterpart',
        () {
      expect(sellerWithB1.matchesTyping(typing(b1)), isTrue);
      expect(sellerWithB1.matchesTyping(typing(b2)), isFalse);
    });
  });

  group('read receipts', () {
    Map<String, dynamic> read(String reader, {String carId = car}) =>
        <String, dynamic>{'car_id': carId, 'reader_id': reader};

    test('only the counterpart\'s read of THIS listing counts', () {
      expect(sellerWithB1.matchesRead(read(b1)), isTrue);
      expect(sellerWithB1.matchesRead(read(b2)), isFalse,
          reason: 'buyer 2 reading must not tick buyer 1\'s messages');
      expect(sellerWithB1.matchesRead(read(b1, carId: 'car_2')), isFalse);
    });

    test('buyer without a named counterpart accepts the listing\'s receipts',
        () {
      const buyer = ChatConversationScope(carId: car, myId: b1);
      expect(buyer.matchesRead(read(s)), isTrue);
      expect(buyer.matchesRead(read(s, carId: 'car_2')), isFalse);
    });
  });
}
