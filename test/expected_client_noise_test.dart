import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/debug/expected_client_noise.dart';
import 'package:car_listing_app/shared/listings/body_type_assets.dart';

void main() {
  group('isExpectedClientNoise', () {
    test('drops AssetManifest.json load failures', () {
      expect(
        isExpectedClientNoise(
          'Unable to load asset: "AssetManifest.json".',
        ),
        isTrue,
      );
    });

    test('drops listing photo 404s', () {
      expect(
        isPermanentHttpImageError(
          'HttpException: Invalid statusCode: 404, uri = '
          'https://example.com/static/uploads/car_photos/preview.jpg',
        ),
        isTrue,
      );
      expect(
        isExpectedClientNoise(
          'HttpException: Invalid statusCode: 404, uri = '
          'https://example.com/static/uploads/car_photos/preview.jpg',
        ),
        isTrue,
      );
    });

    test('drops iOS bad file descriptor after background', () {
      expect(
        isStaleHttpClientError(
          'ClientException: Bad file descriptor, uri=https://example.com/api/cars',
        ),
        isTrue,
      );
      expect(
        isExpectedClientNoise(
          'ClientException: Bad file descriptor, uri=https://example.com/api/cars',
        ),
        isTrue,
      );
    });

    test('does not drop unrelated errors', () {
      expect(isExpectedClientNoise(StateError('boom')), isFalse);
      expect(isPermanentHttpImageError('SocketException: timed out'), isFalse);
    });
  });

  group('discoverBodyTypeAssetMap', () {
    test('maps pngs and skips dark variants', () {
      final map = discoverBodyTypeAssetMap([
        'assets/body_types_png/sedan.png',
        'assets/body_types_png/sedan_dark.png',
        'assets/body_types_png/suv.png',
        'AssetManifest.json',
      ]);
      expect(map['Sedan'], 'assets/body_types_png/sedan.png');
      expect(map['Suv'], 'assets/body_types_png/suv.png');
      expect(map.keys, isNot(contains('Sedan Dark')));
    });

    test('prefers svg over png for the same label', () {
      final map = discoverBodyTypeAssetMap([
        'assets/body_types_png/coupe.png',
        'assets/body_types_clean/coupe.svg',
      ]);
      expect(map['Coupe'], 'assets/body_types_clean/coupe.svg');
    });
  });
}
