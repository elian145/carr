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
  group('resolveOwnerControlsAccess', () {
    final owned = _car(seller: {'id': 'u1'});

    test('owner of the listing, entry point allows management -> granted', () {
      expect(
        resolveOwnerControlsAccess(
          allowOwnerManagement: true,
          car: owned,
          userId: 'u1',
          hasSession: true,
        ),
        OwnerControlsAccess.granted,
      );
    });

    test('entry point without management (Home feed etc.) -> hidden', () {
      expect(
        resolveOwnerControlsAccess(
          allowOwnerManagement: false,
          car: owned,
          userId: 'u1',
          hasSession: true,
        ),
        OwnerControlsAccess.hidden,
      );
      expect(
        resolveOwnerControlsAccess(
          allowOwnerManagement: false,
          car: owned,
          userId: null,
          hasSession: true,
        ),
        OwnerControlsAccess.hidden,
        reason: 'unknown user must not turn a non-management entry into one',
      );
    });

    test('listing not loaded -> hidden', () {
      expect(
        resolveOwnerControlsAccess(
          allowOwnerManagement: true,
          car: null,
          userId: 'u1',
          hasSession: true,
        ),
        OwnerControlsAccess.hidden,
      );
    });

    test('known different user -> hidden (never granted, never resolving)', () {
      expect(
        resolveOwnerControlsAccess(
          allowOwnerManagement: true,
          car: owned,
          userId: 'someone_else',
          hasSession: true,
        ),
        OwnerControlsAccess.hidden,
      );
    });

    test('session exists but user id unknown -> resolving, not hidden', () {
      for (final unknown in <String?>[null, '', '   ']) {
        expect(
          resolveOwnerControlsAccess(
            allowOwnerManagement: true,
            car: owned,
            userId: unknown,
            hasSession: true,
          ),
          OwnerControlsAccess.resolving,
        );
      }
    });

    test('no session at all (logged out) -> hidden, nothing to wait for', () {
      expect(
        resolveOwnerControlsAccess(
          allowOwnerManagement: true,
          car: owned,
          userId: null,
          hasSession: false,
        ),
        OwnerControlsAccess.hidden,
      );
    });

    test('listing without any seller info -> hidden once the user is known', () {
      expect(
        resolveOwnerControlsAccess(
          allowOwnerManagement: true,
          car: _car(),
          userId: 'u1',
          hasSession: true,
        ),
        OwnerControlsAccess.hidden,
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
