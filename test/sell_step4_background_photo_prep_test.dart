// Follow-up to `sell_step4_immediate_photo_preview_test.dart` (Bug A).
//
// Real-device report this fixes: "In Sell Step 1, after I choose multiple
// images, they appear slowly one-by-one while background
// processing/upload is happening." Bug A had already made `_pickImages`
// insert every picked photo into `_selectedImages` with a single
// `setState` and zero awaited I/O beforehand -- so every photo's *grid
// slot* was already appearing instantly. The remaining, separate bug was
// downstream of that:
//
//  1. `_backfillImageDimensions` (which generates the JPEG preview a
//     HEIC/HEIF photo needs before it can render at all -- see
//     `sell_step4_build_photos.dart`'s `previewLocalFile` fallback to the
//     raw, Skia-undecodable HEIC path) ran as a strictly SERIAL
//     `for`-loop, one file at a time. For a batch of HEIC photos this
//     revealed real thumbnails one at a time, each roughly N x (one
//     file's conversion time) after the previous -- visually
//     indistinguishable from "appearing slowly one-by-one" even though
//     every grid slot was already present from the first frame.
//  2. `_pickImages` awaited that entire backfill (plus the durable-copy
//     sync afterward) before resetting `_isImportingMedia` to `false` --
//     and `sell_step4_build.dart` uses `_isImportingMedia` to show a
//     full-screen `AbsorbPointer` + dark scrim + spinner over the ENTIRE
//     Step 1 page, and to disable Previous/Next navigation. So the user
//     could not interact with Step 1 at all until every photo's
//     background work had finished.
//
// The fix (see `sell_step4_logic.dart`):
//  - `_backfillImageDimensions`/`_backfillDamageImagePreviews` now run a
//    small bounded-concurrency worker pool (`_kBackfillConcurrency`)
//    instead of a serial loop.
//  - `_pickImages`/`_pickDamageImages` now reset `_isImportingMedia` to
//    `false` INSIDE the same `setState` that publishes the picked photos,
//    then hand everything else (backfill, durable-copy sync, draft
//    snapshot, blur prestage) to a new `_prepareImagesInBackground`/
//    `_prepareDamageImagesInBackground` helper, invoked via `unawaited`
//    -- so `_pickImages` itself returns, and the page becomes
//    interactive again, without waiting on any of it.
//
// This stays a static/source-shape regression test (same convention and
// rationale as `sell_step4_immediate_photo_preview_test.dart`): driving
// the real `image_picker` plugin, the native HEIC decoder MethodChannel,
// and real file I/O through a full `SellCarPage` widget test is not
// practical here (no such harness exists anywhere in this test suite --
// `SellCarPage` depends on the car catalog, localization delegates, and
// several providers). Each test below is mapped to the corresponding
// item in the task spec's "Tests A-H" list in its own doc comment.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _stripDartComments(String source) {
  // Normalize CRLF -> LF first: this file is edited/read on Windows, and a
  // raw `\r` left attached to each line would otherwise break every exact
  // multi-line substring match below (`\n` in a Dart string literal here
  // never matches a `\r\n` pair in the source file).
  final normalized = source.replaceAll('\r\n', '\n');
  final buffer = StringBuffer();
  for (final line in normalized.split('\n')) {
    final idx = line.indexOf('//');
    buffer.writeln(idx == -1 ? line : line.substring(0, idx));
  }
  return buffer.toString();
}

/// Extracts the body of a top-level (mixin-member) function by name,
/// scanning from its `Future<void> name(` signature to the start of the
/// next `Future<void> ` declaration that follows it in the file. Mirrors
/// the extraction approach `sell_step4_immediate_photo_preview_test.dart`
/// already uses.
String _functionBody(
  String content,
  String signature, {
  required String nextSignature,
}) {
  final start = content.indexOf(signature);
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: 'could not find `$signature` in sell_step4_logic.dart -- has '
        'it been renamed?',
  );
  final nextStart = content.indexOf(nextSignature, start + signature.length);
  expect(
    nextStart,
    greaterThan(start),
    reason: 'could not find `$nextSignature` after `$signature` -- has the '
        'function order in sell_step4_logic.dart changed?',
  );
  return content.substring(start, nextStart);
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

  group('A/B/F: every selected slot publishes in one atomic state update '
      '(picker_returned -> ui_published is synchronous, no per-item '
      'await loop)', () {
    test(
      '_pickImages still has zero awaits between building `additions` and '
      'the setState that publishes them (Bug A invariant, unchanged)',
      () {
        final body = _functionBody(
          content,
          'Future<void> _pickImages()',
          nextSignature: 'Future<void> _prepareImagesInBackground(',
        );
        // Stale-media-after-delete fix (`_ui_media_id` tagging) changed
        // this from a one-line `.map(ListingImageMedia.map)` into a
        // small inline closure that also assigns each addition a fresh
        // per-pick identity -- still zero `await`s, just more lines; the
        // literal below anchors on its still-present start.
        final additionsIdx = body.indexOf(
          'final uiMediaIdsByPath = <String, String>{};',
        );
        final setStateIdx = body.indexOf(
          '_selectedImages = [..._selectedImages, ...additions];',
        );
        expect(additionsIdx, greaterThanOrEqualTo(0));
        expect(setStateIdx, greaterThan(additionsIdx));
        final between = body.substring(additionsIdx, setStateIdx);
        expect(
          between.contains('await'),
          isFalse,
          reason: 'no await may appear between building the immediate '
              'media list and the setState that renders it',
        );
      },
    );

    test(
      '_pickImages APPENDS to the existing _selectedImages list (never '
      'replaces/clears it) -- so a second pick while an earlier batch is '
      'still being prepared keeps the first batch and adds the new one '
      '(spec test F)',
      () {
        final body = _functionBody(
          content,
          'Future<void> _pickImages()',
          nextSignature: 'Future<void> _prepareImagesInBackground(',
        );
        expect(
          body.contains(
            '_selectedImages = [..._selectedImages, ...additions];',
          ),
          isTrue,
          reason: 'must spread the EXISTING list before appending new '
              'additions, never `_selectedImages = additions`',
        );
      },
    );

    test(
      'the publish setState resets _isImportingMedia to false in the SAME '
      'setState call that appends the new photos -- not after awaiting '
      'any background work',
      () {
        final body = _functionBody(
          content,
          'Future<void> _pickImages()',
          nextSignature: 'Future<void> _prepareImagesInBackground(',
        );
        final publishSetStateIdx = body.indexOf(
          'setState(() {\n          _selectedImages = [..._selectedImages, ...additions];',
        );
        expect(publishSetStateIdx, greaterThanOrEqualTo(0));
        final closeIdx = body.indexOf('});', publishSetStateIdx);
        expect(closeIdx, greaterThan(publishSetStateIdx));
        final setStateBlock = body.substring(publishSetStateIdx, closeIdx);
        expect(
          setStateBlock.contains('_isImportingMedia = false'),
          isTrue,
          reason: 'the "Add more photos" button / wizard Next-Previous '
              'nav (gated on _isImportingMedia in sell_step4_build.dart) '
              'must unblock in the exact same frame the gallery is '
              'published, not after background prep finishes',
        );
      },
    );
  });

  group('B/C/H: durable copy, HEIC/dimension backfill, draft snapshot, and '
      'blur prestage are all scheduled via unawaited(...) AFTER the '
      'publish setState -- _pickImages returns without waiting for any '
      'of them', () {
    test(
      '_pickImages hands all post-publish work to '
      '_prepareImagesInBackground via unawaited(...), and does not await '
      'it',
      () {
        final body = _functionBody(
          content,
          'Future<void> _pickImages()',
          nextSignature: 'Future<void> _prepareImagesInBackground(',
        );
        expect(
          body.contains('unawaited(\n          _prepareImagesInBackground('),
          isTrue,
          reason: '_pickImages must not `await _prepareImagesInBackground`'
              ' -- that would re-block the page on background work',
        );
        expect(
          body.contains('await _backfillImageDimensions'),
          isFalse,
          reason: '_pickImages itself must no longer directly await the '
              'backfill -- that now only happens inside '
              '_prepareImagesInBackground, off the UI-blocking path',
        );
        expect(
          body.contains('await _syncMediaDraftToParent()'),
          isFalse,
          reason: '_pickImages itself must no longer directly await the '
              'durable-copy sync',
        );
      },
    );

    test(
      '_prepareImagesInBackground still preserves the required internal '
      'ordering: backfill (HEIC preview/dimensions, matched by ORIGINAL '
      'path) must finish before the durable-copy sync (which rewrites '
      'that path) -- otherwise the by-path match would silently fail',
      () {
        final body = _functionBody(
          content,
          'Future<void> _prepareImagesInBackground(',
          nextSignature: 'void _showMediaPickError(',
        );
        final backfillIdx = body.indexOf('await _backfillImageDimensions(');
        final syncIdx = body.indexOf('await _syncMediaDraftToParent();');
        expect(backfillIdx, greaterThanOrEqualTo(0));
        expect(syncIdx, greaterThan(backfillIdx));
      },
    );

    test(
      '_prepareImagesInBackground calls startBackgroundPlateBlur() via '
      'unawaited(...) -- blur prestage never blocks or is awaited from '
      'the picker flow (spec item 7: "blur prestage must become '
      'background-only")',
      () {
        final body = _functionBody(
          content,
          'Future<void> _prepareImagesInBackground(',
          nextSignature: 'void _showMediaPickError(',
        );
        expect(
          body.contains('unawaited(parentState?.startBackgroundPlateBlur())'),
          isTrue,
        );
        expect(body.contains('await parentState?.startBackgroundPlateBlur'),
            isFalse);
      },
    );

    test(
      'the mounted guard inside _prepareImagesInBackground prevents '
      'setState-after-dispose: it bails out before _syncMediaDraftToParent '
      'if the widget was disposed while backfill was still running (spec '
      'test H)',
      () {
        final body = _functionBody(
          content,
          'Future<void> _prepareImagesInBackground(',
          nextSignature: 'void _showMediaPickError(',
        );
        final backfillIdx = body.indexOf('await _backfillImageDimensions(');
        final mountedGuardIdx = body.indexOf('if (!mounted) return;', backfillIdx);
        final syncIdx = body.indexOf('await _syncMediaDraftToParent();');
        expect(mountedGuardIdx, greaterThan(backfillIdx));
        expect(syncIdx, greaterThan(mountedGuardIdx));
      },
    );
  });

  group('D: failure behavior -- a background failure never removes an '
      'already-published photo', () {
    test(
      '_prepareImagesInBackground wraps its entire body in try/catch and '
      'reports failures non-fatally instead of rethrowing (a thrown '
      'error here must never propagate back and never undoes the already'
      '-applied setState)',
      () {
        final body = _functionBody(
          content,
          'Future<void> _prepareImagesInBackground(',
          nextSignature: 'void _showMediaPickError(',
        );
        expect(body.contains('try {'), isTrue);
        expect(body.contains('} catch (e, st) {'), isTrue);
        expect(body.contains('logNonFatal(e, st);'), isTrue);
        expect(
          RegExp(r'\}\s*catch[\s\S]*rethrow').hasMatch(body),
          isFalse,
          reason: '_prepareImagesInBackground must never rethrow -- it is '
              'fire-and-forget (unawaited) so a rethrow would only '
              'surface as an unhandled async error, never actually '
              'reach the user or undo the publish',
        );
      },
    );

    test(
      '_backfillImageDimensions matches each background result back onto '
      '_selectedImages BY PATH and skips (never crashes/removes) an item '
      'that is no longer found -- covers both "removed while in flight" '
      '(spec test G) and "one failed item among several" without '
      'disturbing the others',
      () {
        final body = _functionBody(
          content,
          'Future<void> _backfillImageDimensions(',
          nextSignature: 'Future<void> _backfillDamageImagePreviews(',
        );
        expect(
          body.contains('ListingImageMedia.source(item) == file.path'),
          isTrue,
        );
        expect(body.contains('if (idx == -1) continue;'), isTrue);
        expect(
          body.contains('_selectedImages.removeAt') ||
              body.contains('_selectedImages.remove('),
          isFalse,
          reason: 'the backfill worker must never remove an entry -- only '
              'ever replace one in place via `_selectedImages[idx] = '
              'enriched`',
        );
      },
    );
  });

  group('E/concurrency: background persistence runs with bounded '
      'concurrency, not strictly serial and not unbounded', () {
    test(
      '_backfillImageDimensions no longer has a strictly serial '
      '`for (final file in files) { ... await ... }` loop -- it now runs '
      'a bounded pool of `worker()` coroutines via Future.wait',
      () {
        final body = _functionBody(
          content,
          'Future<void> _backfillImageDimensions(',
          nextSignature: 'Future<void> _backfillDamageImagePreviews(',
        );
        expect(
          body.contains('for (final file in files) {'),
          isFalse,
          reason: 'the old strictly-serial loop (one HEIC conversion at a '
              'time, applied with its own setState before starting the '
              'next) is exactly what caused thumbnails to reveal '
              'one-by-one -- it must be gone',
        );
        expect(body.contains('Future<void> worker() async {'), isTrue);
        expect(
          body.contains('await Future.wait(List.generate(workerCount'),
          isTrue,
        );
        expect(
          body.contains('_kBackfillConcurrency'),
          isTrue,
          reason: 'concurrency must be bounded by a fixed constant, not '
              'unbounded (e.g. Future.wait(files.map(...)) would start '
              'every conversion at once)',
        );
      },
    );

    test(
      '_kBackfillConcurrency is a small, sane bound (per spec: "e.g. 3-4 '
      'concurrent jobs")',
      () {
        final match =
            RegExp(r'const int _kBackfillConcurrency = (\d+);').firstMatch(
          content,
        );
        expect(match, isNotNull);
        final value = int.parse(match!.group(1)!);
        expect(value, greaterThanOrEqualTo(2));
        expect(value, lessThanOrEqualTo(8));
      },
    );

    test(
      'each backfill worker replaces its item IN PLACE at its matched '
      'index -- finishing out of order (spec test E) cannot reorder '
      '_selectedImages, since nothing ever re-sorts or re-appends it',
      () {
        final body = _functionBody(
          content,
          'Future<void> _backfillImageDimensions(',
          nextSignature: 'Future<void> _backfillDamageImagePreviews(',
        );
        expect(
          body.contains('_selectedImages[idx] = enriched;'),
          isTrue,
          reason: 'each worker must replace its own matched slot in place '
              '(by idx), never re-sort/re-append the list',
        );
      },
    );

    test(
      'the damage-photo backfill got the identical bounded-concurrency '
      'treatment (consistency -- damage photos share the exact same '
      'architecture and would otherwise regress the same way)',
      () {
        final body = _functionBody(
          content,
          'Future<void> _backfillDamageImagePreviews(',
          nextSignature: 'Future<void> _removePhotoAt(',
        );
        expect(body.contains('for (final file in files) {'), isFalse);
        expect(body.contains('Future<void> worker() async {'), isTrue);
        expect(body.contains('_kBackfillConcurrency'), isTrue);
      },
    );
  });

  group('Reference implementation unchanged (_pickDamageImages mirrors '
      '_pickImages\' fixes)', () {
    test(
      '_pickDamageImages also resets _isImportingMedia inside its publish '
      'setState and defers everything else to '
      '_prepareDamageImagesInBackground via unawaited(...)',
      () {
        final body = _functionBody(
          content,
          'Future<void> _pickDamageImages()',
          nextSignature: 'Future<void> _prepareDamageImagesInBackground(',
        );
        final publishSetStateIdx = body.indexOf(
          'setState(() {\n          _damageImages = [..._damageImages, ...additions];',
        );
        expect(publishSetStateIdx, greaterThanOrEqualTo(0));
        final closeIdx = body.indexOf('});', publishSetStateIdx);
        final setStateBlock = body.substring(publishSetStateIdx, closeIdx);
        expect(setStateBlock.contains('_isImportingMedia = false'), isTrue);
        expect(
          body.contains(
            'unawaited(\n          _prepareDamageImagesInBackground(',
          ),
          isTrue,
        );
        expect(body.contains('await _backfillDamageImagePreviews'), isFalse);
      },
    );
  });
}
