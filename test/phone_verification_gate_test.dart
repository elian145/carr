import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/shared/auth/phone_verification_gate.dart';

void main() {
  group('isPhoneVerificationRequired', () {
    test('returns true for ApiException with error code', () {
      final err = ApiException(
        statusCode: 403,
        message: 'Verify your phone number before continuing.',
        body: {'code': kPhoneVerificationRequiredCode},
      );
      expect(isPhoneVerificationRequired(err), isTrue);
    });

    test('returns true for 403 message without code', () {
      final err = ApiException(
        statusCode: 403,
        message: 'Please verify your phone first.',
      );
      expect(isPhoneVerificationRequired(err), isTrue);
    });

    test('returns false for other ApiException', () {
      final err = ApiException(
        statusCode: 401,
        message: 'Unauthorized',
      );
      expect(isPhoneVerificationRequired(err), isFalse);
    });

    test('returns false for non-ApiException', () {
      expect(isPhoneVerificationRequired(Exception('network')), isFalse);
    });
  });

  group('phoneVerificationRequiredMessage', () {
    test('falls back to English when loc is null', () {
      expect(
        phoneVerificationRequiredMessage(null),
        contains('Verify your phone'),
      );
    });
  });
}
