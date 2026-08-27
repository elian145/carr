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
}
