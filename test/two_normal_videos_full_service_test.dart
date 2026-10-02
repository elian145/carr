// Section F.1 + F.3 (multi-video audit): the SAME two-normal-video
// scenario as `two_video_partial_failure_regression_test.dart`, but
// driven through the FULL public entry points real callers use --
// `PendingSellSubmissionService.submitFast()` / `.submit()` /
// `.resumeAll()` -- instead of calling `SellListingMediaUpload` directly.
// Proves the whole-stack contract (Section D):
//
//   F.1: two videos that BOTH succeed attach exactly once each, and a
//        later resumeAll() is a complete no-op.
//   F.3: one video (A) succeeds while its sibling (B) is permanently
//        rejected -- `submitFast()` rejects the WHOLE submission (Phase A
//        never reaches "every item complete" while B never lands), A's
//        own successful upload is never repeated across Phase A AND
//        multiple later resumeAll() retries, only B is ever retried, and
//        the durable record ends up `needsAttention` with the real
//        (already-created) carId retained -- never silently discarded.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

http.Response _jsonOk(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Same exact-boundary multipart extraction as
/// `two_video_partial_failure_regression_test.dart` -- see that file's
/// comment for why a guessed boundary charset is unsafe.
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

Future<void> _waitUntil(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (await condition()) return;
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> _baseCarData({List<dynamic>? videos}) => {
  'brand': 'toyota',
  'model': 'camry',
  'trim': 'base',
  'year': '2020',
  'mileage': '10000',
  'condition': 'used',
  'transmission': 'automatic',
  'fuel_type': 'gasoline',
  'color': 'black',
  'body_type': 'sedan',
  'seating': '5',
  'drive_type': 'fwd',
  'city': 'baghdad',
  'contact_phone': '07701234567',
  'images': <dynamic>[],
  'videos': videos ?? <dynamic>[],
  'damage_images': <dynamic>[],
  'server_transcode_videos': <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('two_normal_video_full_');
    final docsDir = Directory('${tempDir.path}/docs')..createSync(recursive: true);
    PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);
    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = true;
    debugSellSubmissionRetryBackoffOverride = (_) => Duration.zero;
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    ApiService.testHttpClient = null;
    TokenStore.testMode = false;
    TokenStore.resetForTests();
    debugSellSubmissionRetryBackoffOverride = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'F.1: two normal videos that BOTH succeed attach exactly once each '
    'via a full submit() call, and a later resumeAll() performs zero '
    'additional video-upload HTTP calls',
    () async {
      const draftId = 'two_good_videos';
      final videoA = File(p.join(tempDir.path, 'a.mp4'))
        ..writeAsBytesSync(List<int>.filled(32, 1));
      final videoB = File(p.join(tempDir.path, 'b.mp4'))
        ..writeAsBytesSync(List<int>.filled(32, 2));

      var carCreated = false;
      final attachedIds = <String>{};
      var videoUploadCalls = 0;

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;

        if (method == 'POST' && path == '/api/cars') {
          carCreated = true;
          return _jsonOk({
            'car': {'id': 'car_two_good', 'images': [], 'videos': []},
          }, 201);
        }

        final videoMatch = RegExp(r'^/api/cars/([^/]+)/videos$').firstMatch(path);
        if (method == 'POST' && videoMatch != null) {
          videoUploadCalls++;
          final ids = _clientMediaIdsInBody(request);
          final videos = <Map<String, dynamic>>[];
          for (final id in ids) {
            attachedIds.add(id);
            videos.add({'id': videos.length + 1, 'video_url': 'uploads/car_videos/$id.mp4'});
          }
          return _jsonOk({'videos': videos, 'rejected': <dynamic>[]}, 201);
        }

        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
          return _jsonOk({
            'media_status': attachedIds.length >= 2 ? 'ready' : 'processing',
            'items': attachedIds
                .map((id) => {
                      'client_media_id': id,
                      'kind': 'video',
                      'status': 'attached',
                      'phase_a_complete': true,
                    })
                .toList(),
            'phase_a_complete': attachedIds.length >= 2,
          });
        }

        if (method == 'GET' && RegExp(r'^/api/cars/[^/]+$').hasMatch(path)) {
          return _jsonOk({
            'car': {
              'id': 'car_two_good',
              'images': [],
              'videos': attachedIds
                  .map((id) => {'id': 1, 'video_url': 'uploads/car_videos/$id.mp4'})
                  .toList(),
            },
          });
        }

        return _jsonOk({'cars': []});
      });

      final carData = _baseCarData(videos: [videoA.path, videoB.path]);
      final result = await PendingSellSubmissionService.instance.submit(
        draftId: draftId,
        carData: carData,
      );

      expect(result, isNotNull);
      expect(carCreated, isTrue);
      expect(
        videoUploadCalls,
        1,
        reason: 'both videos are sent together in ONE multipart request',
      );
      expect(
        attachedIds.length,
        2,
        reason: 'both distinct videos attached exactly once each',
      );
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);

      final resumed = await PendingSellSubmissionService.instance.resumeAll();
      expect(resumed, isFalse);
      expect(
        videoUploadCalls,
        1,
        reason: 'resumeAll() after full completion must not re-upload '
            'either video',
      );
    },
  );

  test(
    'F.3: video A succeeds while sibling video B is permanently rejected '
    '-- submitFast() rejects the WHOLE submission (Phase A never fully '
    'completes while B never lands), A is never re-uploaded across Phase '
    'A and multiple resumeAll() retries, only B is ever retried, and the '
    'durable record ends up needsAttention with the real carId retained',
    () async {
      const draftId = 'one_good_one_bad_video';
      final videoA = File(p.join(tempDir.path, 'good.mp4'))
        ..writeAsBytesSync(List<int>.filled(32, 1));
      final videoB = File(p.join(tempDir.path, 'bad.mp4'))
        ..writeAsBytesSync(List<int>.filled(32, 2));

      // Deliberately NOT precomputed via `SellMediaIdentity` up front --
      // unlike `two_video_partial_failure_regression_test.dart` (which
      // calls `SellListingMediaUpload` directly on the ORIGINAL paths),
      // `PendingSellSubmissionService.submit()`/`submitFast()` durably
      // copies every picked file into `sell_draft_media/<draftId>/`
      // BEFORE uploading, so the real `client_media_id` is derived from
      // that COPY's path, not `videoA.path`/`videoB.path`. The first
      // multipart call always carries BOTH ids together (nothing is
      // attached yet to filter out), in the SAME order as
      // `carData['videos']` -- captured here on first sight instead.
      String? idA;
      String? idB;
      var goodUploadCallCount = 0;
      var badUploadAttemptCount = 0;
      var goodAttached = false;

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;

        if (method == 'POST' && path == '/api/cars') {
          return _jsonOk({
            'car': {'id': 'car_one_good_one_bad', 'images': [], 'videos': []},
          }, 201);
        }

        final videoMatch = RegExp(r'^/api/cars/([^/]+)/videos$').firstMatch(path);
        if (method == 'POST' && videoMatch != null) {
          final ids = _clientMediaIdsInBody(request);
          if (idA == null && ids.length >= 2) {
            idA = ids[0];
            idB = ids[1];
          }
          final videos = <Map<String, dynamic>>[];
          final rejected = <Map<String, dynamic>>[];
          for (final id in ids) {
            if (id == idB) {
              badUploadAttemptCount++;
              rejected.add({'filename': 'bad.mp4', 'reason': 'corrupt file'});
            } else if (id == idA) {
              goodUploadCallCount++;
              goodAttached = true;
              videos.add({'id': 1, 'video_url': 'uploads/car_videos/good.mp4'});
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
          if (idA == null || idB == null) {
            // Neither video has been attempted yet -- report incomplete
            // (never vacuously "phase_a_complete: true" over an empty
            // items list before the real ids are even known).
            return _jsonOk({
              'media_status': 'processing',
              'items': <dynamic>[],
              'phase_a_complete': false,
            });
          }
          return _jsonOk({
            'media_status': 'processing',
            'items': [
              {
                'client_media_id': idA,
                'kind': 'video',
                'status': goodAttached ? 'attached' : 'awaiting_upload',
                'phase_a_complete': goodAttached,
              },
              {
                'client_media_id': idB,
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
              'id': 'car_one_good_one_bad',
              'images': [],
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

      final carData = _baseCarData(videos: [videoA.path, videoB.path]);

      // submitFast() must reject -- Phase A never completes for B.
      await expectLater(
        PendingSellSubmissionService.instance.submitFast(
          draftId: draftId,
          carData: carData,
        ),
        throwsA(anything),
      );

      expect(
        goodUploadCallCount,
        1,
        reason: 'A uploads exactly once during Phase A',
      );
      expect(badUploadAttemptCount, greaterThanOrEqualTo(1));

      // Wait for the background worker (still running after submitFast's
      // rejection) to settle into needsAttention.
      SellSubmissionRecord? record;
      await _waitUntil(() async {
        record = await SellSubmissionStatePrefs.load(draftId);
        return record?.status == SellSubmissionStatus.needsAttention;
      });
      expect(record, isNotNull);
      expect(
        record!.carId,
        isNotEmpty,
        reason: 'the already-created listing must be retained, never lost',
      );
      final goodCallsAfterFirstRun = goodUploadCallCount;
      expect(
        goodCallsAfterFirstRun,
        1,
        reason: 'A must never be re-uploaded just because B failed, even '
            'once Phase B has also run and given up',
      );

      // `needsAttention` (unlike `retryable`) is deliberately NEVER
      // auto-retried by `resumeAll()` -- it requires an explicit
      // user-initiated retry (e.g. re-opening the draft and tapping
      // Submit again, which re-calls `submitFast()`/`submit()` for the
      // SAME draftId). Simulate exactly that: only B should be retried --
      // A must never be touched again.
      final badAttemptsBeforeRetry = badUploadAttemptCount;
      final resumedNoop = await PendingSellSubmissionService.instance.resumeAll();
      expect(
        resumedNoop,
        isFalse,
        reason: 'resumeAll() must never auto-retry a needsAttention record',
      );
      expect(badUploadAttemptCount, badAttemptsBeforeRetry);

      await expectLater(
        PendingSellSubmissionService.instance.submitFast(
          draftId: draftId,
          carData: carData,
        ),
        throwsA(anything),
      );
      await _waitUntil(() async {
        final r = await SellSubmissionStatePrefs.load(draftId);
        return r?.status == SellSubmissionStatus.needsAttention;
      });
      expect(
        goodUploadCallCount,
        goodCallsAfterFirstRun,
        reason: 'an explicit user-initiated retry must never re-upload '
            'the already-successful video A',
      );
      expect(
        badUploadAttemptCount,
        greaterThan(badAttemptsBeforeRetry),
        reason: 'an explicit user-initiated retry must retry the '
            'still-failing video B',
      );
    },
  );
}
