// Section A regression properties 3, 6, 7, 8, 9 (real-device evidence):
// unit-level proof that `applySellPlateBlurChoice` -- the function that
// commits the user's blur-choice-screen selection onto `carData['images']`
// -- never loses the original reference, correctly picks processed vs.
// original media per the user's choice, tolerates a failed/empty blur
// result, and preserves 1:1 original<->blurred pairing across multiple
// images (including after edits that would shift array positions).
//
// `applySellPlateBlurChoice` lives in `sell_plate_blur_choice.dart`, a
// `part of 'sell_flow.dart'` file -- imported here via the top-level
// `sell_flow.dart` library (a normal importable library, not itself a
// `part of` anything), so it can be unit-tested directly without any
// widget/mixin machinery.
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applySellPlateBlurChoice', () {
    test(
      'property 6: selecting Blurred (useBlurred=true) sets carData[images] '
      'to the processed/blurred media',
      () {
        final carData = <String, dynamic>{
          'original_images': ['orig_1.jpg', 'orig_2.jpg'],
          'blurred_images': ['blurred_1.jpg', 'blurred_2.jpg'],
          'images': ['orig_1.jpg', 'orig_2.jpg'],
        };

        applySellPlateBlurChoice(carData, true);

        expect(carData['images'], ['blurred_1.jpg', 'blurred_2.jpg']);
        expect(carData['use_blurred_plates'], isTrue);
      },
    );

    test(
      'property 5: selecting Unblurred (useBlurred=false) sets '
      'carData[images] to the ORIGINAL media, never the blurred result',
      () {
        final carData = <String, dynamic>{
          'original_images': ['orig_1.jpg', 'orig_2.jpg'],
          'blurred_images': ['blurred_1.jpg', 'blurred_2.jpg'],
          'images': ['blurred_1.jpg', 'blurred_2.jpg'],
        };

        applySellPlateBlurChoice(carData, false);

        expect(carData['images'], ['orig_1.jpg', 'orig_2.jpg']);
        expect(carData['use_blurred_plates'], isFalse);
      },
    );

    test(
      'property 3: after selecting Blurred, original_images is left '
      'completely untouched -- the blur result never overwrites the '
      'original reference, only carData[images] (the active/canonical '
      'field) changes',
      () {
        final carData = <String, dynamic>{
          'original_images': ['orig_1.jpg', 'orig_2.jpg'],
          'blurred_images': ['blurred_1.jpg', 'blurred_2.jpg'],
          'images': ['orig_1.jpg', 'orig_2.jpg'],
        };

        applySellPlateBlurChoice(carData, true);

        expect(
          carData['original_images'],
          ['orig_1.jpg', 'orig_2.jpg'],
          reason: 'original_images must survive a Blurred choice unchanged '
              '-- switching back to Unblurred later must still work',
        );

        // Prove the original is still genuinely recoverable, not just
        // present-but-stale.
        applySellPlateBlurChoice(carData, false);
        expect(carData['images'], ['orig_1.jpg', 'orig_2.jpg']);
      },
    );

    test(
      'property 7: if the blur job produced no result at all '
      '(blurred_images empty/absent -- e.g. the job failed), selecting '
      'Blurred still falls back to the original media instead of '
      'publishing an empty photo list',
      () {
        final carData = <String, dynamic>{
          'original_images': ['orig_1.jpg', 'orig_2.jpg'],
          'blurred_images': <dynamic>[],
          'images': ['orig_1.jpg', 'orig_2.jpg'],
        };

        applySellPlateBlurChoice(carData, true);

        expect(
          carData['images'],
          ['orig_1.jpg', 'orig_2.jpg'],
          reason: 'a failed/empty blur result must never leave the listing '
              'with no usable photos',
        );
      },
    );

    test(
      'property 8: multiple images preserve correct original<->blurred '
      'pairing by position -- selecting Blurred does not shuffle or '
      'mismatch which blurred photo corresponds to which original',
      () {
        final carData = <String, dynamic>{
          'original_images': ['orig_A.jpg', 'orig_B.jpg', 'orig_C.jpg'],
          'blurred_images': ['blurred_A.jpg', 'blurred_B.jpg', 'blurred_C.jpg'],
          'images': ['orig_A.jpg', 'orig_B.jpg', 'orig_C.jpg'],
        };

        applySellPlateBlurChoice(carData, true);
        expect(
          carData['images'],
          ['blurred_A.jpg', 'blurred_B.jpg', 'blurred_C.jpg'],
        );

        applySellPlateBlurChoice(carData, false);
        expect(
          carData['images'],
          ['orig_A.jpg', 'orig_B.jpg', 'orig_C.jpg'],
        );
      },
    );

    test(
      'damage photos use the same original/blurred/fallback logic '
      'independently of listing photos',
      () {
        final carData = <String, dynamic>{
          'original_images': ['orig_1.jpg'],
          'blurred_images': ['blurred_1.jpg'],
          'images': ['orig_1.jpg'],
          'original_damage_images': ['dmg_orig_1.jpg'],
          'blurred_damage_images': <dynamic>[],
          'damage_images': ['dmg_orig_1.jpg'],
        };

        applySellPlateBlurChoice(carData, true);

        expect(carData['images'], ['blurred_1.jpg']);
        expect(
          carData['damage_images'],
          ['dmg_orig_1.jpg'],
          reason: 'damage photos with no blurred result must fall back to '
              'their originals, independent of the listing photos choice',
        );
      },
    );

    test(
      'with no original_images/blurred_images recorded at all, the active '
      '"images" field (whatever it already held) is preserved rather than '
      'being wiped',
      () {
        final carData = <String, dynamic>{
          'images': ['legacy_1.jpg'],
        };

        applySellPlateBlurChoice(carData, false);

        expect(carData['images'], ['legacy_1.jpg']);
      },
    );
  });

  group('sellImagesWithPrimaryFirst (property 9 support)', () {
    test(
      'property 9: reordering (moving a non-zero primary index to the '
      'front) does not drop or duplicate any image -- every original '
      'entry is still present exactly once',
      () {
        final images = ['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg'];

        final reordered = sellImagesWithPrimaryFirst(images, primaryIndex: 2);

        expect(reordered, ['c.jpg', 'a.jpg', 'b.jpg', 'd.jpg']);
        expect(reordered.toSet(), images.toSet());
        expect(reordered.length, images.length);
      },
    );

    test('does not mutate the input list', () {
      final images = ['a.jpg', 'b.jpg', 'c.jpg'];
      sellImagesWithPrimaryFirst(images, primaryIndex: 1);
      expect(images, ['a.jpg', 'b.jpg', 'c.jpg']);
    });

    test('an out-of-range primaryIndex is clamped instead of throwing', () {
      final images = ['a.jpg', 'b.jpg'];
      expect(
        () => sellImagesWithPrimaryFirst(images, primaryIndex: 99),
        returnsNormally,
      );
      final result = sellImagesWithPrimaryFirst(images, primaryIndex: 99);
      expect(result.toSet(), images.toSet());
    });

    test('an empty list returns empty, never throws', () {
      expect(sellImagesWithPrimaryFirst(const []), isEmpty);
    });
  });
}
