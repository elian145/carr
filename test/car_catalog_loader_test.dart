import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';

void main() {
  tearDown(() {
    CarCatalog.resetCatalogOverrideForTest();
  });

  test('applyCatalogFromAsset overrides embedded catalog sections', () {
    final embeddedBrandCount = CarCatalog.brands.length;
    expect(embeddedBrandCount, greaterThan(10));
    expect(CarCatalog.models.isNotEmpty, isTrue);

    CarCatalog.applyCatalogFromAsset({
      'brands': ['TestBrandA'],
      'models': {
        'TestBrandA': ['Model1'],
      },
      'trimsByBrandModel': {
        'TestBrandA': {
          'Model1': ['Base', 'Sport'],
        },
      },
    });

    expect(CarCatalog.brands, ['TestBrandA']);
    expect(CarCatalog.models['TestBrandA'], ['Model1']);
    expect(CarCatalog.trimsFor('TestBrandA', 'Model1'), ['Base', 'Sport']);
  });

  test('toAssetJson includes brands models and trims', () {
    final json = CarCatalog.toAssetJson();
    expect(json['brands'], isA<List>());
    expect(json['models'], isA<Map>());
    expect(json['trimsByBrandModel'], isA<Map>());
    expect((json['brands'] as List).length, greaterThan(10));
    expect((json['models'] as Map).isNotEmpty, isTrue);
  });
}
