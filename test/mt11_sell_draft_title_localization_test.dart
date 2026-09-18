// Regression test for the MT-11 device QA finding: a saved Sell Draft card
// showed the vehicle brand/model title in English even when the app locale
// was Arabic or Kurdish (e.g. "Toyota Avalon • TRD • 2022"), because
// `sell_draft_gate.dart` (and two duplicate call sites) concatenated the raw
// English `carData['brand']`/`carData['model']` strings instead of routing
// them through the app's existing catalog localization helper
// (`CarNameTranslations`, already used by published listing cards and the
// car details page). See `localizedSellDraftTitle` in
// `lib/features/sell/sell_draft_helpers.dart` and PRODUCTION_AUDIT.md MT-11.
//
// Trim (e.g. "TRD") and year are expected to remain unchanged in every
// locale, matching every other title helper in the app.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/data/car_name_translations.dart';
import 'package:car_listing_app/features/sell/sell_draft_gate.dart';
import 'package:car_listing_app/features/sell/sell_draft_helpers.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/feature_flags.dart';
import 'package:car_listing_app/shared/i18n/ku_delegates.dart';

/// A known catalog example with installed Arabic/Kurdish display names,
/// matching the exact bug-report example ("Toyota Avalon • TRD • 2022").
const Map<String, dynamic> _carData = {
  'brand': 'Toyota',
  'model': 'Avalon',
  'trim': 'TRD',
  'year': '2022',
};

void _installTestCatalogPacks() {
  CarNameTranslations.debugInstallPack(
    'ar',
    brands: const {'toyota': 'تويوتا'},
    models: const {'toyota|avalon': 'أفالون'},
  );
  CarNameTranslations.debugInstallPack(
    'ku',
    brands: const {'toyota': 'تۆیۆتا'},
    models: const {'toyota|avalon': 'ئەڤالۆن'},
  );
}

Widget _appFor(Locale locale, Widget home) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar'), Locale('ku')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      KuMaterialLocalizationsDelegate(),
      KuWidgetsLocalizationsDelegate(),
      KuCupertinoLocalizationsDelegate(),
    ],
    home: home,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(CarNameTranslations.debugResetForTest);

  group('MT-11 localizedSellDraftTitle (unit level)', () {
    testWidgets('Locale(en): keeps the existing English brand/model', (
      tester,
    ) async {
      _installTestCatalogPacks();
      late BuildContext capturedContext;
      await tester.pumpWidget(
        _appFor(
          const Locale('en'),
          Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        localizedSellDraftTitle(capturedContext, _carData),
        'Toyota Avalon • TRD • 2022',
      );
    });

    testWidgets(
      'Locale(ar): uses the catalog Arabic brand/model display names',
      (tester) async {
        _installTestCatalogPacks();
        late BuildContext capturedContext;
        await tester.pumpWidget(
          _appFor(
            const Locale('ar'),
            Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final title = localizedSellDraftTitle(capturedContext, _carData);
        expect(title, 'تويوتا أفالون • TRD • 2022');
        // Must not silently keep the raw English catalog names.
        expect(title, isNot(contains('Toyota')));
        expect(title, isNot(contains('Avalon')));
        // Trim/year are proper names/numbers -- unchanged in every locale.
        expect(title, contains('TRD'));
        expect(title, contains('2022'));
      },
    );

    testWidgets(
      'Locale(ku): uses the catalog Kurdish brand/model display names',
      (tester) async {
        _installTestCatalogPacks();
        late BuildContext capturedContext;
        await tester.pumpWidget(
          _appFor(
            const Locale('ku'),
            Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final title = localizedSellDraftTitle(capturedContext, _carData);
        expect(title, 'تۆیۆتا ئەڤالۆن • TRD • 2022');
        expect(title, isNot(contains('Toyota')));
        expect(title, isNot(contains('Avalon')));
        expect(title, contains('TRD'));
        expect(title, contains('2022'));
      },
    );

    testWidgets(
      'brand/model with no catalog translation installed fall back to the '
      'original (untranslated) English text rather than crashing',
      (tester) async {
        // No debugInstallPack call for 'ar' here -- simulates a brand/model
        // the catalog JSON has no translation for.
        late BuildContext capturedContext;
        await tester.pumpWidget(
          _appFor(
            const Locale('ar'),
            Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          localizedSellDraftTitle(capturedContext, _carData),
          'Toyota Avalon • TRD • 2022',
        );
      },
    );

    testWidgets('empty carData falls back to "Untitled draft"', (
      tester,
    ) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        _appFor(
          const Locale('en'),
          Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        localizedSellDraftTitle(capturedContext, const {}),
        'Untitled draft',
      );
    });
  });

  group('MT-11 SellDraftGatePage renders a localized title end-to-end', () {
    setUp(() {
      FeatureFlags.setCachedForTests(FeatureFlagsSnapshot.defaults());
    });

    tearDown(() {
      FeatureFlags.resetCacheForTests();
    });

    Future<void> seedActiveDraft() async {
      SharedPreferences.setMockInitialValues({
        'legacy_sell_draft_snapshot_v1': json.encode({
          'draftId': 'mt11_draft',
          'currentStep': 1,
          'carData': _carData,
          'isPlaceholder': false,
          'updatedAt': 1700000000000,
        }),
      });
    }

    testWidgets('Locale(ar): the Continue Draft card title is Arabic', (
      tester,
    ) async {
      _installTestCatalogPacks();
      await seedActiveDraft();

      await tester.pumpWidget(
        _appFor(const Locale('ar'), const SellDraftGatePage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('تويوتا أفالون • TRD • 2022'), findsOneWidget);
      expect(find.text('Toyota Avalon • TRD • 2022'), findsNothing);

      // Draft resume/delete UI is unaffected by this fix: the Continue and
      // Discard actions (localized) are still present on the card.
      expect(find.text('متابعة'), findsOneWidget); // continueAction
      expect(find.text('حذف'), findsOneWidget); // discard

      // Discard confirmation flow still works; cancelling must not remove
      // the draft or otherwise change its (still-localized) title.
      await tester.tap(find.text('حذف'));
      await tester.pumpAndSettle();
      expect(find.text('حذف المسودة؟'), findsOneWidget); // discardDraft
      await tester.tap(find.text('إلغاء')); // cancelAction
      await tester.pumpAndSettle();

      expect(find.text('تويوتا أفالون • TRD • 2022'), findsOneWidget);
    });

    testWidgets('Locale(ku): the Continue Draft card title is Kurdish', (
      tester,
    ) async {
      _installTestCatalogPacks();
      await seedActiveDraft();

      await tester.pumpWidget(
        _appFor(const Locale('ku'), const SellDraftGatePage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('تۆیۆتا ئەڤالۆن • TRD • 2022'), findsOneWidget);
      expect(find.text('Toyota Avalon • TRD • 2022'), findsNothing);

      expect(find.text('بەردەوامبوون'), findsOneWidget); // continueAction
      expect(find.text('بسڕەوە'), findsOneWidget); // discard
    });

    testWidgets('Locale(en): the Continue Draft card title is unchanged', (
      tester,
    ) async {
      _installTestCatalogPacks();
      await seedActiveDraft();

      await tester.pumpWidget(
        _appFor(const Locale('en'), const SellDraftGatePage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Toyota Avalon • TRD • 2022'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
    });
  });
}
