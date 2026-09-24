import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:car_listing_app/shared/listings/listing_card_media.dart';
import 'package:car_listing_app/shared/listings/listing_image_media.dart';
import 'package:car_listing_app/shared/listings/listing_to_sell_draft.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';

void main() {
  test('localFile reconstructs picker files from persisted media maps', () {
    final map = ListingImageMedia.map(
      XFile('/tmp/clip.mp4'),
      source: '/data/sell_draft_media/default/video_1.mp4',
    );
    expect(ListingImageMedia.source(map), '/data/sell_draft_media/default/video_1.mp4');
    expect(
      ListingImageMedia.localFile(map)?.path,
      '/data/sell_draft_media/default/video_1.mp4',
    );
    expect(
      ListingImageMedia.localFiles([
        map,
        XFile('/tmp/other.mov'),
        {'source': '/tmp/other.mov'},
      ]).map((f) => f.path).toList(),
      ['/data/sell_draft_media/default/video_1.mp4', '/tmp/other.mov'],
    );
  });

  test('source unwraps Map.toString leaks from draft media', () {
    expect(
      ListingImageMedia.source(
        '{source: /var/mobile/Containers/Data/Application/ABC/tmp/photo.jpg, image_width: 1200}',
      ),
      '/var/mobile/Containers/Data/Application/ABC/tmp/photo.jpg',
    );
    expect(
      ListingImageMedia.localFile(
        '{source: /var/mobile/Containers/Data/Application/ABC/tmp/photo.jpg}',
      )?.path,
      '/var/mobile/Containers/Data/Application/ABC/tmp/photo.jpg',
    );
  });

  test('media map preserves normalized crop metadata', () {
    final media = ListingImageMedia.map(
      'photo.jpg',
      focusY: 0.75,
      width: 900,
      height: 1600,
    );

    expect(ListingImageMedia.source(media), 'photo.jpg');
    expect(ListingImageMedia.focusY(media), 0.75);
    expect(ListingImageMedia.width(media), 900);
    expect(ListingImageMedia.height(media), 1600);
    expect(ListingImageMedia.coverAlignment(media), const Alignment(0, 0.5));
  });

  test('automatic alignment only biases portrait images', () {
    expect(
      ListingImageMedia.coverAlignment({
        'source': 'portrait.jpg',
        'image_width': 900,
        'image_height': 1600,
      }),
      const Alignment(0, 0.4),
    );
    expect(
      ListingImageMedia.coverAlignment({
        'source': 'landscape.jpg',
        'image_width': 1600,
        'image_height': 900,
      }),
      Alignment.center,
    );
    expect(
      ListingImageMedia.coverAlignment({
        'source': 'square.jpg',
        'image_width': 1000,
        'image_height': 1000,
      }),
      Alignment.center,
    );
  });

  test('card media keeps metadata for every carousel image', () {
    final slots = ListingCardMedia.collectFromCar({
      'image_url': 'a.jpg',
      'images': [
        {
          'id': 1,
          'image_url': 'a.jpg',
          'focus_y': 0.8,
          'image_width': 900,
          'image_height': 1600,
        },
        {
          'id': 2,
          'image_url': 'b.jpg',
          'image_width': 1600,
          'image_height': 900,
        },
      ],
    }, resolveNetworkUrl: (value) => 'https://example.test/$value');

    expect(slots, hasLength(2));
    expect(slots.first.metadata?['id'], 1);
    expect(ListingImageMedia.focusY(slots.first.metadata), 0.8);
    expect(slots.last.metadata?['id'], 2);
  });

  test('edit draft preserves server id, dimensions, and crop', () {
    final snapshot = listingToSellDraftSnapshot({
      'id': 'car-1',
      'image_url': 'uploads/a.jpg',
      'images': [
        {
          'id': 42,
          'image_url': 'uploads/a.jpg',
          'focus_y': 0.72,
          'image_width': 900,
          'image_height': 1600,
          'kind': 'listing',
        },
      ],
    });
    final images =
        (snapshot['carData'] as Map<String, dynamic>)['images'] as List;

    expect(images, hasLength(1));
    expect(ListingImageMedia.id(images.single), 42);
    expect(ListingImageMedia.focusY(images.single), 0.72);
    expect(ListingImageMedia.height(images.single), 1600);
  });

  test(
    'edit draft populates existing_video_records from a REAL backend-shaped '
    'listing response (structured {id, video_url, thumbnail_url} objects, '
    'not bare URL strings)',
    () {
      // Shape matches what GET /api/cars/<id> now returns after the video
      // serialization fix (kk/routes/cars.py::_serialize_videos /
      // CarVideo.to_dict()) -- id/video_url/thumbnail_url/duration/order.
      final snapshot = listingToSellDraftSnapshot({
        'id': 'car-1',
        'image_url': 'uploads/a.jpg',
        'images': const [],
        'videos': [
          {
            'id': 601,
            'video_url': 'https://cdn.example.com/car_videos/one.mp4',
            'thumbnail_url': 'https://cdn.example.com/car_videos/one.jpg',
            'duration': 12,
            'order': 0,
          },
          {
            'id': 602,
            'video_url': 'https://cdn.example.com/car_videos/two.mp4',
            'thumbnail_url': 'https://cdn.example.com/car_videos/two.jpg',
            'duration': 30,
            'order': 1,
          },
        ],
      });
      final carData = snapshot['carData'] as Map<String, dynamic>;
      final records = carData['existing_video_records'] as List;
      final paths = carData['videos'] as List;

      expect(records, hasLength(2));
      expect(records[0]['id'], 601);
      expect(records[0]['video_url'], 'https://cdn.example.com/car_videos/one.mp4');
      expect(records[0]['thumbnail_url'], 'https://cdn.example.com/car_videos/one.jpg');
      expect(records[1]['id'], 602);

      // The bare-path list used by the new-video upload pipeline must still
      // be derived correctly from the structured records.
      expect(paths, [
        'https://cdn.example.com/car_videos/one.mp4',
        'https://cdn.example.com/car_videos/two.mp4',
      ]);
    },
  );

  test(
    'edit draft has no existing_video_records when the backend returns no '
    'videos',
    () {
      final snapshot = listingToSellDraftSnapshot({
        'id': 'car-2',
        'image_url': 'uploads/a.jpg',
        'images': const [],
        'videos': const [],
      });
      final carData = snapshot['carData'] as Map<String, dynamic>;

      expect(carData.containsKey('existing_video_records'), isFalse);
    },
  );

  test('resolveDynamicMediaList keeps Android content URIs', () {
    final out = SellDraftMediaPersistence.resolveDynamicMediaList([
      {'source': 'content://media/external/images/media/42'},
      XFile('content://media/external/images/media/43'),
    ]);
    expect(
      out.map(ListingImageMedia.source).toList(),
      [
        'content://media/external/images/media/42',
        'content://media/external/images/media/43',
      ],
    );
  });

  group('regression: Sell media Android content:// rendering bug', () {
    // These cover the "selected photo shows as a placeholder" / "created
    // listing still shows a placeholder" production bug: Android's picker
    // (or the "My Listings" recently-submitted-draft preview) can hand back
    // a `content://` path that `File.existsSync()` cannot confirm, even
    // though the file is genuinely readable via `XFile.readAsBytes()`. Card
    // media collection must not silently drop such an item -- dropping it
    // is indistinguishable, in the UI, from "no photo was ever selected".

    test(
      'collectFromCar keeps a content:// local image slot even though '
      'File.existsSync() cannot confirm it on this (non-Android) host',
      () {
        const contentUri = 'content://media/external/images/media/99';
        final slots = ListingCardMedia.collectFromCar(
          {
            'image_url': contentUri,
            'images': [contentUri],
          },
          resolveNetworkUrl: (value) => 'https://example.test/$value',
        );

        expect(slots, hasLength(1));
        expect(slots.single.filePath, contentUri);
        expect(slots.single.url, isNull);
      },
    );

    test(
      'collectFromCar keeps a content:// XFile image item (not just bare '
      'string sources)',
      () {
        const contentUri = 'content://media/external/images/media/100';
        final slots = ListingCardMedia.collectFromCar(
          {
            'images': [XFile(contentUri)],
          },
          resolveNetworkUrl: (value) => 'https://example.test/$value',
        );

        expect(slots, hasLength(1));
        expect(slots.single.filePath, contentUri);
      },
    );

    test(
      'collectFromCar still drops a local path that is neither on disk nor '
      'a content:// URI (genuinely missing file, not a picker quirk)',
      () {
        final slots = ListingCardMedia.collectFromCar(
          {
            'images': ['/data/sell_draft_media/default/definitely_missing.jpg'],
          },
          resolveNetworkUrl: (value) => 'https://example.test/$value',
        );

        expect(slots, isEmpty);
      },
    );
  });
}
