import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_filter_chip_style.dart';
import 'package:car_listing_app/features/home/home_filter_chips.dart';
import 'package:car_listing_app/features/home/home_filters_query.dart';
import 'package:car_listing_app/features/home/home_multi_select_filter.dart';

void main() {
  const labels = HomeFilterChipLabels(
    brand: 'Brand',
    model: 'Model',
    trim: 'Trim',
    keyword: 'Search',
    price: 'Price',
    year: 'Year',
    mileage: 'Mileage',
    condition: 'Condition',
    transmission: 'Transmission',
    fuel: 'Fuel',
    titleStatus: 'Title',
    bodyType: 'Body',
    color: 'Color',
    driveType: 'Drive',
    regionSpecs: 'Region',
    cylinders: 'Cylinders',
    seating: 'Seating',
    engineSize: 'Engine',
    plateType: 'Plate type',
    plateCity: 'Plate city',
    sortBy: 'Sort',
    minPrice: 'Min price',
    maxPrice: 'Max price',
    minYear: 'Min year',
    maxYear: 'Max year',
    minMileage: 'Min mileage',
    maxMileage: 'Max mileage',
    unitKm: 'km',
  );

  final formatters = HomeFilterChipFormatters(
    localizedBrand: _identity,
    localizedModel: (_, model) => model ?? '',
    translateValue: (raw) => raw ?? '',
    localizeDigits: (raw) => raw,
    formatCurrency: (raw) => '\$$raw',
    engineSizeLabel: (raw) => raw,
    plateTypeLabel: (raw) => raw,
    regionSpecsLabel: (raw) => raw.toUpperCase(),
    titleStatusDamagedWithParts: (parts) => 'Damaged ($parts parts)',
  );

  group('homeFilterChipValueActive', () {
    test('treats Any and empty as inactive', () {
      expect(homeFilterChipValueActive(null), isFalse);
      expect(homeFilterChipValueActive(''), isFalse);
      expect(homeFilterChipValueActive('Any'), isFalse);
      expect(homeFilterChipValueActive('any'), isFalse);
      expect(homeFilterChipValueActive('Toyota'), isTrue);
    });
  });

  group('buildHomeFilterChipDescriptors', () {
    test('includes brand model trim and price range', () {
      const filters = HomeFiltersSnapshot(
        brand: 'Toyota',
        model: 'Camry',
        trim: 'LE',
        minPrice: '1000',
        maxPrice: '5000',
      );
      final chips = buildHomeFilterChipDescriptors(
        filters: filters,
        labels: labels,
        formatters: formatters,
      );
      expect(chips.map((c) => c.filterType), [
        'brand',
        'model',
        'trim',
        'price',
      ]);
      expect(chips.last.value, '\$1000 - \$5000');
    });

    test('includes damaged title with parts', () {
      const filters = HomeFiltersSnapshot(
        titleStatus: 'damaged',
        damagedParts: '2',
      );
      final chips = buildHomeFilterChipDescriptors(
        filters: filters,
        labels: labels,
        formatters: formatters,
      );
      expect(chips.single.filterType, 'titleStatus');
      expect(chips.single.value, 'Damaged (2 parts)');
    });

    test('skips default sort', () {
      const filters = HomeFiltersSnapshot(sortByUi: 'default');
      final chips = buildHomeFilterChipDescriptors(
        filters: filters,
        labels: labels,
        formatters: formatters,
      );
      expect(chips, isEmpty);
    });

    test('includes a keyword chip when a free-text keyword is active', () {
      const filters = HomeFiltersSnapshot(keyword: 'Land Cruiser 2018');
      final chips = buildHomeFilterChipDescriptors(
        filters: filters,
        labels: labels,
        formatters: formatters,
      );
      expect(chips.single.filterType, 'keyword');
      expect(chips.single.value, 'Land Cruiser 2018');
      expect(chips.single.label, 'Search');
    });

    test('trims the keyword value shown on the chip', () {
      const filters = HomeFiltersSnapshot(keyword: '  toyota  ');
      final chips = buildHomeFilterChipDescriptors(
        filters: filters,
        labels: labels,
        formatters: formatters,
      );
      expect(chips.single.filterType, 'keyword');
      expect(chips.single.value, 'toyota');
    });

    test('omits the keyword chip when keyword is null', () {
      const filters = HomeFiltersSnapshot(brand: 'Toyota');
      final chips = buildHomeFilterChipDescriptors(
        filters: filters,
        labels: labels,
        formatters: formatters,
      );
      expect(chips.any((c) => c.filterType == 'keyword'), isFalse);
    });

    test('omits the keyword chip when keyword is empty or whitespace-only',
        () {
      const filters = HomeFiltersSnapshot(keyword: '   ');
      final chips = buildHomeFilterChipDescriptors(
        filters: filters,
        labels: labels,
        formatters: formatters,
      );
      expect(chips, isEmpty);
    });
  });

  group('clearHomeFilterChip', () {
    test('clearing brand also clears model and trim', () {
      const filters = HomeFiltersSnapshot(
        brand: 'Toyota',
        model: 'Camry',
        trim: 'LE',
        city: 'Baghdad',
      );
      final cleared = clearHomeFilterChip(filters, 'brand');
      expect(cleared.brand, isNull);
      expect(cleared.model, isNull);
      expect(cleared.trim, isNull);
      expect(cleared.city, 'Baghdad');
    });

    test('clearing price clears both bounds', () {
      const filters = HomeFiltersSnapshot(minPrice: '1', maxPrice: '9');
      final cleared = clearHomeFilterChip(filters, 'price');
      expect(cleared.minPrice, isNull);
      expect(cleared.maxPrice, isNull);
    });

    test('clearing keyword removes it without touching other filters', () {
      const filters = HomeFiltersSnapshot(
        keyword: 'Land Cruiser',
        brand: 'Toyota',
      );
      final cleared = clearHomeFilterChip(filters, 'keyword');
      expect(cleared.keyword, isNull);
      expect(cleared.brand, 'Toyota');
    });
  });

  group('homeFilterBodyTypeIcon', () {
    test('maps known body types', () {
      expect(homeFilterBodyTypeIcon('suv'), Icons.directions_car_filled);
      expect(homeFilterBodyTypeIcon('pickup'), Icons.local_shipping);
    });
  });

  group('homeFilterNamedColor', () {
    test('maps red', () {
      expect(homeFilterNamedColor('red'), Colors.red);
    });
  });
}

String _identity(String? v) => v ?? '';
