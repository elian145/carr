import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/features/saved_searches/saved_search_home_bridge.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persistFiltersForHome sets one-time filters and pending fetch', () async {
    await SavedSearchHomeBridge.persistFiltersForHome({
      'brand': 'Toyota',
      'min_price': '10000',
      'q': 'camry',
    });

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(SavedSearchHomeBridge.oneTimeFiltersKey), isNotNull);
    expect(sp.getBool(SavedSearchHomeBridge.pendingFetchKey), isTrue);
    expect(
      sp.getString(SavedSearchHomeBridge.oneTimeFiltersKey),
      contains('"keyword":"camry"'),
    );
  });

  test('consumeOneTimeFilters returns and clears stored map', () async {
    SharedPreferences.setMockInitialValues({
      SavedSearchHomeBridge.oneTimeFiltersKey: '{"brand":"BMW"}',
    });

    final filters = await SavedSearchHomeBridge.consumeOneTimeFilters();
    expect(filters?['brand'], 'BMW');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(SavedSearchHomeBridge.oneTimeFiltersKey), isNull);
  });

  test('persistFiltersForHome keeps trim, color, condition, sort_by', () async {
    await SavedSearchHomeBridge.persistFiltersForHome({
      'brand': 'Toyota',
      'model': 'Camry',
      'trim': 'LE',
      'color': 'Black',
      'condition': 'Used',
      'sort_by': 'price_desc',
    });

    final filters = await SavedSearchHomeBridge.consumeOneTimeFilters();
    expect(filters, isNotNull);
    expect(filters!['trim'], 'LE');
    expect(filters['color'], 'Black');
    expect(filters['condition'], 'Used');
    expect(filters['sort_by'], 'price_desc');
  });
}
