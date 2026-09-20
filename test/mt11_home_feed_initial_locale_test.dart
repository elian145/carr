// Regression tests for the MT-11 device QA finding: on cold app launch
// under Arabic/Kurdish, the Home feed's FIRST paint showed car brand/model
// names in English (e.g. "Ford Explorer") even though the rest of the UI
// (menus, RTL, AppLocalizations strings) was already correctly localized.
// Only after a pull-to-refresh did the same listings show localized names.
//
// Root cause: `CarNameTranslations`'s ar/ku display-name JSON pack loads
// asynchronously. Before this fix, `bootstrap.dart` only awaited
// `LocaleController.loadSavedLocale()` (which loads that pack) in a
// *post*-`runApp` microtask, while the app locale itself (RTL,
// AppLocalizations) was already applied *before* `runApp`. The Home feed's
// first frame could render listing cards -- which localize brand/model at
// *render time* via `CarNameTranslations.getLocalizedBrand`/`getLocalizedModel`
// (see `global_listing_card.dart`'s `localizedCarTitleForCard`, called from
// the exact same `buildGlobalCarCard` the Home feed uses,
// `lib/features/home/home_slivers.dart`) -- before that pack finished
// loading. Nothing rebuilds the feed when the pack later arrives (no
// `Listenable`/`ChangeNotifier` on `CarNameTranslations`), so the stale
// English text stuck around until an unrelated `setState` (like
// pull-to-refresh) happened to fire afterward.
//
// Fix: `bootstrap.dart` now also awaits
// `CarNameTranslations.ensureLoadedForLocale(LocaleController.resolveCode())`
// *before* `runApp`, mirroring the existing (already correct) pre-`runApp`
// locale-prefs read. This test file proves both halves: (1) that ordering
// itself loads the pack synchronously relative to first paint, and (2) that
// once the pack is ready, the *existing* render-time helper (unchanged)
// already produces correct en/ar/ku output on the very first pump with no
// extra rebuild, refresh, or re-fetch -- and that the exact same helper
// keeps working identically for a "refreshed" listing map and for a live
// locale switch on already-loaded data (no backend re-fetch required).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/widgets/global_listing_card.dart';
import 'package:car_listing_app/data/car_name_translations.dart';
import 'package:car_listing_app/features/comparison/state/car_comparison_store.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/shared/i18n/ku_delegates.dart';
import 'package:car_listing_app/state/locale_controller.dart';

/// A known catalog vehicle matching the bug report's example family
/// ("Ford Explorer" shown in English under Kurdish on first launch). Unlike
/// "F-150" (kept verbatim everywhere as a code-like alphanumeric trim/model
/// -- see `CarNameTranslations._isCodeLike`), "Explorer" is a real word the
/// catalog pack translates, so it exercises the actual brand+model lookup
/// path this bug affects.
Map<String, dynamic> _carData() => <String, dynamic>{
  'id': 'mt11-1',
  'brand': 'Ford',
  'model': 'Explorer',
  'trim': 'XLT',
  'year': '2022',
};

void _installTestCatalogPacks() {
  CarNameTranslations.debugInstallPack(
    'ar',
    brands: const {'ford': 'فورد'},
    models: const {'ford|explorer': 'إكسبلورر'},
  );
  CarNameTranslations.debugInstallPack(
    'ku',
    brands: const {'ford': 'فۆرد'},
    models: const {'ford|explorer': 'ئێکسپلۆرەر'},
  );
}

/// Renders the exact same card-building function the real Home feed grid
/// uses (`lib/features/home/home_slivers.dart` calls `buildGlobalCarCard`
/// directly on raw listing maps), so this exercises the real render path --
/// not just `CarNameTranslations` in isolation.
Widget _homeFeedCardHarness(Locale locale, Map<String, dynamic> car) {
  // `buildGlobalCarCard` now also renders a compact "Add to Compare" toggle
  // (CarNet V1 batch, item 8) that reads `CarComparisonStore` via
  // `provider` -- same as every real page, which wires it app-wide in
  // `lib/app/providers.dart`. Mirror that here so this harness matches the
  // real render path it claims to exercise.
  return ChangeNotifierProvider<CarComparisonStore>(
    create: (_) => CarComparisonStore(),
    child: MaterialApp(
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
      home: Scaffold(
        body: Builder(
          builder: (context) => SizedBox(
            width: 340,
            height: 420,
            child: buildGlobalCarCard(context, car),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalLocale = LocaleController.currentLocale.value;

  tearDown(() {
    CarNameTranslations.debugResetForTest();
    LocaleController.currentLocale.value = originalLocale;
  });

  group('MT-11: bootstrap pre-runApp locale/pack loading order', () {
    test(
      'CarNameTranslations pack for the resolved locale is loaded '
      'synchronously by the same pre-runApp sequence bootstrap.dart now '
      'runs, before any widget can build',
      () async {
        SharedPreferences.setMockInitialValues({'app_locale': 'ku'});
        final sp = await SharedPreferences.getInstance();

        // Mirrors bootstrap.dart's pre-`runApp` block exactly.
        LocaleController.applyFromPrefs(sp);
        expect(LocaleController.resolveCode(), 'ku');
        // Not loaded yet -- this is the pre-fix state at this point.
        expect(CarNameTranslations.debugHasPack('ku'), isFalse);

        await CarNameTranslations.ensureLoadedForLocale(
          LocaleController.resolveCode(),
        ).timeout(const Duration(seconds: 15));

        // Loaded and ready *before* `runApp`/first paint would happen.
        expect(CarNameTranslations.debugHasPack('ku'), isTrue);
        expect(
          CarNameTranslations.getLocalizedBrandForLocale('ku', 'Ford'),
          isNot('Ford'),
        );
      },
    );

    test(
      'resolves to en (no-op pack load) when no locale is persisted',
      () async {
        SharedPreferences.setMockInitialValues({});
        final sp = await SharedPreferences.getInstance();
        LocaleController.applyFromPrefs(sp);
        // With no persisted `app_locale` and no supported device locale in
        // the test harness, resolveCode() falls back to 'en'.
        await CarNameTranslations.ensureLoadedForLocale(
          LocaleController.resolveCode(),
        );
        expect(CarNameTranslations.debugHasPack('ar'), isFalse);
        expect(CarNameTranslations.debugHasPack('ku'), isFalse);
      },
    );
  });

  group(
    'MT-11: initial/cached Home feed card renders localized names on the '
    'very first pump (no refresh needed)',
    () {
      testWidgets('Locale(en): first paint keeps English brand/model', (
        tester,
      ) async {
        _installTestCatalogPacks();
        await tester.pumpWidget(_homeFeedCardHarness(const Locale('en'), _carData()));
        // Single pump: proves no extra frame/refresh is required.
        await tester.pump();

        expect(find.textContaining('Ford Explorer'), findsOneWidget);
      });

      testWidgets(
        'Locale(ar): first paint shows the catalog Arabic brand/model '
        'immediately (pack already loaded, simulating the bootstrap fix)',
        (tester) async {
          _installTestCatalogPacks();
          await tester.pumpWidget(
            _homeFeedCardHarness(const Locale('ar'), _carData()),
          );
          await tester.pump();

          expect(find.textContaining('فورد إكسبلورر'), findsOneWidget);
          expect(find.textContaining('Ford Explorer'), findsNothing);
        },
      );

      testWidgets(
        'Locale(ku): first paint shows the catalog Kurdish brand/model '
        'immediately (pack already loaded, simulating the bootstrap fix)',
        (tester) async {
          _installTestCatalogPacks();
          await tester.pumpWidget(
            _homeFeedCardHarness(const Locale('ku'), _carData()),
          );
          await tester.pump();

          expect(find.textContaining('فۆرد ئێکسپلۆرەر'), findsOneWidget);
          expect(find.textContaining('Ford Explorer'), findsNothing);
        },
      );
    },
  );

  group(
    'MT-11: documents the pre-fix race (pack not yet loaded at first '
    'paint never self-corrects without a rebuild trigger)',
    () {
      testWidgets(
        'Locale(ar): if the pack is still loading when the card first '
        'renders, it stays English even after the pack finishes -- unless '
        'something rebuilds the card (proves pre-loading before first '
        'paint, not "wait and hope", is the correct fix)',
        (tester) async {
          // No debugInstallPack('ar', ...) call yet -- pack not ready.
          final car = _carData();
          await tester.pumpWidget(_homeFeedCardHarness(const Locale('ar'), car));
          await tester.pump();
          expect(find.textContaining('Ford Explorer'), findsOneWidget);

          // Pack "finishes loading" a moment later (as it would in the old
          // post-runApp microtask) -- but nothing marks the card dirty.
          _installTestCatalogPacks();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Still stale/English: this is exactly the bug users saw.
          expect(find.textContaining('Ford Explorer'), findsOneWidget);
          expect(find.textContaining('فورد إكسبلورر'), findsNothing);
        },
      );
    },
  );

  group(
    'MT-11: refresh path produces the same localized result as the '
    'initial path',
    () {
      testWidgets(
        'a freshly-constructed "refreshed" listing map (as if just '
        're-parsed from a new network response) localizes identically to '
        'the original "initial" map for the same locale',
        (tester) async {
          _installTestCatalogPacks();

          // "Initial" map (as if from cache/first fetch).
          final initialCar = _carData();
          await tester.pumpWidget(
            _homeFeedCardHarness(const Locale('ku'), initialCar),
          );
          await tester.pump();
          expect(find.textContaining('فۆرد ئێکسپلۆرەر'), findsOneWidget);

          // "Refreshed" map: a brand-new Map instance with the same
          // canonical brand/model, exactly as `refreshHomeFeed()` ->
          // `fetchCars(bypassCache: true)` -> `listingMapsFromApiResponse`
          // would construct from a fresh network response.
          final refreshedCar = Map<String, dynamic>.from(_carData());
          await tester.pumpWidget(
            _homeFeedCardHarness(const Locale('ku'), refreshedCar),
          );
          await tester.pump();

          expect(find.textContaining('فۆرد ئێکسپلۆرەر'), findsOneWidget);
          expect(find.textContaining('Ford Explorer'), findsNothing);
        },
      );
    },
  );

  group(
    'MT-11: live locale switch on already-loaded listing data updates '
    'names without re-fetching',
    () {
      testWidgets(
        'the same listing Map instance re-renders with the new locale\'s '
        'catalog display name when the app locale changes, with no new '
        'network fetch/model reconstruction',
        (tester) async {
          _installTestCatalogPacks();
          // One Map instance, reused (not refetched) across both pumps --
          // matches `production_app.dart`'s `ValueListenableBuilder` on
          // `LocaleController.currentLocale` rebuilding `MaterialApp` (and
          // everything under it) when the locale changes.
          final car = _carData();

          await tester.pumpWidget(_homeFeedCardHarness(const Locale('en'), car));
          await tester.pump();
          expect(find.textContaining('Ford Explorer'), findsOneWidget);

          await tester.pumpWidget(_homeFeedCardHarness(const Locale('ar'), car));
          await tester.pump();
          expect(find.textContaining('فورد إكسبلورر'), findsOneWidget);
          expect(find.textContaining('Ford Explorer'), findsNothing);
        },
      );
    },
  );

  group('MT-11: unknown catalog names still fall back safely', () {
    testWidgets(
      'a brand/model with no installed translation renders the original '
      'English text under ar, instead of crashing or showing empty text',
      (tester) async {
        // No debugInstallPack call at all -- simulates an unrecognized
        // catalog entry.
        final car = _carData();
        await tester.pumpWidget(_homeFeedCardHarness(const Locale('ar'), car));
        await tester.pump();

        expect(find.textContaining('Ford Explorer'), findsOneWidget);
      },
    );
  });
}
