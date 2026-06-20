import 'package:car_listing_app/shared/phone/phone_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizePhoneNumber', () {
    test('returns empty for blank input', () {
      expect(normalizePhoneNumber(''), '');
      expect(normalizePhoneNumber('   '), '');
    });

    test('preserves explicit international plus prefix', () {
      expect(normalizePhoneNumber('+964 770 123 4567'), '+9647701234567');
    });

    test('converts Iraqi local mobile formats', () {
      expect(normalizePhoneNumber('07701234567'), '+9647701234567');
      expect(normalizePhoneNumber('7701234567'), '+9647701234567');
      expect(normalizePhoneNumber('9647701234567'), '+9647701234567');
    });

    test('converts 00 international prefix', () {
      expect(normalizePhoneNumber('009647701234567'), '+9647701234567');
    });

    test('falls back to digits-only for unknown local formats', () {
      expect(normalizePhoneNumber('(555) 123-4567'), '5551234567');
    });
  });
}
