import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/shared/home/home_filter_query.dart';
import 'package:car_listing_app/shared/home/home_filter_persistence.dart';
import 'package:car_listing_app/shared/home/home_active_filter_chips.dart';
import 'package:car_listing_app/shared/home/home_sort_api.dart';
import 'package:flutter/material.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeFilterQuery', () {
    test('builds query map from persist map', () {
      final q = HomeFilterQuery.fromPersistMap({
        'brand': 'toyota',
        'price_min': '1000',
        'condition': 'Any',
        'region_specs': 'gcc',
      });
      expect(q['brand'], 'toyota');
      expect(q['min_price'], '1000');
      expect(q.containsKey('condition'), isFalse);
      expect(q['region_specs'], 'gcc');
    });

    test('loads filters from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        HomeFilterQuery.prefsKey:
            '{"brand":"bmw","sort_by":"Price: Low to High"}',
      });
      final q = await HomeFilterQuery.fromSharedPreferences(includeSort: false);
      expect(q['brand'], 'bmw');
    });

    test('counts active filters', () async {
      SharedPreferences.setMockInitialValues({
        HomeFilterQuery.prefsKey: '{"brand":"bmw","condition":"Any"}',
      });
      expect(await HomeFilterQuery.activeFilterCount(), 1);
    });

    test('updateSort persists localized label', () async {
      SharedPreferences.setMockInitialValues({});
      await HomeFilterPersistence.updateSort('Price: Low to High');
      final map = await HomeFilterPersistence.loadMap();
      expect(map['sort_by'], 'Price: Low to High');
      await HomeFilterPersistence.updateSort(null);
      expect(await HomeFilterPersistence.loadMap(), isEmpty);
    });
  });

  testWidgets('homeSortToApiValue maps localized labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            final v = homeSortToApiValue(
              context,
              AppLocalizations.of(context)!.sort_newest,
            );
            expect(v, 'newest');
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('homeActiveFilterChipSpecs builds brand and price chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            final specs = homeActiveFilterChipSpecs(context, {
              'brand': 'Toyota',
              'price_min': '10000',
              'price_max': '20000',
              'condition': 'Any',
            });
            expect(specs.length, 2);
            expect(specs.first.filterType, 'brand');
            expect(
              specs.any((s) => s.filterType == 'price'),
              isTrue,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
}
