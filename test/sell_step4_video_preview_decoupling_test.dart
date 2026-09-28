// Sell-flow video preview/transcode decoupling fix.
//
// Real-device evidence: a Samsung Galaxy A17's Dolby Vision 4K video plays
// fine in the phone's Gallery app, but CarNet's local compression
// correctly cannot transcode it on-device (`SellVideoPrepareStatus
// .requiresServerTranscode`). Server-side transcoding works after
// submission -- but the video was completely INVISIBLE in the Sell UI
// until the whole listing was submitted and the server transcode job
// finished.
//
// Root cause (confirmed by reading `sell_step4_logic.dart` and
// `sell_step4_build_videos.dart`): a freshly-picked video was never added
// to `_selectedVideos` (the ONLY list `sell_step4_build_videos.dart`
// rendered from) until AFTER `SellVideoCompression.prepare()` finished --
// and a video classified `requiresServerTranscode` was staged only into
// `carData['server_transcode_videos']`, a key written by `_pickVideos`
// and read only by the upload pipeline (`sell_listing_media_upload.dart`
// / `pending_sell_submission_service.dart`), NEVER by any UI-rendering
// code. So that class of video stayed invisible in the grid no matter how
// long the seller waited on the Sell step, and, worse, had no gap between
// picking it and Submit during which the seller could even confirm the
// right file was selected.
//
// Fix (see `sell_step4_logic.dart::_pickVideos` for the full contract in
// its doc comment):
//   - Every picked candidate's UNTOUCHED original `XFile` is inserted into
//     `_selectedVideos` immediately -- no `await` between the picker
//     returning and that `setState` -- so the existing video-grid tile
//     (thumbnail via `generateVideoThumbnail` + tap-to-play via
//     `ListingPreviewGalleryPage` -> `GalleryEmbeddedVideoPlayer` ->
//     `VideoPlayerController.file`) renders/plays the ORIGINAL local file
//     right away, using entirely EXISTING playback infrastructure.
//   - Once `SellVideoCompression.prepare()` resolves, the entry is
//     reconciled in place: swapped for the compressed file, removed on
//     failure/too-long/still-too-large, or -- for
//     `requiresServerTranscode` -- migrated atomically (single `setState`)
//     from `_selectedVideos` into the new `_pendingServerTranscodeVideos`
//     field, so the preview tile never visibly disappears; it only
//     switches which backing list renders it. Classification only ever
//     affects the SUBMISSION path (`carData['server_transcode_videos']`,
//     read by `SellServerTranscodeVideoRunner` -- completely unchanged),
//     never the preview.
//   - `_pendingServerTranscodeVideos` is rendered by
//     `sell_step4_build_videos.dart` with the EXACT SAME thumbnail +
//     tap-to-play tile pattern as `_selectedVideos`, sourced from
//     `ServerTranscodeVideoSpec.localSourcePath` -- the same original
//     local file, read directly off disk; nothing is uploaded or
//     server-transcoded merely to build a preview.
//
// Section A below is a static/source-shape regression test (same
// convention as `sell_step4_immediate_photo_preview_test.dart`) proving
// the `_pickVideos()` ordering/reconciliation contract, since driving the
// real `image_picker` + native on-device compression plugin end-to-end
// through a widget test would only prove this one call site, not guard
// against the ordering regressing again inside a future edit.
//
// Section B drives the real Sell wizard widget tree with a
// `requiresServerTranscode` video staged the SAME way `_pickVideos`
// stages one (via `carData['server_transcode_videos']`, exactly as
// `_loadMediaDraft`'s resume branch restores it) to prove: the preview
// renders even with zero `_selectedVideos`/`_existingServerVideos`
// entries (classification never hides the preview), and removing it is a
// purely local, no-backend-call operation (unlike removing an
// already-uploaded server video).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

String _stripDartComments(String source) {
  final buffer = StringBuffer();
  for (final line in source.split('\n')) {
    final idx = line.indexOf('//');
    buffer.writeln(idx == -1 ? line : line.substring(0, idx));
  }
  return buffer.toString();
}

void main() {
  group('Section A: _pickVideos preview/reconciliation source-shape contract', () {
    late String content;

    setUpAll(() {
      final file = File(
        p.join('lib', 'features', 'sell', 'sell_step4_logic.dart'),
      );
      expect(file.existsSync(), isTrue);
      content = _stripDartComments(file.readAsStringSync());
    });

    String pickVideosBody() {
      final start = content.indexOf('Future<void> _pickVideos()');
      final end = content.indexOf(
        'void _removeSelectedVideoByPath(',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      return content.substring(start, end);
    }

    test(
      'newly-picked candidates are inserted into _selectedVideos with NO '
      'await in between the picker resolving candidates and that '
      'setState -- the original file must render immediately',
      () {
        final body = pickVideosBody();

        final candidatesResolvedIdx = body.indexOf(
          'if (candidates.isEmpty) {',
        );
        final insertIdx = body.indexOf(
          '_selectedVideos.addAll(candidates);',
        );
        expect(candidatesResolvedIdx, greaterThanOrEqualTo(0));
        expect(insertIdx, greaterThan(candidatesResolvedIdx));

        final between = body.substring(candidatesResolvedIdx, insertIdx);
        expect(
          between.contains('await'),
          isFalse,
          reason: 'no await (duration probe, SellVideoCompression.prepare, '
              'server staging, etc.) may run before the immediate-preview '
              'setState -- that is exactly the regression that hid the '
              'original video until compression/server-transcode finished',
        );
      },
    );

    test(
      'the immediate-preview insertion happens before the duration probe '
      'and SellVideoCompression.prepare() calls, not after',
      () {
        final body = pickVideosBody();
        final insertIdx = body.indexOf(
          '_selectedVideos.addAll(candidates);',
        );
        final probeIdx = body.indexOf('SellVideoCompression.probe(');
        final prepareIdx = body.indexOf('SellVideoCompression.prepare(');
        expect(insertIdx, greaterThanOrEqualTo(0));
        expect(probeIdx, greaterThan(insertIdx));
        expect(prepareIdx, greaterThan(insertIdx));
      },
    );

    test(
      'requiresServerTranscode migrates the entry from _selectedVideos to '
      '_pendingServerTranscodeVideos inside a single setState, never '
      'leaving a gap where the video is in neither list',
      () {
        final body = pickVideosBody();
        final caseIdx = body.indexOf(
          'case SellVideoPrepareStatus.requiresServerTranscode:',
        );
        expect(caseIdx, greaterThanOrEqualTo(0));
        final caseBody = body.substring(caseIdx);

        final setStateIdx = caseBody.indexOf('setState(() {');
        final removeIdx = caseBody.indexOf(
          '_selectedVideos.removeWhere((f) => f.path == candidate.path);',
        );
        final addIdx = caseBody.indexOf(
          '_pendingServerTranscodeVideos.add(spec);',
        );
        expect(setStateIdx, greaterThanOrEqualTo(0));
        expect(
          removeIdx,
          greaterThan(setStateIdx),
          reason: 'removal from _selectedVideos must happen inside the '
              'setState, not before/after it',
        );
        expect(
          addIdx,
          greaterThan(removeIdx),
          reason: 'the migration into _pendingServerTranscodeVideos must '
              'be part of the SAME setState as the removal, so there is '
              'never a rendered frame where the video is in neither list',
        );

        // Both mutations must be strictly inside the same setState body
        // (i.e. before its closing) -- a crude but effective check: no
        // intervening top-level `setState(() {` between them.
        final betweenRemoveAndAdd = caseBody.substring(removeIdx, addIdx);
        expect(betweenRemoveAndAdd.contains('setState(() {'), isFalse);
      },
    );

    test(
      'a video that requires server transcode is NEVER left in '
      '_selectedVideos (which drives the normal <=100MB multipart upload) '
      '-- it must not be uploaded through both paths',
      () {
        final body = pickVideosBody();
        final caseIdx = body.indexOf(
          'case SellVideoPrepareStatus.requiresServerTranscode:',
        );
        final nextCaseIdx = body.indexOf('case SellVideoPrepareStatus.', caseIdx + 1);
        final caseBody = body.substring(
          caseIdx,
          nextCaseIdx == -1 ? body.length : nextCaseIdx,
        );
        expect(
          caseBody.contains('_selectedVideos.removeWhere'),
          isTrue,
        );
        expect(
          caseBody.contains('prepared.add(result.file!)'),
          isFalse,
          reason: 'requiresServerTranscode must never add to `prepared` '
              '(the list synced into _selectedVideos for upload)',
        );
      },
    );

    test(
      'compressed results are swapped into the existing preview entry in '
      'place, not appended as a second/duplicate tile',
      () {
        final body = pickVideosBody();
        final caseIdx = body.indexOf('case SellVideoPrepareStatus.compressed:');
        expect(caseIdx, greaterThanOrEqualTo(0));
        final nextCaseIdx = body.indexOf('case SellVideoPrepareStatus.', caseIdx + 1);
        final caseBody = body.substring(caseIdx, nextCaseIdx);
        expect(
          caseBody.contains(
            '_replaceSelectedVideoByPath(candidate.path, result.file!);',
          ),
          isTrue,
        );
      },
    );

    test(
      'the per-listing video cap counts both _selectedVideos AND '
      '_pendingServerTranscodeVideos, so a video migrating out of '
      '_selectedVideos can never let a seller exceed _kSellMaxVideos',
      () {
        final start = content.indexOf('Future<void> _pickVideos()');
        final idx = content.indexOf(
          '_selectedVideos.length + _pendingServerTranscodeVideos.length',
          start,
        );
        expect(idx, greaterThanOrEqualTo(0));
      },
    );

    test(
      'picking a video never calls any upload/sign/finalize/attach API -- '
      'selection is purely local (staging only happens for '
      'requiresServerTranscode, via the durable-copy helper, not a '
      'network call)',
      () {
        final body = pickVideosBody();
        for (final forbidden in [
          'ApiService.uploadCarVideos',
          'sign-video-source-upload',
          'finalize-video-source-upload',
          'attach-transcoded-video',
          '.processAll(',
        ]) {
          expect(
            body.contains(forbidden),
            isFalse,
            reason: '_pickVideos must never reference "$forbidden" -- '
                'selecting a video must not trigger any server upload',
          );
        }
      },
    );
  });

  group('Section B: pending server-transcode video preview (widget)', () {
    late Directory tempDir;
    late String fakeVideoPath;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await FakeApiServer.ensureStarted();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'sell_transcode_preview_test_',
      );
      fakeVideoPath = p.join(tempDir.path, 'original_source.mp4');
      File(fakeVideoPath).writeAsBytesSync(<int>[
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x69, 0x73, 0x6F, 0x6D, // 'isom' brand
        ...List.filled(16, 0),
      ]);

      SharedPreferences.setMockInitialValues({
        'push_enabled': false,
        'app_locale': 'en',
      });
      await ApiService.clearTokens();
      await AuthService().adoptTestSession(
        user: {
          'id': 1,
          'username': 'seller',
          'is_admin': false,
          'is_verified': true,
          'account_type': 'individual',
        },
      );
    });

    tearDown(() async {
      await ApiService.clearTokens();
      AuthService().resetTestSession();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    tearDownAll(() async {
      await FakeApiServer.stop();
    });

    Future<void> bootSellWizard(WidgetTester tester) async {
      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Map<String, dynamic> draftCarDataWithOnePendingTranscodeVideo() => {
          'sell_wizard_v2': true,
          'images': const <dynamic>[],
          'videos': const <dynamic>[],
          'server_transcode_videos': [
            {
              'draft_media_id': 'srv_video_1',
              'local_source_path': fakeVideoPath,
              'source_byte_size': 123456789,
              'source_mime_type': 'video/mp4',
            },
          ],
        };

    testWidgets(
      'a pending server-transcode video is previewed immediately in the '
      'Sell video grid even though _selectedVideos/_existingServerVideos '
      'are both empty -- classification never hides the preview',
      (tester) async {
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 0,
          carData: draftCarDataWithOnePendingTranscodeVideo(),
        );

        expect(find.text('Photos & Videos'), findsWidgets);
        // One removable tile rendered purely from
        // `_pendingServerTranscodeVideos`.
        expect(find.byIcon(Icons.close), findsOneWidget);
      },
    );

    testWidgets(
      'a draft with no server_transcode_videos renders no pending-'
      'transcode tile (no regression for the normal case)',
      (tester) async {
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 0,
          carData: {
            'sell_wizard_v2': true,
            'images': const <dynamic>[],
            'videos': const <dynamic>[],
          },
        );

        expect(find.text('Photos & Videos'), findsWidgets);
        expect(find.byIcon(Icons.close), findsNothing);
      },
    );

    testWidgets(
      'removing a pending server-transcode video preview removes the '
      'tile locally with no backend call (unlike removing an already-'
      'uploaded server video, which requires a successful DELETE first)',
      (tester) async {
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 0,
          carData: draftCarDataWithOnePendingTranscodeVideo(),
        );

        expect(find.byIcon(Icons.close), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byIcon(Icons.close), findsNothing);
        expect(FakeApiServer.deletedCarVideoCalls, isEmpty);
      },
    );
  });
}
