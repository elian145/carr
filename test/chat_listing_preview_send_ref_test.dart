import 'package:car_listing_app/shared/listings/listing_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chatListingPreviewRefForSend (N-1)', () {
    test('sends only the listing id, never the local display fields', () {
      final ref = chatListingPreviewRefForSend({
        'id': 'abc-123',
        'title': 'Anything',
        'price': 1,
        'image_url': 'https://evil.example/x.jpg',
        'images': List.generate(50, (i) => {'image_url': 'u$i'}),
      });
      expect(ref, {'id': 'abc-123'});
    });

    test('prefers public_id like every other listing id lookup', () {
      expect(
        chatListingPreviewRefForSend({'id': 7, 'public_id': 'pub-1'}),
        {'id': 'pub-1'},
      );
    });

    test('no preview stays no preview', () {
      expect(chatListingPreviewRefForSend(null), isNull);
      expect(chatListingPreviewRefForSend(<String, dynamic>{}), isNull);
    });

    test('id-less preview still asks for the conversation listing', () {
      expect(chatListingPreviewRefForSend({'title': 'x'}), {'id': ''});
    });
  });
}
