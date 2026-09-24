// OOM-fix follow-up: proves `SellPhotoPrestage.stageCarData()` (the Sell
// wizard's pre-create photo staging step) now goes through the EXISTING
// Celery async image-processing pipeline instead of running full
// synchronous PIL decode/blur/downscale/encode work inline on
//
//   POST /api/process-car-images   (no `async=1` -- the confirmed OOM root
//                                    cause: this ran inside the single-
//                                    worker `carr` Gunicorn web process)
//
// New path:
//
//   POST /api/process-car-images?async=1&skip_blur=1  (existing endpoint,
//                                                        already used by
//                                                        `/api/cars/<id>/images?async=1`)
//     -> GET /api/jobs/<task_id>  (existing, shared job-status endpoint)
//
// No second job framework, no new endpoints -- same pipeline `SellListingMediaUpload`
// already uses for post-create uploads (see `test/p01_async_car_image_upload_test.dart`).
//
// Also proves the listing-photo and damage-photo batches, which used to
// start in parallel (`Future.wait`), now run SEQUENTIALLY -- both hit the
// same shared `carr-worker-fra` Celery pool, so running them in parallel no
// longer buys meaningful wall-clock time and would only double one
// seller's worker-queue pressure per submission.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/sell_photo_prestage.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory tempDir;
  late List<Map<String, String>> enqueueCalls; // {query} per enqueue call
  late List<String> jobStatusPolls; // job ids polled, in order
  late Map<String, String> jobOutcome; // jobId -> 'SUCCESS' | 'FAILURE'
  int jobIdSeq = 0;
  http.Response? Function(Uri uri)? enqueueOverride;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sell_photo_prestage_');
    enqueueCalls = <Map<String, String>>[];
    jobStatusPolls = <String>[];
    jobOutcome = <String, String>{};
    jobIdSeq = 0;
    enqueueOverride = null;

    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');

    ApiService.testHttpClient = MockClient((request) async {
      final method = request.method.toUpperCase();
      final path = request.url.path;

      if (method == 'POST' && path == '/api/process-car-images') {
        final override = enqueueOverride;
        if (override != null) {
          final forced = override(request.url);
          if (forced != null) return forced;
        }
        // The multipart body's bytes may not be valid UTF-8 -- decode with
        // latin1 (never throws) just to count `name="images"` parts.
        final bodyText = latin1.decode(request.bodyBytes);
        final fileCount = RegExp(
          'name="images"',
        ).allMatches(bodyText).length;
        enqueueCalls.add(request.url.queryParameters);
        final jobIds = <String>[];
        for (var i = 0; i < fileCount; i++) {
          jobIdSeq++;
          final id = 'job-$jobIdSeq';
          jobOutcome[id] = 'SUCCESS';
          jobIds.add(id);
        }
        return http.Response(
          json.encode({'success': true, 'job_ids': jobIds}),
          202,
          headers: {'content-type': 'application/json'},
        );
      }

      if (method == 'GET' && path.startsWith('/api/jobs/')) {
        final jobId = path.substring('/api/jobs/'.length);
        jobStatusPolls.add(jobId);
        final outcome = jobOutcome[jobId] ?? 'SUCCESS';
        if (outcome == 'FAILURE') {
          return http.Response(
            json.encode({'task_id': jobId, 'state': 'FAILURE'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          json.encode({
            'task_id': jobId,
            'state': 'SUCCESS',
            'result': {'rel_path': 'uploads/car_photos/$jobId.jpg'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('{}', 200, headers: {
        'content-type': 'application/json',
      });
    });

    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    ApiService.testHttpClient = null;
    setRuntimeApiBaseOverride(null);
    TokenStore.testMode = false;
    TokenStore.resetForTests();
    tempDir.deleteSync(recursive: true);
  });

  File writeFakeJpeg(String name) {
    final f = File('${tempDir.path}/$name');
    f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    return f;
  }

  test(
    'stages listing + damage photos via the async job pipeline (never the '
    'synchronous branch), preserving skip_blur=1 and result shape',
    () async {
      final listingPhoto = writeFakeJpeg('listing.jpg');
      final damagePhoto = writeFakeJpeg('damage.jpg');

      final carData = <String, dynamic>{
        'images': [listingPhoto.path],
        'damage_images': [damagePhoto.path],
      };

      final staged = await SellPhotoPrestage.stageCarData(carData);

      expect(staged, 2);
      expect(enqueueCalls, hasLength(2));
      for (final q in enqueueCalls) {
        expect(
          q['async'],
          '1',
          reason: 'production Sell prestage must always opt into async '
              'processing -- this is the confirmed OOM fix',
        );
        expect(q['skip_blur'], '1');
      }
      expect(
        jobStatusPolls,
        isNotEmpty,
        reason: 'the shared job-status endpoint must be polled',
      );

      // Listing photo rewritten to the server path, with a local fallback
      // path preserved.
      final images = carData['images'] as List;
      expect(images, hasLength(1));
      final listingItem = images.single as Map;
      expect(listingItem['source'], startsWith('uploads/car_photos/job-'));
      expect(
        listingItem[SellPhotoPrestage.stagedFromKey],
        listingPhoto.path,
      );

      // Damage photo rewritten the same way, independently.
      final damageImages = carData['damage_images'] as List;
      expect(damageImages, hasLength(1));
      final damageItem = damageImages.single as Map;
      expect(damageItem['source'], startsWith('uploads/car_photos/job-'));
      expect(
        damageItem[SellPhotoPrestage.stagedFromKey],
        damagePhoto.path,
      );
    },
  );

  test(
    'listing and damage batches run sequentially, not in parallel -- the '
    'damage batch is not enqueued until the listing batch fully resolves',
    () async {
      final listingPhoto = writeFakeJpeg('listing_seq.jpg');
      final damagePhoto = writeFakeJpeg('damage_seq.jpg');

      final gate = Completer<void>();

      // Gate the job-status poll for the listing photo's job so the
      // listing batch cannot finish until this test explicitly allows it
      // to -- the assertion below checks that the damage batch has not
      // enqueued anything while that gate is held closed.
      final carData = <String, dynamic>{
        'images': [listingPhoto.path],
        'damage_images': [damagePhoto.path],
      };

      // Swap in a client that lets us stall the listing job's FIRST status
      // poll indefinitely until the test completes it.
      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        if (method == 'POST' && path == '/api/process-car-images') {
          final bodyText = latin1.decode(request.bodyBytes);
          final fileCount = RegExp(
            'name="images"',
          ).allMatches(bodyText).length;
          enqueueCalls.add(request.url.queryParameters);
          jobIdSeq++;
          final jobId = 'job-$jobIdSeq';
          jobOutcome[jobId] = 'SUCCESS';
          return http.Response(
            json.encode({
              'success': true,
              'job_ids': List<String>.filled(fileCount, jobId),
            }),
            202,
            headers: {'content-type': 'application/json'},
          );
        }
        if (method == 'GET' && path.startsWith('/api/jobs/')) {
          final jobId = path.substring('/api/jobs/'.length);
          jobStatusPolls.add(jobId);
          // The first job ever created (the listing batch's) stalls on its
          // very first poll until the test lets it through.
          if (jobId == 'job-1' && !gate.isCompleted) {
            await gate.future;
          }
          return http.Response(
            json.encode({
              'task_id': jobId,
              'state': 'SUCCESS',
              'result': {'rel_path': 'uploads/car_photos/$jobId.jpg'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      });

      final future = SellPhotoPrestage.stageCarData(carData);

      // Give the listing batch's enqueue + first poll a moment to happen.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        enqueueCalls.length,
        1,
        reason: 'the damage batch must not enqueue while the listing batch '
            'is still awaiting its job',
      );

      gate.complete();
      final staged = await future;

      expect(staged, 2);
      expect(enqueueCalls.length, 2);
    },
  );

  test(
    'a FAILUREd job leaves carData untouched for that key (falls back to '
    'upload-after-create instead of attaching a bogus path)',
    () async {
      final listingPhoto = writeFakeJpeg('listing_fail.jpg');
      final carData = <String, dynamic>{
        'images': [listingPhoto.path],
      };

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        if (method == 'POST' && path == '/api/process-car-images') {
          return http.Response(
            json.encode({'success': true, 'job_ids': ['job-fail-1']}),
            202,
            headers: {'content-type': 'application/json'},
          );
        }
        if (method == 'GET' && path.startsWith('/api/jobs/')) {
          return http.Response(
            json.encode({'task_id': 'job-fail-1', 'state': 'FAILURE'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      });

      final staged = await SellPhotoPrestage.stageCarData(carData);

      expect(staged, 0);
      expect(
        carData['images'],
        [listingPhoto.path],
        reason: 'a failed job must leave the original local path in place',
      );
    },
  );

  test(
    'an enqueue rejection (400) is handled gracefully -- returns 0, never '
    'throws, and carData is left untouched',
    () async {
      final listingPhoto = writeFakeJpeg('listing_400.jpg');
      final carData = <String, dynamic>{
        'images': [listingPhoto.path],
      };
      enqueueOverride = (_) => http.Response(
        json.encode({'error': 'No image files provided'}),
        400,
        headers: {'content-type': 'application/json'},
      );

      final staged = await SellPhotoPrestage.stageCarData(carData);

      expect(staged, 0);
      expect(carData['images'], [listingPhoto.path]);
    },
  );
}
