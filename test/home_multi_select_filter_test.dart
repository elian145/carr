import 'package:car_listing_app/features/home/home_filter_chips.dart';
import 'package:car_listing_app/features/home/home_filters_query.dart';
import 'package:car_listing_app/features/home/home_multi_select_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('homeFilterEncodeList / homeFilterDecodeList', () {
    test('round-trips multiple values', () {
      const encoded = 'Toyota,BMW,Sedan';
      expect(homeFilterDecodeList(encoded), ['Toyota', 'BMW', 'Sedan']);
      expect(
        homeFilterEncodeList(['Toyota', 'BMW', 'Sedan']),
        encoded,
      );
    });

    test('toggle adds and removes values', () {
      var list = homeFilterToggleValue(const [], 'Toyota');
      expect(list, ['Toyota']);
      list = homeFilterToggleValue(list, 'BMW');
      expect(list, ['Toyota', 'BMW']);
      list = homeFilterToggleValue(list, 'Toyota');
      expect(list, ['BMW']);
    });
  });

  group('homeFiltersToApiQuery multi filters', () {
    test('sends comma-separated brand and body_type', () {
      const f = HomeFiltersSnapshot(
        brand: 'Toyota,BMW',
        bodyType: 'Sedan,SUV',
      );
      final q = homeFiltersToApiQuery(f);
      expect(q['brand'], 'Toyota,BMW');
      expect(q['body_type'], 'sedan,suv');
    });
  });

  group('clearHomeFilterChip multi brand', () {
    test('removes one brand and keeps model when one brand remains', () {
      const filters = HomeFiltersSnapshot(
        brand: 'Toyota,BMW',
        model: 'Camry',
      );
      final cleared = clearHomeFilterChip(
        filters,
        homeFilterChipItemKey('brand', 'BMW'),
      );
      expect(cleared.brand, 'Toyota');
      expect(cleared.model, 'Camry');
    });
  });
}
