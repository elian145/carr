// APPLY-CHOICE-TIMING bug (found while investigating a real-device report
// that a new listing submitted with "unblurred" explicitly chosen still
// uploaded blurred photos): `_loadMediaDraft()` in `sell_step4_logic.dart`
// runs from `initState()` -- i.e. every time the Photos step widget is
// (re)created, which includes revisiting Photos (e.g. tapping "Previous"
// back to it, then "Next" forward again) after the user has already made a
// blur choice on the plate-blur-choice step.
//
// Before this fix, the tail of `_loadMediaDraft()` unconditionally set
// `parentState.carData['images'] = List<dynamic>.from(mergedImages)` (the
// ORIGINALS), completely ignoring `carData['use_blurred_plates']`. So a
// user who explicitly chose "blurred", then merely revisited the Photos
// step and moved forward again with no further action, would silently have
// their listing's active `images` list reset back to the originals -- while
// `use_blurred_plates` stayed `true`, leaving the two flags mismatched.
//
// This is exactly the bug class explicitly asked about: "a later
// restore/reload/rebuild step overwrites carData['images']". The byte-level
// service-layer tests in
// `test/sell_new_listing_unblurred_upload_bytes_test.dart` proved the
// create->Phase A->upload pipeline itself is correct for a single
// continuous pass; THIS test guards the widget-reload path that feeds that
// pipeline its `carData['images']` in the first place.
//
// This is a static/source-shape regression test (same convention as
// `test/sell_step4_immediate_photo_preview_test.dart`) rather than a full
// widget test, because mounting the entire multi-step `SellCarPage` wizard
// end-to-end (photo pick -> background blur -> blur-choice page -> navigate
// back to Photos -> navigate forward -> submit) would require driving
// `image_picker`, the Celery-style background blur job, and full wizard
// PageView navigation together; a source-shape assertion on the exact
// choice-respecting call this fix introduced still guards against the
// unconditional-overwrite regression coming back.
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
    '_loadMediaDraft re-derives carData[images]/damage_images from '
    'use_blurred_plates (via applySellPlateBlurChoice) instead of '
    'unconditionally forcing them back to the originals every time this '
    'step widget reloads',
    () {
      final loadDraftStart = content.indexOf(
        'Future<void> _loadMediaDraft()',
      );
      final nextMethodStart = content.indexOf(
        'List<dynamic> _persistedOrLiveMedia(',
      );
      expect(loadDraftStart, greaterThanOrEqualTo(0));
      expect(nextMethodStart, greaterThan(loadDraftStart));
      final body = content.substring(loadDraftStart, nextMethodStart);

      final originalImagesIdx = body.indexOf(
        "parentState.carData['original_images'] =",
      );
      expect(originalImagesIdx, greaterThanOrEqualTo(0));

      final guardIdx = body.indexOf(
        "parentState.carData['use_blurred_plates'] is bool",
        originalImagesIdx,
      );
      expect(
        guardIdx,
        greaterThan(originalImagesIdx),
        reason: 'the reload path must check the already-recorded blur '
            'choice before deciding what the active images list becomes',
      );

      final applyChoiceIdx = body.indexOf(
        'applySellPlateBlurChoice(',
        guardIdx,
      );
      expect(
        applyChoiceIdx,
        greaterThan(guardIdx),
        reason: 'when a blur choice is already recorded, the reload path '
            'must re-derive images/damage_images through the same '
            'applySellPlateBlurChoice used everywhere else, not '
            're-implement its own (potentially inconsistent) logic',
      );

      // The exact unconditional-overwrite regression this fix removed:
      // setting `images` straight from `mergedImages` with NO guard at
      // all must never reappear before the use_blurred_plates check.
      final unguardedOverwrite = body.substring(0, guardIdx).contains(
        "parentState.carData['images'] = List<dynamic>.from(mergedImages);",
      );
      expect(
        unguardedOverwrite,
        isFalse,
        reason: 'carData[images] must never be force-set to the originals '
            'BEFORE checking whether a blurred choice is already recorded '
            '-- doing so silently reverts an already-made "blurred" '
            'choice back to unblurred purely from revisiting this step',
      );

      // The fallback (only for a truly fresh draft, before any choice has
      // ever been recorded) must remain gated behind an `else`, not run
      // unconditionally alongside the choice-respecting branch.
      final elseIdx = body.indexOf('} else {', guardIdx);
      expect(elseIdx, greaterThan(applyChoiceIdx));
      final fallbackOverwriteIdx = body.indexOf(
        "parentState.carData['images'] = List<dynamic>.from(mergedImages);",
        elseIdx,
      );
      expect(
        fallbackOverwriteIdx,
        greaterThan(elseIdx),
        reason: 'the originals-fallback must only run in the else branch, '
            'i.e. only when no blur choice has been recorded yet',
      );
    },
  );
}
