import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/shared/home/home_filter_persistence.dart';
import 'package:car_listing_app/shared/home/home_filter_query.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeFilterPersistence', () {
    test('clearFilter removes brand and dependent model/trim', () async {
      SharedPreferences.setMockInitialValues({
        HomeFilterQuery.prefsKey:
            '{"brand":"Toyota","model":"Camry","trim":"LE"}',
      });

      final updated = await HomeFilterPersistence.clearFilter('brand');
      expect(updated.containsKey('brand'), isFalse);
      expect(updated.containsKey('model'), isFalse);
      expect(updated.containsKey('trim'), isFalse);

      final stored = await HomeFilterPersistence.loadMap();
      expect(stored, isEmpty);
    });

    test('clearFilterInMap clears price range keys', () {
      final updated = HomeFilterPersistence.clearFilterInMap(
        {'price_min': '1000', 'price_max': '5000', 'brand': 'BMW'},
        'price',
      );
      expect(updated['brand'], 'BMW');
      expect(updated.containsKey('price_min'), isFalse);
      expect(updated.containsKey('price_max'), isFalse);
    });

    test('hasAnyActive ignores Any values', () {
      expect(
        HomeFilterPersistence.hasAnyActive({'condition': 'Any', 'brand': ''}),
        isFalse,
      );
      expect(
        HomeFilterPersistence.hasAnyActive({'condition': 'used'}),
        isTrue,
      );
    });
  });
}
