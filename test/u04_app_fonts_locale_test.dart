import 'package:car_listing_app/theme/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// U-04: Orbitron/BarlowCondensed are bundled Latin-only display fonts with
/// no Arabic/Kurdish glyphs. Text whose content can be translated/localized
/// must not resolve to those fonts as the sole family for Arabic/Kurdish --
/// it must instead deterministically resolve to the bundled
/// [AppFonts.notoSansArabicFamily] (Noto Sans Arabic) font, which has full
/// Arabic-script glyph coverage including the extended Sorani Kurdish
/// letters this app's `ku` content uses, rather than depend on whichever
/// OEM/platform fallback happens to substitute glyphs for the wrong font.
void main() {
  group('AppFonts.isLatinBrandFontLocale', () {
    test('true for English', () {
      expect(AppFonts.isLatinBrandFontLocale(const Locale('en')), isTrue);
    });

    test('false for Arabic and Kurdish', () {
      expect(AppFonts.isLatinBrandFontLocale(const Locale('ar')), isFalse);
      expect(AppFonts.isLatinBrandFontLocale(const Locale('ku')), isFalse);
    });
  });

  group('AppFonts.orbitronForLocale', () {
    test('English keeps the branded Latin-only Orbitron family', () {
      final style = AppFonts.orbitronForLocale(
        const Locale('en'),
        fontSize: 20,
      );
      expect(style.fontFamily, AppFonts.orbitronFamily);
    });

    test(
        'Arabic deterministically resolves to the bundled Noto Sans '
        'Arabic font, not the Latin-only Orbitron family', () {
      final style = AppFonts.orbitronForLocale(
        const Locale('ar'),
        fontSize: 20,
      );
      expect(style.fontFamily, isNot(AppFonts.orbitronFamily));
      expect(style.fontFamily, AppFonts.notoSansArabicFamily);
    });

    test(
        'Kurdish deterministically resolves to the bundled Noto Sans '
        'Arabic font, not the Latin-only Orbitron family', () {
      final style = AppFonts.orbitronForLocale(
        const Locale('ku'),
        fontSize: 20,
      );
      expect(style.fontFamily, isNot(AppFonts.orbitronFamily));
      expect(style.fontFamily, AppFonts.notoSansArabicFamily);
    });

    test('non-fontFamily properties are preserved for ar/ku', () {
      final style = AppFonts.orbitronForLocale(
        const Locale('ar'),
        color: Colors.red,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      );
      expect(style.color, Colors.red);
      expect(style.fontSize, 22);
      expect(style.fontWeight, FontWeight.bold);
    });
  });

  group('AppFonts.barlowCondensedForLocale', () {
    test('English keeps the branded Latin-only BarlowCondensed family', () {
      final style = AppFonts.barlowCondensedForLocale(
        const Locale('en'),
        fontSize: 40,
      );
      expect(style.fontFamily, AppFonts.barlowCondensedFamily);
    });

    test(
        'Arabic/Kurdish deterministically resolve to the bundled Noto Sans '
        'Arabic font, not the Latin-only family', () {
      expect(
        AppFonts.barlowCondensedForLocale(
          const Locale('ar'),
          fontSize: 40,
        ).fontFamily,
        AppFonts.notoSansArabicFamily,
      );
      expect(
        AppFonts.barlowCondensedForLocale(
          const Locale('ku'),
          fontSize: 40,
        ).fontFamily,
        AppFonts.notoSansArabicFamily,
      );
    });
  });

  group('AppFonts.fontFamilyForLocale (centralized selection helper)', () {
    test('English resolves to the given Latin family', () {
      expect(
        AppFonts.fontFamilyForLocale(
          const Locale('en'),
          latinFamily: AppFonts.orbitronFamily,
        ),
        AppFonts.orbitronFamily,
      );
    });

    test('Arabic and Kurdish always resolve to Noto Sans Arabic, '
        'regardless of which Latin family is requested', () {
      for (final latinFamily in [
        AppFonts.orbitronFamily,
        AppFonts.barlowCondensedFamily,
      ]) {
        expect(
          AppFonts.fontFamilyForLocale(
            const Locale('ar'),
            latinFamily: latinFamily,
          ),
          AppFonts.notoSansArabicFamily,
        );
        expect(
          AppFonts.fontFamilyForLocale(
            const Locale('ku'),
            latinFamily: latinFamily,
          ),
          AppFonts.notoSansArabicFamily,
        );
      }
    });

    test('is deterministic: repeated calls for the same locale always '
        'return the same family', () {
      final results = List.generate(
        5,
        (_) => AppFonts.fontFamilyForLocale(
          const Locale('ar'),
          latinFamily: AppFonts.orbitronFamily,
        ),
      );
      expect(results.toSet(), {AppFonts.notoSansArabicFamily});
    });
  });

  group('AppFonts.orbitron / barlowCondensed (direct, locale-agnostic)', () {
    test('always apply the branded family regardless of locale', () {
      // Intentional: these remain correct for content that is always
      // Latin/numeric regardless of locale (e.g. plate codes).
      expect(AppFonts.orbitron().fontFamily, AppFonts.orbitronFamily);
      expect(
        AppFonts.barlowCondensed().fontFamily,
        AppFonts.barlowCondensedFamily,
      );
    });
  });
}
