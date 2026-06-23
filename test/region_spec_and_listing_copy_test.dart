import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/listing/listing_mappers.dart';
import 'package:car_listing_app/shared/i18n/region_spec_labels.dart';

void main() {
  test('copyListingMapList clones maps for feed cache', () {
    final source = [
      {'id': '1', 'title': 'A'},
    ];
    final copy = copyListingMapList(source);
    expect(copy, source);
    copy[0]['title'] = 'B';
    expect(source[0]['title'], 'A');
  });

  test('isValidCarRegionSpecCode accepts known codes', () {
    expect(isValidCarRegionSpecCode('gcc'), isTrue);
    expect(isValidCarRegionSpecCode('US'), isTrue);
    expect(isValidCarRegionSpecCode(''), isFalse);
    expect(isValidCarRegionSpecCode('mars'), isFalse);
  });

  test('carRegionSpecDisplayLabel normalizes codes', () {
    expect(carRegionSpecDisplayLabel('gcc'), 'GCC');
    expect(carRegionSpecDisplayLabel('unknown'), 'unknown');
  });
}
