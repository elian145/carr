// Regression test for `mergeBlurResultsIntoOriginals`
// (`lib/features/sell/sell_plate_blur_merge.dart`).
//
// Root-cause bug this proves fixed: `_blurMediaList`
// (`sell_car_page_plate_blur.dart`) only sends the LOCAL-file subset of
// `originals` to the async blur job -- already-remote items (e.g.
// pre-existing edit-mode photos already attached to the listing) are
// filtered out by `ListingImageMedia.localFile()` before the job is
// enqueued, so the blur job's per-item results only ever cover that
// filtered subset, in the filtered subset's own order.
//
// The OLD code wrote `relPaths[i]` back to `originals[i]` directly --
// correct ONLY when `originals` is ALL local files (a first-time, brand
// new listing with nothing already remote). As soon as `originals` mixes
// a remote item with local ones (the ordinary "edit an existing listing,
// add one more photo" case), `i` walks the FILTERED list's indices while
// `originals[i]` is read from the UNFILTERED list -- silently pairing each
// blur result with the WRONG original item, and/or dropping trailing
// remote items from the returned list entirely. User-visible symptom:
// a remote photo's `source` gets overwritten with a blurred output that
// actually belongs to a *different* photo -- e.g. exactly the reported
// "picked unblurred, still got a blurred image attached" bug, whenever
// the blurred_images list (built by this exact code) desyncs from
// original_images's positions.
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeBlurResultsIntoOriginals', () {
    test('all-local originals: each item gets its own blur result back '
        'at its own position (baseline, no remote items involved)', () {
      final originals = <dynamic>[
        {'source': '/local/a.jpg'},
        {'source': '/local/b.jpg'},
        {'source': '/local/c.jpg'},
      ];
      final result = mergeBlurResultsIntoOriginals(
        originals: originals,
        localIndices: const [0, 1, 2],
        relPaths: const ['uploads/blurred_a.jpg', 'uploads/blurred_b.jpg', 'uploads/blurred_c.jpg'],
      );
      expect(result.length, 3);
      expect(result[0]['source'], 'uploads/blurred_a.jpg');
      expect(result[1]['source'], 'uploads/blurred_b.jpg');
      expect(result[2]['source'], 'uploads/blurred_c.jpg');
    });

    test('mixed remote + local originals: the REMOTE item is preserved '
        'unchanged at its own position, and the LOCAL item is blurred at '
        'ITS OWN position -- not swapped/misaligned between the two', () {
      // Position 0 is already-remote (e.g. a pre-existing edit-mode
      // photo); position 1 is a newly-added local file. Only position 1
      // is ever sent to the blur job, so `localIndices == [1]` and
      // `relPaths` has exactly one entry, for that one job.
      final originals = <dynamic>[
        {'source': 'uploads/existing_remote_photo.jpg'},
        {'source': '/local/new_photo.jpg'},
      ];
      final result = mergeBlurResultsIntoOriginals(
        originals: originals,
        localIndices: const [1],
        relPaths: const ['uploads/blurred_new_photo.jpg'],
      );
      expect(result.length, 2);
      // The remote item at position 0 must be UNTOUCHED -- this is the
      // exact assertion that fails under the old, misaligned code (which
      // would overwrite position 0's `source` with the blur result that
      // actually belongs to position 1).
      expect(result[0]['source'], 'uploads/existing_remote_photo.jpg');
      // The local item at position 1 must carry ITS OWN blur result.
      expect(result[1]['source'], 'uploads/blurred_new_photo.jpg');
    });

    test('mixed remote + local originals with the local item FIRST: the '
        'remote item further down the list is not dropped/overwritten', () {
      final originals = <dynamic>[
        {'source': '/local/new_photo.jpg'},
        {'source': 'uploads/existing_remote_photo.jpg'},
        {'source': 'uploads/another_existing_remote_photo.jpg'},
      ];
      final result = mergeBlurResultsIntoOriginals(
        originals: originals,
        localIndices: const [0],
        relPaths: const ['uploads/blurred_new_photo.jpg'],
      );
      expect(result.length, 3);
      expect(result[0]['source'], 'uploads/blurred_new_photo.jpg');
      expect(result[1]['source'], 'uploads/existing_remote_photo.jpg');
      expect(result[2]['source'], 'uploads/another_existing_remote_photo.jpg');
    });

    test('multiple local items interleaved with remote items: each local '
        'result lands at its own original index, remote items untouched', () {
      final originals = <dynamic>[
        {'source': 'uploads/remote_0.jpg'},
        {'source': '/local/local_1.jpg'},
        {'source': 'uploads/remote_2.jpg'},
        {'source': '/local/local_3.jpg'},
      ];
      final result = mergeBlurResultsIntoOriginals(
        originals: originals,
        localIndices: const [1, 3],
        relPaths: const ['uploads/blurred_1.jpg', 'uploads/blurred_3.jpg'],
      );
      expect(result[0]['source'], 'uploads/remote_0.jpg');
      expect(result[1]['source'], 'uploads/blurred_1.jpg');
      expect(result[2]['source'], 'uploads/remote_2.jpg');
      expect(result[3]['source'], 'uploads/blurred_3.jpg');
    });

    test('per-item blur failure (null relPath) falls back to the ORIGINAL '
        'item unchanged, at that item\'s own position only', () {
      final originals = <dynamic>[
        {'source': '/local/a.jpg'},
        {'source': '/local/b.jpg'},
      ];
      final result = mergeBlurResultsIntoOriginals(
        originals: originals,
        localIndices: const [0, 1],
        relPaths: const [null, 'uploads/blurred_b.jpg'],
      );
      expect(result[0]['source'], '/local/a.jpg');
      expect(result[1]['source'], 'uploads/blurred_b.jpg');
    });

    test('per-item blur failure (empty relPath) also falls back to the '
        'original item unchanged', () {
      final originals = <dynamic>[
        {'source': '/local/a.jpg'},
      ];
      final result = mergeBlurResultsIntoOriginals(
        originals: originals,
        localIndices: const [0],
        relPaths: const [''],
      );
      expect(result[0]['source'], '/local/a.jpg');
    });

    test('no local items at all (localIndices empty): originals returned '
        'unchanged', () {
      final originals = <dynamic>[
        {'source': 'uploads/remote_0.jpg'},
        {'source': 'uploads/remote_1.jpg'},
      ];
      final result = mergeBlurResultsIntoOriginals(
        originals: originals,
        localIndices: const [],
        relPaths: const [],
      );
      expect(result.length, 2);
      expect(result[0]['source'], 'uploads/remote_0.jpg');
      expect(result[1]['source'], 'uploads/remote_1.jpg');
    });

    test('empty originals returns an empty list', () {
      final result = mergeBlurResultsIntoOriginals(
        originals: const [],
        localIndices: const [],
        relPaths: const [],
      );
      expect(result, isEmpty);
    });

    test('defensive: mismatched localIndices/relPaths lengths never throws '
        'and only processes the overlapping prefix', () {
      final originals = <dynamic>[
        {'source': '/local/a.jpg'},
        {'source': '/local/b.jpg'},
      ];
      final result = mergeBlurResultsIntoOriginals(
        originals: originals,
        localIndices: const [0, 1],
        relPaths: const ['uploads/blurred_a.jpg'], // shorter than localIndices
      );
      expect(result[0]['source'], 'uploads/blurred_a.jpg');
      expect(result[1]['source'], '/local/b.jpg');
    });

    test('preserves other fields (focus_y/dimensions) from the original '
        'item when writing the blurred source at the correct position', () {
      final originals = <dynamic>[
        {'source': 'uploads/remote_0.jpg'},
        {
          'source': '/local/new_photo.jpg',
          'focus_y': 0.3,
          'image_width': 800,
          'image_height': 600,
        },
      ];
      final result = mergeBlurResultsIntoOriginals(
        originals: originals,
        localIndices: const [1],
        relPaths: const ['uploads/blurred_new_photo.jpg'],
      );
      expect(result[1]['source'], 'uploads/blurred_new_photo.jpg');
      expect(result[1]['focus_y'], 0.3);
      expect(result[1]['image_width'], 800);
      expect(result[1]['image_height'], 600);
      // Untouched remote item keeps its original map identity/content.
      expect(result[0]['source'], 'uploads/remote_0.jpg');
    });
  });
}
