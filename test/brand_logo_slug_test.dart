import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/brand_logo_filenames.dart';

void main() {
  group('brandLogoSlug', () {
    test('uses explicit map entries', () {
      expect(brandLogoSlug('Toyota'), 'toyota');
      expect(brandLogoSlug('Dongfeng'), 'dongfeng-motor');
      expect(brandLogoSlug('Geely'), 'geely-zgh');
      expect(brandLogoSlug('Gwm'), 'great-wall');
      expect(brandLogoSlug('JAC'), 'jac-motors');
    });

    test('folds accents and matches catalog casing', () {
      expect(brandLogoSlug('Citroën'), 'citroen');
      expect(brandLogoSlug('Škoda'), 'skoda');
      expect(brandLogoSlug('Baic'), 'baic');
      expect(brandLogoSlug('Mg'), 'mg');
      expect(brandLogoSlug('Li Auto'), 'li-auto');
    });

    test('aliases naive slugs to on-disk filenames', () {
      expect(brandLogoSlug('dongfeng'), 'dongfeng-motor');
      expect(brandLogoSlug('geely'), 'geely-zgh');
      expect(brandLogoSlug('Mercedes Maybach'), 'mercedes-maybach');
      expect(brandLogoSlug('Jetour'), 'jetour');
      expect(brandLogoSlug('Soueast'), 'soueast');
    });
  });
}
