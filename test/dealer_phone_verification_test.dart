import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/pages/edit_dealer_page.dart';

void main() {
  test('dealer phone verification uses canonical local digits', () {
    expect(
      normalizeDealerPhoneForVerification('+964 750 123 4567'),
      '7501234567',
    );
    expect(normalizeDealerPhoneForVerification('0750-123-4567'), '07501234567');
  });

  test('dealer phone normalization rejects non-number content as empty', () {
    expect(normalizeDealerPhoneForVerification('phone'), isEmpty);
  });

  test('dealer email verification normalizes case and whitespace', () {
    expect(
      normalizeDealerEmailForVerification('  Sales@Shop.COM '),
      'sales@shop.com',
    );
  });

  test('dealer email validation accepts only real addresses', () {
    expect(isValidDealerEmailForVerification('sales@shop.com'), isTrue);
    expect(isValidDealerEmailForVerification('not-an-email'), isFalse);
    expect(isValidDealerEmailForVerification('x@phone.local'), isFalse);
    expect(isValidDealerEmailForVerification(''), isFalse);
  });
}
