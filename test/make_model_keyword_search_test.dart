import 'package:car_listing_app/shared/ui/make_model_keyword_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const brands = ['Toyota', 'Honda', 'BMW'];
  const models = {
    'Toyota': ['Camry', 'Corolla'],
    'Honda': ['Civic', 'Accord'],
    'BMW': ['3 Series', 'X5'],
  };

  group('makeModelKeywordMatchedBrands', () {
    test('returns empty for blank query', () {
      expect(makeModelKeywordMatchedBrands(brands, ''), isEmpty);
      expect(makeModelKeywordMatchedBrands(brands, '   '), isEmpty);
    });

    test('matches brand substring case-insensitively', () {
      expect(makeModelKeywordMatchedBrands(brands, 'toy'), ['Toyota']);
      expect(makeModelKeywordMatchedBrands(brands, 'bmw'), ['BMW']);
    });
  });

  group('makeModelKeywordMatchedModels', () {
    test('returns empty for blank query', () {
      expect(makeModelKeywordMatchedModels(brands, models, ''), isEmpty);
    });

    test('returns all models when brand matches', () {
      final hits = makeModelKeywordMatchedModels(brands, models, 'toyota');
      expect(hits.map((e) => e['model']).toList(), ['Camry', 'Corolla']);
      expect(hits.every((e) => e['brand'] == 'Toyota'), isTrue);
    });

    test('matches model substring', () {
      final hits = makeModelKeywordMatchedModels(brands, models, 'civic');
      expect(hits, [
        {'brand': 'Honda', 'model': 'Civic'},
      ]);
    });

    test('dedupes brand and model hits', () {
      final hits = makeModelKeywordMatchedModels(brands, models, 'camry');
      expect(hits.length, 1);
      expect(hits.first['brand'], 'Toyota');
      expect(hits.first['model'], 'Camry');
    });
  });
}
