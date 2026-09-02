import 'package:car_listing_app/features/sell/sell_listing_submit_result.dart';
import 'package:car_listing_app/shared/listings/listing_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isListingPendingReview covers moderation states (UX-05)', () {
    expect(isListingPendingReview({'status': 'pending'}), isTrue);
    expect(isListingPendingReview({'status': 'active'}), isFalse);
    expect(isListingPendingReview({'status': 'sold'}), isFalse);
  });

  test('publicListingsOnly drops under-review rows', () {
    final rows = publicListingsOnly([
      {'id': '1', 'status': 'pending'},
      {'id': '2', 'status': 'active'},
      {'id': '3', 'status': 'draft'},
      {'id': '4', 'status': 'sold'},
      {'id': '5', 'status': 'hidden'},
    ]);
    expect(rows.map((r) => r['id']), ['2', '4']);
  });

  test('SellListingSubmitResult carries pending flag', () {
    const live = SellListingSubmitResult(id: 'a', pendingReview: false);
    const held = SellListingSubmitResult(id: 'b', pendingReview: true);
    expect(live.pendingReview, isFalse);
    expect(held.pendingReview, isTrue);
  });
}
