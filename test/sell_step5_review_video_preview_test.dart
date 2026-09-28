// Review & Submit video-preview decoupling fix (follow-up to the Step4
// "immediate video preview" fix -- see
// `sell_step4_video_preview_decoupling_test.dart`).
//
// New bug reported after that fix: a video classified
// `requiresServerTranscode` now correctly appears in the Step4 media grid
// immediately after selection, but was completely ABSENT from the final
// Review & Submit carousel.
//
// Root cause (confirmed by reading `sell_step4_preview_review.dart`, the
// file that actually backs Step5's review UI --
// `SellReviewCarDetailScrollView`, built by `sell_step5_build.dart`):
// `_buildMediaList()` only ever read `car['images']` and `car['videos']`.
// A `requiresServerTranscode` video is, by design (see
// `sell_step4_logic.dart::_pickVideos`), MOVED OUT of `carData['videos']`
// and into `carData['server_transcode_videos']` -- a key `_buildMediaList`
// never read. So that class of video vanished from Review & Submit even
// though it was correctly staged for the (unchanged) server sign/upload/
// finalize/poll/attach pipeline.
//
// `ListingPreviewWidget` (`sell_step4_preview_listing.dart`) was confirmed
// dead code by a prior fix's test (`sell_final_preview_damage_image_test
// .dart`) and remains out of scope here -- `SellReviewCarDetailScrollView`
// is the only live Review & Submit renderer.
//
// Fix: `_buildMediaList()` now also merges in every pending server-
// transcode video's ORIGINAL local source
// (`ServerTranscodeVideoSpec.localSourcePath`, wrapped in an `XFile` so it
// flows through every existing helper -- `ListingImageMedia.source`,
// `generateVideoThumbnail`, `GalleryEmbeddedVideoPlayer`'s
// `VideoPlayerController.file` branch -- completely unchanged), deduped
// by path against `carData['videos']`. `carData['videos']` itself, and
// the actual upload/server-transcode pipeline, are never touched by this
// merge -- it is display-only, exactly like the Step4 grid's own
// `_pendingServerTranscodeVideos` section.
//
// Section A: static source-shape checks on `_buildMediaList` (merge logic,
// no-upload guarantee). Section B: full sell-wizard widget tests reaching
// Review & Submit (`step: 5`, matching the existing, already-passing
// "Legacy sell review step opens from draft snapshot" test in
// `legacy_sell_steps_widget_test.dart`), proving what actually renders.
import 'dart:io';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/features/sell/sell_flow.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/widgets/in_app_video_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
  group('Section A: _buildMediaList merge/no-upload source-shape contract', () {
    late String content;

    setUpAll(() {
      final file = File(
        p.join('lib', 'features', 'sell', 'sell_step4_preview_review.dart'),
      );
      expect(file.existsSync(), isTrue);
      content = _stripDartComments(file.readAsStringSync());
    });

    String buildMediaListBody() {
      final start = content.indexOf(
        'List<_PreviewMediaEntry> _buildMediaList(',
      );
      final end = content.indexOf(
        'double _heroPhotoHeight(',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      return content.substring(start, end);
    }

    test(
      '_buildMediaList reads carData["server_transcode_videos"] via '
      'ServerTranscodeVideoSpec.listFromJson, not just carData["videos"]',
      () {
        final body = buildMediaListBody();
        final normalized = body.replaceAll(RegExp(r'\s+'), ' ');
        expect(
          normalized.contains(
            "ServerTranscodeVideoSpec.listFromJson( car['server_transcode_videos'],",
          ),
          isTrue,
          reason: '_buildMediaList must read server_transcode_videos so '
              'requiresServerTranscode videos are not silently dropped '
              'from Review & Submit',
        );
      },
    );

    test(
      'pending server-transcode preview items are built from '
      's.localSourcePath, the untouched original local file',
      () {
        final body = buildMediaListBody();
        expect(body.contains('XFile(s.localSourcePath)'), isTrue);
      },
    );

    test(
      'pending server-transcode videos are deduped against carData["videos"] '
      'by path before being added, so a video temporarily present in both '
      'lists is never rendered twice',
      () {
        final body = buildMediaListBody();
        final existingIdx = body.indexOf(
          'final existingVideoPaths = vl.map(ListingImageMedia.source).toSet();',
        );
        final pendingIdx = body.indexOf(
          'final pendingVideoItems = ServerTranscodeVideoSpec.listFromJson(',
        );
        expect(existingIdx, greaterThanOrEqualTo(0));
        expect(pendingIdx, greaterThan(existingIdx));
        final between = body.substring(existingIdx, pendingIdx + 400);
        expect(
          between.contains('existingVideoPaths.contains(s.localSourcePath)'),
          isTrue,
        );
      },
    );

    test(
      'the normal videos list (carData["videos"]) is still included '
      'unconditionally -- the merge is additive only, never a replacement',
      () {
        final body = buildMediaListBody();
        final normalized = body.replaceAll(RegExp(r'\s+'), ' ');
        expect(
          normalized.contains(
            '...vl .where((e) => ListingImageMedia.source(e).isNotEmpty) '
            '.map((e) => _PreviewMediaEntry(isVideo: true, item: e)),',
          ),
          isTrue,
        );
      },
    );

    test(
      '_buildMediaList never calls any upload/sign/finalize/attach API -- '
      'merging pending videos for display must never trigger the server '
      'pipeline',
      () {
        final body = buildMediaListBody();
        for (final forbidden in [
          'ApiService.uploadCarVideos',
          'sign-video-source-upload',
          'finalize-video-source-upload',
          'attach-transcoded-video',
          '.processAll(',
          'SellServerTranscodeVideoRunner',
        ]) {
          expect(
            body.contains(forbidden),
            isFalse,
            reason:
                '_buildMediaList must never reference "$forbidden" -- '
                'building the review preview must not trigger any upload',
          );
        }
      },
    );

    test(
      '_buildMediaList never mutates carData["videos"] itself -- the '
      'merge is read-only / display-only',
      () {
        final body = buildMediaListBody();
        expect(body.contains("car['videos'] ="), isFalse);
        expect(body.contains("car['server_transcode_videos'] ="), isFalse);
      },
    );
  });

  group('Section B: Review & Submit widget behavior', () {
    late Directory tempDir;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await FakeApiServer.ensureStarted();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'sell_review_video_test_',
      );
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

    String makeVideoFile(String name) {
      final path = p.join(tempDir.path, name);
      File(path).writeAsBytesSync(<int>[
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x69, 0x73, 0x6F, 0x6D, // 'isom' brand
        ...List.filled(16, 0),
      ]);
      return path;
    }

    Map<String, dynamic> reviewDraftCarData({
      List<String> videos = const [],
      List<Map<String, dynamic>> serverTranscodeVideos = const [],
    }) => {
          ...sellCarDataThroughStep3(),
          'sell_wizard_v2': true,
          'images': const <dynamic>['uploads/test_photo.jpg'],
          'use_blurred_plates': false,
          'videos': videos,
          'server_transcode_videos': serverTranscodeVideos,
        };

    Map<String, dynamic> transcodeSpecJson(String path, String id) => {
          'draft_media_id': id,
          'local_source_path': path,
          'source_byte_size': 123456789,
          'source_mime_type': 'video/mp4',
        };

    /// Opens the Review & Submit media carousel's full grid (all images
    /// then all videos as tiles) by tapping the hero carousel -- the same
    /// navigation `_openCarouselDetail` wires up in production.
    Future<void> openReviewMediaGrid(WidgetTester tester) async {
      final carouselFinder = find.descendant(
        of: find.byType(SellReviewCarDetailScrollView),
        matching: find.byType(PageView),
      );
      expect(
        carouselFinder,
        findsOneWidget,
        reason: 'the review hero media carousel must be present',
      );
      await tester.tap(carouselFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
      'a normal (non-transcode) video appears in Review & Submit',
      (tester) async {
        final videoPath = makeVideoFile('normal.mp4');
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 5,
          carData: reviewDraftCarData(videos: [videoPath]),
        );

        expect(find.text('Review & Submit'), findsWidgets);
        await openReviewMediaGrid(tester);

        expect(find.text('VIDEO'), findsOneWidget);
      },
    );

    testWidgets(
      'a requiresServerTranscode (pending) video appears in Review & '
      'Submit even though it is not in carData["videos"] -- this is the '
      'bug fix',
      (tester) async {
        final videoPath = makeVideoFile('pending.mp4');
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 5,
          carData: reviewDraftCarData(
            serverTranscodeVideos: [
              transcodeSpecJson(videoPath, 'srv_video_1'),
            ],
          ),
        );

        expect(find.text('Review & Submit'), findsWidgets);
        await openReviewMediaGrid(tester);

        expect(find.text('VIDEO'), findsOneWidget);
      },
    );

    testWidgets(
      'both a normal video and a pending server-transcode video appear '
      'together, with no duplicate when they share the same path',
      (tester) async {
        final normalPath = makeVideoFile('normal2.mp4');
        final pendingPath = makeVideoFile('pending2.mp4');
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 5,
          carData: reviewDraftCarData(
            videos: [normalPath],
            serverTranscodeVideos: [
              transcodeSpecJson(pendingPath, 'srv_video_2'),
            ],
          ),
        );

        await openReviewMediaGrid(tester);
        expect(
          find.text('VIDEO'),
          findsNWidgets(2),
          reason: 'both distinct videos must be rendered',
        );
      },
    );

    testWidgets(
      'no duplicate video tile is rendered when the same path temporarily '
      'exists in both carData["videos"] and carData["server_transcode_videos"]',
      (tester) async {
        final sharedPath = makeVideoFile('shared.mp4');
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 5,
          carData: reviewDraftCarData(
            videos: [sharedPath],
            serverTranscodeVideos: [
              transcodeSpecJson(sharedPath, 'srv_video_dup'),
            ],
          ),
        );

        await openReviewMediaGrid(tester);
        expect(
          find.text('VIDEO'),
          findsOneWidget,
          reason: 'a video present in both lists under the SAME path must '
              'only be rendered once',
        );
      },
    );

    testWidgets(
      'a pending server-transcode video previews from its localSourcePath '
      '-- the exact original local file, not a server URL or placeholder',
      (tester) async {
        final videoPath = makeVideoFile('exact_path.mp4');
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 5,
          carData: reviewDraftCarData(
            serverTranscodeVideos: [
              transcodeSpecJson(videoPath, 'srv_video_3'),
            ],
          ),
        );

        await openReviewMediaGrid(tester);
        expect(find.text('VIDEO'), findsOneWidget);

        // Tap the video tile to open the full-screen viewer and confirm
        // the SAME local path is what gets handed to the local-playback
        // widget.
        await tester.tap(find.text('VIDEO'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final player = tester.widget<GalleryEmbeddedVideoPlayer>(
          find.byType(GalleryEmbeddedVideoPlayer),
        );
        expect(player.videoUrl, videoPath);
      },
    );

    testWidgets(
      'existing image review still works with no videos at all (no '
      'regression for the normal, video-free case)',
      (tester) async {
        await bootSellWizard(tester);
        await openSellDraftStep(
          tester,
          step: 5,
          carData: reviewDraftCarData(),
        );

        expect(find.text('Review & Submit'), findsWidgets);
        expect(tester.takeException(), isNull);

        await openReviewMediaGrid(tester);
        expect(
          find.text('VIDEO'),
          findsNothing,
          reason: 'no video tiles should render when there are none',
        );
        expect(find.byIcon(Icons.broken_image), findsNothing);
      },
    );
  });
}
