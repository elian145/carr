import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_filters_query.dart';

void main() {
  group('homeFiltersToApiQuery', () {
    test('includes brand model trim and sort', () {
      const f = HomeFiltersSnapshot(
        brand: 'Toyota',
        model: 'Camry',
        trim: 'LE',
      );
      final q = homeFiltersToApiQuery(
        f,
        apiSortValue: 'price_asc',
        includeSort: true,
      );
      expect(q['brand'], 'Toyota');
      expect(q['model'], 'Camry');
      expect(q['trim'], 'LE');
      expect(q['sort_by'], 'price_asc');
    });

    test('skips Any values and normalizes condition', () {
      const f = HomeFiltersSnapshot(
        condition: 'Any',
        transmission: 'Automatic',
        fuelType: 'any',
        bodyType: 'Sedan',
      );
      final q = homeFiltersToApiQuery(f);
      expect(q.containsKey('condition'), isFalse);
      expect(q.containsKey('fuel_type'), isFalse);
      expect(q['transmission'], 'automatic');
      expect(q['body_type'], 'sedan');
    });

    test('includes damaged parts only for damaged title', () {
      const f = HomeFiltersSnapshot(
        titleStatus: 'damaged',
        damagedParts: '2',
      );
      final q = homeFiltersToApiQuery(f);
      expect(q['title_status'], 'damaged');
      expect(q['damaged_parts'], '2');
    });

    test('omits sort when includeSort is false', () {
      const f = HomeFiltersSnapshot(sortByUi: 'Newest');
      final q = homeFiltersToApiQuery(
        f,
        apiSortValue: 'created_desc',
        includeSort: false,
      );
      expect(q.containsKey('sort_by'), isFalse);
    });
  });

  group('applyDamagedPartsListingFilter', () {
    test('filters damaged listings by part count', () {
      final rows = [
        {'title_status': 'damaged', 'damaged_parts': '2'},
        {'title_status': 'damaged', 'damaged_parts': '1'},
        {'title_status': 'clean', 'damaged_parts': '2'},
      ];
      final out = applyDamagedPartsListingFilter(
        rows,
        selectedTitleStatus: 'damaged',
        selectedDamagedParts: '2',
      );
      expect(out.length, 1);
      expect(out.first['damaged_parts'], '2');
    });
  });
}
