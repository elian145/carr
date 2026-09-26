// Phase 3B resume-matrix tests for `SellServerTranscodeVideoRunner` (see
// `lib/features/sell/sell_server_transcode_runner.dart`) -- covers the
// force-close/network-loss resume scenarios from the task's test matrix
// (letters refer to that matrix; A/B/C -- local-compression decision
// logic -- and M/N -- multi-media/UI-level dedupe -- are covered by
// `sell_video_compression_test.dart` and the wider Sell submission test
// suite respectively, not duplicated here).
//
// `ApiService.testHttpClient` (a `MockClient`) intercepts every HTTP call
// this runner makes -- sign/finalize/attach (`_makeAuthenticatedRequest`)
// AND the direct-to-R2 PUT (`uploadVideoSourceToR2`, also routed through
// `ApiService._httpClient`) -- so no real network/device dependency,
// mirroring `test/sell_async_job_tracker_test.dart`'s existing convention
// for the adjacent image-job-polling pipeline.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/sell_server_transcode_runner.dart';
import 'package:car_listing_app/features/sell/sell_server_transcode_video.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const draftId = 'draft_transcode_1';
  const carId = 'car_42';
  late Directory tempDir;
  late ServerTranscodeVideoSpec spec;

  Future<void> seedRecord() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await SellSubmissionStatePrefs.upsert(
      SellSubmissionRecord(
        draftId: draftId,
        status: SellSubmissionStatus.inProgress,
        carId: carId,
        carData: const {'videos': <dynamic>[]},
        idempotencyKey: 'sell-create-$draftId',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<ServerTranscodeVideoState> loadState() async {
    final record = await SellSubmissionStatePrefs.load(draftId);
    return record!.serverTranscodeVideos[spec.draftMediaId]!;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = true;
    final base = Directory(
      p.join(Directory.current.path, '.dart_tool', 'test_tmp'),
    )..createSync(recursive: true);
    tempDir = base.createTempSync('sell_server_transcode_');
    final sourcePath = p.join(tempDir.path, 'source.mov');
    final bytes = List<int>.filled(2048, 0x9);
    File(sourcePath).writeAsBytesSync(bytes);
    spec = ServerTranscodeVideoSpec(
      draftMediaId: 'vst_test_1',
      localSourcePath: sourcePath,
      sourceByteSize: bytes.length,
      sourceMimeType: 'video/quicktime',
    );
    await seedRecord();
  });

  tearDown(() {
    ApiService.testHttpClient = null;
    TokenStore.testMode = false;
    TokenStore.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  http.Response jsonOk(Map<String, dynamic> body, [int status = 200]) =>
      http.Response(
        json.encode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  group('happy path', () {
    test(
      'a single processAll() call advances requiresServerTranscode all '
      'the way through to attached when every step succeeds immediately '
      '(sign -> PUT -> finalize -> poll(SUCCESS) -> attach)',
      () async {
        var signCalls = 0, putCalls = 0, finalizeCalls = 0, pollCalls = 0,
            attachCalls = 0;
        ApiService.testHttpClient = MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/media/r2/sign-video-source-upload') {
            signCalls++;
            return jsonOk({
              'upload_url': 'https://r2.example.test/staging/key123',
              'staging_key': 'staging/key123',
              'expires_in': 900,
              'max_bytes': 500 * 1024 * 1024,
            });
          }
          if (request.method == 'PUT' &&
              request.url.host == 'r2.example.test') {
            putCalls++;
            return http.Response('', 200);
          }
          if (path == '/api/media/r2/finalize-video-source-upload') {
            finalizeCalls++;
            return jsonOk({
              'status': 'staged',
              'staging_key': 'staging/key123',
              'size': spec.sourceByteSize,
              'task_id': 'task-abc',
              'job_state': 'queued',
            });
          }
          if (path == '/api/jobs/task-abc') {
            pollCalls++;
            return jsonOk({'task_id': 'task-abc', 'state': 'SUCCESS'});
          }
          if (path == '/api/media/r2/attach-transcoded-video') {
            attachCalls++;
            return jsonOk({
              'message': 'attached',
              'video': {'id': 7, 'video_url': 'https://cdn/v.mp4'},
            }, 201);
          }
          return http.Response('{"message": "unexpected"}', 404);
        });

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );

        final state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.attached);
        expect(state.attachedVideo, {'id': 7, 'video_url': 'https://cdn/v.mp4'});
        expect(signCalls, 1);
        expect(putCalls, 1);
        expect(finalizeCalls, 1);
        expect(pollCalls, 1);
        expect(attachCalls, 1);

        expect(
          await SellServerTranscodeVideoRunner.allAttached(
            draftId: draftId,
            specs: [spec],
          ),
          isTrue,
        );
      },
    );
  });

  group('scenario D/E/F/G: crash between steps -- resume never duplicates work', () {
    test(
      'PUT fails transiently (app-equivalent: never confirmed) -- resume '
      'retries sign+PUT (never skipped) and then proceeds normally',
      () async {
        var putAttempts = 0;
        ApiService.testHttpClient = MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/media/r2/sign-video-source-upload') {
            return jsonOk({
              'upload_url': 'https://r2.example.test/staging/key123',
              'staging_key': 'staging/key123',
              'expires_in': 900,
              'max_bytes': 500 * 1024 * 1024,
            });
          }
          if (request.method == 'PUT') {
            putAttempts++;
            if (putAttempts == 1) {
              throw const SocketException('connection reset');
            }
            return http.Response('', 200);
          }
          if (path == '/api/media/r2/finalize-video-source-upload') {
            return jsonOk({
              'status': 'staged',
              'task_id': 'task-1',
              'job_state': 'queued',
            });
          }
          if (path == '/api/jobs/task-1') {
            return jsonOk({'task_id': 'task-1', 'state': 'SUCCESS'});
          }
          if (path == '/api/media/r2/attach-transcoded-video') {
            return jsonOk({
              'video': {'id': 1},
            });
          }
          return http.Response('{}', 404);
        });

        // First call: fails during PUT.
        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        var state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.failedRecoverable);
        expect(state.putConfirmed, isFalse);

        // Resume: re-signs and re-PUTs (never skipped since putConfirmed
        // was never set), then completes.
        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.attached);
        expect(putAttempts, 2);
      },
    );

    test(
      'scenario E/G: PUT succeeds but finalize\'s response is lost '
      '(timeout) -- resume finalizes again for the SAME draft_media_id '
      'and NEVER re-signs/re-PUTs (putConfirmed already true)',
      () async {
        var signCalls = 0, putCalls = 0, finalizeCalls = 0;
        ApiService.testHttpClient = MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/media/r2/sign-video-source-upload') {
            signCalls++;
            return jsonOk({
              'upload_url': 'https://r2.example.test/staging/key123',
            });
          }
          if (request.method == 'PUT') {
            putCalls++;
            return http.Response('', 200);
          }
          if (path == '/api/media/r2/finalize-video-source-upload') {
            finalizeCalls++;
            if (finalizeCalls == 1) {
              // A dropped connection AFTER the server processed the
              // request -- the client never sees the response, but this
              // must NOT be silently retried by the transport layer
              // itself (only `isStaleHttpClientError`'s specific
              // substrings are auto-retried there; this message
              // deliberately avoids all of them) so it reaches the
              // runner's own recoverable-failure handling instead.
              throw const SocketException('finalize response lost');
            }
            // Idempotent backend dedupe: SAME task_id on retry.
            return jsonOk({'task_id': 'task-same', 'job_state': 'queued'});
          }
          if (path == '/api/jobs/task-same') {
            return jsonOk({'task_id': 'task-same', 'state': 'SUCCESS'});
          }
          if (path == '/api/media/r2/attach-transcoded-video') {
            return jsonOk({
              'video': {'id': 2},
            });
          }
          return http.Response('{}', 404);
        });

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        var state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.failedRecoverable);
        expect(state.putConfirmed, isTrue, reason: 'PUT itself succeeded');
        expect(state.taskId, isNull);

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.attached);
        expect(signCalls, 1, reason: 'never re-signed after a confirmed PUT');
        expect(putCalls, 1, reason: 'never re-uploaded after a confirmed PUT');
        expect(finalizeCalls, 2);
      },
    );
  });

  group('scenario H/K: polling survives a network blip and an app-close mid-job', () {
    test(
      'a network/5xx error while ALREADY polling (i.e. this is not the '
      'first poll -- `before` is already transcodeProcessing) keeps '
      'task_id and stops for this call instead of hot-looping or '
      'abandoning it; the NEXT processAll() call retries the SAME job id '
      'and completes',
      () async {
        var pollCalls = 0;
        ApiService.testHttpClient = MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/media/r2/sign-video-source-upload') {
            return jsonOk({'upload_url': 'https://r2.example.test/k'});
          }
          if (request.method == 'PUT') return http.Response('', 200);
          if (path == '/api/media/r2/finalize-video-source-upload') {
            // job_state: 'processing' -> starting status is already
            // transcodeProcessing (not transcodeQueued), so a same-call
            // poll failure below reproduces the EXACT "no forward
            // progress this call" condition the runner uses to stop
            // (see `_processOne`'s `if (state.status == before) break;`).
            return jsonOk({
              'task_id': 'task-poll',
              'job_state': 'processing',
            });
          }
          if (path == '/api/jobs/task-poll') {
            pollCalls++;
            if (pollCalls == 1) {
              return http.Response('{"message":"down"}', 503);
            }
            return jsonOk({'task_id': 'task-poll', 'state': 'SUCCESS'});
          }
          if (path == '/api/media/r2/attach-transcoded-video') {
            return jsonOk({
              'video': {'id': 3},
            });
          }
          return http.Response('{}', 404);
        });

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        var state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.transcodeProcessing);
        expect(state.taskId, 'task-poll', reason: 'must survive a 5xx poll');

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.attached);
      },
    );

    test(
      'scenario H: a durably-persisted still-processing job (app closed '
      'mid-job, exactly what a prior call would have left behind) keeps '
      'task_id intact and is picked back up -- NOT re-signed/re-PUT/'
      're-finalized -- by the very next processAll() call',
      () async {
        // Seed state exactly as a prior `processAll()` call would have
        // left it after finalize succeeded but the job had not yet
        // reached a terminal state (see the poll step's own budget-
        // exhaustion path in `sell_server_transcode_runner.dart`).
        final preState = ServerTranscodeVideoState.initial(spec.draftMediaId)
            .copyWith(
          status: ServerTranscodeVideoStatus.transcodeProcessing,
          putConfirmed: true,
          taskId: 'task-slow',
        );
        final record = (await SellSubmissionStatePrefs.load(draftId))!;
        await SellSubmissionStatePrefs.upsert(
          record.copyWith(
            serverTranscodeVideos: {spec.draftMediaId: preState},
          ),
        );

        ApiService.testHttpClient = MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/jobs/task-slow') {
            return jsonOk({'task_id': 'task-slow', 'state': 'SUCCESS'});
          }
          if (path == '/api/media/r2/attach-transcoded-video') {
            return jsonOk({
              'video': {'id': 4},
            });
          }
          // Any sign/PUT/finalize call would mean the resume incorrectly
          // redid an already-completed earlier step.
          fail('unexpected call to ${request.url.path}');
        });

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        final state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.attached);
      },
    );
  });

  group('scenario I/J: attach crash recovery', () {
    test(
      'scenario I: job already SUCCESS but the app "died" before attach '
      '-- resume attaches directly, skipping sign/PUT/finalize/poll',
      () async {
        // Seed state as if a previous run already reached
        // transcodeSucceeded (poll confirmed SUCCESS) but never attached.
        final preState = ServerTranscodeVideoState.initial(spec.draftMediaId)
            .copyWith(
          status: ServerTranscodeVideoStatus.transcodeSucceeded,
          putConfirmed: true,
          transcodeConfirmed: true,
          taskId: 'task-done',
        );
        final record = (await SellSubmissionStatePrefs.load(draftId))!;
        await SellSubmissionStatePrefs.upsert(
          record.copyWith(
            serverTranscodeVideos: {spec.draftMediaId: preState},
          ),
        );

        var attachCalls = 0;
        ApiService.testHttpClient = MockClient((request) async {
          if (request.url.path == '/api/media/r2/attach-transcoded-video') {
            attachCalls++;
            return jsonOk({
              'video': {'id': 5},
            });
          }
          // Any other call means the resume incorrectly redid an earlier
          // step.
          fail('unexpected call to ${request.url.path}');
        });

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );

        final state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.attached);
        expect(attachCalls, 1);
      },
    );

    test(
      'scenario J: attach succeeds server-side but the response is lost '
      '(timeout) -- resume attaches again with the SAME identifiers and '
      'the idempotent backend returns the same CarVideo',
      () async {
        final preState = ServerTranscodeVideoState.initial(spec.draftMediaId)
            .copyWith(
          status: ServerTranscodeVideoStatus.transcodeSucceeded,
          putConfirmed: true,
          transcodeConfirmed: true,
          taskId: 'task-done',
        );
        final record = (await SellSubmissionStatePrefs.load(draftId))!;
        await SellSubmissionStatePrefs.upsert(
          record.copyWith(
            serverTranscodeVideos: {spec.draftMediaId: preState},
          ),
        );

        var attachCalls = 0;
        String? lastCarId, lastDraftMediaId, lastTaskId;
        ApiService.testHttpClient = MockClient((request) async {
          if (request.url.path == '/api/media/r2/attach-transcoded-video') {
            attachCalls++;
            final body = json.decode(request.body) as Map;
            lastCarId = body['car_id'] as String?;
            lastDraftMediaId = body['draft_media_id'] as String?;
            lastTaskId = body['task_id'] as String?;
            if (attachCalls == 1) {
              throw const SocketException('attach response lost');
            }
            return jsonOk({
              'video': {'id': 9},
            });
          }
          fail('unexpected call to ${request.url.path}');
        });

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        var state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.failedRecoverable);

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.attached);
        expect(state.attachedVideo, {'id': 9});
        expect(attachCalls, 2);
        expect(lastCarId, carId);
        expect(lastDraftMediaId, spec.draftMediaId);
        expect(lastTaskId, 'task-done');
      },
    );
  });

  group('scenario L: feature disabled -- no infinite retry, no fallback upload', () {
    test(
      'a 404 from sign-video-source-upload marks the video failedPermanent '
      '+ featureDisabled, and a second processAll() call never retries it '
      '(no further HTTP calls at all)',
      () async {
        var callCount = 0;
        ApiService.testHttpClient = MockClient((request) async {
          callCount++;
          return http.Response('{"message": "Not found"}', 404);
        });

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        var state = await loadState();
        expect(state.status, ServerTranscodeVideoStatus.failedPermanent);
        expect(state.featureDisabled, isTrue);
        expect(state.isTerminal, isTrue);
        expect(callCount, 1);

        // Resume: must NOT retry a terminal failure.
        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );
        expect(
          callCount,
          1,
          reason: 'a permanently-failed (feature-disabled) video must '
              'never be auto-retried',
        );

        final disabledIds = await SellServerTranscodeVideoRunner
            .featureDisabledDraftMediaIds(draftId: draftId, specs: [spec]);
        expect(disabledIds, [spec.draftMediaId]);
      },
    );
  });

  group('scenario O: no presigned URL is ever persisted', () {
    test(
      'after a successful sign+PUT, the persisted state JSON contains no '
      'presigned upload_url anywhere',
      () async {
        ApiService.testHttpClient = MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/media/r2/sign-video-source-upload') {
            return jsonOk({
              'upload_url':
                  'https://r2.example.test/staging/key123?X-Amz-Signature=SECRET',
            });
          }
          if (request.method == 'PUT') return http.Response('', 200);
          if (path == '/api/media/r2/finalize-video-source-upload') {
            // Stop right after staging -- enough to prove the upload_url
            // never made it into the persisted state.
            throw const SocketException('offline');
          }
          return http.Response('{}', 404);
        });

        await SellServerTranscodeVideoRunner.processAll(
          draftId: draftId,
          carId: carId,
          specs: [spec],
        );

        final record = await SellSubmissionStatePrefs.load(draftId);
        final rawJson = json.encode(
          record!.serverTranscodeVideos.map((k, v) => MapEntry(k, v.toJson())),
        );
        expect(rawJson.contains('X-Amz-Signature'), isFalse);
        expect(rawJson.contains('r2.example.test'), isFalse);
        expect(rawJson.toLowerCase().contains('upload_url'), isFalse);
      },
    );
  });

  test(
    'attachedCount() and allAttached() reflect durable per-video status',
    () async {
      expect(
        await SellServerTranscodeVideoRunner.attachedCount(
          draftId: draftId,
          specs: [spec],
        ),
        0,
      );
      expect(
        await SellServerTranscodeVideoRunner.allAttached(
          draftId: draftId,
          specs: [spec],
        ),
        isFalse,
      );

      final record = (await SellSubmissionStatePrefs.load(draftId))!;
      await SellSubmissionStatePrefs.upsert(
        record.copyWith(
          serverTranscodeVideos: {
            spec.draftMediaId: ServerTranscodeVideoState.initial(
              spec.draftMediaId,
            ).copyWith(
              status: ServerTranscodeVideoStatus.attached,
              attachedVideo: const {},
            ),
          },
        ),
      );

      expect(
        await SellServerTranscodeVideoRunner.attachedCount(
          draftId: draftId,
          specs: [spec],
        ),
        1,
      );
      expect(
        await SellServerTranscodeVideoRunner.allAttached(
          draftId: draftId,
          specs: [spec],
        ),
        isTrue,
      );
    },
  );
}
