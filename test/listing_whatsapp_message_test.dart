import 'package:car_listing_app/shared/listings/listing_share_urls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildListingWhatsAppMessage appends listing link', () {
    final msg = buildListingWhatsAppMessage(
      interestText: 'Hi, I am interested in your 2020 Toyota Camry.',
      listingId: 'abc123',
    );
    expect(msg, contains('2020 Toyota Camry'));
    expect(msg, contains('abc123'));
    expect(msg, startsWith('Hi, I am interested in your'));
  });

  test('buildListingWhatsAppMessage works without link when id empty', () {
    final msg = buildListingWhatsAppMessage(
      interestText: 'مرحباً، أنا مهتم بـ سيارة.',
      listingId: '',
    );
    expect(msg, 'مرحباً، أنا مهتم بـ سيارة.');
  });
}
