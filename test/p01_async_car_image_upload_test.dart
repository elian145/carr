// P-01 follow-up: proves the REAL mobile listing-photo upload path
// (`SellListingMediaUpload.uploadForCar`, used by the sell wizard's submit
// step -- see `sell_step5_logic.dart` -> `SellListingMediaUpload.uploadForCar`)
// now goes through the existing async job pipeline instead of blocking one
// HTTP request on the (potentially slow, Roboflow-backed) plate-blur call:
//
//   POST /api/cars/<id>/images?async=1   (existing endpoint, now used by
//                                          the real app, not just tests)
//     -> GET /api/jobs/<task_id>          (existing job-status endpoint)
//     -> POST /api/cars/<id>/images/attach (existing attach endpoint)
//
// No second job framework, no new endpoints -- this only proves the real
// Flutter call path now drives the already-existing async plumbing.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/sell_listing_media_upload.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory tempDir;
  late List<String> requestLog;
  late Map<String, String> jobStates;
  late List<List<String>> attachedPathsCalls;
  String? enqueueOverrideBody;
  int enqueueOverrideStatus = 202;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('p01_async_upload_');
    requestLog = <String>[];
    jobStates = <String, String>{};
    attachedPathsCalls = <List<String>>[];
    enqueueOverrideBody = null;
    enqueueOverrideStatus = 202;

    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');

    ApiService.testHttpClient = MockClient((request) async {
      final method = request.method.toUpperCase();
      final path = request.url.path;
      requestLog.add('$method $path?${request.url.query}');

      // POST /api/cars/<id>/images (enqueue) -- but NOT .../images/attach.
      if (method == 'POST' && RegExp(r'^/api/cars/[^/]+/images$').hasMatch(path)) {
        final overrideBody = enqueueOverrideBody;
        if (overrideBody != null) {
          return http.Response(
            overrideBody,
            enqueueOverrideStatus,
            headers: {'content-type': 'application/json'},
          );
        }
        // The real app must opt into async processing -- this is the crux
        // of the P-01 follow-up (before this fix, Flutter never sent
        // `async=1` and every upload blocked on Roboflow inline).
        expect(
          request.url.queryParameters['async'],
          '1',
          reason: 'the real mobile upload path must request async processing',
        );
        final jobId = 'job-${jobStates.length + 1}';
        jobStates[jobId] = 'SUCCESS';
        return http.Response(
          json.encode({
            'message': '1 image(s) queued for processing',
            'job_ids': [jobId],
          }),
          202,
          headers: {'content-type': 'application/json'},
        );
      }

      // GET /api/jobs/<task_id>
      if (method == 'GET' && path.startsWith('/api/jobs/')) {
        final jobId = path.substring('/api/jobs/'.length);
        final state = jobStates[jobId] ?? 'SUCCESS';
        if (state == 'SUCCESS') {
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
        return http.Response(
          json.encode({
            'task_id': jobId,
            'state': 'FAILURE',
            'error': 'job_failed',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // POST /api/cars/<id>/images/attach
      if (method == 'POST' &&
          RegExp(r'^/api/cars/[^/]+/images/attach$').hasMatch(path)) {
        final decoded = json.decode(request.body) as Map;
        final paths = List<String>.from(decoded['paths'] as List);
        attachedPathsCalls.add(paths);
        var i = 0;
        return http.Response(
          json.encode({
            'images': paths
                .map((p) => {'id': ++i, 'image_url': 'https://cdn.example.test/$p'})
                .toList(),
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      // GET /api/cars/<id> -- car-detail lookups used by `_remoteImageCount`
      // / `_fetchCarMap` before and after the upload.
      if (method == 'GET' && RegExp(r'^/api/cars/[^/]+$').hasMatch(path)) {
        return http.Response(
          json.encode({
            'car': {
              'id': path.split('/').last,
              'images': <dynamic>[],
              'videos': <dynamic>[],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // Everything else this flow touches (primary-image/layout PUTs, the
      // post-upload `getCars(refresh: true)` list refresh) is incidental to
      // this test and already exception-guarded by the caller -- succeed
      // harmlessly so it never masks the assertions above.
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      );
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

  test(
    'real upload path enqueues async, polls the job, then attaches the '
    'processed path (no synchronous Roboflow wait on the HTTP request)',
    () async {
      final photo = File('${tempDir.path}/photo.jpg');
      photo.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

      final confirmed = await SellListingMediaUpload.uploadForCar(
        carId: 'car_async_1',
        carData: {
          'images': [photo.path],
        },
      );

      expect(confirmed, isTrue);
      expect(
        requestLog.any(
          (r) =>
              r.startsWith('POST /api/cars/car_async_1/images?') &&
              r.contains('async=1'),
        ),
        isTrue,
        reason: 'expected the multipart upload to opt into async processing',
      );
      expect(
        requestLog.any((r) => r.startsWith('GET /api/jobs/')),
        isTrue,
        reason: 'expected the job-status endpoint to be polled',
      );
      expect(
        attachedPathsCalls,
        hasLength(1),
        reason: 'the processed image must still be attached to the car',
      );
      expect(attachedPathsCalls.single, ['uploads/car_photos/job-1.jpg']);
    },
  );

  test(
    'an enqueue rejection surfaces as a failure without a false success or '
    'an attach call',
    () async {
      enqueueOverrideBody = json.encode({
        'message': 'No valid images were uploaded (bad file type).',
      });
      enqueueOverrideStatus = 400;

      final photo = File('${tempDir.path}/photo.jpg');
      photo.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

      await expectLater(
        SellListingMediaUpload.uploadForCar(
          carId: 'car_async_2',
          carData: {
            'images': [photo.path],
          },
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        attachedPathsCalls,
        isEmpty,
        reason: 'a rejected enqueue must never reach the attach step',
      );
    },
  );
}
