// Tests for `OwnerPendingMediaMerge` (see
// `lib/shared/listings/owner_pending_media_merge.dart`) -- the seller-side
// optimistic media merge that lets My Listings / the owner listing detail
// page show a seller their own just-selected local photos/videos while
// `PendingSellSubmissionService`'s background media pipeline (image/video
// upload, `requiresServerTranscode` server-side transcode) is still
// running, after `submitFast()` has already navigated the user away from
// Sell.
//
// Pure-Dart unit tests: no HTTP, no widget tree -- this module only ever
// reads durable `SellSubmissionRecord`s already on disk and merges them
// (in-memory) into a listing map, so `SharedPreferences.setMockInitialValues`
// is enough.
import 'package:car_listing_app/features/sell/sell_server_transcode_video.dart';
import 'package:car_listing_app/shared/listings/owner_pending_media_merge.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const draftId = 'draft_owner_merge_1';
  const carId = 'car_owner_merge_1';

  Future<void> seedRecord({
    List<dynamic> images = const [],
    List<dynamic> videos = const [],
    List<Map<String, dynamic>> serverTranscodeVideos = const [],
    Map<String, ServerTranscodeVideoState> transcodeStates = const {},
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await SellSubmissionStatePrefs.upsert(
      SellSubmissionRecord(
        draftId: draftId,
        status: SellSubmissionStatus.inProgress,
        carId: carId,
        carData: {
          'images': images,
          'videos': videos,
          'server_transcode_videos': serverTranscodeVideos,
        },
        idempotencyKey: 'sell-create-$draftId',
        createdAt: now,
        updatedAt: now,
        serverTranscodeVideos: transcodeStates,
      ),
    );
  }

  Map<String, dynamic> localImage(String path) => {'source': path};
  Map<String, dynamic> localVideo(String path) => {'source': path};

  Map<String, dynamic> transcodeSpecJson(String path, String id) => {
        'draft_media_id': id,
        'local_source_path': path,
        'source_byte_size': 12345,
        'source_mime_type': 'video/mp4',
      };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('mediaStatus (isMediaProcessing / processingCarIds)', () {
    test(
      'a listing with no durable pending record is not "processing"',
      () async {
        expect(await OwnerPendingMediaMerge.isMediaProcessing(carId), isFalse);
      },
    );

    test(
      'a listing with a durable pending record for its carId IS '
      '"processing" -- mediaStatus stays processing until the record is '
      'removed (i.e. all media attached), independent of userFacingStatus',
      () async {
        await seedRecord(images: [localImage('/tmp/a.jpg')]);
        expect(await OwnerPendingMediaMerge.isMediaProcessing(carId), isTrue);

        final ids = await OwnerPendingMediaMerge.processingCarIds([
          {'id': carId},
          {'id': 'some_other_car'},
        ]);
        expect(ids, {carId});
      },
    );

    test(
      'once the durable record is removed (background pipeline finished), '
      'mediaStatus flips back to non-processing with no other change',
      () async {
        await seedRecord(images: [localImage('/tmp/a.jpg')]);
        expect(await OwnerPendingMediaMerge.isMediaProcessing(carId), isTrue);
        await SellSubmissionStatePrefs.remove(draftId);
        expect(await OwnerPendingMediaMerge.isMediaProcessing(carId), isFalse);
      },
    );
  });

  group('mergeIfOwner: images', () {
    test(
      'seller sees a pending local image before it is remotely attached',
      () async {
        await seedRecord(images: [localImage('/tmp/photo1.jpg')]);
        final car = {'id': carId, 'images': <dynamic>[]};

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );

        final images = merged['images'] as List;
        expect(images, hasLength(1));
        expect(images.first, containsPair('source', '/tmp/photo1.jpg'));
      },
    );

    test(
      'once the server already has the same number of listing images, '
      'the local fallback is no longer shown for that image',
      () async {
        await seedRecord(images: [localImage('/tmp/photo1.jpg')]);
        final car = {
          'id': carId,
          'images': <dynamic>[
            {'id': 1, 'image_url': 'uploads/photo1_server.jpg'},
          ],
        };

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );

        final images = merged['images'] as List;
        expect(
          images,
          hasLength(1),
          reason: 'remote image already covers this submission\'s only '
              'pending image -- no local fallback duplicate',
        );
        expect(images.first['image_url'], 'uploads/photo1_server.jpg');
      },
    );

    test(
      'a non-owner viewer never sees local fallback media, even when a '
      'durable record exists for that carId on this device',
      () async {
        await seedRecord(images: [localImage('/tmp/photo1.jpg')]);
        final car = {'id': carId, 'images': <dynamic>[]};

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: false,
        );

        expect(merged, same(car));
        expect((merged['images'] as List), isEmpty);
      },
    );

    test(
      'no duplicate images when merge runs twice on an already-merged map',
      () async {
        await seedRecord(images: [localImage('/tmp/photo1.jpg')]);
        final car = {'id': carId, 'images': <dynamic>[]};

        final once = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );
        final twice = await OwnerPendingMediaMerge.mergeIfOwner(
          once,
          isOwner: true,
        );

        expect(twice['images'], hasLength(1));
      },
    );
  });

  group('mergeIfOwner: normal videos', () {
    test(
      'seller sees a pending local (normal, non-transcode) video before '
      'it is remotely attached',
      () async {
        await seedRecord(videos: [localVideo('/tmp/clip1.mp4')]);
        final car = {'id': carId, 'videos': <dynamic>[]};

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );

        expect(merged['videos'], hasLength(1));
      },
    );

    test(
      'once the server has the video, the local fallback disappears',
      () async {
        await seedRecord(videos: [localVideo('/tmp/clip1.mp4')]);
        final car = {
          'id': carId,
          'videos': <dynamic>['uploads/clip1_server.mp4'],
        };

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );

        expect(merged['videos'], ['uploads/clip1_server.mp4']);
      },
    );
  });

  group('mergeIfOwner: requiresServerTranscode videos (exact per-item status)', () {
    test(
      'seller sees a pending local server-transcode video (plays from '
      'localSourcePath) while the transcode/attach pipeline is still in '
      'progress -- this is the core 60-120s-wait scenario',
      () async {
        await seedRecord(
          serverTranscodeVideos: [
            transcodeSpecJson('/tmp/source_video.mov', 'vst_1'),
          ],
          transcodeStates: {
            'vst_1': ServerTranscodeVideoState.initial('vst_1').copyWith(
              status: ServerTranscodeVideoStatus.transcodeProcessing,
              taskId: 'task-1',
            ),
          },
        );
        final car = {'id': carId, 'videos': <dynamic>[]};

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );

        expect(
          merged['videos'],
          ['/tmp/source_video.mov'],
          reason: 'the exact original local source path must be used so '
              'the existing local file player can play it',
        );
      },
    );

    test(
      'once the transcode video is durably `attached`, remote media '
      'replaces the local fallback -- no duplicate, local path no longer '
      'shown even though it is still in this submission\'s carData',
      () async {
        await seedRecord(
          serverTranscodeVideos: [
            transcodeSpecJson('/tmp/source_video.mov', 'vst_1'),
          ],
          transcodeStates: {
            'vst_1': ServerTranscodeVideoState.initial('vst_1').copyWith(
              status: ServerTranscodeVideoStatus.attached,
              attachedVideo: const {'id': 9, 'video_url': 'uploads/final.mp4'},
            ),
          },
        );
        final car = {
          'id': carId,
          'videos': <dynamic>['uploads/final.mp4'],
        };

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );

        expect(
          merged['videos'],
          ['uploads/final.mp4'],
          reason: 'local source must not still be appended once attached',
        );
      },
    );

    test(
      'a pending normal video and a still-processing transcode video on '
      'the SAME listing are both correctly classified -- the transcode '
      'video\'s exact status is never confused with the normal video\'s '
      'count-based heuristic',
      () async {
        await seedRecord(
          videos: [localVideo('/tmp/normal.mp4')],
          serverTranscodeVideos: [
            transcodeSpecJson('/tmp/source_video.mov', 'vst_1'),
          ],
          transcodeStates: {
            'vst_1': ServerTranscodeVideoState.initial('vst_1').copyWith(
              status: ServerTranscodeVideoStatus.attached,
              attachedVideo: const {'id': 9, 'video_url': 'uploads/final.mp4'},
            ),
          },
        );
        // Server already has the attached transcode video, but NOT the
        // normal video yet.
        final car = {
          'id': carId,
          'videos': <dynamic>['uploads/final.mp4'],
        };

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );

        final videos = List<dynamic>.from(merged['videos'] as List);
        expect(videos, contains('uploads/final.mp4'));
        expect(
          videos.any(
            (v) => v is Map && v['source'] == '/tmp/normal.mp4',
          ),
          isTrue,
          reason: 'the still-pending NORMAL video must still show its '
              'local fallback even though an unrelated transcoded video '
              'already landed on the server',
        );
        expect(videos, hasLength(2));
      },
    );
  });

  group('mergeOwnedListings (bulk, My Listings)', () {
    test(
      'merges only listings that have a matching durable record; other '
      'listings pass through unchanged, and unrelated cars never gain a '
      'local fallback', () async {
        await seedRecord(images: [localImage('/tmp/photo1.jpg')]);
        final cars = [
          {'id': carId, 'images': <dynamic>[]},
          {'id': 'unrelated_car', 'images': <dynamic>[]},
        ];

        final merged = await OwnerPendingMediaMerge.mergeOwnedListings(cars);

        expect((merged[0]['images'] as List), hasLength(1));
        expect((merged[1]['images'] as List), isEmpty);
      },
    );

    test('a listing with no durable record anywhere is untouched (identity)', () async {
      final cars = [
        {'id': 'no_pending_car', 'images': <dynamic>[]},
      ];
      final merged = await OwnerPendingMediaMerge.mergeOwnedListings(cars);
      expect(merged, same(cars));
    });
  });
}
