// Source-shape regression test for `_SellStep5Logic._submitPhaseLocalizedMessage`
// (`lib/features/sell/sell_step5_logic.dart`) -- the Step 5 page-local
// status text shown while `SellCarPage` is mounted during the initial
// synchronous Submit call (a SECOND, page-local rendering of the exact
// same `SellSubmissionPhase` this task's widget test drives through
// `SellSubmissionStatusBanner` -- see
// `test/sell_submission_status_banner_test.dart`).
//
// `_submitPhaseLocalizedMessage` is private (`part of 'sell_flow.dart'`),
// requires a `BuildContext` + this mixin's own `State`, and its only
// caller (`_submitListing`) sits inside the full multi-step Sell wizard
// (`SellCarPage`) -- camera/permission/provider dependencies with no
// existing test scaffold anywhere in this suite (confirmed: no test file
// mounts `SellCarPage`/`SellStep5*` at all). Mounting that page purely to
// exercise a 7-case string-returning `switch` would be exactly the
// "oversized harness" this task's own instructions warn against, for a
// mapping the compiler ALREADY exhaustiveness-checks (verified clean by
// `flutter analyze` when the three new cases were added) and which the
// orchestration tests already prove is *reached* at the phase-callback
// level (`sell_server_transcode_orchestration_test.dart`'s `[SELL RUN] UI
// progress=... phase=uploadingVideoSource|processingVideoOnServer|
// finishingVideoUpload` log lines).
//
// So, mirroring this repo's OWN established convention for exactly this
// class of problem (see `test/sell_step4_immediate_photo_preview_test.dart`'s
// header comment), this proves the SOURCE-LEVEL mapping instead: each of
// the three Phase 3B `case` labels for `SellSubmissionPhase` returns the
// matching `AppLocalizations` getter, with nothing else able to sneak in
// between (e.g. an accidental fallthrough, a swapped getter, or a `return`
// pointing at the wrong phase's string).
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
  late String body;

  setUpAll(() {
    final file = File(p.join('lib', 'features', 'sell', 'sell_step5_logic.dart'));
    expect(file.existsSync(), isTrue);
    final content = _stripDartComments(file.readAsStringSync());

    final methodStart = content.indexOf('_submitPhaseLocalizedMessage(');
    expect(
      methodStart,
      greaterThanOrEqualTo(0),
      reason: '_submitPhaseLocalizedMessage must still exist',
    );
    // Bounded to this one method's body -- up to the next top-level method
    // in the mixin (`_submitListing`), so a match anywhere else in the
    // file can never produce a false pass.
    final nextMethodStart = content.indexOf(
      'Future<SellListingSubmitResult?> _submitListing(',
      methodStart,
    );
    expect(nextMethodStart, greaterThan(methodStart));
    body = content.substring(methodStart, nextMethodStart);
  });

  /// Asserts `case SellSubmissionPhase.<phase>:` is followed (with nothing
  /// but whitespace/other `return`s for OTHER phases in between being
  /// possible, since each case's own `return` must appear strictly before
  /// the NEXT `case` keyword) by `return loc.<getter>;` inside [body].
  void expectCaseReturnsGetter(String phase, String getter) {
    final caseIdx = body.indexOf('case SellSubmissionPhase.$phase:');
    expect(
      caseIdx,
      greaterThanOrEqualTo(0),
      reason: 'missing case for SellSubmissionPhase.$phase',
    );
    final nextCaseIdx = body.indexOf('case SellSubmissionPhase.', caseIdx + 1);
    final caseBody = nextCaseIdx > caseIdx
        ? body.substring(caseIdx, nextCaseIdx)
        : body.substring(caseIdx);
    expect(
      caseBody.contains('return loc.$getter;'),
      isTrue,
      reason: 'SellSubmissionPhase.$phase must return exactly '
          '"loc.$getter;" (found: '
          '${caseBody.replaceAll(RegExp(r'\s+'), ' ').trim()})',
    );
  }

  group(
    'Phase 3B: _submitPhaseLocalizedMessage maps each server-transcode '
    'sub-phase to the matching localization getter',
    () {
      test(
        'uploadingVideoSource -> loc.sellVideoUploadingSource',
        () => expectCaseReturnsGetter(
          'uploadingVideoSource',
          'sellVideoUploadingSource',
        ),
      );

      test(
        'processingVideoOnServer -> loc.sellVideoProcessingOnServer',
        () => expectCaseReturnsGetter(
          'processingVideoOnServer',
          'sellVideoProcessingOnServer',
        ),
      );

      test(
        'finishingVideoUpload -> loc.sellVideoFinishing',
        () => expectCaseReturnsGetter(
          'finishingVideoUpload',
          'sellVideoFinishing',
        ),
      );

      test(
        'the three new cases are distinct from each other and from every '
        'pre-existing case -- no two phases accidentally share the same '
        'getter',
        () {
          const mapping = {
            'creating': null, // ternary, not a single getter -- skipped
            'uploadingPhotos': 'uploadingPhotos',
            'uploadingVideos': 'uploadingVideos',
            'uploadingDamagePhotos': 'uploadingDamagePhotos',
            'uploadingVideoSource': 'sellVideoUploadingSource',
            'processingVideoOnServer': 'sellVideoProcessingOnServer',
            'finishingVideoUpload': 'sellVideoFinishing',
          };
          final getters = mapping.values.whereType<String>().toList();
          expect(
            getters.length,
            getters.toSet().length,
            reason: 'every phase must map to a UNIQUE localization getter',
          );
        },
      );
    },
  );
}
