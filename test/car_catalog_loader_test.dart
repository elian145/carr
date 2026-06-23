import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';

void main() {
  tearDown(() {
    CarCatalog.resetBrandsOverrideForTest();
  });

  test('applyBrandsFromAsset overrides embedded brands', () {
    final embeddedCount = CarCatalog.brands.length;
    expect(embeddedCount, greaterThan(10));

    CarCatalog.applyBrandsFromAsset(['TestBrandA', 'TestBrandB']);
    expect(CarCatalog.brands, ['TestBrandA', 'TestBrandB']);

    CarCatalog.applyBrandsFromAsset([]);
    expect(CarCatalog.brands, ['TestBrandA', 'TestBrandB']);
  });
}
