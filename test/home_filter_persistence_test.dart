import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_filter_persistence.dart';
import 'package:car_listing_app/features/home/home_filters_query.dart';

void main() {
  group('homeFilterNormalizeStr', () {
    test('trims and drops empty values', () {
      expect(homeFilterNormalizeStr('  Toyota  '), 'Toyota');
      expect(homeFilterNormalizeStr(''), isNull);
      expect(homeFilterNormalizeStr(null), isNull);
    });
  });

  group('homePersistMapToSavedSearchKeys', () {
    test('maps home_filters_v1 keys to saved-search keys', () {
      final out = homePersistMapToSavedSearchKeys(<String, dynamic>{
        'price_min': '1000',
        'year_max': '2020',
        'cylinders': '4',
      });
      expect(out['min_price'], '1000');
      expect(out['max_year'], '2020');
      expect(out['cylinder_count'], '4');
    });

    test('maps the persisted keyword key to the saved-search q key', () {
      final out = homePersistMapToSavedSearchKeys(<String, dynamic>{
        'keyword': 'Land Cruiser',
      });
      expect(out['q'], 'Land Cruiser');
    });
  });

  group('HomeFilterParsedFields', () {
    test('parses saved-search map and normalizes region specs', () {
      final parsed = HomeFilterParsedFields.fromSavedSearchMap({
        'brand': 'Toyota',
        'region_specs': 'GCC',
        'cylinder_count': '4',
      });
      expect(parsed.brand, 'Toyota');
      expect(parsed.regionSpecs, 'gcc');
      expect(parsed.cylinderCount, '4');
    });

    test('parses home persist map via key remap', () {
      final parsed = HomeFilterParsedFields.fromHomePersistMap({
        'price_min': '5000',
        'year_min': '2018',
        'cylinders': '6',
      });
      expect(parsed.minPrice, '5000');
      expect(parsed.minYear, '2018');
      expect(parsed.cylinderCount, '6');
    });

    test('parses keyword from a saved-search map (q key)', () {
      final parsed = HomeFilterParsedFields.fromSavedSearchMap({
        'q': 'Land Cruiser',
      });
      expect(parsed.keyword, 'Land Cruiser');
    });

    test('parses keyword from a home persist map (keyword key)', () {
      final parsed = HomeFilterParsedFields.fromHomePersistMap({
        'keyword': 'toyota',
      });
      expect(parsed.keyword, 'toyota');
    });

    test('omits keyword when absent from either map shape', () {
      final fromSaved = HomeFilterParsedFields.fromSavedSearchMap({
        'brand': 'Toyota',
      });
      final fromHome = HomeFilterParsedFields.fromHomePersistMap({
        'brand': 'Toyota',
      });
      expect(fromSaved.keyword, isNull);
      expect(fromHome.keyword, isNull);
    });

    test('omits keyword when the persisted value is empty/whitespace-only',
        () {
      final parsed = HomeFilterParsedFields.fromHomePersistMap({
        'keyword': '   ',
      });
      expect(parsed.keyword, isNull);
    });
  });

  group('homeFilterHomePersistMap', () {
    test('round-trips snapshot fields to persist keys', () {
      const snap = HomeFiltersSnapshot(
        brand: 'BMW',
        minPrice: '10000',
        cylinderCount: '6',
        sortByUi: 'Newest',
      );
      final map = homeFilterHomePersistMap(snap);
      expect(map['brand'], 'BMW');
      expect(map['price_min'], '10000');
      expect(map['cylinders'], '6');
      expect(map['sort_by'], 'Newest');
    });

    test('writes the keyword under the keyword key when present', () {
      const snap = HomeFiltersSnapshot(keyword: 'Land Cruiser');
      final map = homeFilterHomePersistMap(snap);
      expect(map['keyword'], 'Land Cruiser');
    });

    test('trims the keyword before writing it', () {
      const snap = HomeFiltersSnapshot(keyword: '  toyota  ');
      final map = homeFilterHomePersistMap(snap);
      expect(map['keyword'], 'toyota');
    });

    test('writes a null/empty keyword when the snapshot has none', () {
      const snap = HomeFiltersSnapshot(brand: 'BMW');
      final map = homeFilterHomePersistMap(snap);
      expect(map['keyword'], isNull);
    });

    test('full round trip: save then restore preserves the keyword', () {
      const snap = HomeFiltersSnapshot(
        keyword: 'Land Cruiser 2018',
        brand: 'Toyota',
        minPrice: '5000',
      );
      final persisted = homeFilterHomePersistMap(snap);
      final restored = HomeFilterParsedFields.fromHomePersistMap(persisted);
      expect(restored.keyword, 'Land Cruiser 2018');
      expect(restored.brand, 'Toyota');
      expect(restored.minPrice, '5000');
    });

    test(
      'full round trip: empty keyword is omitted after restore, other '
      'filters unaffected',
      () {
        const snap = HomeFiltersSnapshot(keyword: '   ', brand: 'Toyota');
        final persisted = homeFilterHomePersistMap(snap);
        final restored = HomeFilterParsedFields.fromHomePersistMap(persisted);
        expect(restored.keyword, isNull);
        expect(restored.brand, 'Toyota');
      },
    );
  });

  group('homeValidDropdownSelection', () {
    test('returns empty for Any and case-insensitive match otherwise', () {
      expect(
        homeValidDropdownSelection(
          selected: 'Any',
          available: const ['Any', 'Automatic'],
        ),
        '',
      );
      expect(
        homeValidDropdownSelection(
          selected: 'automatic',
          available: const ['Any', 'Automatic'],
        ),
        'Automatic',
      );
    });
  });

  group('HomeFiltersSnapshot.hasActiveFilters', () {
    test('is false for empty snapshot', () {
      expect(const HomeFiltersSnapshot().hasActiveFilters, isFalse);
    });

    test('is true when any field is set', () {
      expect(
        const HomeFiltersSnapshot(city: 'Baghdad').hasActiveFilters,
        isTrue,
      );
    });
  });
}
