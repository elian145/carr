// F-01/B-02: the car-detail error/retry states reuse existing localized
// strings (no new .arb keys). This confirms those specific getters resolve
// to real, non-empty, locale-appropriate copy in all three supported
// locales, so a locale switch can't silently leave the new error UI blank.
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/l10n/app_localizations_en.dart';
import 'package:car_listing_app/l10n/app_localizations_ar.dart';
import 'package:car_listing_app/l10n/app_localizations_ku.dart';

void main() {
  group('car-detail error/retry copy exists in every supported locale', () {
    test('English', () {
      final loc = AppLocalizationsEn();
      expect(loc.carNotFound, 'Car not found');
      expect(loc.retryAction, 'Retry');
      expect(
        loc.homeFeedNetworkError,
        'Could not reach the server. Check your connection and try again.',
      );
      expect(
        loc.homeFeedServerError('500'),
        'Server error (500). Please try again later.',
      );
      expect(loc.authenticationRequired, 'Authentication Required');
    });

    test('Arabic', () {
      final loc = AppLocalizationsAr();
      for (final value in [
        loc.carNotFound,
        loc.retryAction,
        loc.homeFeedNetworkError,
        loc.homeFeedServerError('500'),
        loc.authenticationRequired,
      ]) {
        expect(value, isNotEmpty);
      }
      // Sanity: not accidentally falling back to English copy.
      expect(loc.retryAction, isNot('Retry'));
      expect(loc.carNotFound, isNot('Car not found'));
    });

    test('Kurdish (Sorani)', () {
      final loc = AppLocalizationsKu();
      for (final value in [
        loc.carNotFound,
        loc.retryAction,
        loc.homeFeedNetworkError,
        loc.homeFeedServerError('500'),
        loc.authenticationRequired,
      ]) {
        expect(value, isNotEmpty);
      }
      expect(loc.retryAction, isNot('Retry'));
      expect(loc.carNotFound, isNot('Car not found'));
    });
  });
}
