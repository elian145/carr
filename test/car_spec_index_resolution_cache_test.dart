import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/services/car_spec_index.dart';

/// The Search result tap resolves model-aware options through
/// [CarSpecIndex.homeFilterFieldOptions]. That path is memoized (per-trim spec
/// mapping, model family lookup, whole-answer cache); the memoization must be
/// invisible: identical answers to an index whose caches are cold.
void main() {
  late String raw;

  setUpAll(() {
    raw = File('assets/car_spec_dataset.json').readAsStringSync();
  });

  CarSpecIndex fresh() => parseCarSpecDatasetJsonString(raw).index!;

  void expectSameOptions(CatalogSellFieldOptions? a, CatalogSellFieldOptions? b) {
    expect(a == null, b == null);
    if (a == null || b == null) return;
    expect(a.cylinderCounts, b.cylinderCounts);
    expect(a.bodyTypes, b.bodyTypes);
    expect(a.fuelTypes, b.fuelTypes);
    expect(a.driveTypes, b.driveTypes);
    expect(a.transmissions, b.transmissions);
    expect(a.seatings, b.seatings);
    expect(a.engineSizes, b.engineSizes);
  }

  test('memoized resolution equals a cold index for several vehicles/windows', () {
    final warm = fresh();
    final vehicles = <(String, String, String, int?, int?)>[
      ('Chevrolet', 'Camaro', '', null, null),
      ('Chevrolet', 'Camaro', '', 2015, 2020),
      ('Toyota', 'Camry', '', null, null),
      ('Toyota', 'Camry', '', 2023, 2023),
      ('Toyota', 'Camry', 'SE', null, null),
      ('Chevrolet', 'Not In Catalog', '', null, null),
    ];
    // Warm every cache (twice, in a different order than the cold side uses).
    for (final v in vehicles.reversed) {
      warm.homeFilterFieldOptions(v.$1, v.$2, v.$3,
          rangeMinYear: v.$4, rangeMaxYear: v.$5);
    }
    for (final v in vehicles) {
      final cold = fresh().homeFilterFieldOptions(v.$1, v.$2, v.$3,
          rangeMinYear: v.$4, rangeMaxYear: v.$5);
      final cached = warm.homeFilterFieldOptions(v.$1, v.$2, v.$3,
          rangeMinYear: v.$4, rangeMaxYear: v.$5);
      expectSameOptions(cached, cold);
    }
  });

  test('repeat lookups are served from the cache (same answer instance)', () {
    final idx = fresh();
    final a = idx.homeFilterFieldOptions('Chevrolet', 'Camaro', '');
    final b = idx.homeFilterFieldOptions('Chevrolet', 'Camaro', '');
    expect(a, isNotNull);
    expect(identical(a, b), isTrue);
    // A different year window is a different answer, not a stale cache hit.
    final c = idx.homeFilterFieldOptions(
      'Chevrolet',
      'Camaro',
      '',
      rangeMinYear: 2016,
      rangeMaxYear: 2016,
    );
    expect(identical(a, c), isFalse);
  });

  test('per-year Sell-style resolution is unchanged by trim-spec memoization', () {
    final warm = fresh();
    final cold = fresh();
    warm.homeFilterFieldOptions('Chevrolet', 'Camaro', ''); // fills caches
    for (final year in [1970, 1999, 2010, 2016, 2020, 2024]) {
      expectSameOptions(
        warm.sellFieldOptionsUnion('Chevrolet', 'Camaro', '', year),
        cold.sellFieldOptionsUnion('Chevrolet', 'Camaro', '', year),
      );
    }
  });

  testWidgets('sliced background prewarm builds the identical engine list',
      (tester) async {
    final expected = fresh().allCatalogEngineSizeLabels();
    final sliced = fresh();
    expect(sliced.peekAllCatalogEngineSizeLabels(), isNull,
        reason: 'peek never scans');

    var done = false;
    var frames = 0;
    unawaited(
      sliced
          .prewarmAllCatalogEngineSizeLabels(
            sliceBudget: const Duration(milliseconds: 2),
          )
          .then((_) => done = true),
    );
    // The scan yields to the next frame between slices: it must need several
    // frames (never one long block) and still finish.
    while (!done && frames < 5000) {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
    }
    expect(done, isTrue);
    expect(frames, greaterThan(1), reason: 'work was spread over frames');
    expect(sliced.peekAllCatalogEngineSizeLabels(), expected);
  });

  group('lazy default engine sizes', () {
    const base = <String>['Any', 'x'];

    HomeVehicleFieldDefaults defaults(List<String> Function() provider) =>
        HomeVehicleFieldDefaults(
          bodyTypes: base,
          transmissions: base,
          fuelTypes: base,
          driveTypes: base,
          cylinderCounts: base,
          seatings: base,
          engineSizesProvider: provider,
        );

    test('provider is not invoked when the catalog narrows engine sizes', () {
      var calls = 0;
      final o = HomeVehicleFieldOptions.resolve(
        catalog: null,
        engineCatalog: const CatalogSellFieldOptions(
          transmissions: {},
          fuelTypes: {},
          bodyTypes: {},
          driveTypes: {},
          cylinderCounts: {},
          engineSizes: {'2.0', '3.6'},
          seatings: {},
        ),
        defaults: defaults(() {
          calls++;
          return const ['Any', 'all'];
        }),
      );
      expect(o.engineSizes, ['Any', '2.0', '3.6']);
      expect(calls, 0, reason: 'full-catalog engine scan must not run');
    });

    test('provider supplies the default when the catalog has no engines', () {
      var calls = 0;
      final o = HomeVehicleFieldOptions.resolve(
        catalog: null,
        engineCatalog: null,
        defaults: defaults(() {
          calls++;
          return const ['Any', 'all'];
        }),
      );
      expect(o.engineSizes, ['Any', 'all']);
      expect(calls, 1);
    });
  });
}
