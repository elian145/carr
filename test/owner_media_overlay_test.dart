// Pure-Dart unit tests for `OwnerMediaOverlay.buildFromRecord` (see
// `lib/shared/listings/owner_media_overlay.dart`) -- the optimistic-
// local-media fix's per-item local<->remote reconciliation for a
// listing owner's own in-flight Sell submission. Same style/conventions
// as `owner_pending_media_merge_test.dart` (which this module builds on
// top of): no HTTP, no widget tree -- just plain `SellSubmissionRecord`s
// and car maps built by hand.
import 'package:car_listing_app/features/sell/sell_media_identity.dart';
import 'package:car_listing_app/features/sell/sell_server_transcode_video.dart';
import 'package:car_listing_app/shared/listings/owner_media_overlay.dart';
import 'package:car_listing_app/shared/prefs/owner_optimistic_media_prefs.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const draftId = 'draft_overlay_1';
  const carId = 'car_overlay_1';

  SellSubmissionRecord record({
    List<dynamic> images = const [],
    List<dynamic> videos = const [],
    List<Map<String, dynamic>> serverTranscodeVideos = const [],
    Map<String, ServerTranscodeVideoState> transcodeStates = const {},
    bool isEdit = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return SellSubmissionRecord(
      draftId: draftId,
      status: SellSubmissionStatus.inProgress,
      isEdit: isEdit,
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

  group('Scenario A: all local, server empty', () {
    test(
      '5 local photos, server has none -- 5 slots, each local-only, '
      'server-still-processing true',
      () {
        final rec = record(
          images: List.generate(5, (i) => localImage('/tmp/p$i.jpg')),
        );
        final car = {'id': carId, 'images': <dynamic>[]};

        final overlay = OwnerMediaOverlay.buildFromRecord(
          car: car,
          record: rec,
        );

        expect(overlay.expectedCount, 5);
        expect(overlay.serverStillProcessing, isTrue);
        for (final slot in overlay.imageSlots) {
          expect(slot.hasLocal, isTrue);
          expect(slot.hasRemote, isFalse);
        }
      },
    );
  });

  group('Scenario B/C: remote appears but pairing tracked per slot', () {
    test(
      'server returns remote #1 -- only the 1st local slot gets a '
      'remoteUrl; the other 4 remain local-only (server has not caught '
      'up to them yet)',
      () {
        final rec = record(
          images: List.generate(5, (i) => localImage('/tmp/p$i.jpg')),
        );
        final car = {
          'id': carId,
          'images': <dynamic>[
            {'id': 1, 'image_url': 'uploads/p0_server.jpg', 'kind': 'listing'},
          ],
        };

        final overlay = OwnerMediaOverlay.buildFromRecord(
          car: car,
          record: rec,
        );

        final slots = overlay.imageSlots;
        expect(slots, hasLength(5));
        expect(slots[0].hasRemote, isTrue);
        expect(slots[0].remoteUrl, 'uploads/p0_server.jpg');
        for (final s in slots.skip(1)) {
          expect(
            s.hasRemote,
            isFalse,
            reason: 'slot ${s.order} must stay local-only until the server '
                'has that many remote images',
          );
        }
      },
    );
  });

  group('Scenario D: all remote -- every slot paired, no local-only left', () {
    test('5 local photos, server also has 5 -- all 5 slots have a remoteUrl', () {
      final rec = record(
        images: List.generate(5, (i) => localImage('/tmp/p$i.jpg')),
      );
      final car = {
        'id': carId,
        'images': List.generate(
          5,
          (i) => {
            'id': i + 1,
            'image_url': 'uploads/p${i}_server.jpg',
            'kind': 'listing',
          },
        ),
      };

      final overlay = OwnerMediaOverlay.buildFromRecord(
        car: car,
        record: rec,
      );

      final slots = overlay.imageSlots;
      expect(slots, hasLength(5));
      expect(slots.every((s) => s.hasRemote), isTrue);
    });
  });

  group('Scenario E: remote missing for a slot -- stays local, no crash', () {
    test(
      'server has fewer remote images than local picks -- the '
      'not-yet-covered slots simply have a null remoteUrl (never throw, '
      'never fabricate a URL)',
      () {
        final rec = record(
          images: [localImage('/tmp/a.jpg'), localImage('/tmp/b.jpg')],
        );
        final car = {'id': carId, 'images': <dynamic>[]};

        final overlay = OwnerMediaOverlay.buildFromRecord(
          car: car,
          record: rec,
        );

        expect(overlay.imageSlots.every((s) => s.remoteUrl == null), isTrue);
      },
    );
  });

  group('Scenario F: mixed photo + video, independent pairing', () {
    test(
      'a photo slot and a video slot advance independently -- the video '
      'having its remote counterpart already does not affect the '
      'photo\'s own (still-null) remoteUrl, and vice versa',
      () {
        final rec = record(
          images: [localImage('/tmp/photo.jpg')],
          videos: [localVideo('/tmp/clip.mp4')],
        );
        final car = {
          'id': carId,
          'images': <dynamic>[],
          'videos': <dynamic>['uploads/clip_server.mp4'],
        };

        final overlay = OwnerMediaOverlay.buildFromRecord(
          car: car,
          record: rec,
        );

        expect(overlay.imageSlots.single.hasRemote, isFalse);
        expect(overlay.videoSlots.single.hasRemote, isTrue);
      },
    );

    test(
      'a server-transcode video uses its EXACT draft_media_id-keyed '
      'status, never positional guessing -- attached vs. still-processing '
      'is correct even when a sibling normal video landed first',
      () {
        final rec = record(
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
        // Critical Issue 2 fix: a real backend response now includes the
        // attached transcode video's own `client_media_id` (== its
        // `draftMediaId`) -- represented here as a map, not a bare
        // string, matching `GET /api/cars/<id>`'s actual owner-only
        // shape (`kk/routes/cars.py::_serialize_videos`). This is what
        // lets the normal video correctly find NO exact/legacy match
        // below (this remote entry is claimed by 'vst_1', not eligible
        // for positional fallback).
        final car = {
          'id': carId,
          'videos': <dynamic>[
            {'video_url': 'uploads/final.mp4', 'client_media_id': 'vst_1'},
          ],
        };

        final overlay = OwnerMediaOverlay.buildFromRecord(
          car: car,
          record: rec,
        );

        final videoSlots = overlay.videoSlots;
        expect(videoSlots, hasLength(2));
        final transcodeSlot =
            videoSlots.firstWhere((s) => s.clientMediaId == 'vst_1');
        expect(transcodeSlot.remoteUrl, 'uploads/final.mp4');
        final normalSlot =
            videoSlots.firstWhere((s) => s.clientMediaId != 'vst_1');
        expect(
          normalSlot.hasRemote,
          isFalse,
          reason: 'the normal video must not be mistaken for remote-ready '
              'just because an unrelated transcode video already attached',
        );
      },
    );
  });

  group('Scenario J: remote list reorders -- mapping follows order, never a stale index', () {
    test(
      'server-side reordering of an ALREADY-fully-attached set still '
      'pairs every slot to a real remote URL (no null survives once '
      'server count reaches local count)',
      () {
        final rec = record(
          images: [localImage('/tmp/a.jpg'), localImage('/tmp/b.jpg')],
        );
        // Server returns them in a different relative order than picked.
        final car = {
          'id': carId,
          'images': <dynamic>[
            {'id': 2, 'image_url': 'uploads/b_server.jpg', 'kind': 'listing'},
            {'id': 1, 'image_url': 'uploads/a_server.jpg', 'kind': 'listing'},
          ],
        };

        final overlay = OwnerMediaOverlay.buildFromRecord(
          car: car,
          record: rec,
        );

        expect(overlay.imageSlots.every((s) => s.hasRemote), isTrue);
      },
    );
  });

  group('Edit-mode scope: overlay intentionally empty', () {
    test(
      'an edit-mode record never produces overlay slots -- edit-mode '
      'listings keep using OwnerPendingMediaMerge\'s existing (coarser, '
      'unchanged) behavior instead',
      () {
        final rec = record(
          images: [localImage('/tmp/a.jpg')],
          isEdit: true,
        );
        final car = {'id': carId, 'images': <dynamic>[]};

        final overlay = OwnerMediaOverlay.buildFromRecord(
          car: car,
          record: rec,
        );

        expect(overlay.isEmpty, isTrue);
      },
    );
  });

  group('Damage images excluded (matches existing owner-facing surfaces)', () {
    test(
      'damage_images (a separate carData list from images) never '
      'produces a listing-image overlay slot -- only `finalListingImages` '
      'is ever read here, mirroring every other owner-facing media '
      'surface that already excludes damage photos from the hero/gallery',
      () {
        final rec = SellSubmissionRecord(
          draftId: draftId,
          status: SellSubmissionStatus.inProgress,
          carId: carId,
          carData: {
            'images': [localImage('/tmp/listing1.jpg')],
            'damage_images': [localImage('/tmp/damage1.jpg')],
            'videos': const <dynamic>[],
            'server_transcode_videos': const <Map<String, dynamic>>[],
          },
          idempotencyKey: 'sell-create-$draftId',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        final car = {'id': carId, 'images': <dynamic>[]};

        final overlay = OwnerMediaOverlay.buildFromRecord(
          car: car,
          record: rec,
        );

        expect(overlay.imageSlots, hasLength(1));
        expect(overlay.imageSlots.single.localPath, '/tmp/listing1.jpg');
      },
    );
  });

  group('Regression test 6: exact client_media_id reconciliation survives '
      'server reordering', () {
    test(
      'server reorders 5 image URLs but includes client_media_id -- each '
      'local item maps to its CORRECT remote asset, never a wrong-image '
      'swap from positional guessing',
      () {
        final rec = record(
          images: List.generate(5, (i) => localImage('/tmp/p$i.jpg')),
        );
        // Compute the exact ids the overlay itself derives for each local
        // item, same technique `SellMediaIdentity.forImageItem` uses
        // internally -- we just need the SAME ids the overlay will look
        // up, in a DELIBERATELY shuffled server order + with each
        // FILENAME below an already-obviously-WRONG string if paired by
        // position (p4's real image would be 'wrong_if_positional' under
        // naive positional pairing since it is returned FIRST).
        final localIds = List.generate(
          5,
          (i) => SellMediaIdentity.forImageItem(
            localImage('/tmp/p$i.jpg'),
            kind: 'listing',
          )!,
        );
        // Server returns them completely out of upload order, each
        // carrying its OWN owner-only client_media_id (Critical Issue 2
        // fix -- `kk/routes/cars.py::_with_media_compat`).
        final shuffledOrder = [4, 2, 0, 3, 1];
        final car = {
          'id': carId,
          'images': [
            for (final i in shuffledOrder)
              {
                'image_url': 'uploads/p${i}_server.jpg',
                'kind': 'listing',
                'client_media_id': localIds[i],
              },
          ],
        };

        final overlay = OwnerMediaOverlay.buildFromRecord(
          car: car,
          record: rec,
        );

        final slots = overlay.imageSlots;
        expect(slots, hasLength(5));
        for (var i = 0; i < 5; i++) {
          final slot = slots.firstWhere((s) => s.clientMediaId == localIds[i]);
          expect(
            slot.remoteUrl,
            'uploads/p${i}_server.jpg',
            reason: 'local pick #$i must map to its OWN remote asset by '
                'exact id, regardless of the server\'s return order',
          );
        }
      },
    );
  });

  group(
    'Regression test 7: legacy server response with no client_media_id',
    () {
      test(
        'a legacy response (no client_media_id on any image) still pairs '
        'via the documented positional fallback -- no crash, no null '
        'survives once server count reaches local count',
        () {
          final rec = record(
            images: List.generate(3, (i) => localImage('/tmp/p$i.jpg')),
          );
          final car = {
            'id': carId,
            // No `client_media_id` key at all -- exactly a pre-this-fix
            // (legacy) `GET /api/cars/<id>` response shape.
            'images': List.generate(
              3,
              (i) => {
                'image_url': 'uploads/p${i}_server.jpg',
                'kind': 'listing',
              },
            ),
          };

          final overlay = OwnerMediaOverlay.buildFromRecord(
            car: car,
            record: rec,
          );

          final slots = overlay.imageSlots;
          expect(slots, hasLength(3));
          expect(slots.every((s) => s.hasRemote), isTrue);
        },
      );

      test(
        'a legacy response never crashes buildFromOptimisticRecord -- AND '
        '(real-device acceptance fix) now correctly refreshes the URL via '
        'the restart-safe path\'s own positional fallback',
        () {
          final persisted = OwnerOptimisticMediaRecord(
            listingId: carId,
            items: [
              OwnerOptimisticMediaItem(
                clientMediaId: 'img_legacy_1',
                kind: 'image',
                order: 0,
                localPath: '/tmp/legacy1.jpg',
              ),
            ],
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          final car = {
            'id': carId,
            'images': <dynamic>[
              {'image_url': 'uploads/legacy1_server.jpg', 'kind': 'listing'},
            ],
          };

          final result = OwnerMediaOverlay.buildFromOptimisticRecord(
            car: car,
            record: persisted,
          );

          expect(result.slots, hasLength(1));
          // Real-device acceptance fix: no client_media_id on the remote
          // side used to mean this could NEVER refresh (confirmed real-
          // device defect: 5 correctly-attached images stayed
          // `remote_url=null` forever) -- `buildFromOptimisticRecord` now
          // has the same legacy positional-within-kind fallback
          // `buildFromRecord` already had, so a single id-less remote
          // image correctly pairs with the single not-yet-matched local
          // item.
          expect(result.slots.single.remoteUrl, 'uploads/legacy1_server.jpg');
          expect(result.serverStillProcessing, isTrue);
        },
      );
    },
  );

  group(
    'Real-device acceptance fix: buildFromOptimisticRecord legacy fallback '
    '(the exact broken lifecycle -- SellSubmissionRecord already gone, '
    'only OwnerOptimisticMediaRecord remains)',
    () {
      OwnerOptimisticMediaRecord optimisticRecord({
        required List<String> imageClientMediaIds,
        List<String> videoClientMediaIds = const [],
        String? draftId,
      }) {
        final items = <OwnerOptimisticMediaItem>[
          for (var i = 0; i < imageClientMediaIds.length; i++)
            OwnerOptimisticMediaItem(
              clientMediaId: imageClientMediaIds[i],
              kind: 'image',
              order: i,
              localPath: '/tmp/${imageClientMediaIds[i]}.jpg',
            ),
          for (var i = 0; i < videoClientMediaIds.length; i++)
            OwnerOptimisticMediaItem(
              clientMediaId: videoClientMediaIds[i],
              kind: 'video',
              order: i,
              localPath: '/tmp/${videoClientMediaIds[i]}.mp4',
            ),
        ];
        return OwnerOptimisticMediaRecord(
          listingId: carId,
          items: items,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          draftId: draftId,
        );
      }

      Map<String, dynamic> legacyImage(String url) =>
          {'image_url': url, 'kind': 'listing'};
      Map<String, dynamic> idImage(String url, String cmid) =>
          {'image_url': url, 'kind': 'listing', 'client_media_id': cmid};
      Map<String, dynamic> legacyVideo(String url) => {'video_url': url};

      test(
        'A: OwnerOptimisticMediaRecord survives after SellSubmissionRecord '
        'is gone -- 5 image URLs, NO client_media_id on any -- all 5 get '
        'distinct remote URLs, no nulls, no duplicates, order preserved',
        () {
          final persisted = optimisticRecord(
            imageClientMediaIds: [
              'img_a',
              'img_b',
              'img_c',
              'img_d',
              'img_e',
            ],
          );
          final car = {
            'id': carId,
            'images': List.generate(5, (i) => legacyImage('uploads/s$i.jpg')),
          };

          final result = OwnerMediaOverlay.buildFromOptimisticRecord(
            car: car,
            record: persisted,
          );

          expect(result.slots, hasLength(5));
          expect(result.slots.every((s) => s.hasRemote), isTrue);
          // Order preserved (matches `record.items` / original expected
          // order, independent of which pool index resolved each URL).
          expect(
            result.slots.map((s) => s.clientMediaId).toList(),
            ['img_a', 'img_b', 'img_c', 'img_d', 'img_e'],
          );
          // No duplicates: every remote URL consumed exactly once.
          final urls = result.slots.map((s) => s.remoteUrl).toList();
          expect(urls.toSet(), hasLength(5));
          expect(
            urls,
            ['uploads/s0.jpg', 'uploads/s1.jpg', 'uploads/s2.jpg',
              'uploads/s3.jpg', 'uploads/s4.jpg'],
          );
        },
      );

      test(
        'B: server has client_media_id values -- exact matching used even '
        'when server order differs from local/expected order',
        () {
          final persisted = optimisticRecord(
            imageClientMediaIds: ['img_a', 'img_b', 'img_c'],
          );
          // Server returns them shuffled -- exact id matching must not
          // care about order at all.
          final car = {
            'id': carId,
            'images': [
              idImage('uploads/c.jpg', 'img_c'),
              idImage('uploads/a.jpg', 'img_a'),
              idImage('uploads/b.jpg', 'img_b'),
            ],
          };

          final result = OwnerMediaOverlay.buildFromOptimisticRecord(
            car: car,
            record: persisted,
          );

          final byId = {for (final s in result.slots) s.clientMediaId: s};
          expect(byId['img_a']!.remoteUrl, 'uploads/a.jpg');
          expect(byId['img_b']!.remoteUrl, 'uploads/b.jpg');
          expect(byId['img_c']!.remoteUrl, 'uploads/c.jpg');
        },
      );

      test(
        'C: mixed modern + legacy rows -- id-bearing rows exact-match '
        'first, remaining legacy rows use the remaining positional pool, '
        'no remote URL assigned twice',
        () {
          final persisted = optimisticRecord(
            imageClientMediaIds: ['img_a', 'img_b', 'img_c'],
          );
          final car = {
            'id': carId,
            'images': [
              // img_b's row is id-bearing and happens to come first on
              // the wire -- exact match must claim it regardless of
              // position.
              idImage('uploads/b.jpg', 'img_b'),
              // These two rows are legacy (no id) -- only img_a and
              // img_c (the two NOT already exact-matched) may consume
              // them, in encounter order.
              legacyImage('uploads/legacy_0.jpg'),
              legacyImage('uploads/legacy_1.jpg'),
            ],
          };

          final result = OwnerMediaOverlay.buildFromOptimisticRecord(
            car: car,
            record: persisted,
          );

          final byId = {for (final s in result.slots) s.clientMediaId: s};
          expect(byId['img_b']!.remoteUrl, 'uploads/b.jpg');
          expect(byId['img_a']!.remoteUrl, 'uploads/legacy_0.jpg');
          expect(byId['img_c']!.remoteUrl, 'uploads/legacy_1.jpg');
          // No URL assigned twice.
          final urls = result.slots.map((s) => s.remoteUrl).toList();
          expect(urls.toSet(), hasLength(3));
        },
      );

      test(
        'D: 5 images + 1 video, all legacy/no IDs -- image pool reconciles '
        '5 images, video pool reconciles 1 video, kinds never cross',
        () {
          final persisted = optimisticRecord(
            imageClientMediaIds: [
              'img_a',
              'img_b',
              'img_c',
              'img_d',
              'img_e',
            ],
            videoClientMediaIds: ['vid_a'],
          );
          final car = {
            'id': carId,
            'images': List.generate(5, (i) => legacyImage('uploads/i$i.jpg')),
            'videos': [legacyVideo('uploads/v0.mp4')],
          };

          final result = OwnerMediaOverlay.buildFromOptimisticRecord(
            car: car,
            record: persisted,
          );

          expect(result.imageSlots, hasLength(5));
          expect(result.videoSlots, hasLength(1));
          expect(result.imageSlots.every((s) => s.hasRemote), isTrue);
          expect(result.videoSlots.single.remoteUrl, 'uploads/v0.mp4');
          // Kinds never cross: no image slot ever receives the video's
          // remote URL and vice versa.
          expect(
            result.imageSlots.any((s) => s.remoteUrl == 'uploads/v0.mp4'),
            isFalse,
          );
        },
      );

      test(
        'E: SellSubmissionRecord already deleted before app restart -- '
        'only OwnerOptimisticMediaRecord remains -- optimistic overlay '
        'restores AND remote reconciliation still succeeds end-to-end '
        'via buildFromOptimisticRecordForCarId',
        () async {
          SharedPreferences.setMockInitialValues({});
          final persisted = optimisticRecord(
            imageClientMediaIds: ['img_a', 'img_b'],
          );
          await OwnerOptimisticMediaPrefs.upsert(persisted);

          final car = {
            'id': carId,
            'images': [
              legacyImage('uploads/a.jpg'),
              legacyImage('uploads/b.jpg'),
            ],
          };

          final result = await OwnerMediaOverlay.buildFromOptimisticRecordForCarId(
            car: car,
            carId: carId,
          );

          expect(result.isEmpty, isFalse);
          expect(result.slots, hasLength(2));
          expect(result.slots.every((s) => s.hasRemote), isTrue);
          expect(result.serverStillProcessing, isTrue);
        },
      );
    },
  );

  group('Non-owner / no record: always empty', () {
    test('OwnerMediaOverlay.build is empty for a non-owner', () async {
      final overlay = await OwnerMediaOverlay.build(
        car: const {'id': carId, 'images': <dynamic>[]},
        isOwner: false,
      );
      expect(overlay.isEmpty, isTrue);
    });
  });

  group(
    'Real-device acceptance fix: mergeForCardDisplay / '
    'mergeOwnedListingsForCardDisplay (My Listings card shows zero '
    'photos until Car Details is opened)',
    () {
      OwnerOptimisticMediaRecord optimisticRecord(
        String listingId, {
        required List<String> imageClientMediaIds,
        bool allReady = false,
      }) {
        return OwnerOptimisticMediaRecord(
          listingId: listingId,
          items: [
            for (var i = 0; i < imageClientMediaIds.length; i++)
              OwnerOptimisticMediaItem(
                clientMediaId: imageClientMediaIds[i],
                kind: 'image',
                order: i,
                localPath: '/tmp/${imageClientMediaIds[i]}.jpg',
                remoteDisplayReady: allReady,
              ),
          ],
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }

      test(
        'mergeForCardDisplay: no live SellSubmissionRecord, only a '
        'durable OwnerOptimisticMediaRecord -- local images are still '
        'appended (the exact gap the live-record-only '
        'OwnerPendingMediaMerge.mergeIfOwner leaves once the backend '
        'has already finished and removed its own record)',
        () async {
          SharedPreferences.setMockInitialValues({});
          await OwnerOptimisticMediaPrefs.upsert(
            optimisticRecord('card_car_1', imageClientMediaIds: ['a', 'b']),
          );
          final car = {'id': 'card_car_1', 'images': <dynamic>[]};

          final merged = await OwnerMediaOverlay.mergeForCardDisplay(
            car,
            isOwner: true,
          );

          expect(merged['images'], hasLength(2));
          expect(merged['images'], contains('/tmp/a.jpg'));
          expect(merged['images'], contains('/tmp/b.jpg'));
        },
      );

      test(
        'mergeForCardDisplay: a non-owner never gets local fallback '
        'media, even with a matching durable record on this device',
        () async {
          SharedPreferences.setMockInitialValues({});
          await OwnerOptimisticMediaPrefs.upsert(
            optimisticRecord('card_car_2', imageClientMediaIds: ['a']),
          );
          final car = {'id': 'card_car_2', 'images': <dynamic>[]};

          final merged = await OwnerMediaOverlay.mergeForCardDisplay(
            car,
            isOwner: false,
          );

          expect(merged, same(car));
        },
      );

      test(
        'mergeForCardDisplay: every item already remoteDisplayReady -- '
        'no stale local fallback is appended (record is effectively '
        'done, same as Car Details would treat it)',
        () async {
          SharedPreferences.setMockInitialValues({});
          await OwnerOptimisticMediaPrefs.upsert(
            optimisticRecord(
              'card_car_3',
              imageClientMediaIds: ['a'],
              allReady: true,
            ),
          );
          final car = {
            'id': 'card_car_3',
            'images': [
              {'url': 'https://cdn.example/a.jpg', 'client_media_id': 'a'},
            ],
          };

          final merged = await OwnerMediaOverlay.mergeForCardDisplay(
            car,
            isOwner: true,
          );

          expect(merged['images'], hasLength(1));
        },
      );

      test(
        'mergeOwnedListingsForCardDisplay: a batch of listings each get '
        'the right treatment -- one with only a durable optimistic '
        'record (gets local fallback appended), one with neither record '
        '(unchanged), one already fully remote-display-ready (unchanged)',
        () async {
          SharedPreferences.setMockInitialValues({});
          await OwnerOptimisticMediaPrefs.upsert(
            optimisticRecord('batch_1', imageClientMediaIds: ['x', 'y']),
          );
          await OwnerOptimisticMediaPrefs.upsert(
            optimisticRecord(
              'batch_2',
              imageClientMediaIds: ['z'],
              allReady: true,
            ),
          );
          final cars = [
            {'id': 'batch_1', 'images': <dynamic>[]},
            {
              'id': 'batch_2',
              'images': [
                {'url': 'https://cdn.example/z.jpg', 'client_media_id': 'z'},
              ],
            },
            {
              'id': 'batch_3',
              'images': [
                {'url': 'https://cdn.example/untouched.jpg'},
              ],
            },
          ];

          final merged =
              await OwnerMediaOverlay.mergeOwnedListingsForCardDisplay(cars);

          final byId = {for (final c in merged) c['id']: c};
          expect(byId['batch_1']!['images'], hasLength(2));
          expect(byId['batch_2']!['images'], hasLength(1));
          expect(byId['batch_3']!['images'], hasLength(1));
        },
      );
    },
  );
}
