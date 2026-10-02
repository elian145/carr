// Section A (real-device evidence, HIGHEST PRIORITY): real Android
// behavior reported that after picking a photo in Sell, the ORIGINAL image
// does NOT appear immediately -- only later, once background plate blur
// has already run.
//
// Root cause (confirmed by reading `sell_step4_logic.dart`): `_pickImages`
// used to `await Future.wait(newFiles.map(_pickedImageMedia))` -- an image
// decode (`XFile.readAsBytes()` + `ui.instantiateImageCodec`) for EVERY
// newly-picked file, to extract width/height for aspect-ratio hinting only
// -- BEFORE the very first `setState` that inserted the picked photos into
// `_selectedImages` (the list the Step4 photo grid actually renders from,
// per `sell_step4_build_photos.dart`). For `content://` sources in
// particular, that decode is a real, user-visible delay. Contrast with
// `_pickDamageImages`, which inserts its picked files into `_damageImages`
// immediately with no such decode -- proving this asymmetry was never
// required for correct rendering.
//
// Fix: `_pickImages` now inserts `ListingImageMedia.map(file)` (no
// width/height) into `_selectedImages` immediately, with the SAME
// zero-`await`-before-setState shape `_pickDamageImages` already used, and
// backfills width/height afterward via `_backfillImageDimensions`
// (`unawaited`, matched back onto `_selectedImages` by path) so it can
// never block or delay the original's first render.
//
// This is a static/source-shape regression test (same convention as
// `sell_no_sync_image_processing_test.dart`) rather than a full widget
// test, because driving the real `image_picker` plugin end-to-end through
// a widget test would only prove this ONE call site stays fixed, not
// guard against the ordering regressing again inside a future edit to the
// same method.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _stripDartComments(String source) {
  final buffer = StringBuffer();
  for (final line in source.split('\n')) {
    final idx = line.indexOf('//');
    buffer.writeln(idx == -1 ? line : line.substring(0, idx));
  }
  return buffer.toString();
}

void main() {
  late String content;

  setUpAll(() {
    final file = File(
      p.join('lib', 'features', 'sell', 'sell_step4_logic.dart'),
    );
    expect(file.existsSync(), isTrue);
    content = _stripDartComments(file.readAsStringSync());
  });

  test(
    '_pickImages inserts newly-picked photos into _selectedImages with NO '
    'decode/await in between the picker returning and that setState -- '
    'exactly like _pickDamageImages already does',
    () {
      final pickImagesStart = content.indexOf('Future<void> _pickImages()');
      final pickDamageImagesStart =
          content.indexOf('Future<void> _pickDamageImages()');
      expect(pickImagesStart, greaterThanOrEqualTo(0));
      expect(pickDamageImagesStart, greaterThan(pickImagesStart));

      final body = content.substring(pickImagesStart, pickDamageImagesStart);

      // Stale-media-after-delete fix (`_ui_media_id` tagging) turned the
      // one-line `.map(ListingImageMedia.map)` into a small inline
      // closure that also assigns each addition a fresh per-pick
      // identity -- still zero `await`s, just more lines; anchor on its
      // still-present start.
      final additionsIdx = body.indexOf(
        'final uiMediaIdsByPath = <String, String>{};',
      );
      expect(
        additionsIdx,
        greaterThanOrEqualTo(0),
        reason: '_pickImages must build the immediate (no-decode) media '
            'list the same way _pickDamageImages inserts its additions '
            'directly',
      );

      final setStateIdx = body.indexOf(
        '_selectedImages = [..._selectedImages, ...additions];',
      );
      expect(setStateIdx, greaterThan(additionsIdx));

      final between = body.substring(additionsIdx, setStateIdx);
      expect(
        between.contains('await'),
        isFalse,
        reason: 'no await may appear between building the immediate media '
            'list and the setState that renders it -- an await here is '
            'exactly the regression that delayed the original photo\'s '
            'first render (e.g. a per-file image decode for '
            'width/height)',
      );

      // The dangerous pattern this fix removed: decoding EVERY file before
      // the first setState.
      expect(
        body.contains(
          'await Future.wait(newFiles.map(_pickedImageMedia))',
        ),
        isFalse,
        reason: 'must never decode every picked file before the first '
            'setState again',
      );
    },
  );

  test(
    'width/height (+ HEIC/HEIF preview) backfill for freshly-picked photos '
    'runs strictly AFTER the immediate setState (so it never delays the '
    'original\'s first render) and strictly BEFORE the durable-copy sync '
    '(so its by-path match -- safe if the user removes/reorders photos '
    'while it is still running -- finds the entry before that path gets '
    'rewritten)',
    () {
      final pickImagesStart = content.indexOf('Future<void> _pickImages()');
      final pickDamageImagesStart =
          content.indexOf('Future<void> _pickDamageImages()');
      final body = content.substring(pickImagesStart, pickDamageImagesStart);

      final backfillCallIdx = body.indexOf(
        'await _backfillImageDimensions(',
      );
      final syncCallIdx = body.indexOf('await _syncMediaDraftToParent();');
      expect(
        backfillCallIdx,
        greaterThanOrEqualTo(0),
        reason: 'the width/height + HEIC preview decode must be awaited '
            'inline in the pick handler -- NOT fired unawaited after the '
            'durable-copy sync, which would rewrite the path this backfill '
            'matches against before it ever runs',
      );
      expect(
        syncCallIdx,
        greaterThan(backfillCallIdx),
        reason: 'the durable-copy sync must run AFTER the backfill '
            'finishes, not before -- otherwise the backfill\'s by-path '
            'match against _selectedImages would already be stale',
      );

      final setStateIdx = body.indexOf(
        '_selectedImages = [..._selectedImages, ...additions];',
      );
      expect(
        backfillCallIdx,
        greaterThan(setStateIdx),
        reason: 'the backfill must still run strictly AFTER the immediate '
            'setState that renders the original -- never before it',
      );

      final backfillStart = content.indexOf(
        'Future<void> _backfillImageDimensions(',
      );
      expect(backfillStart, greaterThanOrEqualTo(0));
      final backfillBody = content.substring(
        backfillStart,
        backfillStart + 1600 > content.length
            ? content.length
            : backfillStart + 1600,
      );
      expect(
        backfillBody.contains(
          'ListingImageMedia.source(item) == file.path',
        ),
        isTrue,
        reason: 'the backfill must match each decoded result back onto '
            '_selectedImages BY PATH, not by a positional index that could '
            'go stale if photos are removed/reordered mid-backfill',
      );
    },
  );

  test(
    '_pickDamageImages (the already-correct reference implementation) is '
    'unchanged: still no decode/await before its own setState',
    () {
      final pickDamageImagesStart =
          content.indexOf('Future<void> _pickDamageImages()');
      final nextMethodStart = content.indexOf(
        'Future<void> _pickVideos()',
        pickDamageImagesStart,
      );
      expect(pickDamageImagesStart, greaterThanOrEqualTo(0));
      expect(nextMethodStart, greaterThan(pickDamageImagesStart));
      final body = content.substring(pickDamageImagesStart, nextMethodStart);

      final setStateIdx = body.indexOf(
        '_damageImages = [..._damageImages, ...additions];',
      );
      expect(setStateIdx, greaterThan(0));
      final before = body.substring(0, setStateIdx);
      expect(
        before.contains('await Future.wait'),
        isFalse,
        reason: '_pickDamageImages must keep inserting picked files with '
            'no batch-decode await before its setState',
      );
    },
  );
}
