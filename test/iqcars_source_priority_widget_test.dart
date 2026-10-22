import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/data/car_catalog_loader.dart';
import 'package:car_listing_app/data/car_name_translations.dart';
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/feature_flags.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';
import 'package:car_listing_app/shared/ui/filter_make_section.dart';
import 'package:car_listing_app/shared/i18n/ku_delegates.dart';
import 'package:car_listing_app/shared/listings/listing_to_sell_draft.dart';

import 'cached_image_store_test_support.dart';
import 'fake_api_server.dart';

/// Drives the REAL Sell wizard (`SellCarPage`, which Edit Listing also uses) with
/// the real bundled catalog, spec dataset, IQ overlay and IQ provenance, in
/// English, Arabic and Kurdish: IQ Cars options are listed above CarNet-only
/// options, every option stays available, and a saved CarNet-only value is still
/// a regular (non-manual) selection.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('iq_prio_test').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
    primeCachedImageStoreForTests();
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FeatureFlags.setCachedForTests(FeatureFlagsSnapshot.defaults());
  });

  tearDown(() {
    FeatureFlags.resetCacheForTests();
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalogLoader.debugResetForTest();
    IqCarsOverlay.debugResetForTest();
    CarNameTranslations.debugResetForTest();
    // Each widget test runs in its own FakeAsync zone; the bundle's cached
    // string futures from the previous test must not leak into the next one.
    rootBundle.evict(CarSpecIndex.assetPath);
    rootBundle.evict(IqCarsOverlay.assetPath);
    rootBundle.evict(IqCarsOverlay.provenanceAssetPath);
    rootBundle.evict('assets/car_catalog.json');
  });

  Future<void> preloadOverlay(WidgetTester tester) async {
    await tester.runAsync(() => IqCarsOverlay.ensureLoaded());
  }

  Widget app(String locale, Map<String, dynamic> snapshot) => MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          KuMaterialLocalizationsDelegate(),
          KuWidgetsLocalizationsDelegate(),
          KuCupertinoLocalizationsDelegate(),
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SellCarPage(initialDraftSnapshot: snapshot),
      );

  Map<String, dynamic> newListingDraft({
    required int step,
    required String brand,
    required String model,
    required String trim,
    bool applied = true,
  }) =>
      <String, dynamic>{
        'draftId': 'iq-priority-test',
        'currentStep': step,
        'updatedAt': 1700000000000,
        'carData': <String, dynamic>{
          'brand': brand,
          'model': model,
          'trim': trim,
          'year': '2020',
          if (applied) '_catalog_specs_applied': 1,
        },
      };

  /// What Edit Listing opens: the snapshot built from the saved listing.
  Map<String, dynamic> editDraft({required int step, required String trim}) {
    final snap = listingToSellDraftSnapshot(<String, dynamic>{
      'id': 4242,
      'brand': 'Ford',
      'model': 'Everest',
      'trim': trim,
      'year': 2020,
      'engine_size': 2.0,
      'cylinder_count': 4,
    });
    snap['currentStep'] = step;
    (snap['carData'] as Map<String, dynamic>)['_catalog_specs_applied'] = 1;
    return snap;
  }

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() ready,
    String what,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
  }

  /// The page state, once the (possibly asynchronously loaded) localization
  /// delegates of the locale under test have let the page build.
  Future<dynamic> stateOf(WidgetTester tester, Type page) async {
    await waitFor(
      tester,
      () => find.byType(page).evaluate().isNotEmpty,
      '$page to build',
    );
    return tester.state(find.byType(page));
  }

  const everestTrims = [
    'Limited', 'XLT', 'XLS', 'Titanium', 'Trend', 'Ambiente', // IQ Cars
    'Mid Range', 'Other', // CarNet only, then the Other placeholder
  ];
  const everestEngines = [
    'Any',
    '2.0 TD', '2.2 TD', '2.3 T', '2.5', '2.7 T', '3.0 TD', '3.2 TD', // IQ Cars
    '2.0 D', '3.2 D', // CarNet only
  ];

  for (final locale in const ['en', 'ar', 'ku']) {
    group('[$locale]', () {
      testWidgets('Sell step 1: IQ trims above CarNet-only trims, all options kept',
          (tester) async {
        await preloadOverlay(tester);
        await tester.pumpWidget(app(
          locale,
          newListingDraft(step: 0, brand: 'Ford', model: 'Everest', trim: 'XLT'),
        ));
        await tester.pump();
        final s = await stateOf(tester, SellStep1Page);
        await waitFor(
          tester,
          () => (s.availableTrims as List).contains('Titanium'),
          'Everest trims to include the IQ trims',
        );
        expect((s.availableTrims as List).cast<String>(), everestTrims);
        // brands / models the picker offers are the catalog's, none missing
        expect((s.brands as List).cast<String>(), CarCatalog.brands);
        expect((s.models as Map)['Ford'], CarCatalog.models['Ford']);
        expect(CarCatalog.baselineTrimsFor('Ford', 'Everest').toSet().difference(
              (s.availableTrims as List).cast<String>().toSet(),
            ),
            isEmpty,
            reason: 'every CarNet trim is still offered');
        // the picked value is the canonical one, and it is one of the offered trims
        expect(s.selectedTrim, 'XLT');
        expect((s.availableTrims as List), contains(s.selectedTrim));
        await _unmount(tester);
      });

      testWidgets('Sell step 2: IQ engines above CarNet-only, cylinders unchanged',
          (tester) async {
        await preloadOverlay(tester);
        await tester.pumpWidget(app(
          locale,
          newListingDraft(step: 1, brand: 'Ford', model: 'Everest', trim: 'XLT'),
        ));
        await tester.pump();
        final s = await stateOf(tester, SellStep2Page);
        await waitFor(
          tester,
          () => !(s.getAvailableEngineSizes() as List).contains('0.5'),
          'step 2 to narrow its engine sizes to the catalog',
        );
        expect((s.getAvailableEngineSizes() as List).cast<String>(), everestEngines);
        expect((s.getAvailableCylinderCounts() as List).cast<String>(), ['4', '5', '6']);
        await _unmount(tester);
      });

      testWidgets('Edit Listing: a saved CarNet-only trim stays selectable',
          (tester) async {
        await preloadOverlay(tester);
        await tester.pumpWidget(app(locale, editDraft(step: 0, trim: 'Mid Range')));
        await tester.pump();
        final s = await stateOf(tester, SellStep1Page);
        await waitFor(
          tester,
          () => (s.availableTrims as List).contains('Titanium'),
          'Everest trims to include the IQ trims',
        );
        expect((s.availableTrims as List).cast<String>(), everestTrims);
        expect(s.selectedTrim, 'Mid Range');
        expect((s.availableTrims as List), contains(s.selectedTrim),
            reason: 'the saved CarNet-only trim is still in the list');
        await _unmount(tester);
      });

      testWidgets('Edit Listing: a saved IQ trim stays selectable',
          (tester) async {
        await preloadOverlay(tester);
        await tester.pumpWidget(app(locale, editDraft(step: 0, trim: 'Titanium')));
        await tester.pump();
        final s = await stateOf(tester, SellStep1Page);
        await waitFor(
          tester,
          () => (s.availableTrims as List).contains('Titanium'),
          'Everest trims to include the IQ trims',
        );
        expect(s.selectedTrim, 'Titanium');
        expect((s.availableTrims as List), contains(s.selectedTrim));
        await _unmount(tester);
      });

      testWidgets('Edit Listing step 2: the saved engine and cylinders stay selectable',
          (tester) async {
        await preloadOverlay(tester);
        await tester.pumpWidget(app(locale, editDraft(step: 1, trim: 'XLT')));
        await tester.pump();
        final s = await stateOf(tester, SellStep2Page);
        await waitFor(
          tester,
          () => !(s.getAvailableEngineSizes() as List).contains('0.5'),
          'step 2 to narrow its engine sizes to the catalog',
        );
        final engines = (s.getAvailableEngineSizes() as List).cast<String>();
        expect(engines, everestEngines);
        final cyls = (s.getAvailableCylinderCounts() as List).cast<String>();
        expect(cyls, contains('4'));
        await _unmount(tester);
      });
    });
  }

  testWidgets('switching brand and model leaves no stale trim, model or option list',
      (tester) async {
    await preloadOverlay(tester);
    await tester.pumpWidget(app(
      'en',
      newListingDraft(step: 0, brand: 'Ford', model: 'Everest', trim: 'XLT'),
    ));
    await tester.pump();
    final s = await stateOf(tester, SellStep1Page);
    await waitFor(
      tester,
      () => (s.availableTrims as List).contains('Titanium'),
      'Everest trims to include the IQ trims',
    );
    FilterMakeSection section() =>
        tester.widget<FilterMakeSection>(find.byType(FilterMakeSection));
    Map<String, dynamic> carData() =>
        (tester.state(find.byType(SellCarPage)) as dynamic).carData
            as Map<String, dynamic>;
    List<String> trims() => (s.availableTrims as List).cast<String>();

    // Ford Everest "XLT" -> Toyota: model and trim are cleared, no Ford trims left.
    section().onBrandSelected('Toyota');
    await tester.pump();
    expect(s.selectedBrand, 'Toyota');
    expect(s.selectedModel, isNull);
    expect(s.selectedTrim, isNull);
    expect(trims(), ['Base']);
    expect(carData()['model'], isNull);
    expect(carData()['trim'], isNull);
    expect(section().models['Toyota'], CarCatalog.models['Toyota']);

    // Corolla: its own IQ-first trims; picking an IQ-only trim stores it as is.
    section().onModelSelected!('Corolla');
    await tester.pump();
    expect(trims(), CarCatalog.trimsFor('Toyota', 'Corolla'));
    expect(s.selectedTrim, isNull);
    section().onTrimSelected!('Limited');
    await tester.pump();
    expect(carData()['brand'], 'Toyota');
    expect(carData()['model'], 'Corolla');
    expect(carData()['trim'], 'Limited');

    // Corolla Cross: the Corolla trim is dropped and no Corolla-only trim leaks in.
    section().onModelSelected!('Corolla Cross');
    await tester.pump();
    expect(s.selectedTrim, isNull);
    expect(carData()['trim'], isNull);
    expect(trims(), CarCatalog.trimsFor('Toyota', 'Corolla Cross'));
    expect(trims(), isNot(contains('Limited')));
    expect(trims(), isNot(contains('GR Corolla')));
    section().onTrimSelected!('Hybrid'); // CarNet-only trim stays selectable
    await tester.pump();
    expect(carData()['model'], 'Corolla Cross');
    expect(carData()['trim'], 'Hybrid');

    // Back to Ford Everest: the Toyota choices are gone, the CarNet-only trim works.
    section().onBrandSelected('Ford');
    await tester.pump();
    expect(trims(), ['Base']);
    expect(carData()['model'], isNull);
    section().onModelSelected!('Everest');
    await tester.pump();
    expect(trims(), everestTrims);
    section().onTrimSelected!('Mid Range');
    await tester.pump();
    expect(carData()['brand'], 'Ford');
    expect(carData()['model'], 'Everest');
    expect(carData()['trim'], 'Mid Range');
    await _unmount(tester);
  });

  testWidgets('a saved draft with CarNet-ordered option lists is shown IQ-first, losslessly',
      (tester) async {
    await preloadOverlay(tester);
    final draft = newListingDraft(step: 1, brand: 'Ford', model: 'Everest', trim: 'XLT');
    final car = draft['carData'] as Map<String, dynamic>;
    // lists as an older build stored them (litres order, no source priority)
    car['_online_opts_engine_size'] = [
      '2.0 D', '2.0 TD', '2.2 TD', '2.3 T', '2.5', '2.7 T', '3.0 TD', '3.2 D', '3.2 TD', //
    ];
    car['_online_opts_cylinder'] = ['4', '5', '6'];
    await tester.pumpWidget(app('en', draft));
    await tester.pump();
    final s = await stateOf(tester, SellStep2Page);
    await waitFor(
      tester,
      () => (s.getAvailableEngineSizes() as List).cast<String>().join('|') ==
          everestEngines.join('|'),
      'the saved engine list to be reordered by the live IQ provenance',
    );
    final engines = (s.getAvailableEngineSizes() as List).cast<String>();
    expect(engines.toSet(), {...car['_online_opts_engine_size'] as List, 'Any'});
    expect((s.getAvailableCylinderCounts() as List).cast<String>(), ['4', '5', '6']);
    await _unmount(tester);
  });

  testWidgets('Land Cruiser / Corolla Cross step 1 lists IQ trims first', (tester) async {
    await preloadOverlay(tester);
    for (final c in const [
      ('Toyota', 'Land Cruiser', 'GX'),
      ('Toyota', 'Corolla Cross', 'LE'),
    ]) {
      await tester.pumpWidget(app(
        'en',
        newListingDraft(step: 0, brand: c.$1, model: c.$2, trim: c.$3),
      ));
      await tester.pump();
      final s = await stateOf(tester, SellStep1Page);
      await waitFor(
        tester,
        // the catalog AND the IQ overlay / provenance have been applied
        () =>
            (s.availableTrims as List).length > 5 &&
            CarCatalog.isIqTrim(c.$1, c.$2, (s.availableTrims as List).first as String),
        '${c.$2} trims with IQ Cars first',
      );
      final trims = (s.availableTrims as List).cast<String>();
      expect(trims, CarCatalog.trimsFor(c.$1, c.$2));
      final firstNonIq = trims.indexWhere((t) => !CarCatalog.isIqTrim(c.$1, c.$2, t));
      expect(firstNonIq, greaterThan(0), reason: c.$2);
      expect(
        trims.skip(firstNonIq).where((t) => t != 'Other').any(
              (t) => CarCatalog.isIqTrim(c.$1, c.$2, t),
            ),
        isFalse,
        reason: '${c.$2}: no IQ trim below a CarNet-only trim',
      );
      await _unmount(tester);
    }
  });
}

/// Same teardown as the Search widget tests: unmount, then let the logo cache
/// manager's cleanup timer fire so the pending-timer invariant holds.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 15));
}
