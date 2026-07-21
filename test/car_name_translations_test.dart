import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_name_translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(CarNameTranslations.debugResetForTest);

  test('installed pack translates brand by locale code', () {
    CarNameTranslations.debugInstallPack(
      'ar',
      brands: const {'toyota': 'تويوتا'},
    );
    expect(
      CarNameTranslations.getLocalizedBrandForLocale('ar', 'Toyota'),
      'تويوتا',
    );
    expect(
      CarNameTranslations.getLocalizedBrandForLocale('en', 'Toyota'),
      'Toyota',
    );
  });

  test('ensureLoadedForLocale keeps only active translated pack', () async {
    await CarNameTranslations.ensureLoadedForLocale('ar').timeout(
      const Duration(seconds: 15),
    );
    expect(CarNameTranslations.debugHasPack('ar'), isTrue);
    expect(
      CarNameTranslations.getLocalizedBrandForLocale('ar', 'Toyota'),
      'تويوتا',
    );

    await CarNameTranslations.ensureLoadedForLocale('ku').timeout(
      const Duration(seconds: 15),
    );
    expect(CarNameTranslations.debugHasPack('ku'), isTrue);
    expect(CarNameTranslations.debugHasPack('ar'), isFalse);
  });

  test('english skips pack load', () async {
    await CarNameTranslations.ensureLoadedForLocale('en');
    expect(CarNameTranslations.debugHasPack('ar'), isFalse);
    expect(CarNameTranslations.debugHasPack('ku'), isFalse);
  });
}
