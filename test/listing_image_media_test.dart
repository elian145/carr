import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/listings/listing_card_media.dart';
import 'package:car_listing_app/shared/listings/listing_image_media.dart';
import 'package:car_listing_app/shared/listings/listing_to_sell_draft.dart';

void main() {
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
}
