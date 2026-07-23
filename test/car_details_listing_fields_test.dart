import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/listing/car_details_listing_fields.dart';

void main() {
  group('listingFirstNonEmpty', () {
    test('returns first non-empty key', () {
      expect(
        listingFirstNonEmpty({'a': '', 'b': 'ok'}, ['a', 'b']),
        'ok',
      );
    });

    test('returns null when all empty', () {
      expect(listingFirstNonEmpty({'a': ''}, ['a', 'b']), isNull);
    });
  });

  group('sellerPhonesForContact', () {
    test('returns all listing contact phones', () {
      expect(
        sellerPhonesForContact({
          'contact_phones': ['+9647700000001', '+9647700000002'],
          'contact_phone': '+9647700000001',
        }),
        ['+9647700000001', '+9647700000002'],
      );
    });

    test('falls back to seller when listing phones missing', () {
      expect(
        sellerPhonesForContact({
          'seller': {'phone_number': '07701234567'},
        }),
        ['07701234567'],
      );
    });
  });

  group('sellerPhoneRawForContact', () {
    test('prefers contact_phone on listing', () {
      expect(
        sellerPhoneRawForContact({
          'contact_phone': '+9647700000000',
          'seller': {'phone': '111'},
        }),
        '+9647700000000',
      );
    });

    test('falls back to seller phone', () {
      expect(
        sellerPhoneRawForContact({
          'seller': {'phone_number': '07701234567'},
        }),
        '07701234567',
      );
    });

    test('uses first of contact_phones list', () {
      expect(
        sellerPhoneRawForContact({
          'contact_phones': ['+9647700000001', '+9647700000002'],
        }),
        '+9647700000001',
      );
    });
  });

  group('hasDialableSellerPhone', () {
    test('true when digits present', () {
      expect(
        hasDialableSellerPhone({'contact_phone': '+964 770 000 0000'}),
        isTrue,
      );
    });

    test('false when no digits', () {
      expect(hasDialableSellerPhone({'contact_phone': 'n/a'}), isFalse);
    });
  });

  group('listingIdentityIds', () {
    test('collects route and listing ids', () {
      final ids = listingIdentityIds(
        {'id': '1', 'public_id': 'pub-1'},
        'route-id',
      );
      expect(ids, {'route-id', '1', 'pub-1'});
    });
  });
}
