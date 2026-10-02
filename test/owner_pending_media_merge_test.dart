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

    test(
      'placeholder-regression: 4 picked photos, only the 3rd (out of pick '
      'order) has attached remotely so far -- every one of the 4 picks is '
      'still shown (never silently dropped), even though the server '
      'count-based heuristic cannot know WHICH pick attached',
      () async {
        await seedRecord(
          images: [
            localImage('/tmp/A.jpg'),
            localImage('/tmp/B.jpg'),
            localImage('/tmp/C.jpg'),
            localImage('/tmp/D.jpg'),
          ],
        );
        // Phase-A images self-attach concurrently and can land OUT OF
        // pick order -- here only C (3rd picked) has landed so far.
        final car = {
          'id': carId,
          'images': <dynamic>[
            {'id': 1, 'image_url': 'uploads/C_server.jpg'},
          ],
        };

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );

        final images = merged['images'] as List;
        final localSources = images
            .where((it) => it is Map && it.containsKey('source'))
            .map((it) => (it as Map)['source'])
            .toSet();
        expect(
          localSources,
          {'/tmp/A.jpg', '/tmp/B.jpg', '/tmp/C.jpg', '/tmp/D.jpg'},
          reason: 'A must never be silently dropped just because the '
              'server-reported count (1) happens to be less than A\'s '
              'pick-order position -- the old count-based "skip the '
              'first N picks" heuristic wrongly assumed pick order '
              'matches attach order and dropped A entirely in this '
              'exact scenario',
        );
        expect(
          images.any((it) => it is Map && it['image_url'] == 'uploads/C_server.jpg'),
          isTrue,
          reason: 'the real remote row for C must still be present',
        );
      },
    );

    test(
      'placeholder-regression: once every picked photo is remotely '
      'attached, no local fallback (and no duplicate) is shown regardless '
      'of attach order', () async {
        await seedRecord(
          images: [
            localImage('/tmp/A.jpg'),
            localImage('/tmp/B.jpg'),
          ],
        );
        final car = {
          'id': carId,
          'images': <dynamic>[
            {'id': 1, 'image_url': 'uploads/B_server.jpg'},
            {'id': 2, 'image_url': 'uploads/A_server.jpg'},
          ],
        };

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );

        expect(
          merged['images'],
          hasLength(2),
          reason: 'remote already fully covers this submission -- no '
              'local fallback, no duplicate, regardless of attach order',
        );
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

    test(
      'two-video-regression: 2 normal videos picked, only the 2nd '
      '(picked later) has attached so far -- the 1st (still pending) '
      'must still be shown, never dropped just because the server count '
      '(1) is less than the 1st video\'s pick-order position',
      () async {
        await seedRecord(
          videos: [
            localVideo('/tmp/video_a.mp4'),
            localVideo('/tmp/video_b.mp4'),
          ],
        );
        final car = {
          'id': carId,
          'videos': <dynamic>['uploads/video_b_server.mp4'],
        };

        final merged = await OwnerPendingMediaMerge.mergeIfOwner(
          car,
          isOwner: true,
        );

        final videos = List<dynamic>.from(merged['videos'] as List);
        expect(
          videos.any((v) => v is Map && v['source'] == '/tmp/video_a.mp4'),
          isTrue,
          reason: 'video A (still pending) must not be dropped just '
              'because video B (picked later) happened to attach first',
        );
        expect(videos, contains('uploads/video_b_server.mp4'));
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

  group(
    'Real-device incident: 5 self-attached server images must never '
    'collapse below 5',
    () {
      List<Map<String, dynamic>> fiveServerImages() {
        return List.generate(5, (i) {
          return {
            'id': i + 1,
            // Deliberately NO client_media_id/source_media_id field --
            // matches the real backend shape exactly (`CarImage.
            // source_media_id` is "internal bookkeeping only -- never
            // exposed in to_dict()", per kk/models.py).
            'image_url': 'uploads/car_photos/photo_$i.jpg',
            'is_primary': i == 0,
            'order': i,
            'kind': 'listing',
          };
        });
      }

      test(
        'server already has all 5 images, no pending record on this '
        'device -- result is exactly the 5 server images unchanged',
        () async {
          final car = {'id': carId, 'images': fiveServerImages()};

          final merged = await OwnerPendingMediaMerge.mergeIfOwner(
            car,
            isOwner: true,
          );

          expect(merged['images'], hasLength(5));
          expect(merged, same(car));
        },
      );

      test(
        'server already has all 5 images; a STALE durable record on this '
        'device still lists only 1 local pending image (e.g. an old '
        'retry that never got cleaned up) -- result must remain exactly '
        'the 5 server images, never fewer, and never duplicated',
        () async {
          await seedRecord(images: [localImage('/tmp/stale_only_one.jpg')]);
          final car = {'id': carId, 'images': fiveServerImages()};

          final merged = await OwnerPendingMediaMerge.mergeIfOwner(
            car,
            isOwner: true,
          );

          final images = merged['images'] as List;
          expect(
            images,
            hasLength(5),
            reason: 'remote already covers (and exceeds) this stale '
                'record\'s only pending image -- must not be reduced',
          );
          expect(
            images.map((it) => it['image_url']),
            [
              'uploads/car_photos/photo_0.jpg',
              'uploads/car_photos/photo_1.jpg',
              'uploads/car_photos/photo_2.jpg',
              'uploads/car_photos/photo_3.jpg',
              'uploads/car_photos/photo_4.jpg',
            ],
          );
        },
      );

      test(
        'server has all 5 images (none carrying client_media_id/'
        'source_media_id); a durable record with 5 DIFFERENT local '
        'pending images also exists -- exactly 5 server images remain '
        '(no merge triggered since remote count already equals pending '
        'count), proving a Map/Set keyed by a missing '
        'client_media_id/source_media_id field cannot have collapsed '
        'them',
        () async {
          await seedRecord(
            images: [
              localImage('/tmp/A.jpg'),
              localImage('/tmp/B.jpg'),
              localImage('/tmp/C.jpg'),
              localImage('/tmp/D.jpg'),
              localImage('/tmp/E.jpg'),
            ],
          );
          final car = {'id': carId, 'images': fiveServerImages()};

          final merged = await OwnerPendingMediaMerge.mergeIfOwner(
            car,
            isOwner: true,
          );

          final images = merged['images'] as List;
          expect(images, hasLength(5));
          expect(
            images.map((it) => it['image_url']).toSet(),
            {
              'uploads/car_photos/photo_0.jpg',
              'uploads/car_photos/photo_1.jpg',
              'uploads/car_photos/photo_2.jpg',
              'uploads/car_photos/photo_3.jpg',
              'uploads/car_photos/photo_4.jpg',
            },
          );
        },
      );
    },
  );

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
