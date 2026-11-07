import 'dart:io';

import 'package:car_listing_app/shared/phone/tel_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dialableTelNumber (F-40: never strip the leading +)', () {
    test('the E.164 form the API serves keeps its +', () {
      expect(dialableTelNumber('+9647701234567'), '+9647701234567');
      expect(telUriFor('+9647701234567').toString(), 'tel:+9647701234567');
    });

    test('digits-only (the old behaviour) is no longer produced for +964', () {
      // Old code: "+9647701234567" -> "tel:9647701234567" (a local-looking number).
      expect(telUriFor('+9647701234567').toString(), isNot('tel:9647701234567'));
    });

    test('every Iraqi spelling collapses to one dial string', () {
      const spellings = [
        '+9647701234567',
        '+964 770 123 4567',
        '+964-770-123-4567',
        '(+964) 770.123.4567',
        '009647701234567',
        '9647701234567',
        '07701234567',
        '0770 123 4567',
        '7701234567',
      ];
      for (final s in spellings) {
        expect(dialableTelNumber(s), '+9647701234567', reason: s);
      }
    });

    test('malformed legacy +9640... (trunk zero after country code) is repaired', () {
      expect(dialableTelNumber('+96407701234567'), '+9647701234567');
    });

    test('Arabic-Indic and Persian digits are folded to ASCII', () {
      expect(dialableTelNumber('٠٧٧٠١٢٣٤٥٦٧'), '+9647701234567');
      expect(dialableTelNumber('+٩٦٤٧٧٠١٢٣٤٥٦٧'), '+9647701234567');
      expect(dialableTelNumber('۰۷۷۰۱۲۳۴۵۶۷'), '+9647701234567');
    });

    test('a foreign number keeps its explicit + and is not rewritten', () {
      expect(dialableTelNumber('+44 20 7183 8750'), '+442071838750');
      expect(dialableTelNumber('0044 20 7183 8750'), '+442071838750');
    });

    test('a bare non-Iraqi local number stays digits-only (nothing to infer)', () {
      expect(dialableTelNumber('020 7183 8750'), '02071838750');
    });

    test('not dialable -> null (callers show "phone not available")', () {
      for (final s in [null, '', '   ', 'abc', '+', '---', '+ -']) {
        expect(dialableTelNumber(s), isNull, reason: '$s');
        expect(telUriFor(s), isNull, reason: '$s');
      }
    });

    test('the tel Uri carries no query, fragment or encoded plus', () {
      final uri = telUriFor('+964 770 123 4567')!;
      expect(uri.scheme, 'tel');
      expect(uri.path, '+9647701234567');
      expect(uri.hasQuery, isFalse);
      expect(uri.hasFragment, isFalse);
      expect(uri.toString(), isNot(contains('%2B')));
    });
  });

  test('no call site builds a tel: Uri from digits-only / raw text', () {
    for (final f in [
      'lib/pages/car_details_page_contact.dart',
      'lib/pages/dealer_profile_page_helpers.dart',
      'lib/pages/help_center_page.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src, contains('telUriFor('), reason: f);
      expect(src.contains("Uri.parse('tel:"), isFalse, reason: f);
    }
  });
}
