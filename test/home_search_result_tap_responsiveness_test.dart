import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:car_listing_app/features/home/home_flow.dart' show HomePage;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/services/car_spec_index.dart';

import 'cached_image_store_test_support.dart';
import 'fake_api_server.dart';

/// Responsiveness contract for the Search page's make/model autocomplete:
///
///   tap "Camaro" -> selection registers + suggestions close on THAT frame
///                -> catalog resolution / dependent cleanup / persistence
///                   happen afterwards and never gate the visible response.
///
/// Drives the real Search state (`HomePage.searchFilters()`) and taps the real
/// suggestion `ListTile`. The spec catalog future is a test-controlled
/// completer ([CarSpecIndexBase.debugLoadWithResultOverride]) so "slow catalog"
/// is deterministic instead of timing based.
void main() {
  late CarSpecIndexLoadResult loaded;
  late CatalogSellFieldOptions camaro;
  Completer<CarSpecIndexLoadResult>? pendingCatalog;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('result_tap_test').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
    primeCachedImageStoreForTests();
    await FakeApiServer.ensureStarted();
    final raw = File('assets/car_spec_dataset.json').readAsStringSync();
    loaded = parseCarSpecDatasetJsonString(raw);
    camaro = loaded.index!.homeFilterFieldOptions('Chevrolet', 'Camaro', '')!;
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    CarSpecIndexBase.debugLoadWithResultOverride = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
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

  Finder camaroSuggestion() => find.widgetWithText(ListTile, 'Camaro');

  Future<dynamic> openSearchAndTypeCamaro(WidgetTester tester) async {
    // Created inside the test body so the completion callbacks run in the
    // test's FakeAsync zone (a pump flushes them).
    final completer = pendingCatalog = Completer<CarSpecIndexLoadResult>();
    CarSpecIndexBase.debugLoadWithResultOverride = () => completer.future;
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final s = tester.state(find.byType(HomePage)) as dynamic;
    await tester.enterText(find.byType(TextField).first, 'Camaro');
    await tester.pump();
    expect(camaroSuggestion(), findsOneWidget,
        reason: 'Camaro must be offered as a suggestion');
    return s;
  }

  Future<void> completeCatalog(WidgetTester tester) async {
    pendingCatalog!.complete(loaded);
    // The state's `.then` runs as a microtask; a pump flushes it and rebuilds.
    await tester.pump();
    await tester.pump();
  }

  Future<void> disposePage(WidgetTester tester) async {
    // Let cached_network_image's 10 s cleanup timer fire so the framework's
    // pending-timer invariant holds.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
  }

  testWidgets(
    'tapping Camaro selects it and closes suggestions on the tap frame while '
    'the spec catalog future is still pending, UI stays interactive, and the '
    'model-aware options arrive when it completes',
    (tester) async {
      final s = await openSearchAndTypeCamaro(tester);
      final defaultCylinders = real(s.getAvailableCylinderCounts());
      expect(pendingCatalog!.isCompleted, isFalse);

      await tester.tap(camaroSuggestion());
      await tester.pump(); // exactly ONE frame, no settling, no catalog.

      // Selection is visible immediately ...
      expect(s.selectedBrand, 'Chevrolet');
      expect(s.selectedModel, 'Camaro');
      expect(s.selectedTrim, isNull);
      expect(find.text('Camaro'), findsWidgets,
          reason: 'the Model section now shows the picked model');
      // ... and the suggestion list is dismissed.
      expect(camaroSuggestion(), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isFalse);

      // The catalog has NOT answered yet; nothing waited on it and no stale
      // vehicle options are invented: defaults stay in force.
      expect(pendingCatalog!.isCompleted, isFalse);
      expect(real(s.getAvailableCylinderCounts()), defaultCylinders);

      // The UI is interactable while the catalog is still pending.
      await tester.enterText(find.byType(TextField).first, 'Cam');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Camaro'), findsOneWidget,
          reason: 'search box accepts input and shows suggestions again');
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();

      // Catalog finally arrives: dependent options become model-aware.
      await completeCatalog(tester);
      expect(real(s.getAvailableCylinderCounts()), camaro.cylinderCounts);
      expect(real(s.getAvailableBodyTypes()), camaro.bodyTypes);
      expect(real(s.getAvailableFuelTypes()), camaro.fuelTypes);
      expect(real(s.getAvailableDriveTypes()), camaro.driveTypes);
      expect(real(s.getAvailableTransmissions()), camaro.transmissions);
      expect(real(s.getAvailableSeatings()), camaro.seatings);
      expect(real(s.getAvailableEngineSizes()), camaro.engineSizes);
      expect(real(s.getAvailableCylinderCounts()).length,
          lessThan(defaultCylinders.length));

      await disposePage(tester);
    },
  );

  testWidgets(
    'catalog already loaded: the tap handler runs no catalog scan; the '
    'resolution is deferred to right after the tap frame',
    (tester) async {
      final s = await openSearchAndTypeCamaro(tester);
      await completeCatalog(tester);
      final defaultCylinders = {'1', '2', '3', '4', '5', '6', '8', '10', '12', '16'};
      expect(real(s.getAvailableCylinderCounts()), defaultCylinders,
          reason: 'no model selected yet -> defaults');

      await tester.tap(camaroSuggestion());
      // The handler has run (selection state set) but no frame has been
      // pumped: the catalog scan must not have happened inside the handler.
      expect(s.selectedModel, 'Camaro');
      expect(real(s.getAvailableCylinderCounts()), defaultCylinders,
          reason: 'handler must not resolve catalog options synchronously');

      await tester.pump(); // tap frame + post-frame resolution
      expect(camaroSuggestion(), findsNothing);
      expect(real(s.getAvailableCylinderCounts()), camaro.cylinderCounts,
          reason: 'resolved right after the tap frame');
      await tester.pump();
      expect(real(s.getAvailableBodyTypes()), camaro.bodyTypes);

      await disposePage(tester);
    },
  );

  testWidgets(
    'incompatible dependent filters are sanitized when resolution completes, '
    'compatible ones and color survive',
    (tester) async {
      final s = await openSearchAndTypeCamaro(tester);

      final defaultCyl = {'1', '2', '3', '4', '5', '6', '8', '10', '12', '16'};
      final staleCyl = defaultCyl.difference(camaro.cylinderCounts);
      expect(staleCyl, isNotEmpty, reason: 'scenario needs a stale cylinder');
      s.selectedCylinderCount = staleCyl.first;
      s.selectedFuelType = camaro.fuelTypes.first; // compatible
      s.selectedColor = 'Red'; // not vehicle dependent

      await tester.tap(camaroSuggestion());
      await tester.pump();
      // Catalog pending: nothing may be cleared yet (nothing is known).
      expect(s.selectedCylinderCount, staleCyl.first);

      await completeCatalog(tester);
      expect(s.selectedCylinderCount, isNull,
          reason: 'cylinder Camaro does not offer is dropped on resolution');
      expect(s.selectedFuelType, camaro.fuelTypes.first);
      expect(s.selectedColor, 'Red');

      await disposePage(tester);
    },
  );

  testWidgets(
    'a stalled preferences write cannot delay or block the visible selection',
    (tester) async {
      final gate = _GatedPrefsStore();
      SharedPreferencesStorePlatform.instance = gate;

      final s = await openSearchAndTypeCamaro(tester);
      await completeCatalog(tester);

      await tester.tap(camaroSuggestion());
      await tester.pump();

      expect(s.selectedModel, 'Camaro');
      expect(camaroSuggestion(), findsNothing);
      expect(find.text('Camaro'), findsWidgets);
      expect(real(s.getAvailableCylinderCounts()), camaro.cylinderCounts);
      expect(gate.blockedWrites, 0,
          reason: 'a result tap must not even start a disk write');

      // Even if some write were stalled, the UI still responds.
      await tester.enterText(find.byType(TextField).first, 'Cam');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Camaro'), findsOneWidget);

      gate.release();
      await disposePage(tester);
    },
  );
}

/// In-memory preferences store whose writes park until [release] -- stands in
/// for a slow disk.
class _GatedPrefsStore extends InMemorySharedPreferencesStore {
  _GatedPrefsStore() : super.empty();

  final Completer<void> _gate = Completer<void>();
  int blockedWrites = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    blockedWrites++;
    await _gate.future;
    return super.setValue(valueType, key, value);
  }
}
