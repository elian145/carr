// Phase 3B end-to-end/orchestration tests, driven through the SAME public
// entry points the real app uses -- `PendingSellSubmissionService.instance
// .submit()` / `.resumeAll()` -- rather than calling
// `SellServerTranscodeVideoRunner` directly (already unit-tested in
// `test/sell_server_transcode_runner_test.dart`). Covers the two resume-
// matrix letters that specifically require the FULL orchestration stack
// (car creation -> normal images -> normal videos -> server-transcode
// videos -> damage images, all sharing one `SellSubmissionRecord`):
//
//   M. Mixed-media dedupe: normal images + a normal (already-compressed)
//      video + a server-transcode video all upload/attach exactly once;
//      already-completed media (whether the whole submission already
//      finished, or just one item within it) is never repeated.
//   N. No double runners on reopen: two overlapping `resumeAll()` triggers
//      (or two overlapping `submit()` calls) for the SAME draft must not
//      run the server-transcode video's finalize/poll/attach sequence
//      more than once -- the existing `_activeRuns` dedup
//      (`PendingSellSubmissionService._ensureRunning`) must hold even
//      while a step is genuinely still in flight, not just when the two
//      triggers happen to be scheduled far apart.
//
// Same fake-server-via-MockClient convention as
// `test/pending_sell_submission_service_test.dart` and
// `test/sell_server_transcode_runner_test.dart`, sized down to only what
// these two scenarios need.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/features/sell/sell_server_transcode_video.dart';
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

Map<String, dynamic> _carData({
  List<dynamic>? images,
  List<dynamic>? videos,
  List<dynamic>? serverTranscodeVideos,
}) => {
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
  'images': images ?? <dynamic>[],
  'videos': videos ?? <dynamic>[],
  'damage_images': <dynamic>[],
  'server_transcode_videos': serverTranscodeVideos ?? <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  late Map<String, Map<String, dynamic>> carsById;
  late int carIdCounter;
  late int imageRowIdCounter;
  late int videoRowIdCounter;
  late List<List<String>> imageAttachCallsLog;
  late List<String> videoUploadLog;
  late List<String> signCallsLog; // draft_media_id per call
  late int putCalls;
  late List<String> finalizeCallsLog; // draft_media_id per call
  late int pollCalls;
  late List<Map<String, String>> attachTranscodeCallsLog; // {carId, draftMediaId, taskId}
  Completer<void>? finalizeGate;
  // Scenario O2 only: makes the FIRST poll attempt for one specific
  // task_id fail with a transient 503, while every other poll (any other
  // task, or that same task's later attempts) succeeds normally -- lets a
  // test force one video to stall for a whole `processAll()` call without
  // waiting out any real poll budget/delay.
  String? pollFailFirstForTaskId;
  late Map<String, int> pollAttemptCountByTaskId;
  // Scenario O2 only: overrides finalize's `job_state` from the default
  // `'queued'` to `'processing'` -- see that test's own comment for why.
  String? finalizeJobStateOverride;

  String taskIdFor(String draftMediaId) => 'task_$draftMediaId';

  Future<String> writeLocalFile(String name, {int bytes = 256}) async {
    final f = File(p.join(tempDir.path, name));
    f.writeAsBytesSync(List<int>.filled(bytes, 0x5));
    return f.path;
  }

  Future<void> seedRecord(SellSubmissionRecord record) =>
      SellSubmissionStatePrefs.upsert(record);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sell_transcode_orch_');
    final docsDir = Directory(p.join(tempDir.path, 'docs'))
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);

    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = true;
    debugSellSubmissionRetryBackoffOverride = (_) => Duration.zero;

    carsById = <String, Map<String, dynamic>>{};
    carIdCounter = 0;
    imageRowIdCounter = 0;
    videoRowIdCounter = 0;
    imageAttachCallsLog = <List<String>>[];
    videoUploadLog = <String>[];
    signCallsLog = <String>[];
    putCalls = 0;
    finalizeCallsLog = <String>[];
    pollCalls = 0;
    attachTranscodeCallsLog = <Map<String, String>>[];
    finalizeGate = null;
    pollFailFirstForTaskId = null;
    pollAttemptCountByTaskId = <String, int>{};
    finalizeJobStateOverride = null;

    ApiService.testHttpClient = MockClient((request) async {
      final method = request.method.toUpperCase();
      final path = request.url.path;

      // ---- POST /api/cars (create) --------------------------------------
      if (method == 'POST' && path == '/api/cars') {
        carIdCounter++;
        final id = 'car_$carIdCounter';
        carsById[id] = {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]};
        return http.Response(
          json.encode({'car': carsById[id]}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- POST /api/cars/<id>/images/attach -----------------------------
      final attachMatch =
          RegExp(r'^/api/cars/([^/]+)/images/attach$').firstMatch(path);
      if (method == 'POST' && attachMatch != null) {
        final id = attachMatch.group(1)!;
        final decoded = json.decode(request.body) as Map;
        final paths = List<String>.from(decoded['paths'] as List);
        final kind = (decoded['kind'] ?? 'listing').toString();
        imageAttachCallsLog.add(paths);
        final car = carsById.putIfAbsent(
          id,
          () => {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]},
        );
        final rows = <Map<String, dynamic>>[];
        for (final path in paths) {
          imageRowIdCounter++;
          final row = {'id': imageRowIdCounter, 'kind': kind, 'source': path};
          rows.add(row);
          (car['images'] as List).add(row);
        }
        return http.Response(
          json.encode({
            'images':
                rows.map((r) => {'id': r['id'], 'image_url': r['source']}).toList(),
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- POST /api/cars/<id>/videos (normal multipart video) ----------
      final videoMatch = RegExp(r'^/api/cars/([^/]+)/videos$').firstMatch(path);
      if (method == 'POST' && videoMatch != null) {
        final id = videoMatch.group(1)!;
        videoUploadLog.add(id);
        videoRowIdCounter++;
        final car = carsById.putIfAbsent(
          id,
          () => {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]},
        );
        (car['videos'] as List).add({'id': videoRowIdCounter});
        return http.Response(
          json.encode({'videos': [{'id': videoRowIdCounter}]}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- Phase 3B: sign-video-source-upload ----------------------------
      if (method == 'POST' && path == '/api/media/r2/sign-video-source-upload') {
        final decoded = json.decode(request.body) as Map;
        final draftMediaId = (decoded['draft_media_id'] ?? '').toString();
        signCallsLog.add(draftMediaId);
        return http.Response(
          json.encode({
            'upload_url': 'https://r2.fake.test/staging/$draftMediaId',
            'staging_key': 'staging/$draftMediaId',
            'expires_in': 900,
            'max_bytes': 500 * 1024 * 1024,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- Phase 3B: direct-to-R2 PUT (fake host, no /api prefix) --------
      if (method == 'PUT' && request.url.host == 'r2.fake.test') {
        putCalls++;
        return http.Response('', 200);
      }

      // ---- Phase 3B: finalize-video-source-upload (idempotent enqueue) --
      if (method == 'POST' &&
          path == '/api/media/r2/finalize-video-source-upload') {
        final decoded = json.decode(request.body) as Map;
        final draftMediaId = (decoded['draft_media_id'] ?? '').toString();
        finalizeCallsLog.add(draftMediaId);
        // Scenario N: lets a test hold this call open to force two
        // concurrent orchestration triggers to genuinely overlap around a
        // real in-flight network step, instead of relying on unreliable
        // wall-clock timing.
        final gate = finalizeGate;
        if (gate != null) await gate.future;
        return http.Response(
          json.encode({
            'status': 'staged',
            'task_id': taskIdFor(draftMediaId),
            'job_state': finalizeJobStateOverride ?? 'queued',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- Phase 3B: poll GET /api/jobs/<task_id> ------------------------
      if (method == 'GET' && path.startsWith('/api/jobs/')) {
        pollCalls++;
        final taskId = path.substring('/api/jobs/'.length);
        final attempt = (pollAttemptCountByTaskId[taskId] ?? 0) + 1;
        pollAttemptCountByTaskId[taskId] = attempt;
        if (attempt == 1 && taskId == pollFailFirstForTaskId) {
          return http.Response(
            json.encode({'message': 'temporarily unavailable'}),
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          json.encode({'task_id': taskId, 'state': 'SUCCESS'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- Phase 3B: attach-transcoded-video (idempotent) ----------------
      if (method == 'POST' &&
          path == '/api/media/r2/attach-transcoded-video') {
        final decoded = json.decode(request.body) as Map;
        final carId = (decoded['car_id'] ?? '').toString();
        final draftMediaId = (decoded['draft_media_id'] ?? '').toString();
        final taskId = (decoded['task_id'] ?? '').toString();
        attachTranscodeCallsLog.add({
          'carId': carId,
          'draftMediaId': draftMediaId,
          'taskId': taskId,
        });
        videoRowIdCounter++;
        final car = carsById.putIfAbsent(
          carId,
          () => {'id': carId, 'images': <dynamic>[], 'videos': <dynamic>[]},
        );
        (car['videos'] as List).add({'id': videoRowIdCounter});
        return http.Response(
          json.encode({
            'video': {'id': videoRowIdCounter, 'video_url': 'https://cdn.fake.test/v.mp4'},
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- GET /api/cars/<id> --------------------------------------------
      final getMatch = RegExp(r'^/api/cars/([^/]+)$').firstMatch(path);
      if (method == 'GET' && getMatch != null) {
        final id = getMatch.group(1)!;
        final car =
            carsById[id] ?? {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]};
        return http.Response(
          json.encode({'car': car}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- Everything else (layout/primary-image PUTs, list refresh,
      // analytics, edit PATCH) -- succeed harmlessly, matching the
      // existing test file's own catch-all convention. --------------------
      return http.Response(
        '{"cars": []}',
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
    TokenStore.testMode = false;
    TokenStore.resetForTests();
    debugSellSubmissionRetryBackoffOverride = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('M. Mixed-media dedupe', () {
    test(
      'a normal image, a normal (already-compressed) video, and a '
      'server-transcode video all upload/attach exactly once on a full '
      'submit() -- and a later resumeAll() of the (now completed and '
      'removed) record makes ZERO additional HTTP calls of any kind',
      () async {
        const draftId = 'mixed_media_m1';
        final videoPath = await writeLocalFile('normal_video.mp4');
        final transcodeSourcePath = await writeLocalFile('transcode_source.mov');
        const draftMediaId = 'vst_m1';

        final carData = _carData(
          images: const [
            // Already has a server id -- must be skipped entirely, never
            // sent to images/attach.
            {'id': 501, 'source': 'uploads/car_photos/existing.jpg'},
            // Needs attach.
            {'source': 'uploads/car_photos/new.jpg'},
          ],
          videos: [videoPath],
          serverTranscodeVideos: ServerTranscodeVideoSpec.listToJson([
            ServerTranscodeVideoSpec(
              draftMediaId: draftMediaId,
              localSourcePath: transcodeSourcePath,
              sourceByteSize: 256,
              sourceMimeType: 'video/quicktime',
            ),
          ]),
        );

        final result = await PendingSellSubmissionService.instance.submit(
          draftId: draftId,
          carData: carData,
        );
        expect(result, isNotNull);

        expect(
          imageAttachCallsLog,
          [['uploads/car_photos/new.jpg']],
          reason: 'the already-attached (id=501) image must never be '
              're-sent to images/attach',
        );
        expect(videoUploadLog.length, 1);
        expect(signCallsLog, [draftMediaId]);
        expect(putCalls, 1);
        expect(finalizeCallsLog, [draftMediaId]);
        expect(pollCalls, 1);
        expect(attachTranscodeCallsLog.length, 1);
        expect(attachTranscodeCallsLog.single['draftMediaId'], draftMediaId);

        // The submission is complete -- its durable record is removed.
        expect(await SellSubmissionStatePrefs.load(draftId), isNull);

        // A later resume trigger (stray lifecycle/connectivity callback,
        // or an app relaunch that still had the draftId cached somewhere)
        // must be a complete no-op: nothing left to do, nothing repeated.
        final resumed = await PendingSellSubmissionService.instance.resumeAll();
        expect(resumed, isFalse);
        expect(imageAttachCallsLog.length, 1);
        expect(videoUploadLog.length, 1);
        expect(signCallsLog.length, 1);
        expect(putCalls, 1);
        expect(finalizeCallsLog.length, 1);
        expect(pollCalls, 1);
        expect(attachTranscodeCallsLog.length, 1);
      },
    );

    test(
      'reopening a record where the server-transcode video is ALREADY '
      'attached (server-confirmed) alongside a still-pending image and a '
      'still-pending normal video: the pending items are processed '
      'normally, but the already-attached video\'s sign/PUT/finalize/'
      'poll/attach endpoints are never called again',
      () async {
        const draftId = 'mixed_media_m2';
        const carId = 'car_existing_m2';
        const draftMediaId = 'vst_m2';
        final videoPath = await writeLocalFile('pending_video.mp4');
        final transcodeSourcePath = await writeLocalFile('already_done.mov');

        // Server already has this car (as a prior partial run would have
        // left it) with nothing attached yet for the pending image/video,
        // but the transcode video's OWN CarVideo already landed.
        carsById[carId] = {'id': carId, 'images': <dynamic>[], 'videos': <dynamic>[]};

        final carData = _carData(
          images: const [
            {'source': 'uploads/car_photos/pending.jpg'},
          ],
          videos: [videoPath],
          serverTranscodeVideos: ServerTranscodeVideoSpec.listToJson([
            ServerTranscodeVideoSpec(
              draftMediaId: draftMediaId,
              localSourcePath: transcodeSourcePath,
              sourceByteSize: 256,
              sourceMimeType: 'video/quicktime',
            ),
          ]),
        );
        final now = DateTime.now().millisecondsSinceEpoch;
        await seedRecord(
          SellSubmissionRecord(
            draftId: draftId,
            status: SellSubmissionStatus.inProgress,
            carId: carId,
            carData: carData,
            idempotencyKey: 'sell-create-$draftId',
            createdAt: now,
            updatedAt: now,
            totalMediaCount: 3,
            serverTranscodeVideos: {
              draftMediaId: ServerTranscodeVideoState.initial(draftMediaId)
                  .copyWith(
                status: ServerTranscodeVideoStatus.attached,
                putConfirmed: true,
                transcodeConfirmed: true,
                taskId: taskIdFor(draftMediaId),
                attachedVideo: const {'id': 999},
              ),
            },
          ),
        );

        final resumed = await PendingSellSubmissionService.instance.resumeAll();
        expect(resumed, isTrue);

        expect(
          imageAttachCallsLog,
          [['uploads/car_photos/pending.jpg']],
          reason: 'the still-pending image must be attached',
        );
        expect(videoUploadLog.length, 1, reason: 'the still-pending video must upload');
        expect(
          signCallsLog,
          isEmpty,
          reason: 'an already-attached server-transcode video must never '
              're-sign a source upload',
        );
        expect(putCalls, 0);
        expect(finalizeCallsLog, isEmpty);
        expect(pollCalls, 0);
        expect(
          attachTranscodeCallsLog,
          isEmpty,
          reason: 'an already-attached server-transcode video must never '
              're-attach',
        );
      },
    );
  });

  group('N. No double runners on reopen', () {
    test(
      'two overlapping resumeAll() triggers for the SAME in-progress '
      'record (server-transcode video genuinely still in flight inside '
      'finalize) join a SINGLE worker -- finalize/poll/attach each run '
      'exactly once, never twice',
      () async {
        const draftId = 'no_double_runner_n1';
        const carId = 'car_existing_n1';
        const draftMediaId = 'vst_n1';
        final transcodeSourcePath = await writeLocalFile('in_flight.mov');

        carsById[carId] = {'id': carId, 'images': <dynamic>[], 'videos': <dynamic>[]};

        final carData = _carData(
          serverTranscodeVideos: ServerTranscodeVideoSpec.listToJson([
            ServerTranscodeVideoSpec(
              draftMediaId: draftMediaId,
              localSourcePath: transcodeSourcePath,
              sourceByteSize: 256,
              sourceMimeType: 'video/quicktime',
            ),
          ]),
        );
        final now = DateTime.now().millisecondsSinceEpoch;
        await seedRecord(
          SellSubmissionRecord(
            draftId: draftId,
            status: SellSubmissionStatus.inProgress,
            carId: carId,
            carData: carData,
            idempotencyKey: 'sell-create-$draftId',
            createdAt: now,
            updatedAt: now,
            totalMediaCount: 1,
            // Already staged (PUT confirmed) -- the very next step is
            // finalize, which this test gates open below.
            serverTranscodeVideos: {
              draftMediaId: ServerTranscodeVideoState.initial(draftMediaId)
                  .copyWith(
                status: ServerTranscodeVideoStatus.sourceStaged,
                putConfirmed: true,
              ),
            },
          ),
        );

        final gate = Completer<void>();
        finalizeGate = gate;

        // First trigger: starts the worker, which will reach finalize and
        // suspend there (gated) -- genuinely still in flight.
        final f1 = PendingSellSubmissionService.instance.resumeAll();
        // Give the first call's synchronous dispatch phase, and its await
        // chain up to (and including) the gated finalize call, real time
        // to actually run -- the gate itself (not this delay) is what
        // guarantees no false pass: call 1 CANNOT complete finalize until
        // the test explicitly completes `gate` below, no matter how long
        // this waits.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          finalizeCallsLog.length,
          1,
          reason: 'the first trigger must already be inside the gated '
              'finalize call by now',
        );

        // Second "reopen" trigger, fired while the first is still
        // genuinely in flight.
        final f2 = PendingSellSubmissionService.instance.resumeAll();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Release the gate and let both futures resolve.
        gate.complete();
        await Future.wait([f1, f2]);

        expect(
          finalizeCallsLog,
          [draftMediaId],
          reason: 'finalize must have run exactly once total, never twice, '
              'despite two overlapping resumeAll() triggers',
        );
        expect(pollCalls, 1);
        expect(attachTranscodeCallsLog.length, 1);
        expect(signCallsLog, isEmpty, reason: 'already staged -- never re-signed');
        expect(putCalls, 0, reason: 'already staged -- never re-PUT');

        // The submission had exactly this one video to attach, so
        // completing it finishes the whole record -- confirms the shared
        // worker actually reached a real terminal outcome, not just "no
        // crash".
        expect(await SellSubmissionStatePrefs.load(draftId), isNull);
      },
    );

    test(
      'two overlapping submit() calls for a brand-new draft (never '
      'submitted before) only create ONE car and process the '
      'server-transcode video ONCE -- the second call joins the first\'s '
      'in-flight worker via the same per-draft dedup',
      () async {
        const draftId = 'no_double_runner_n2';
        const draftMediaId = 'vst_n2';
        final transcodeSourcePath = await writeLocalFile('fresh_source.mov');

        final carData = _carData(
          serverTranscodeVideos: ServerTranscodeVideoSpec.listToJson([
            ServerTranscodeVideoSpec(
              draftMediaId: draftMediaId,
              localSourcePath: transcodeSourcePath,
              sourceByteSize: 256,
              sourceMimeType: 'video/quicktime',
            ),
          ]),
        );

        final gate = Completer<void>();
        finalizeGate = gate;

        final f1 = PendingSellSubmissionService.instance.submit(
          draftId: draftId,
          carData: carData,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(finalizeCallsLog.length, 1);

        final f2 = PendingSellSubmissionService.instance.submit(
          draftId: draftId,
          carData: carData,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        gate.complete();
        final results = await Future.wait([f1, f2]);

        expect(carsById.length, 1, reason: 'only one car must be created');
        expect(finalizeCallsLog, [draftMediaId]);
        expect(pollCalls, 1);
        expect(attachTranscodeCallsLog.length, 1);
        expect(
          results[0]?.id,
          results[1]?.id,
          reason: 'both callers must observe the SAME resulting car id',
        );
      },
    );
  });

  group('O. Two server-transcode videos in one submission', () {
    test(
      'two distinct server-transcode videos in the SAME submission each '
      'get their own sign/PUT/finalize/task_id/poll/attach, both '
      'complete within a single submit() call, and a later resumeAll() '
      'is a total no-op',
      () async {
        const draftId = 'two_video_o1';
        const draftMediaIdA = 'vst_o1_a';
        const draftMediaIdB = 'vst_o1_b';
        final sourceA = await writeLocalFile('two_video_o1_a.mov');
        final sourceB = await writeLocalFile('two_video_o1_b.mov');

        final carData = _carData(
          serverTranscodeVideos: ServerTranscodeVideoSpec.listToJson([
            ServerTranscodeVideoSpec(
              draftMediaId: draftMediaIdA,
              localSourcePath: sourceA,
              sourceByteSize: 256,
              sourceMimeType: 'video/quicktime',
            ),
            ServerTranscodeVideoSpec(
              draftMediaId: draftMediaIdB,
              localSourcePath: sourceB,
              sourceByteSize: 256,
              sourceMimeType: 'video/quicktime',
            ),
          ]),
        );

        final result = await PendingSellSubmissionService.instance.submit(
          draftId: draftId,
          carData: carData,
        );
        expect(result, isNotNull);
        final carId = result!.id;

        // -- one car created ------------------------------------------
        expect(carsById.length, 1);

        // -- source-sign / PUT / finalize each called exactly ONCE per --
        //    video ------------------------------------------------------
        expect(signCallsLog, [draftMediaIdA, draftMediaIdB]);
        expect(putCalls, 2);
        expect(finalizeCallsLog, [draftMediaIdA, draftMediaIdB]);

        // -- each task polled independently, using its own distinct id -
        expect(pollCalls, 2);

        // -- attach called exactly ONCE per video, each with the -------
        //    matching (car_id, draft_media_id, task_id) triple ----------
        expect(attachTranscodeCallsLog.length, 2);
        final attachA = attachTranscodeCallsLog.firstWhere(
          (m) => m['draftMediaId'] == draftMediaIdA,
        );
        final attachB = attachTranscodeCallsLog.firstWhere(
          (m) => m['draftMediaId'] == draftMediaIdB,
        );
        expect(attachA['carId'], carId);
        expect(attachB['carId'], carId);
        expect(attachA['taskId'], taskIdFor(draftMediaIdA));
        expect(attachB['taskId'], taskIdFor(draftMediaIdB));
        expect(
          attachA['taskId'],
          isNot(equals(attachB['taskId'])),
          reason: 'each video must be assigned its own distinct task_id',
        );

        // -- both attached; the whole submission is complete and its ---
        //    durable record removed --------------------------------------
        expect(await SellSubmissionStatePrefs.load(draftId), isNull);

        // -- neither transcode video ever touches the normal multipart -
        //    video-upload path (no duplicate normal-video upload for ---
        //    either item) ---------------------------------------------
        expect(videoUploadLog, isEmpty);

        // -- a later resumeAll() performs ZERO additional server- ------
        //    transcode calls -- nothing left to do, record already gone
        final resumed = await PendingSellSubmissionService.instance.resumeAll();
        expect(resumed, isFalse);
        expect(signCallsLog.length, 2);
        expect(putCalls, 2);
        expect(finalizeCallsLog.length, 2);
        expect(pollCalls, 2);
        expect(attachTranscodeCallsLog.length, 2);
      },
    );

    test(
      'video B (second in the media list) races ahead and fully attaches '
      'while video A (first in the list) is still stuck on a transient '
      'poll hiccup within the SAME submit() call -- neither video\'s '
      'persisted state overwrites the other\'s, submit() correctly fails '
      '(retryable) instead of prematurely reporting success, and a later '
      'resumeAll() finishes A without touching B again -- attach order '
      'ends up [B, A], the OPPOSITE of the media list order [A, B], '
      'proving completion is keyed by draft_media_id, never list index',
      () async {
        const draftId = 'two_video_o2';
        const draftMediaIdA = 'vst_o2_a';
        const draftMediaIdB = 'vst_o2_b';
        final sourceA = await writeLocalFile('two_video_o2_a.mov');
        final sourceB = await writeLocalFile('two_video_o2_b.mov');

        // Finalize reports `job_state: 'processing'` (not the mock's
        // usual 'queued') for every video, so each video's status
        // immediately BEFORE its first poll attempt already equals
        // `transcodeProcessing`. That way, a single failed poll for A
        // (which also leaves it at `transcodeProcessing`) is genuinely
        // "no forward progress this call" per `_processOne`'s own
        // `state.status == before` check, and stops A there -- rather
        // than immediately looping into a second, same-call poll retry
        // that would hide the stall this test needs.
        finalizeJobStateOverride = 'processing';
        // Only A's task's FIRST poll attempt fails (503); B's poll (a
        // different task_id) always succeeds immediately.
        pollFailFirstForTaskId = taskIdFor(draftMediaIdA);

        final carData = _carData(
          serverTranscodeVideos: ServerTranscodeVideoSpec.listToJson([
            ServerTranscodeVideoSpec(
              draftMediaId: draftMediaIdA,
              localSourcePath: sourceA,
              sourceByteSize: 256,
              sourceMimeType: 'video/quicktime',
            ),
            ServerTranscodeVideoSpec(
              draftMediaId: draftMediaIdB,
              localSourcePath: sourceB,
              sourceByteSize: 256,
              sourceMimeType: 'video/quicktime',
            ),
          ]),
        );

        // -- Pass 1 (submit()): B fully completes; A stalls mid-pipeline.
        //    The overall submission must NOT be reported done/removed --
        //    it must throw (retryable), matching how the pre-existing
        //    images check just above this one in `_runSubmission` already
        //    behaves for a not-actually-finished listing.
        await expectLater(
          PendingSellSubmissionService.instance.submit(
            draftId: draftId,
            carData: carData,
          ),
          throwsA(isException),
        );

        expect(signCallsLog, [draftMediaIdA, draftMediaIdB]);
        expect(putCalls, 2);
        expect(finalizeCallsLog, [draftMediaIdA, draftMediaIdB]);
        expect(
          attachTranscodeCallsLog.length,
          1,
          reason: 'only B has attached so far',
        );
        expect(attachTranscodeCallsLog.single['draftMediaId'], draftMediaIdB);

        final midRecord = await SellSubmissionStatePrefs.load(draftId);
        expect(
          midRecord,
          isNotNull,
          reason: 'the record must survive -- A has not finished yet',
        );
        expect(
          midRecord!.status,
          SellSubmissionStatus.retryable,
          reason: 'classified retryable (never needsAttention), so a '
              'later resumeAll() retries automatically with no user '
              'action required',
        );
        expect(
          midRecord.serverTranscodeVideos[draftMediaIdB]!.status,
          ServerTranscodeVideoStatus.attached,
          reason: "B's own persisted state is correct...",
        );
        expect(
          midRecord.serverTranscodeVideos[draftMediaIdA]!.status,
          ServerTranscodeVideoStatus.transcodeProcessing,
          reason: "...and A's own persisted state is INDEPENDENTLY "
              'correct -- neither entry overwrote the other, each keyed '
              'by its own draft_media_id',
        );

        // The transient hiccup has passed -- A's poll succeeds from now on.
        pollFailFirstForTaskId = null;

        // -- Pass 2 (resumeAll()): must finish A only -- B is already ---
        //    terminal (attached), so its endpoints must never be called
        //    again.
        final resumed = await PendingSellSubmissionService.instance.resumeAll();
        expect(resumed, isTrue);

        // -- every endpoint still called exactly ONCE per video, summed -
        //    across BOTH passes ------------------------------------------
        expect(signCallsLog, [draftMediaIdA, draftMediaIdB]);
        expect(putCalls, 2);
        expect(finalizeCallsLog, [draftMediaIdA, draftMediaIdB]);
        expect(attachTranscodeCallsLog.length, 2);

        final attachA = attachTranscodeCallsLog.firstWhere(
          (m) => m['draftMediaId'] == draftMediaIdA,
        );
        expect(attachA['taskId'], taskIdFor(draftMediaIdA));
        expect(
          attachTranscodeCallsLog
              .firstWhere((m) => m['draftMediaId'] == draftMediaIdB)['taskId'],
          taskIdFor(draftMediaIdB),
        );

        // -- REVERSE COMPLETION ORDER: B (2nd in the media list) reached
        //    `attached` back in pass 1, strictly before A (1st in the
        //    list) did in pass 2 -- attach call order is [B, A], the
        //    OPPOSITE of the media list order [A, B].
        expect(
          attachTranscodeCallsLog.map((m) => m['draftMediaId']).toList(),
          [draftMediaIdB, draftMediaIdA],
          reason: 'attach call order is the REVERSE of the media list '
              'order -- completion is keyed by draft_media_id, never by '
              'list index/position',
        );

        // -- both now fully attached; submission complete and removed --
        expect(await SellSubmissionStatePrefs.load(draftId), isNull);

        // -- no duplicate normal-video upload for either item -----------
        expect(videoUploadLog, isEmpty);

        // -- a later resumeAll() performs ZERO additional server- ------
        //    transcode calls -----------------------------------------------
        final resumedAgain =
            await PendingSellSubmissionService.instance.resumeAll();
        expect(resumedAgain, isFalse);
        expect(signCallsLog.length, 2);
        expect(putCalls, 2);
        expect(finalizeCallsLog.length, 2);
        expect(attachTranscodeCallsLog.length, 2);
      },
    );
  });
}
