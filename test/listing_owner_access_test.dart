// Unit tests for the pure ownership decision behind the Listing Details
// owner controls (Edit / Delete / Analytics).
import 'package:car_listing_app/shared/listings/listing_owner.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _car({String? sellerId, Object? seller}) => {
  'id': 'c1',
  if (sellerId != null) 'seller_id': sellerId,
  if (seller != null) 'seller': seller,
};

void main() {
  group('canManageListing', () {
    final owned = _car(seller: {'id': 'u1'});

    test('owner of the listing, entry point allows management -> true', () {
      expect(
        canManageListing(allowOwnerManagement: true, car: owned, userId: 'u1'),
        isTrue,
      );
    });

    test('entry point without management (Home / Search) -> false, always', () {
      for (final uid in <String?>['u1', null, '']) {
        expect(
          canManageListing(
            allowOwnerManagement: false,
            car: owned,
            userId: uid,
          ),
          isFalse,
          reason: 'navigation origin alone / identity alone never suffice',
        );
      }
    });

    test('listing not loaded -> false', () {
      expect(
        canManageListing(allowOwnerManagement: true, car: null, userId: 'u1'),
        isFalse,
      );
    });

    test('a different account -> false', () {
      expect(
        canManageListing(
          allowOwnerManagement: true,
          car: owned,
          userId: 'someone_else',
        ),
        isFalse,
      );
    });

    test('identity unknown (null / blank) -> false (never granted)', () {
      for (final unknown in <String?>[null, '', '   ']) {
        expect(
          canManageListing(
            allowOwnerManagement: true,
            car: owned,
            userId: unknown,
          ),
          isFalse,
        );
      }
    });

    test('listing without any seller info -> false', () {
      expect(
        canManageListing(allowOwnerManagement: true, car: _car(), userId: 'u1'),
        isFalse,
      );
    });
  });
  group('mergeListingKeepingOwner', () {
    test('a partial result without a seller keeps the owner', () {
      final current = _car(seller: {'id': 'u1'})..['price'] = 1;
      final merged = mergeListingKeepingOwner(current, {'price': 2}, 'u1');
      expect(merged['price'], 2);
      expect(isListingOwner(merged, 'u1'), isTrue);
    });

    test('a result that blanks the seller cannot erase ownership', () {
      final current = _car(sellerId: 'u1', seller: {'id': 'u1'});
      final merged = mergeListingKeepingOwner(current, {
        'seller': null,
        'seller_id': '',
        'price': 3,
      }, 'u1');
      expect(merged['price'], 3);
      expect(isListingOwner(merged, 'u1'), isTrue);
    });

    test('a result carrying the same seller is applied as-is', () {
      final current = _car(seller: {'id': 'u1', 'username': 'old'});
      final merged = mergeListingKeepingOwner(current, {
        'seller': {'id': 'u1', 'username': 'new'},
      }, 'u1');
      expect((merged['seller'] as Map)['username'], 'new');
    });

    test('never creates ownership for a non-owner', () {
      final current = _car(seller: {'id': 'u9'});
      final merged = mergeListingKeepingOwner(current, {'price': 2}, 'u1');
      expect(isListingOwner(merged, 'u1'), isFalse);
    });

    test('does not mutate its inputs', () {
      final current = _car(seller: {'id': 'u1'});
      final updated = <String, dynamic>{'seller': null};
      mergeListingKeepingOwner(current, updated, 'u1');
      expect(current['seller'], isNotNull);
      expect(updated['seller'], isNull);
    });
  });
}
