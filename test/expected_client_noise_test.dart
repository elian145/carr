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

    test('retries listing photo 404s but still drops them from Sentry', () {
      const notFound =
          'HttpException: Invalid statusCode: 404, uri = '
          'https://example.com/static/uploads/car_photos/preview.jpg';
      expect(isPermanentHttpImageError(notFound), isFalse);
      expect(isListingImageNotFoundError(notFound), isTrue);
      expect(isExpectedClientNoise(notFound), isTrue);
    });

    test('treats listing photo 403 as permanent', () {
      const forbidden =
          'HttpException: Invalid statusCode: 403, uri = '
          'https://example.com/static/uploads/car_photos/preview.jpg';
      expect(isPermanentHttpImageError(forbidden), isTrue);
      expect(isExpectedClientNoise(forbidden), isTrue);
    });

    test('retries transient upload network errors', () {
      expect(
        isTransientNetworkError('TimeoutException after 0:03:00.000000:'),
        isTrue,
      );
      expect(
        isTransientNetworkError(
          'SocketException: Failed host lookup: carr-5hrm.onrender.com',
        ),
        isTrue,
      );
      expect(isTransientNetworkError(StateError('boom')), isFalse);
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

    test('drops Uri.parse of local media map leaks', () {
      expect(
        isUnparseableImageUrlError(
          const FormatException(
            'Scheme not starting with alphabetic character (at character 1)\n'
            '{source: /var/mobile/Containers/Data/Application/ABC/tmp.jpg}',
          ),
        ),
        isTrue,
      );
      expect(
        isExpectedClientNoise(
          const FormatException(
            'Scheme not starting with alphabetic character (at character 1)',
          ),
        ),
        isTrue,
      );
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
