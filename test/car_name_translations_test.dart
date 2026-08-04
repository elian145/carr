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

  test('hyphenated brand matches spaced translation key', () {
    CarNameTranslations.debugInstallPack(
      'ar',
      brands: const {'land rover': 'لاند روفر'},
      models: const {'land rover|range rover sport': 'رينج روفر سبورت'},
    );
    expect(
      CarNameTranslations.getLocalizedBrandForLocale('ar', 'Land-Rover'),
      'لاند روفر',
    );
    expect(
      CarNameTranslations.getLocalizedModelForLocale(
        'ar',
        'Land-Rover',
        'Range Rover Sport',
      ),
      'رينج روفر سبورت',
    );
  });

  test('spaced brand matches hyphenated translation key', () {
    CarNameTranslations.debugInstallPack(
      'ar',
      brands: const {'mercedes-benz': 'مرسيدس بنز'},
      models: const {'mercedes-benz|c-class': 'سي كلاس'},
    );
    expect(
      CarNameTranslations.getLocalizedBrandForLocale('ar', 'Mercedes Benz'),
      'مرسيدس بنز',
    );
    expect(
      CarNameTranslations.getLocalizedModelForLocale(
        'ar',
        'Mercedes Benz',
        'C-Class',
      ),
      'سي كلاس',
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
