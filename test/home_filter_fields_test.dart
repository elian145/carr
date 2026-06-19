import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/home/home_filter_fields.dart';

void main() {
  test('HomeFilterFields round-trips persist map keys', () {
    const fields = HomeFilterFields(
      brand: 'Toyota',
      model: 'Camry',
      priceMin: '5000',
      priceMax: '25000',
      yearMin: '2018',
      cylinders: '4',
      sortBy: 'Newest',
    );
    final map = fields.toPersistMap();
    expect(map['brand'], 'Toyota');
    expect(map['model'], 'Camry');
    expect(map['price_min'], '5000');
    expect(map['cylinders'], '4');

    final restored = HomeFilterFields.fromPersistMap(map);
    expect(restored.brand, 'Toyota');
    expect(restored.model, 'Camry');
    expect(restored.priceMin, '5000');
    expect(restored.cylinders, '4');
    expect(restored.sortBy, 'Newest');
  });

  test('HomeFilterFields maps saved-search keys', () {
    final fields = HomeFilterFields.fromSavedSearchMap({
      'brand': 'BMW',
      'min_price': '10000',
      'max_price': '40000',
      'cylinder_count': '6',
    });
    expect(fields.brand, 'BMW');
    expect(fields.priceMin, '10000');
    expect(fields.priceMax, '40000');
    expect(fields.cylinders, '6');
    expect(fields.toPersistMap()['price_min'], '10000');
  });

  test('HomeFilterFields copyWith and cleared', () {
    const fields = HomeFilterFields(
      brand: 'Toyota',
      model: 'Camry',
      priceMin: '5000',
    );
    final updated = fields.copyWith(model: null, priceMin: '6000');
    expect(updated.brand, 'Toyota');
    expect(updated.model, isNull);
    expect(updated.priceMin, '6000');

    expect(fields.cleared().brand, isNull);
    expect(fields.cleared().hasAnyActive, isFalse);
  });
}
