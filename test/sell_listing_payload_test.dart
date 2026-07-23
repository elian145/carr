import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/sell/sell_listing_payload.dart';

void main() {
  const sampleCarData = <String, dynamic>{
    'brand': 'Toyota',
    'model': 'Camry',
    'trim': 'LE',
    'year': '2020',
    'price': '\$12,500',
    'mileage': '45000',
    'condition': 'Used',
    'transmission': 'Automatic',
    'fuel_type': 'Gasoline',
    'color': 'White',
    'body_type': 'Sedan',
    'seating': '5',
    'drive_type': 'fwd',
    'region_specs': 'GCC',
    'title_status': 'clean',
    'engine_size': '2.5L',
    'city': 'Baghdad',
    'plate_type': 'private',
    'plate_city': 'Baghdad',
    'contact_phone': ' 07701234567 ',
    'description': ' Well maintained ',
    'vin': ' 1HGBH41JXMN109186 ',
  };

  group('buildSellCarUpdatePayload', () {
    test('normalizes core listing fields for update API', () {
      final payload = buildSellCarUpdatePayload(sampleCarData);

      expect(payload['title'], 'Toyota Camry LE');
      expect(payload['brand'], 'toyota');
      expect(payload['model'], 'Camry');
      expect(payload['year'], 2020);
      expect(payload['price'], 12500);
      expect(payload['mileage'], 45000);
      expect(payload['condition'], 'used');
      expect(payload['transmission'], 'automatic');
      expect(payload['fuel_type'], 'gasoline');
      expect(payload['engine_type'], 'gasoline');
      expect(payload['region_specs'], 'gcc');
      expect(payload['engine_size'], 2.5);
      expect(payload['plate_type'], 'private');
      expect(payload['plate_city'], 'Baghdad');
      expect(payload['description'], 'Well maintained');
      expect(payload['vin'], '1HGBH41JXMN109186');
      expect(payload.containsKey('city'), isFalse);
      expect(payload['contact_phone'], '+9647701234567');
      expect(payload['contact_phones'], ['+9647701234567']);
    });

    test('sends up to three contact phones on update', () {
      final payload = buildSellCarUpdatePayload({
        ...sampleCarData,
        'contact_phones': [
          '+9647701111111',
          '+9647702222222',
          '+9647703333333',
          '+9647704444444',
        ],
      });
      expect(payload['contact_phone'], '+9647701111111');
      expect(payload['contact_phones'], [
        '+9647701111111',
        '+9647702222222',
        '+9647703333333',
      ]);
    });

    test('drops invalid region specs', () {
      final payload = buildSellCarUpdatePayload({
        ...sampleCarData,
        'region_specs': 'INVALID',
      });
      expect(payload.containsKey('region_specs'), isFalse);
    });

    test('converts miles to km for API payload', () {
      final payload = buildSellCarUpdatePayload({
        ...sampleCarData,
        'mileage': '10000',
        'mileage_unit': 'miles',
      });
      expect(payload['mileage'], 16093);
    });
  });

  group('sellMileageKmFromCarData', () {
    test('returns km value unchanged', () {
      expect(
        sellMileageKmFromCarData({'mileage': '45000', 'mileage_unit': 'km'}),
        45000,
      );
    });

    test('converts miles to km', () {
      expect(
        sellMileageKmFromCarData({'mileage': '10000', 'mileage_unit': 'miles'}),
        16093,
      );
    });
  });

  group('buildSellCarCreatePayload', () {
    test('includes create-only fields and dual plate keys', () {
      final payload = buildSellCarCreatePayload(sampleCarData);

      expect(payload['title'], 'Toyota Camry LE');
      expect(payload['brand'], 'toyota');
      expect(payload['price'], 12500);
      expect(payload['city'], 'baghdad');
      expect(payload['location'], 'baghdad');
      expect(payload['plate_type'], 'private');
      expect(payload['plateType'], 'private');
      expect(payload['plate_city'], 'Baghdad');
      expect(payload['plateCity'], 'Baghdad');
      expect(payload['contact_phone'], '+9647701234567');
      expect(payload['contact_phones'], ['+9647701234567']);
      expect(payload['description'], 'Well maintained');
      expect(payload['is_quick_sell'], isFalse);
      expect(payload['vin'], '1HGBH41JXMN109186');
    });

    test('parses damaged title status parts', () {
      final payload = buildSellCarCreatePayload({
        ...sampleCarData,
        'title_status': 'damaged',
        'damaged_parts': '3',
      });
      expect(payload['title_status'], 'damaged');
      expect(payload['damaged_parts'], 3);
    });
  });
}
