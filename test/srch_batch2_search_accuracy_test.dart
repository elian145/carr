import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_filters_query.dart';
import 'package:car_listing_app/features/sell/sell_listing_payload.dart';

void main() {
  group('SRCH-1 brand key matching', () {
    test('Land Rover matches land-rover', () {
      expect(homeBrandsMatch('land-rover', 'Land Rover'), isTrue);
      expect(homeBrandsMatch('Land Rover', 'land-rover'), isTrue);
      expect(homeBrandMatchKey('Alfa Romeo'), homeBrandMatchKey('alfa-romeo'));
      expect(
        homeBrandMatchKey('Aston Martin'),
        homeBrandMatchKey('aston-martin'),
      );
      expect(
        homeBrandMatchKey('Rolls-Royce'),
        homeBrandMatchKey('rolls royce'),
      );
      expect(homeBrandMatchKey('Toyota'), 'toyota');
    });

    test('sell payload persists display brand, not slug', () {
      final create = buildSellCarCreatePayload({
        'brand': 'Land Rover',
        'model': 'Discovery',
        'trim': 'Base',
        'year': '2020',
        'price': '20000',
        'mileage': '1000',
        'condition': 'Used',
        'transmission': 'Automatic',
        'fuel_type': 'Gasoline',
        'color': 'Black',
        'body_type': 'SUV',
        'seating': '5',
        'drive_type': 'awd',
        'title_status': 'clean',
        'city': 'Erbil',
        'contact_phone': '07701234567',
      });
      expect(create['brand'], 'Land Rover');

      final update = buildSellCarUpdatePayload({
        'brand': 'Alfa Romeo',
        'model': 'Giulia',
        'trim': 'Base',
        'year': '2021',
        'price': '25000',
        'mileage': '2000',
        'condition': 'Used',
        'transmission': 'Automatic',
        'fuel_type': 'Gasoline',
        'color': 'Red',
        'body_type': 'Sedan',
        'seating': '5',
        'drive_type': 'rwd',
        'title_status': 'clean',
        'city': 'Erbil',
        'contact_phone': '07701234567',
      });
      expect(update['brand'], 'Alfa Romeo');
    });
  });

  group('SRCH-2 exact model API contract', () {
    test('homeFiltersToApiQuery sends model_match=exact', () {
      final q = homeFiltersToApiQuery(
        const HomeFiltersSnapshot(
          brand: 'Toyota',
          model: 'Land Cruiser',
        ),
      );
      expect(q['model'], 'Land Cruiser');
      expect(q['model_match'], 'exact');
      expect(q['brand'], 'Toyota');
    });

    test('omits model_match when model unset', () {
      final q = homeFiltersToApiQuery(
        const HomeFiltersSnapshot(brand: 'Toyota'),
      );
      expect(q.containsKey('model_match'), isFalse);
    });

    test('applyExactModelListingFilter still drops siblings', () {
      final filtered = applyExactModelListingFilter(
        [
          {'id': '1', 'model': 'Land Cruiser'},
          {'id': '2', 'model': 'Land Cruiser Prado'},
        ],
        selectedModel: 'Land Cruiser',
      );
      expect(filtered.map((e) => e['id']).toList(), ['1']);
    });
  });

  group('SRCH-3 random sort_seed session', () {
    test('pages in one session reuse the same seed', () {
      String? session;
      final pageSeeds = <String>[];
      for (var page = 1; page <= 3; page++) {
        final seed = homeResolveRandomSortSeed(
          existing: session,
          isRandomSort: true,
          refreshSession: false,
          micros: 1000,
          salt: 7,
        );
        session = seed;
        pageSeeds.add(seed!);
      }
      expect(pageSeeds.toSet(), hasLength(1));
      expect(pageSeeds.first, isNotEmpty);
    });

    test('refresh mints a new seed; non-random omits seed', () {
      final first = homeResolveRandomSortSeed(
        existing: null,
        isRandomSort: true,
        refreshSession: false,
        micros: 100,
        salt: 1,
      );
      final refreshed = homeResolveRandomSortSeed(
        existing: first,
        isRandomSort: true,
        refreshSession: true,
        micros: 200,
        salt: 1,
      );
      expect(refreshed, isNot(equals(first)));

      expect(
        homeResolveRandomSortSeed(
          existing: first,
          isRandomSort: false,
          refreshSession: false,
        ),
        isNull,
      );
    });
  });
}
