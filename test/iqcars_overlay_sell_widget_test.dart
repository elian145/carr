import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/data/car_catalog_loader.dart';
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/feature_flags.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

import 'cached_image_store_test_support.dart';
import 'fake_api_server.dart';

/// Drives the REAL Sell wizard (`SellCarPage`) with the real bundled catalog,
/// spec dataset and IQ Cars overlay: the trim picker list (step 1) and the
/// engine-size / cylinder pickers (step 2) must show existing options PLUS the
/// approved additions, with no other Sell behaviour touched.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('iq_sell_test').path;
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
    // Each widget test runs in its own FakeAsync zone; the bundle's cached
    // string futures from the previous test must not leak into the next one.
    rootBundle.evict(CarSpecIndex.assetPath);
    rootBundle.evict(IqCarsOverlay.assetPath);
    rootBundle.evict('assets/car_catalog.json');
  });

  /// The app starts the overlay load at launch (real zone). `flutter test`
  /// pumps widgets in a FakeAsync zone where the asset bundle's isolate decode
  /// cannot complete on its own, so do the one-time load in the real zone.
  Future<void> preloadOverlay(WidgetTester tester) async {
    await tester.runAsync(() => IqCarsOverlay.ensureLoaded());
  }

  Widget app(
    int step, {
    String brand = 'Ford',
    String model = 'Everest',
    String trim = 'XLT',
    bool applied = true,
  }) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SellCarPage(
          initialDraftSnapshot: <String, dynamic>{
            'draftId': 'iq-overlay-test',
            'currentStep': step,
            'updatedAt': 1700000000000,
            'carData': <String, dynamic>{
              'brand': brand,
              'model': model,
              'trim': trim,
              'year': '2020',
              // Same switch the "Apply specs" action flips: step 2 narrows its
              // pickers to the catalog for this vehicle.
              if (applied) '_catalog_specs_applied': 1,
            },
          },
        ),
      );

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() ready,
    String what,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) {
        final pageState = tester.state(find.byType(SellCarPage)) as dynamic;
        fail('timed out waiting for $what (carData=${pageState.carData}, '
            'engines=${(tester.state(find.byType(SellStep2Page)) as dynamic).getAvailableEngineSizes()}, '
            'overlay loadCount='
            '${IqCarsOverlay.loadCount}, models=${IqCarsOverlay.current.modelCount}, '
            'catalogTrims=${CarCatalog.trimsFor("Ford", "Everest")})');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
  }

  testWidgets(
    'Sell step 2 lists the catalog engine sizes plus the approved IQ sizes, '
    'cylinders and everything else unchanged',
    (tester) async {
      await preloadOverlay(tester);
      await tester.pumpWidget(app(1));
      await tester.pump();
      final s = tester.state(find.byType(SellStep2Page)) as dynamic;

      await waitFor(
        tester,
        // Until the spec catalog arrives step 2 shows the full default ladder.
        () => !(s.getAvailableEngineSizes() as List).contains('0.5'),
        'step 2 to narrow its engine sizes to the catalog',
      );
      final engines = (s.getAvailableEngineSizes() as List).cast<String>();
      // existing catalog sizes survive, the approved IQ sizes are added, ascending
      expect(engines.first, 'Any');
      expect(
        engines,
        // 2.0 D / 3.2 D are the catalog's own 2020 Everest sizes (kept); the
        // plain 2.2 / 2.3 / 2.5 / 2.7 are the approved IQ displacements.
        ['Any', '2.0 D', '2.0 TD', '2.2 TD', '2.3 T', '2.5', '2.7 T', '3.0 TD', '3.2 D', '3.2 TD'],
      );
      // Cylinders: CarNet's 2020 Everest [4, 5] UNION the full approved IQ set [4, 5, 6].
      expect(
        (s.getAvailableCylinderCounts() as List).cast<String>(),
        ['4', '5', '6'],
      );
      await _unmount(tester);
    },
  );

  testWidgets(
    'Sell step 2, model with NO legacy spec coverage (Alfa Romeo Mito): the '
    'approved IQ engines / cylinders now narrow the pickers',
    (tester) async {
      await preloadOverlay(tester);
      await tester.pumpWidget(
        app(1, brand: 'Alfa Romeo', model: 'Mito', trim: '', applied: false),
      );
      await tester.pump();
      final s = tester.state(find.byType(SellStep2Page)) as dynamic;
      await waitFor(
        tester,
        () => !(s.getAvailableEngineSizes() as List).contains('0.5'),
        'step 2 to narrow engine sizes to the IQ values',
      );
      expect(
        (s.getAvailableEngineSizes() as List).cast<String>(),
        ['Any', '1.3 D', '1.4', '1.4 T'],
      );
      expect(
        (s.getAvailableCylinderCounts() as List).cast<String>(),
        ['4'],
      );
      // Fields IQ says nothing about keep the full static sets.
      expect((s.getAvailableFuelTypes() as List).length, greaterThan(2));
      await _unmount(tester);
    },
  );

  testWidgets(
    'Sell step 2, approved IQ cylinders outside the generic 3-12 range '
    '(Bugatti Chiron = 16, Polaris RZR = 2) are offered exactly',
    (tester) async {
      for (final c in const [
        ('Bugatti', 'Chiron', '16'),
        ('Polaris', 'RZR', '2'),
      ]) {
        await preloadOverlay(tester);
        await tester.pumpWidget(
          app(1, brand: c.$1, model: c.$2, trim: '', applied: false),
        );
        await tester.pump();
        final s = tester.state(find.byType(SellStep2Page)) as dynamic;
        await waitFor(
          tester,
          () => (s.getAvailableCylinderCounts() as List).length == 1,
          'step 2 to offer the approved IQ cylinder count for ${c.$2}',
        );
        expect(
          (s.getAvailableCylinderCounts() as List).cast<String>(),
          [c.$3],
        );
        // not the generic ladder, which stays 3-12
        expect((s.getAvailableCylinderCounts() as List).contains('12'), isFalse);
        await _unmount(tester);
      }
    },
  );

  testWidgets(
    'Sell step 2, no legacy coverage and no IQ engines / cylinders: the '
    'existing full default pickers are unchanged',
    (tester) async {
      await preloadOverlay(tester);
      await tester.pumpWidget(
        app(1, brand: 'Not A Brand', model: 'Nope', trim: '', applied: false),
      );
      await tester.pump();
      final s = tester.state(find.byType(SellStep2Page)) as dynamic;
      // Give the spec index time to load; nothing may narrow.
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect((s.getAvailableEngineSizes() as List).contains('0.5'), isTrue);
      expect(
        (s.getAvailableCylinderCounts() as List).cast<String>(),
        ['3', '4', '5', '6', '8', '10', '12'],
      );
      await _unmount(tester);
    },
  );

  testWidgets(
    'Sell step 1 trim picker: existing Everest trims first, approved IQ trims added',
    (tester) async {
      await preloadOverlay(tester);
      await tester.pumpWidget(app(0));
      await tester.pump();
      final s = tester.state(find.byType(SellStep1Page)) as dynamic;

      await waitFor(
        tester,
        () => (s.availableTrims as List).contains('Titanium'),
        'Everest trims to include the approved IQ trims',
      );
      expect(
        (s.availableTrims as List).cast<String>(),
        [
          'Limited', 'XLT', 'Mid Range', 'XLS', //
          'Titanium', 'Trend', 'Ambiente', 'Other',
        ],
      );
      await _unmount(tester);
    },
  );
}

/// Same teardown as the Search widget tests: unmount, then let the logo cache
/// manager's cleanup timer fire so the pending-timer invariant holds.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 15));
}
