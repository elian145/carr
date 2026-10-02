import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_flow.dart' show HomePage;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/car_spec_index.dart';

import 'fake_api_server.dart';

/// Drives the REAL Search/Filters state (`HomePage.searchFilters()`), loading
/// the real bundled spec catalog exactly as the app does, to prove that the
/// Search lists are model-aware again (same resolver as Sell) and that
/// dependent selections are cleaned per field when the parent vehicle changes
/// or filters are restored.
///
/// The State class is private, so its public members are driven dynamically.
/// All scenarios share ONE pumped page: the state loads the catalog through
/// `rootBundle` (cached per binding), and repeated loads across separate
/// widget tests are not reliable under FakeAsync.
void main() {
  late CarSpecIndex idx;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The page's brand logos use cached_network_image, which asks path_provider
    // for a cache dir; give it a harmless temp dir (no platform plugins here).
    final tmp = Directory.systemTemp.createTempSync('vehicle_filters_test').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
    await FakeApiServer.ensureStarted();
    final raw = File('assets/car_spec_dataset.json').readAsStringSync();
    idx = parseCarSpecDatasetJsonString(raw).index!;
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Widget harness() => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomePage.searchFilters(),
      );

  Set<String> real(dynamic list) =>
      (list as List).cast<String>().where((e) => e != 'Any').toSet();

  /// The state loads the catalog asynchronously (isolate parse). Poll until the
  /// model-aware list appears, which also proves the catalog-load hook fired.
  Future<void> waitForCatalog(WidgetTester tester, dynamic s) async {
    for (var i = 0; i < 240; i++) {
      if (real(s.getAvailableCylinderCounts()).length < 8) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();
    }
    fail('catalog never loaded into the Search filters state');
  }

  testWidgets(
    'Search filters are model-aware via the shared catalog resolver and '
    'dependent selections follow the vehicle',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final s = tester.state(find.byType(HomePage)) as dynamic;

      // ---- C/D. No model: every field shows its full default list. ----
      final defaultCylinders = real(s.getAvailableCylinderCounts());
      final defaultBodies = real(s.getAvailableBodyTypes());
      final defaultFuels = real(s.getAvailableFuelTypes());
      final defaultSeatings = real(s.getAvailableSeatings());
      expect(defaultCylinders, containsAll(<String>['1', '4', '8', '12', '16']));
      expect(defaultBodies, containsAll(<String>['Sedan', 'SUV', 'Minivan']));

      // ---- A/J. Chevrolet -> Camaro narrows every dependent field like Sell. ----
      s.selectedBrand = 'Chevrolet';
      s.selectedModel = 'Camaro';
      await waitForCatalog(tester, s);

      final camaro = idx.homeFilterFieldOptions('Chevrolet', 'Camaro', '')!;
      expect(real(s.getAvailableCylinderCounts()), camaro.cylinderCounts);
      expect(real(s.getAvailableBodyTypes()), camaro.bodyTypes);
      expect(real(s.getAvailableFuelTypes()), camaro.fuelTypes);
      expect(real(s.getAvailableDriveTypes()), camaro.driveTypes);
      expect(real(s.getAvailableTransmissions()), camaro.transmissions);
      expect(real(s.getAvailableSeatings()), camaro.seatings);
      expect(real(s.getAvailableEngineSizes()), camaro.engineSizes);
      expect(real(s.getAvailableCylinderCounts()).length,
          lessThan(defaultCylinders.length),
          reason: 'cylinders regression: no longer the global ladder');
      expect(real(s.getAvailableBodyTypes()).length,
          lessThan(defaultBodies.length));
      expect(real(s.getAvailableFuelTypes()).length,
          lessThan(defaultFuels.length));
      expect(real(s.getAvailableSeatings()).length,
          lessThan(defaultSeatings.length));
      expect(s.getAvailableCylinderCounts(), contains('Any'));

      // Clearing the model returns every field to its default list.
      s.selectedModel = null;
      expect(real(s.getAvailableCylinderCounts()), defaultCylinders);
      expect(real(s.getAvailableBodyTypes()), defaultBodies);

      // ---- D/E. Changing model clears only what the new model rules out. ----
      final camry = idx.homeFilterFieldOptions('Toyota', 'Camry', '')!;
      final onlyCamaroCyl = camaro.cylinderCounts.difference(camry.cylinderCounts);
      final sharedCyl = camaro.cylinderCounts.intersection(camry.cylinderCounts);
      final onlyCamaroDrive = camaro.driveTypes.difference(camry.driveTypes);
      expect(onlyCamaroCyl, isNotEmpty, reason: 'scenario needs a stale cylinder');
      expect(sharedCyl, isNotEmpty, reason: 'scenario needs a compatible cylinder');
      expect(onlyCamaroDrive, isNotEmpty, reason: 'scenario needs a stale drive');

      s.selectedBrand = 'Chevrolet';
      s.selectedModel = 'Camaro';
      s.selectedDriveType = onlyCamaroDrive.first;
      s.selectedFuelType = 'Gasoline';
      s.selectedCylinderCount = onlyCamaroCyl.first;
      s.selectedColor = 'Red'; // not vehicle-dependent: must survive
      expect(s.syncDependentFiltersToVehicle(), isFalse,
          reason: 'everything is valid for Camaro; nothing may be cleared');
      expect(s.selectedCylinderCount, onlyCamaroCyl.first);

      s.selectedBrand = 'Toyota';
      s.selectedModel = 'Camry';
      s.selectedTrim = null;
      expect(s.syncDependentFiltersToVehicle(), isTrue);
      expect(s.selectedCylinderCount, isNull,
          reason: 'Camry has no such cylinder count');
      expect(s.selectedDriveType, isNull, reason: 'drive not offered by Camry');
      expect(s.selectedFuelType, 'Gasoline', reason: 'still valid -> kept');
      expect(s.selectedColor, 'Red', reason: 'unrelated field untouched');

      // E. A cylinder valid for both models survives the change.
      s.selectedBrand = 'Chevrolet';
      s.selectedModel = 'Camaro';
      s.selectedCylinderCount = sharedCyl.first;
      s.selectedBrand = 'Toyota';
      s.selectedModel = 'Camry';
      s.syncDependentFiltersToVehicle();
      expect(s.selectedCylinderCount, sharedCyl.first);

      // ---- G. Restored saved search: keep valid, drop stale. ----
      final camry2023 = idx.homeFilterFieldOptions(
        'Toyota',
        'Camry',
        '',
        rangeMinYear: 2023,
        rangeMaxYear: 2023,
      )!;
      final validCyl = (camry2023.cylinderCounts.toList()..sort()).first;
      s.applyFiltersFromSavedSearch(<String, dynamic>{
        'brand': 'Toyota',
        'model': 'Camry',
        'min_year': '2023',
        'max_year': '2023',
        'transmission': 'Manual', // Camry 2023 is automatic only
        'cylinder_count': validCyl, // valid
        'fuel_type': 'Gasoline', // valid
        'body_type': 'Pickup,Sedan', // Pickup stale, Sedan valid
      });
      expect(s.selectedTransmission, isNull);
      expect(s.selectedCylinderCount, validCyl);
      expect(s.selectedFuelType, 'Gasoline');
      expect(s.selectedBodyType, 'Sedan');

      // ---- G/C. Restoring a vehicle the catalog does not know wipes nothing. ----
      s.applyFiltersFromSavedSearch(<String, dynamic>{
        'brand': 'Chevrolet',
        'model': 'Not In Catalog',
        'cylinder_count': '16',
        'transmission': 'Manual',
      });
      expect(s.selectedCylinderCount, '16');
      expect(s.selectedTransmission, 'Manual');
      expect(real(s.getAvailableCylinderCounts()), contains('16'));

      // Dispose and let cached_network_image's 10 s cleanup timer fire so the
      // framework's pending-timer invariant holds.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
    },
  );
}
