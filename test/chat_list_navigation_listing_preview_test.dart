import 'package:car_listing_app/features/chat/chat_pages.dart' as carzo_chat;
import 'package:flutter_test/flutter_test.dart';

/// Focused, widget-free tests for the exact `listingPreview` construction
/// logic added to `ChatListPage`'s `Navigator.pushNamed('/chat/conversation')`
/// call (Fix A — see chat_list_page.dart).
///
/// `listingMetaFromChatRow` is the same public helper `ChatListPage` uses to
/// build both the display title and the forwarded `listingPreview` map, so
/// this test exercises the identical building block with the identical
/// merge logic used at the call site.
void main() {
  group('ChatListPage listingPreview forwarding (Fix A)', () {
    Map<String, dynamic> buildListingPreview(Map<String, dynamic> chatRow) {
      final listingMeta = carzo_chat.listingMetaFromChatRow(chatRow);
      final carImageRel = (chatRow['car_image_url'] ?? chatRow['image_url'] ?? '')
          .toString()
          .trim();
      return <String, dynamic>{
        ...listingMeta,
        if (carImageRel.isNotEmpty) 'image_url': carImageRel,
      };
    }

    test(
      'includes brand, model and image_url when the chat row has them',
      () {
        final chatRow = <String, dynamic>{
          'car_id': 'list_car_1',
          'car_title': 'Test car',
          'car_brand': 'toyota',
          'car_model': 'camry',
          'car_trim': 'LE',
          'car_year': 2020,
          'car_image_url': 'car_photos/abc.jpg',
        };

        final listingPreview = buildListingPreview(chatRow);

        expect(listingPreview['brand'], 'toyota');
        expect(listingPreview['model'], 'camry');
        expect(listingPreview['trim'], 'LE');
        expect(listingPreview['year'], '2020');
        expect(listingPreview['image_url'], 'car_photos/abc.jpg');
      },
    );

    test(
      'is empty (no brand/model/image_url) when the chat row lacks listing '
      'metadata, preserving the existing ApiService.getCar() fallback',
      () {
        final chatRow = <String, dynamic>{
          'car_id': 'list_car_2',
          'other_user': {'id': 'buyer_1', 'name': 'Test Buyer'},
          // Deliberately no car_brand / car_model / car_title / car_image_url.
        };

        final listingPreview = buildListingPreview(chatRow);

        expect(listingPreview.containsKey('brand'), isFalse);
        expect(listingPreview.containsKey('model'), isFalse);
        expect(listingPreview.containsKey('image_url'), isFalse);
        expect(listingPreview.isEmpty, isTrue);
      },
    );

    test(
      'falls back to title only (still no image_url) when brand/model are '
      'missing but a title is present',
      () {
        final chatRow = <String, dynamic>{
          'car_id': 'list_car_3',
          'car_title': 'Mystery Listing',
        };

        final listingPreview = buildListingPreview(chatRow);

        expect(listingPreview['title'], 'Mystery Listing');
        expect(listingPreview.containsKey('brand'), isFalse);
        expect(listingPreview.containsKey('image_url'), isFalse);
      },
    );
  });
}
