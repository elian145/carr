import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/app/widgets/listing_hero_focus.dart';

void main() {
  group('listingHeroAlignmentFor', () {
    test('centers legacy images without dimensions', () {
      expect(listingHeroAlignmentFor(null), Alignment.center);
      expect(listingHeroAlignmentFor({}), Alignment.center);
    });

    test('biases portrait images down and centers landscape images', () {
      expect(
        listingHeroAlignmentFor({'image_width': 1000, 'image_height': 1600}),
        const Alignment(0, 0.4),
      );
      expect(
        listingHeroAlignmentFor({'image_width': 1600, 'image_height': 1000}),
        Alignment.center,
      );
    });

    test('uses focus_y when present', () {
      final a = listingHeroAlignmentFor({'focus_y': 0.7, 'focus_x': 0.5});
      expect(a.x, closeTo(0.0, 0.001));
      expect(a.y, closeTo(0.4, 0.001));
    });

    test('uses car_bbox center when present', () {
      final a = listingHeroAlignmentFor({
        'car_bbox': {'left': 0.1, 'top': 0.4, 'width': 0.8, 'height': 0.4},
      });
      // center x=0.5 → 0, center y=0.6 → 0.2
      expect(a.x, closeTo(0.0, 0.001));
      expect(a.y, closeTo(0.2, 0.001));
    });

    test('saved focus takes precedence over a detected car box', () {
      final a = listingHeroAlignmentFor({
        'focus_y': 0.8,
        'car_bbox': {'left': 0.1, 'top': 0.1, 'width': 0.8, 'height': 0.2},
      });
      expect(a.y, closeTo(0.6, 0.001));
    });
  });

  group('expandCarBBox', () {
    test('pads by 8% of box size and clamps', () {
      const box = ListingHeroCarBBox(
        left: 0.2,
        top: 0.2,
        width: 0.5,
        height: 0.5,
      );
      final padded = expandCarBBox(box, paddingFraction: 0.08);
      expect(padded.left, closeTo(0.16, 0.001));
      expect(padded.top, closeTo(0.16, 0.001));
      expect(padded.width, closeTo(0.58, 0.001));
      expect(padded.height, closeTo(0.58, 0.001));
    });
  });

  group('resolveHeroCoverSourceRect', () {
    test('keeps padded car inside crop and prefers lower framing', () {
      const box = ListingHeroCarBBox(
        left: 0.1,
        top: 0.55,
        width: 0.8,
        height: 0.35,
      );
      final crop = resolveHeroCoverSourceRect(
        viewportAspect: 16 / 9,
        carBBox: box,
      );
      final padded = expandCarBBox(box);
      expect(crop.left, lessThanOrEqualTo(padded.left + 0.001));
      expect(crop.top, lessThanOrEqualTo(padded.top + 0.001));
      expect(
        crop.right,
        greaterThanOrEqualTo(padded.left + padded.width - 0.001),
      );
      expect(
        crop.bottom,
        greaterThanOrEqualTo(padded.top + padded.height - 0.001),
      );
      expect(crop.width / crop.height, closeTo(16 / 9, 0.05));
      // Car should dominate visible height (~70–90%).
      final fill = padded.height / crop.height;
      expect(fill, greaterThanOrEqualTo(0.65));
      expect(fill, lessThanOrEqualTo(0.95));
    });
  });

  group('parseListingHeroCarBBox', () {
    test('parses normalized list as l,t,w,h', () {
      final box = parseListingHeroCarBBox([0.1, 0.2, 0.5, 0.4]);
      expect(box, isNotNull);
      expect(box!.left, 0.1);
      expect(box.top, 0.2);
      expect(box.width, 0.5);
      expect(box.height, 0.4);
    });

    test('parses Roboflow-style center prediction', () {
      final box = parseListingHeroCarBBox({
        'detection': {
          'predictions': [
            {
              'x': 300.0,
              'y': 400.0,
              'width': 200.0,
              'height': 100.0,
              'confidence': 0.9,
              'class': 'car',
            },
          ],
          'image': {'width': 600.0, 'height': 800.0},
        },
      });
      expect(box, isNotNull);
      expect(box!.left, closeTo(200 / 600, 0.01));
      expect(box.top, closeTo(350 / 800, 0.01));
      expect(box.width, closeTo(200 / 600, 0.01));
      expect(box.height, closeTo(100 / 800, 0.01));
    });
  });
}
