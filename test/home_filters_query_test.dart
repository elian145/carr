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

    test('emits q for a non-empty free-text keyword', () {
      const f = HomeFiltersSnapshot(keyword: 'Land Cruiser');
      final q = homeFiltersToApiQuery(f);
      expect(q['q'], 'Land Cruiser');
    });

    test('trims leading/trailing whitespace from q', () {
      const f = HomeFiltersSnapshot(keyword: '  toyota  ');
      final q = homeFiltersToApiQuery(f);
      expect(q['q'], 'toyota');
    });

    test('omits q for an empty keyword', () {
      const f = HomeFiltersSnapshot(keyword: '');
      final q = homeFiltersToApiQuery(f);
      expect(q.containsKey('q'), isFalse);
    });

    test('omits q for a whitespace-only keyword', () {
      const f = HomeFiltersSnapshot(keyword: '   ');
      final q = homeFiltersToApiQuery(f);
      expect(q.containsKey('q'), isFalse);
    });

    test('omits q when keyword is null (default)', () {
      const f = HomeFiltersSnapshot();
      final q = homeFiltersToApiQuery(f);
      expect(q.containsKey('q'), isFalse);
    });

    test('combines q with brand/model/year/price and other filters', () {
      const f = HomeFiltersSnapshot(
        keyword: 'sunroof',
        brand: 'Toyota',
        model: 'Camry',
        minPrice: '5000',
        maxPrice: '20000',
        minYear: '2015',
        maxYear: '2022',
        condition: 'Used',
      );
      final q = homeFiltersToApiQuery(f, apiSortValue: 'relevance');
      expect(q['q'], 'sunroof');
      expect(q['brand'], 'Toyota');
      expect(q['model'], 'Camry');
      expect(q['min_price'], '5000');
      expect(q['max_price'], '20000');
      expect(q['min_year'], '2015');
      expect(q['max_year'], '2022');
      expect(q['condition'], 'used');
      expect(q['sort_by'], 'relevance');
    });

    test('special-character-only keyword is trimmed but still sent as-is', () {
      // Trimming only strips surrounding whitespace, not punctuation; the
      // backend's normalize_search_query / ILIKE fallback are responsible
      // for sanitizing special characters, not the Flutter query builder.
      const f = HomeFiltersSnapshot(keyword: '  !!! ??? ');
      final q = homeFiltersToApiQuery(f);
      expect(q['q'], '!!! ???');
    });
  });

  group('HomeFiltersSnapshot.keyword', () {
    test('hasActiveFilters is true when only keyword is set', () {
      const f = HomeFiltersSnapshot(keyword: 'toyota');
      expect(f.hasActiveFilters, isTrue);
    });

    test('hasActiveFilters is false for a whitespace-only keyword', () {
      const f = HomeFiltersSnapshot(keyword: '   ');
      expect(f.hasActiveFilters, isFalse);
    });

    test('copyWith updates keyword without touching other fields', () {
      const f = HomeFiltersSnapshot(brand: 'Toyota', keyword: 'old');
      final updated = f.copyWith(keyword: 'new');
      expect(updated.keyword, 'new');
      expect(updated.brand, 'Toyota');
    });

    test('copyWith clearKeyword removes the keyword', () {
      const f = HomeFiltersSnapshot(brand: 'Toyota', keyword: 'old');
      final updated = f.copyWith(clearKeyword: true);
      expect(updated.keyword, isNull);
      expect(updated.brand, 'Toyota');
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

  group('listingMatchesHomeFilters', () {
    const toyota = {
      'brand': 'toyota',
      'model': 'camry',
      'year': 2020,
      'price': 10000,
      'mileage': 40000,
      'condition': 'used',
      'body_type': 'sedan',
      'fuel_type': 'gasoline',
    };
    const honda = {
      'brand': 'honda',
      'model': 'civic',
      'year': 2018,
      'price': 8000,
      'mileage': 70000,
      'condition': 'used',
      'body_type': 'sedan',
      'fuel_type': 'gasoline',
    };

    test('keeps only matching dealer inventory rows', () {
      final out = filterListingsByHomeFilters(
        [toyota, honda],
        const HomeFiltersSnapshot(brand: 'Toyota'),
      );
      expect(out, [toyota]);
    });

    test('applies price range', () {
      final out = filterListingsByHomeFilters(
        [toyota, honda],
        const HomeFiltersSnapshot(minPrice: '9000'),
      );
      expect(out, [toyota]);
    });

    test('returns all rows when no filters are active', () {
      final out = filterListingsByHomeFilters(
        [toyota, honda],
        const HomeFiltersSnapshot(),
      );
      expect(out, [toyota, honda]);
    });
  });
}
