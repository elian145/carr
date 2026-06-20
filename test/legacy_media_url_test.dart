import 'package:car_listing_app/shared/media/media_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildLegacyFullImageUrl', () {
    test('returns empty for null-like values', () {
      expect(buildLegacyFullImageUrl('null'), '');
      expect(buildLegacyFullImageUrl('NONE'), '');
      expect(buildLegacyFullImageUrl(''), '');
    });

    test('maps uploads and car_photos paths under static', () {
      expect(
        buildLegacyFullImageUrl('uploads/foo.jpg'),
        contains('/static/uploads/foo.jpg'),
      );
      expect(
        buildLegacyFullImageUrl('car_photos/foo.jpg'),
        contains('/static/uploads/car_photos/foo.jpg'),
      );
    });

    test('bare filename stays under static/uploads (legacy behavior)', () {
      expect(
        buildLegacyFullImageUrl('photo.jpg'),
        contains('/static/uploads/photo.jpg'),
      );
      expect(buildLegacyFullImageUrl('photo.jpg'), isNot(contains('car_photos')));
    });
  });
}
