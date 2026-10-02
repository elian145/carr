// Real-device regression: "I submitted TWO videos. One video encountered
// an error and did not upload."
//
// Root cause (client-side, `lib/features/sell/sell_listing_media_upload.dart`):
// both `runPhaseAOnly` (Phase A) and `uploadForCar` (Phase B)'s normal-
// video blocks (a) unconditionally credited `videosToUpload.length`
// regardless of what `POST /api/cars/<id>/videos` actually confirmed, and
// (b) used a coarse `existingVideoCount >= videosToUpload.length` count
// check that cannot tell WHICH of several videos already landed -- so
// once one video in a batch is permanently rejected while a sibling
// succeeds, every later Phase-A/Phase-B/resume pass re-sent the WHOLE
// batch again, including the already-successful sibling (a genuine
// duplicate upload).
//
// These tests call `SellListingMediaUpload.runPhaseAOnly` /
// `.uploadForCar` directly (the same functions
// `PendingSellSubmissionService` calls) with two normal videos -- one
// that always succeeds server-side, one that is always rejected -- and
// prove the successful video is uploaded exactly once, across BOTH Phase
// A and multiple Phase-B/resume passes.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/sell_listing_media_upload.dart';
import 'package:car_listing_app/features/sell/sell_media_identity.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _jsonOk(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Extracts every `client_media_id` VALUE sent in a multipart request, in
/// the order the parts appear. Splits on the EXACT boundary declared in
/// the request's own `Content-Type` header (never a guessed charset --
/// `package:http`'s randomly-generated boundaries can contain `+`, `/`,
/// `=`, etc, which an approximate regex can miss on some runs and not
/// others).
List<String> _clientMediaIdsInBody(http.Request request) {
  final contentType = request.headers['content-type'] ?? '';
  final boundaryMatch = RegExp('boundary=([^;]+)').firstMatch(contentType);
  final boundary = boundaryMatch?.group(1)?.trim();
  if (boundary == null || boundary.isEmpty) return const [];
  final text = latin1.decode(request.bodyBytes);
  final out = <String>[];
  for (final part in text.split('--$boundary')) {
    final headerEnd = part.indexOf('\r\n\r\n');
    if (headerEnd == -1) continue;
    final headers = part.substring(0, headerEnd);
    if (!headers.contains('name="client_media_id"')) continue;
    final rest = part.substring(headerEnd + 4);
    final value = rest.split('\r\n').first.trim();
    out.add(value);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('two_video_regression_');
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
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
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'two normal videos, one permanently rejected: the successful sibling '
    'is uploaded exactly once across Phase A AND multiple later Phase-B/'
    'resume passes -- it is never re-sent just because its sibling keeps '
    'failing',
    () async {
      const carId = 'car_two_video_1';
      final goodVideo = File('${tempDir.path}/good.mp4')
        ..writeAsBytesSync(List<int>.filled(32, 1));
      final badVideo = File('${tempDir.path}/bad.mp4')
        ..writeAsBytesSync(List<int>.filled(32, 2));
      final carData = <String, dynamic>{
        'videos': [goodVideo.path, badVideo.path],
        'images': <dynamic>[],
        'damage_images': <dynamic>[],
      };

      // Precompute the EXACT stable ids the real code derives (an
      // FNV-1a hash of the local path) so this test's mock can key its
      // behavior off the real id, not a guessed one. Valid because this
      // test calls `runPhaseAOnly`/`uploadForCar` directly on the SAME
      // `carData['videos']` list (no durable-copy rewrite in between,
      // unlike the full `PendingSellSubmissionService` pipeline).
      final goodId = SellMediaIdentity.forNormalVideoItem(goodVideo.path)!;
      final badId = SellMediaIdentity.forNormalVideoItem(badVideo.path)!;

      var goodUploadCallCount = 0;
      var badUploadAttemptCount = 0;
      var goodAttached = false;
      final mediaConfirmedDeltas = <int>[];

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;

        final videoMatch =
            RegExp(r'^/api/cars/([^/]+)/videos$').firstMatch(path);
        if (method == 'POST' && videoMatch != null) {
          final ids = _clientMediaIdsInBody(request);
          final videos = <Map<String, dynamic>>[];
          final rejected = <Map<String, dynamic>>[];
          for (final id in ids) {
            if (id == badId) {
              badUploadAttemptCount++;
              rejected.add({'filename': 'bad.mp4', 'reason': 'corrupt file'});
            } else if (id == goodId) {
              goodUploadCallCount++;
              goodAttached = true;
              videos.add({
                'id': 1,
                'video_url': 'uploads/car_videos/good.mp4',
              });
            }
          }
          if (videos.isEmpty) {
            return _jsonOk({
              'message': 'No valid videos uploaded',
              'videos': <dynamic>[],
              'rejected': rejected,
            }, 400);
          }
          return _jsonOk({'videos': videos, 'rejected': rejected}, 201);
        }

        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
          return _jsonOk({
            'media_status': 'processing',
            'items': [
              {
                'client_media_id': goodId,
                'kind': 'video',
                'status': goodAttached ? 'attached' : 'awaiting_upload',
                'phase_a_complete': goodAttached,
              },
              {
                'client_media_id': badId,
                'kind': 'video',
                'status': 'awaiting_upload',
                'phase_a_complete': false,
              },
            ],
            'phase_a_complete': false,
          });
        }

        if (method == 'GET' && RegExp(r'^/api/cars/[^/]+$').hasMatch(path)) {
          return _jsonOk({
            'car': {
              'id': carId,
              'images': <dynamic>[],
              'videos': goodAttached
                  ? [
                      {'id': 1, 'video_url': 'uploads/car_videos/good.mp4'},
                    ]
                  : <dynamic>[],
            },
          });
        }

        return _jsonOk({'cars': []});
      });

      // ---- Phase A -----------------------------------------------------
      await SellListingMediaUpload.runPhaseAOnly(
        carId: carId,
        carData: carData,
        onMediaConfirmed: (delta) async => mediaConfirmedDeltas.add(delta),
      );
      expect(
        goodUploadCallCount,
        1,
        reason: 'the good video must be uploaded once during Phase A',
      );
      expect(
        badUploadAttemptCount,
        1,
        reason: 'the bad video is attempted once during Phase A '
            '(and rejected)',
      );
      expect(
        mediaConfirmedDeltas,
        [1],
        reason: 'Phase A must credit ONLY the 1 video the backend actually '
            'confirmed (`response["videos"].length`), never the full '
            'requested count of 2 -- this is the exact overcounting bug '
            'this test guards against',
      );

      // ---- Phase B, pass 1 (e.g. immediately after Phase A) ------------
      // `uploadForCar` deliberately still THROWS when a video fails (by
      // design -- "the failure still has to reach the caller so the user
      // isn't told the listing published intact"); what this test cares
      // about is the SIDE EFFECT, not whether it throws.
      await expectLater(
        SellListingMediaUpload.uploadForCar(carId: carId, carData: carData),
        throwsA(anything),
      );
      expect(
        goodUploadCallCount,
        1,
        reason: 'Phase B must NOT re-upload the already-successful video '
            'just because its sibling failed Phase A -- this is the exact '
            'real-device duplicate-upload regression',
      );
      expect(
        badUploadAttemptCount,
        2,
        reason: 'Phase B should still retry the actually-failing video',
      );

      // ---- Phase B, pass 2 (e.g. a later resumeAll() retry) -------------
      await expectLater(
        SellListingMediaUpload.uploadForCar(carId: carId, carData: carData),
        throwsA(anything),
      );
      expect(
        goodUploadCallCount,
        1,
        reason: 'a SECOND retry pass must still never re-upload the good '
            'video',
      );
      expect(badUploadAttemptCount, 3);
    },
  );
}
