// Real-device OOM evidence (Sept 2026): attaching ONE photo in the Sell
// flow, BEFORE ever pressing Submit, was enough to crash the `carr` web
// service with "Ran out of memory (used over 512MB)". Root cause: every
// photo/damage-photo pick fired `startBackgroundPlateBlur()`
// (`sell_car_page_plate_blur.dart`), which called
// `AiService.processCarImagesToServerPayload()` -- a fully SYNCHRONOUS
// `POST /api/process-car-images` request (no `async=1`) that ran the whole
// PIL decode / OpenCV plate-detection / Roboflow / re-encode pipeline
// directly inside the single-worker `carr` Gunicorn process, for every
// picked photo, immediately on selection. `SellPhotoPrestage` (the
// Submit-time prestage path) was already fixed to use the async Celery job
// pipeline in an earlier pass -- this was a SEPARATE, previously-missed
// instance of the exact same bug class, on a path that fires even earlier
// (before Submit is ever pressed).
//
// This is a repo-wide static guard, not a widget test: it proves the
// dangerous synchronous entry points (`AiService.processCarImagesToServerPayload`,
// `AiService.processCarImagesToServerPaths`, `AiService.analyzeCarImage`)
// have ZERO call sites anywhere under `lib/` -- so this test fails loudly
// if a future change (by a person OR an LLM) reintroduces a call to one of
// them anywhere in the app, not just in the one file fixed here. A widget
// test driving the actual (private, deeply-nested-mixin) `_blurMediaList`/
// `startBackgroundPlateBlur` methods would only catch a regression in that
// one call site; this catches a regression anywhere.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Removes `//` and `///` line-comment content (keeping line count/shape
/// irrelevant here) so a call pattern mentioned only in prose/doc-comments
/// -- e.g. this repo's own OOM-fix-history comments describing the OLD,
/// now-removed call site -- never produces a false positive. Deliberately
/// simple (does not need to handle `/* */` block comments or strings
/// containing `//`, neither of which this codebase's Dart files rely on
/// for the patterns under test here).
String _stripDartComments(String source) {
  final buffer = StringBuffer();
  for (final line in source.split('\n')) {
    final idx = line.indexOf('//');
    buffer.writeln(idx == -1 ? line : line.substring(0, idx));
  }
  return buffer.toString();
}

void main() {
  test(
    'no file under lib/ calls the synchronous, non-async image-processing '
    'AiService methods (the confirmed carr OOM root cause) -- every Sell '
    'path must use the async Celery job pipeline instead',
    () {
      final libDir = Directory('lib');
      expect(
        libDir.existsSync(),
        isTrue,
        reason: 'expected to run from the Flutter project root',
      );

      // Methods that run (or used to run) fully synchronously inside the
      // `carr` web process. `enqueueCarImagesAsync` (the safe replacement)
      // is deliberately NOT in this list.
      const dangerousCallPatterns = <String>[
        'AiService.processCarImagesToServerPayload(',
        'AiService.processCarImagesToServerPaths(',
        'AiService.analyzeCarImage(',
      ];

      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final code = _stripDartComments(entity.readAsStringSync());
        for (final pattern in dangerousCallPatterns) {
          if (code.contains(pattern)) {
            offenders.add('${p.normalize(entity.path)}: $pattern');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Found a real call site for a synchronous AiService image-'
            'processing method -- this is the exact pattern that OOM\'d '
            '`carr` from a single photo pick before Submit was ever '
            'pressed. Use `AiService.enqueueCarImagesAsync` + '
            '`SellImageJobPolling.awaitImageJobRelPath` instead (see '
            '`SellPhotoPrestage` / `sell_car_page_plate_blur.dart` for the '
            'existing pattern). Offenders:\n${offenders.join('\n')}',
      );
    },
  );

  test(
    'sell_car_page_plate_blur.dart (startBackgroundPlateBlur, fired on '
    'every photo pick before Submit) uses the async job-enqueue + poll '
    'pattern, not the synchronous payload call',
    () {
      final file = File(
        p.join('lib', 'features', 'sell', 'sell_car_page_plate_blur.dart'),
      );
      expect(file.existsSync(), isTrue);
      final content = _stripDartComments(file.readAsStringSync());
      expect(
        content.contains('AiService.enqueueCarImagesAsync('),
        isTrue,
        reason:
            'startBackgroundPlateBlur must enqueue via the async Celery '
            'job pipeline',
      );
      expect(
        content.contains('SellImageJobPolling.awaitImageJobRelPath('),
        isTrue,
        reason:
            'startBackgroundPlateBlur must poll job results the same way '
            'SellPhotoPrestage / SellListingMediaUpload already do',
      );
      expect(
        content.contains('processCarImagesToServerPayload'),
        isFalse,
        reason:
            'the old synchronous call must be fully removed (outside of '
            'historical comments), not merely supplemented',
      );
    },
  );
}
