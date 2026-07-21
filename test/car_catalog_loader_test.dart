import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/data/car_catalog_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalogLoader.debugResetForTest();
  });

  test('applyCatalogFromAsset overrides embedded catalog sections', () {
    final embeddedBrandCount = CarCatalog.brands.length;
    expect(embeddedBrandCount, greaterThan(10));

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

  test('ensureLoaded applies asset catalog and is idempotent', () async {
    await CarCatalogLoader.ensureLoaded();
    expect(CarCatalogLoader.assetAvailable, isTrue);
    expect(CarCatalog.brands, isNotEmpty);

    final brandsAfterFirst = List<String>.from(CarCatalog.brands);
    await CarCatalogLoader.ensureLoaded();
    expect(CarCatalog.brands, brandsAfterFirst);
  });
}
