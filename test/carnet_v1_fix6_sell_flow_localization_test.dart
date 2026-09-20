// CarNet V1 release-candidate fix 6 -- remove remaining hardcoded English
// from the common Sell / My Listings flow.
//
// Bug: several user-facing strings were hardcoded English literals despite
// matching (or now newly added) ARB keys existing for the same concepts:
//   * `sell_car_page_draft_banner.dart` -- the mid-wizard "resume draft"
//     banner's step label ("Step 1: Photos" .. "Step 6: Review"), the
//     "Continue here to finish..." subtitle, and its "Discard draft" /
//     "Continue" button labels.
//   * `my_listings_page_widgets.dart` -- the "DRAFT" badge overlay and the
//     same step-label array, duplicated for the My Listings draft card.
//   * `sell_car_page.dart` / `sell_step5_build.dart` -- the
//     "Please complete all required fields before proceeding" /
//     "Please complete: {fields}" validation snackbars.
//   * `sell_draft_gate.dart` -- the "Selling unavailable" /
//     "Creating new listings is temporarily disabled..." dialog shown when
//     the `sell` feature flag is off.
//
// Fix: every site above now reads through `AppLocalizations` -- reusing
// existing keys (`sellStep1Photos`..`sellStep6Review`, `continueAction`,
// `discard`, `ok`) where they already existed, and adding a small number of
// new EN/AR/KU ARB keys only where a matching concept was genuinely missing
// (`discardDraftAction`, `continueHereToFinishTheListingOrDiscardItIfYouWantToStartOver`,
// `draftBadgeLabel`, `pleaseCompleteAllRequiredFieldsBeforeProceeding`,
// `pleaseCompleteMissingFields`, `sellingUnavailableTitle`,
// `sellingUnavailableBody`).
//
// This file proves (a) the `SellDraftGatePage` "Selling unavailable" dialog
// renders fully localized end-to-end in en/ar/ku, and (b) every new/reused
// ARB key resolves to the correct, non-English-leaking string in ar/ku via
// direct `AppLocalizations` lookups (unit level, mirroring the existing
// `mt11_sell_draft_title_localization_test.dart` pattern) for the other
// sites, which are otherwise deep inside the multi-step sell wizard.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/features/sell/sell_draft_gate.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/feature_flags.dart';
import 'package:car_listing_app/shared/i18n/ku_delegates.dart';

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

  group(
    'fix 6: SellDraftGatePage "Selling unavailable" dialog is fully '
    'localized when the sell feature flag is off',
    () {
      setUp(() {
        FeatureFlags.setCachedForTests(
          const FeatureFlagsSnapshot({
            'sell': false,
            'chat': true,
            'dealers': true,
            'comparison': true,
            'saved_searches': true,
          }),
        );
        SharedPreferences.setMockInitialValues({});
      });

      tearDown(() {
        FeatureFlags.resetCacheForTests();
      });

      testWidgets('Locale(en): dialog shows the English copy', (
        tester,
      ) async {
        await tester.pumpWidget(
          _appFor(const Locale('en'), const SellDraftGatePage()),
        );
        await tester.pumpAndSettle();

        expect(find.text('Selling unavailable'), findsOneWidget);
        expect(
          find.text(
            'Creating new listings is temporarily disabled. Please try again later.',
          ),
          findsOneWidget,
        );
        expect(find.text('OK'), findsOneWidget);
      });

      testWidgets(
        'Locale(ar): dialog shows the Arabic copy, not the English literal',
        (tester) async {
          await tester.pumpWidget(
            _appFor(const Locale('ar'), const SellDraftGatePage()),
          );
          await tester.pumpAndSettle();

          expect(find.text('البيع غير متوفر'), findsOneWidget);
          expect(
            find.text(
              'تم تعطيل إنشاء الإعلانات الجديدة مؤقتاً. يرجى المحاولة مرة أخرى لاحقاً.',
            ),
            findsOneWidget,
          );
          expect(find.text('Selling unavailable'), findsNothing);
          expect(
            find.text(
              'Creating new listings is temporarily disabled. Please try again later.',
            ),
            findsNothing,
          );
        },
      );

      testWidgets(
        'Locale(ku): dialog shows the Kurdish copy, not the English literal',
        (tester) async {
          await tester.pumpWidget(
            _appFor(const Locale('ku'), const SellDraftGatePage()),
          );
          await tester.pumpAndSettle();

          expect(find.text('فرۆشتن بەردەست نییە'), findsOneWidget);
          expect(
            find.text(
              'دروستکردنی ڕیکلامی نوێ بۆ ماوەیەک ناچالاک کراوە. تکایە دوایتر هەوڵ بدەوە.',
            ),
            findsOneWidget,
          );
          expect(find.text('Selling unavailable'), findsNothing);
        },
      );
    },
  );

  group(
    'fix 6: every localization key used by the sell-flow/My Listings fixes '
    'resolves to a real, non-English string in ar/ku',
    () {
      Future<AppLocalizations> locFor(
        WidgetTester tester,
        Locale locale,
      ) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          _appFor(
            locale,
            Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        return AppLocalizations.of(capturedContext)!;
      }

      testWidgets('sell wizard step labels (en/ar/ku)', (tester) async {
        final en = await locFor(tester, const Locale('en'));
        expect(en.sellStep1Photos, 'Step 1: Photos');
        expect(en.sellStep6Review, 'Step 6: Review');

        final ar = await locFor(tester, const Locale('ar'));
        expect(ar.sellStep1Photos, isNot('Step 1: Photos'));
        expect(ar.sellStep6Review, isNot('Step 6: Review'));

        final ku = await locFor(tester, const Locale('ku'));
        expect(ku.sellStep1Photos, isNot('Step 1: Photos'));
        expect(ku.sellStep6Review, isNot('Step 6: Review'));
      });

      testWidgets('draft banner subtitle + button labels (en/ar/ku)', (
        tester,
      ) async {
        final en = await locFor(tester, const Locale('en'));
        expect(en.discardDraftAction, 'Discard draft');
        expect(
          en.continueHereToFinishTheListingOrDiscardItIfYouWantToStartOver,
          'Continue here to finish the listing, or discard it if you want to start over.',
        );
        expect(en.continueAction, 'Continue');

        final ar = await locFor(tester, const Locale('ar'));
        expect(ar.discardDraftAction, isNot('Discard draft'));
        expect(
          ar.continueHereToFinishTheListingOrDiscardItIfYouWantToStartOver,
          isNot(
            'Continue here to finish the listing, or discard it if you want to start over.',
          ),
        );

        final ku = await locFor(tester, const Locale('ku'));
        expect(ku.discardDraftAction, isNot('Discard draft'));
        expect(
          ku.continueHereToFinishTheListingOrDiscardItIfYouWantToStartOver,
          isNot(
            'Continue here to finish the listing, or discard it if you want to start over.',
          ),
        );
      });

      testWidgets('My Listings "DRAFT" badge (en/ar/ku)', (tester) async {
        final en = await locFor(tester, const Locale('en'));
        expect(en.draftBadgeLabel, 'DRAFT');

        final ar = await locFor(tester, const Locale('ar'));
        expect(ar.draftBadgeLabel, isNot('DRAFT'));
        expect(ar.draftBadgeLabel, isNotEmpty);

        final ku = await locFor(tester, const Locale('ku'));
        expect(ku.draftBadgeLabel, isNot('DRAFT'));
        expect(ku.draftBadgeLabel, isNotEmpty);
      });

      testWidgets('sell-step validation snackbar text (en/ar/ku)', (
        tester,
      ) async {
        final en = await locFor(tester, const Locale('en'));
        expect(
          en.pleaseCompleteAllRequiredFieldsBeforeProceeding,
          'Please complete all required fields before proceeding',
        );
        expect(
          en.pleaseCompleteMissingFields('brand, model'),
          'Please complete: brand, model',
        );

        final ar = await locFor(tester, const Locale('ar'));
        expect(
          ar.pleaseCompleteAllRequiredFieldsBeforeProceeding,
          isNot('Please complete all required fields before proceeding'),
        );
        expect(ar.pleaseCompleteMissingFields('brand, model'), contains('brand, model'));
        expect(
          ar.pleaseCompleteMissingFields('brand, model'),
          isNot('Please complete: brand, model'),
        );

        final ku = await locFor(tester, const Locale('ku'));
        expect(
          ku.pleaseCompleteAllRequiredFieldsBeforeProceeding,
          isNot('Please complete all required fields before proceeding'),
        );
        expect(ku.pleaseCompleteMissingFields('brand, model'), contains('brand, model'));
      });

      testWidgets('"Selling unavailable" dialog copy (en/ar/ku)', (
        tester,
      ) async {
        final en = await locFor(tester, const Locale('en'));
        expect(en.sellingUnavailableTitle, 'Selling unavailable');

        final ar = await locFor(tester, const Locale('ar'));
        expect(ar.sellingUnavailableTitle, isNot('Selling unavailable'));
        expect(ar.sellingUnavailableBody, isNotEmpty);

        final ku = await locFor(tester, const Locale('ku'));
        expect(ku.sellingUnavailableTitle, isNot('Selling unavailable'));
        expect(ku.sellingUnavailableBody, isNotEmpty);
      });
    },
  );
}
