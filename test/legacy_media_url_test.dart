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

    // Section 5 regression (Sell media investigation): an already-absolute
    // R2/CDN URL (e.g. what `_resolve_rel`'s bare-R2-key self-heal fix now
    // returns, or any already-correct `https://` value) must pass through
    // completely unchanged -- never get a second, local API-base prefix
    // stapled onto it (which would 404, since that combined URL points
    // nowhere real on either host).
    test(
      'an absolute non-/static R2/CDN https:// URL is never double-prefixed',
      () {
        const r2Url = 'https://cdn.example.com/car_photos/owner1/photo.jpg';
        expect(buildLegacyFullImageUrl(r2Url), r2Url);
        expect(
          buildLegacyFullImageUrl(r2Url),
          isNot(contains('/static/')),
        );
      },
    );

    test(
      'an absolute http:// URL (not just https://) is also passed through '
      'unchanged',
      () {
        const url = 'http://cdn.example.com/car_photos/photo.jpg';
        expect(buildLegacyFullImageUrl(url), url);
      },
    );
  });
}
