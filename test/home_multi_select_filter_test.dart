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
    test('sends comma-separated body_type fuel and drive', () {
      const f = HomeFiltersSnapshot(
        bodyType: 'Sedan,SUV',
        fuelType: 'Gasoline,Hybrid',
        driveType: 'FWD,AWD',
      );
      final q = homeFiltersToApiQuery(f);
      expect(q['body_type'], 'sedan,suv');
      expect(q['fuel_type'], 'gasoline,hybrid');
      expect(q['drive_type'], 'fwd,awd');
    });

    test('sends only first brand when legacy multi-brand value stored', () {
      const f = HomeFiltersSnapshot(brand: 'Toyota,BMW');
      final q = homeFiltersToApiQuery(f);
      expect(q['brand'], 'Toyota');
    });
  });

  group('clearHomeFilterChip brand', () {
    test('clearing brand also clears model and trim', () {
      const filters = HomeFiltersSnapshot(
        brand: 'Toyota',
        model: 'Camry',
        trim: 'LE',
      );
      final cleared = clearHomeFilterChip(filters, 'brand');
      expect(cleared.brand, isNull);
      expect(cleared.model, isNull);
      expect(cleared.trim, isNull);
    });
  });
}
