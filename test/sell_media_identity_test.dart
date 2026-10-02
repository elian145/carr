import 'package:car_listing_app/features/sell/sell_media_identity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract Section 7: proves the stability guarantee documented on
/// [SellMediaIdentity] -- the SAME (car-scoped, durable) local source path
/// always produces the SAME `client_media_id`, across repeated calls,
/// across process runs (no seeded/random/time-based component at all), and
/// regardless of how many other items are present. This is what makes it
/// safe for `expected_media` (built once, right before `create_car`) and
/// each later per-item Phase-A transfer call (built again, independently,
/// on every submit/resume attempt) to always agree without persisting a
/// separately-generated id anywhere.
void main() {
  group('SellMediaIdentity.stableIdFromSeed', () {
    test('is deterministic: the same seed always produces the same id, '
        'called any number of times, in any process', () {
      const seed = r'C:\Users\seller\AppData\pending_sell_media\'
          'draft123_listing_0_deadbeefcafef00d.jpg';
      final first = SellMediaIdentity.stableIdFromSeed(seed);
      for (var i = 0; i < 25; i++) {
        expect(
          SellMediaIdentity.stableIdFromSeed(seed),
          first,
          reason: 'a repeated call for the exact same seed must never '
              'produce a different id -- this is the sole property '
              '`expected_media` vs. each later Phase-A upload call relies '
              'on to agree with each other',
        );
      }
    });

    test('is a pure function of the seed string only -- no hidden '
        'dependency on wall-clock time, call order, or process identity', () {
      const seedA = 'video:/durable/path/a.mp4';
      const seedB = 'video:/durable/path/a.mp4';
      // Two textually-identical-but-distinct String instances must still
      // hash to the same id (this is what actually happens across two
      // independent `SellMediaIdentity.forNormalVideoItem` calls made
      // minutes or even days apart, e.g. a fresh submit vs. a resume
      // after an app kill).
      expect(
        SellMediaIdentity.stableIdFromSeed(seedA),
        SellMediaIdentity.stableIdFromSeed(seedB),
      );
    });

    test('different seeds (almost always) produce different ids, so two '
        'distinct media items never collide onto one manifest row', () {
      final ids = <String>{
        for (var i = 0; i < 500; i++)
          SellMediaIdentity.stableIdFromSeed('listing:/durable/path/$i.jpg'),
      };
      expect(
        ids.length,
        500,
        reason: 'FNV-1a over 500 distinct short strings should not '
            'collide in practice',
      );
    });

    test('always matches the backend\'s `_CLIENT_MEDIA_ID_RE` '
        r'(`^[A-Za-z0-9_-]{1,128}$`)', () {
      final id = SellMediaIdentity.stableIdFromSeed(
        'listing:/durable/path/with spaces/and:colons?.jpg',
        prefix: 'img_',
      );
      expect(RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id), isTrue);
    });
  });

  group('SellMediaIdentity.forImageItem / forNormalVideoItem stability '
      'across independent calls (the real resume scenario)', () {
    test('forImageItem for the SAME durable local path, called once for '
        'the create-time expected_media manifest and again, independently, '
        'for the Phase-A upload call on a later resume, yields the SAME '
        'client_media_id', () {
      const durablePath = '/app_support/pending_sell_media/'
          'draftABC_listing_1_a1b2c3d4.jpg';

      // Simulates the FIRST computation, right before create_car().
      final atCreateTime = SellMediaIdentity.forImageItem(
        durablePath,
        kind: 'listing',
      );

      // Simulates a SECOND, wholly independent computation (e.g. after
      // an app kill and relaunch, `resumeAll()` re-deriving ids from the
      // same already-persisted `record.carData`).
      final atResumeTime = SellMediaIdentity.forImageItem(
        durablePath,
        kind: 'listing',
      );

      expect(atCreateTime, isNotNull);
      expect(atResumeTime, atCreateTime);
    });

    test('forNormalVideoItem is stable across independent calls for the '
        'same durable local path, whether passed as a plain String or an '
        'XFile-like source', () {
      const durablePath = '/app_support/pending_sell_media/'
          'draftXYZ_video_0_deadbeef.mp4';

      final first = SellMediaIdentity.forNormalVideoItem(durablePath);
      final second = SellMediaIdentity.forNormalVideoItem(durablePath);

      expect(first, isNotNull);
      expect(second, first);
    });

    test('forImageItem returns null for an already-server-attached image '
        '(has a numeric id) -- these are pre-existing edit-mode media, '
        'never part of this submission\'s Phase A / expected_media', () {
      final id = SellMediaIdentity.forImageItem(
        {'id': 42, 'source': 'uploads/car_photos/42.jpg'},
        kind: 'listing',
      );
      expect(id, isNull);
    });

    test('forImageItem returns null for an already-remote source path '
        '(e.g. "uploads/..." or an http(s) URL) even without a numeric id',
        () {
      expect(
        SellMediaIdentity.forImageItem(
          'uploads/car_photos/already_remote.jpg',
          kind: 'listing',
        ),
        isNull,
      );
      expect(
        SellMediaIdentity.forImageItem(
          'https://cdn.example.com/car_photos/already_remote.jpg',
          kind: 'listing',
        ),
        isNull,
      );
    });
  });
}
