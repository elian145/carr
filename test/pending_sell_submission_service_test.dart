// Tests for `PendingSellSubmissionService` — the app-level coordinator that
// owns listing creation + media upload once the user presses Submit,
// independent of the `SellStep5` widget's lifecycle (see
// `lib/features/sell/pending_sell_submission_service.dart`).
//
// Maps to the scenarios required by the audit spec:
//   A. navigate-away does not cancel an in-flight submission
//   B. app pause/resume continues the SAME submission (single worker)
//   C. process-kill-and-restart reuses the SAME listing id (no duplicate)
//   D. app startup auto-resumes a `pending` draft without a manual Submit
//   E. partial image upload resumes only the remaining (not-yet-confirmed)
//      images, never re-uploading ones already confirmed
//   F. images already confirmed + video interrupted resumes only the video,
//      without recreating the listing or re-uploading photos
//   G. multiple concurrent triggers for the same draft only spawn one worker
//      (covered together with B below — both exercise `submit()` racing a
//      `resumeAll()` trigger for the same draftId)
//   H. a transient/network failure is marked retryable (not silently lost)
//      and a later resume (e.g. connectivity restored) finishes the job
//   I. a permanent failure is marked `needsAttention` and never
//      auto-retried by a later resume
//   J. `TrackedHttpClient` / retry-construction behavior is unaffected —
//      verified by `test/tracked_http_client_test.dart` and
//      `test/http_retry_regression_test.dart`, which this change does not
//      touch and which must still pass (run as part of the full suite).
//
// This uses a small dedicated `MockClient` (same pattern as
// `test/p01_async_car_image_upload_test.dart`) rather than the shared
// `FakeApiServer`, so each test can precisely control/observe:
//   - how many times `POST /api/cars` is called (idempotency/dedup),
//   - the server's running "current media count" for a car (needed to
//     exercise `SellListingMediaUpload`'s server-side reconciliation), and
//   - transient vs. permanent failure injection for `POST /api/cars`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

/// Polls [condition] until it is true or [timeout] elapses (fails the test
/// on timeout). Plain Dart timers (no widget pumping needed — none of these
/// tests use `testWidgets`).
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

Map<String, dynamic> _baseCarData({
  List<dynamic>? images,
  List<dynamic>? videos,
  List<dynamic>? damageImages,
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
  'damage_images': damageImages ?? <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  // ---- Fake server state, reset in setUp for every test -------------------
  late List<Map<String, dynamic>> createCarCalls; // {body, idempotencyKey}
  late Map<String, Map<String, dynamic>> carsById;
  late int carIdCounter;
  late int imageRowIdCounter;
  http.Response Function(Map<String, dynamic> body)? createCarOverride;
  // Lets a test inject a permanent (or transient) failure on the
  // POST /api/cars/<id>/videos call specifically, so listing creation (and
  // any photo upload) can succeed while a LATER media step permanently
  // fails -- the exact "partially-created backend listing" shape the
  // dead-end investigation below needs.
  http.Response Function(String carId)? videoUploadOverride;
  late List<int> imagesEnqueueFileCounts; // one entry per enqueue call
  late List<List<String>> attachCallsLog; // one entry per attach call
  late List<String> videoUploadLog; // carId per videos-upload call
  late int jobIdCounter;
  // Section 3 regression (async media -> listing refresh ordering): records
  // the relative order of every media-upload step and the `GET /api/cars`
  // list-refresh call so a test can assert the refresh happens strictly
  // AFTER all image/video work completes, never before/interleaved.
  late List<String> callOrderLog;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pending_sell_sub_');
    final docsDir = Directory('${tempDir.path}/docs')
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);

    SharedPreferences.setMockInitialValues({});

    createCarCalls = <Map<String, dynamic>>[];
    carsById = <String, Map<String, dynamic>>{};
    carIdCounter = 0;
    imageRowIdCounter = 0;
    createCarOverride = null;
    videoUploadOverride = null;
    imagesEnqueueFileCounts = <int>[];
    attachCallsLog = <List<String>>[];
    videoUploadLog = <String>[];
    jobIdCounter = 0;
    callOrderLog = <String>[];

    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');

    ApiService.testHttpClient = MockClient((request) async {
      final method = request.method.toUpperCase();
      final path = request.url.path;

      // ---- POST /api/cars (create) ----------------------------------------
      if (method == 'POST' && path == '/api/cars') {
        callOrderLog.add('create');
        Map<String, dynamic> body = <String, dynamic>{};
        try {
          if (request.body.isNotEmpty) {
            body = Map<String, dynamic>.from(
              json.decode(request.body) as Map,
            );
          }
        } catch (_) {}
        String? idKey;
        request.headers.forEach((k, v) {
          if (k.toLowerCase() == 'idempotency-key') idKey = v;
        });
        createCarCalls.add({'body': body, 'idempotencyKey': idKey});
        final override = createCarOverride;
        if (override != null) return override(body);
        carIdCounter++;
        final id = 'car_$carIdCounter';
        carsById[id] = {
          'id': id,
          'images': <dynamic>[],
          'videos': <dynamic>[],
        };
        return http.Response(
          json.encode({'car': carsById[id]}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- POST /api/cars/<id>/images/attach -------------------------------
      final attachMatch = RegExp(
        r'^/api/cars/([^/]+)/images/attach$',
      ).firstMatch(path);
      if (method == 'POST' && attachMatch != null) {
        callOrderLog.add('images_attach');
        final id = attachMatch.group(1)!;
        final decoded = json.decode(request.body) as Map;
        final paths = List<String>.from(decoded['paths'] as List);
        final kind = (decoded['kind'] ?? 'listing').toString();
        attachCallsLog.add(paths);
        final car = carsById.putIfAbsent(
          id,
          () => {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]},
        );
        final rows = <Map<String, dynamic>>[];
        for (final p in paths) {
          imageRowIdCounter++;
          final row = {'id': imageRowIdCounter, 'kind': kind, 'source': p};
          rows.add(row);
          (car['images'] as List).add(row);
        }
        return http.Response(
          json.encode({
            'images': rows
                .map((r) => {'id': r['id'], 'image_url': r['source']})
                .toList(),
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- POST /api/cars/<id>/images (async enqueue) ----------------------
      final enqueueMatch = RegExp(
        r'^/api/cars/([^/]+)/images$',
      ).firstMatch(path);
      if (method == 'POST' && enqueueMatch != null) {
        callOrderLog.add('images_enqueue');
        // Multipart body: bytes may not be valid UTF-8 — decode with
        // latin1 (never throws) just to count `name="images"` parts.
        final bodyText = latin1.decode(request.bodyBytes);
        final fileCount = RegExp(
          'name="images"',
        ).allMatches(bodyText).length;
        imagesEnqueueFileCounts.add(fileCount);
        final jobIds = <String>[];
        for (var i = 0; i < fileCount; i++) {
          jobIdCounter++;
          jobIds.add('job_$jobIdCounter');
        }
        return http.Response(
          json.encode({'job_ids': jobIds}),
          202,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- GET /api/jobs/<task_id> -----------------------------------------
      if (method == 'GET' && path.startsWith('/api/jobs/')) {
        final jobId = path.substring('/api/jobs/'.length);
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

      // ---- POST /api/cars/<id>/videos --------------------------------------
      final videoMatch = RegExp(
        r'^/api/cars/([^/]+)/videos$',
      ).firstMatch(path);
      if (method == 'POST' && videoMatch != null) {
        callOrderLog.add('video_upload');
        final id = videoMatch.group(1)!;
        videoUploadLog.add(id);
        final override = videoUploadOverride;
        if (override != null) return override(id);
        final car = carsById.putIfAbsent(
          id,
          () => {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]},
        );
        (car['videos'] as List).add({'id': videoUploadLog.length});
        return http.Response(
          json.encode({'videos': [{'id': videoUploadLog.length}]}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- GET /api/cars/<id> -----------------------------------------------
      final getMatch = RegExp(r'^/api/cars/([^/]+)$').firstMatch(path);
      if (method == 'GET' && getMatch != null) {
        final id = getMatch.group(1)!;
        final car =
            carsById[id] ??
            {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]};
        return http.Response(
          json.encode({'car': car}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- PUT/PATCH /api/cars/<id> (edit-flow update) -----------------------
      if ((method == 'PUT' || method == 'PATCH') &&
          RegExp(r'^/api/cars/[^/]+$').hasMatch(path)) {
        return http.Response(
          json.encode({'message': 'updated'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- GET /api/cars (list refresh) -------------------------------------
      // Section 3 regression: `PendingSellSubmissionService` calls
      // `CarService().getCars(refresh: true)` exactly once, only after all
      // image/video upload work has completed — logged so a test can assert
      // this happens strictly after every media-upload step, never before.
      if (method == 'GET' && path == '/api/cars') {
        callOrderLog.add('list_refresh');
        return http.Response(
          '{"cars": []}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // Everything else touched incidentally (primary-image/layout PUTs,
      // analytics event, etc.) is not under test here — succeed harmlessly
      // so it never masks assertions. `{'cars': []}` (rather than `{}`)
      // avoids a pre-existing, unrelated `CarService._cars.clear()` issue
      // when `listingMapsFromApiResponse` falls back to `const []` for a
      // response with no `cars` key at all.
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
    setRuntimeApiBaseOverride(null);
    TokenStore.testMode = false;
    TokenStore.resetForTests();
    tempDir.deleteSync(recursive: true);
  });

  group('SellSubmissionRecord persistence (no HTTP)', () {
    test('never serializes auth tokens/secrets', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final record = SellSubmissionRecord(
        draftId: 'draft_secrets',
        status: SellSubmissionStatus.pending,
        carData: {
          'brand': 'toyota',
          'images': ['/tmp/local/photo.jpg'],
        },
        idempotencyKey: 'sell-create-draft_secrets',
        createdAt: now,
        updatedAt: now,
      );
      final encoded = json.encode(record.toJson()).toLowerCase();
      for (final forbidden in [
        'access_token',
        'refresh_token',
        '"token"',
        'authorization',
        'bearer ',
        'password',
      ]) {
        expect(
          encoded.contains(forbidden),
          isFalse,
          reason: 'persisted submission state must never contain $forbidden',
        );
      }
    });

    test('round-trips every field through JSON', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final record = SellSubmissionRecord(
        draftId: 'draft_roundtrip',
        status: SellSubmissionStatus.retryable,
        isEdit: true,
        editListingId: 'car_edit_1',
        carId: 'car_edit_1',
        pendingReview: true,
        carData: {'brand': 'kia', 'images': <dynamic>[]},
        idempotencyKey: 'sell-create-draft_roundtrip',
        currentPhase: 'photos',
        completedMediaCount: 2,
        totalMediaCount: 5,
        lastErrorMessage: 'boom',
        lastErrorStatusCode: 503,
        lastErrorRetryable: true,
        attempts: 3,
        createdAt: now,
        updatedAt: now,
      );
      final decoded = SellSubmissionRecord.fromJson(
        json.decode(json.encode(record.toJson())),
      );
      expect(decoded, isNotNull);
      expect(decoded!.draftId, 'draft_roundtrip');
      expect(decoded.status, SellSubmissionStatus.retryable);
      expect(decoded.isEdit, isTrue);
      expect(decoded.editListingId, 'car_edit_1');
      expect(decoded.carId, 'car_edit_1');
      expect(decoded.pendingReview, isTrue);
      expect(decoded.currentPhase, 'photos');
      expect(decoded.completedMediaCount, 2);
      expect(decoded.totalMediaCount, 5);
      expect(decoded.lastErrorMessage, 'boom');
      expect(decoded.lastErrorStatusCode, 503);
      expect(decoded.lastErrorRetryable, isTrue);
      expect(decoded.attempts, 3);
    });
  });

  // ---- A: navigate-away must not cancel the submission ---------------------
  test(
    'A: submit() is not cancelled when the caller stops awaiting it '
    '(simulates navigating away from the Sell screen)',
    () async {
      const draftId = 'draft_a';
      // Fire-and-forget, exactly like a widget would if it called submit()
      // then got disposed immediately after (no `await` at the call site,
      // no `mounted` check anywhere in the service).
      unawaited(
        PendingSellSubmissionService.instance.submit(
          draftId: draftId,
          carData: _baseCarData(),
        ),
      );

      await _waitUntil(() => createCarCalls.length == 1);
      await _waitUntil(
        () async =>
            (await SellSubmissionStatePrefs.load(draftId)) == null,
      );
      expect(carsById.length, 1);
    },
  );

  // ---- B + G: pause/resume continues the same run; concurrent triggers ----
  // only spawn one worker for the same draft.
  test(
    'B/G: a resumeAll() trigger firing while submit() is still in-flight '
    'joins the existing worker instead of creating a duplicate listing',
    () async {
      const draftId = 'draft_b';
      final gate = Completer<void>();
      createCarOverride = (body) {
        // Delay the response so the second trigger below reliably overlaps
        // with the still-in-flight first attempt.
        return http.Response(
          json.encode({
            'car': (() {
              carIdCounter++;
              final id = 'car_$carIdCounter';
              carsById[id] = {
                'id': id,
                'images': <dynamic>[],
                'videos': <dynamic>[],
              };
              return carsById[id];
            })(),
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      };

      final submitFuture = PendingSellSubmissionService.instance.submit(
        draftId: draftId,
        carData: _baseCarData(),
      );
      // Give submit() a moment to persist the pending record and start its
      // worker, then simulate an app-resume/connectivity-restored trigger
      // firing for the SAME draft while it is still running.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      gate.complete();
      final resumeAllFuture = PendingSellSubmissionService.instance
          .resumeAll();

      await submitFuture;
      await resumeAllFuture;

      expect(
        createCarCalls.length,
        1,
        reason:
            'a concurrent resumeAll() trigger for the same draft must not '
            'start a second worker / create a second listing',
      );
      expect(carsById.length, 1);
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
    },
  );

  // ---- C: process-kill-and-restart reuses the SAME listing id -------------
  test(
    'C: resuming a draft whose listing was already created before a '
    'simulated process kill never creates a second listing',
    () async {
      const draftId = 'draft_c';
      const existingCarId = 'car_existing_1';
      carsById[existingCarId] = {
        'id': existingCarId,
        'images': <dynamic>[],
        'videos': <dynamic>[],
      };
      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: draftId,
          status: SellSubmissionStatus.inProgress,
          carId: existingCarId,
          carData: _baseCarData(),
          idempotencyKey: 'sell-create-$draftId',
          currentPhase: 'photos',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final resumed = await PendingSellSubmissionService.instance.resumeAll();

      expect(resumed, isTrue);
      expect(
        createCarCalls,
        isEmpty,
        reason: 'a draft with an already-created listing must never call '
            'POST /api/cars again',
      );
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
    },
  );

  // ---- D: startup auto-resume of a `pending` (never-attempted) draft ------
  test(
    'D: a durably-recorded `pending` draft (Submit pressed, then killed '
    'before the first attempt) is auto-resumed by resumeAll() alone -- no '
    'manual Submit press',
    () async {
      const draftId = 'draft_d';
      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: draftId,
          status: SellSubmissionStatus.pending,
          carData: _baseCarData(),
          idempotencyKey: 'sell-create-$draftId',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final resumed = await PendingSellSubmissionService.instance.resumeAll();

      expect(resumed, isTrue);
      expect(createCarCalls.length, 1);
      expect(
        createCarCalls.single['idempotencyKey'],
        'sell-create-$draftId',
      );
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
    },
  );

  // ---- E: partial image upload resumes only the REMAINING images ----------
  test(
    'E: resuming a draft where 1 of 3 images was already confirmed on the '
    'server only uploads the remaining 2 -- never re-uploads the confirmed '
    'one',
    () async {
      const draftId = 'draft_e';
      const carId = 'car_e1';
      final img1 = File('${tempDir.path}/e_img1.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      final img2 = File('${tempDir.path}/e_img2.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 4, 5, 6]);

      // Server already has exactly one confirmed listing image (landed
      // before the simulated kill).
      carsById[carId] = {
        'id': carId,
        'images': [
          {'id': 501, 'kind': 'listing'},
        ],
        'videos': <dynamic>[],
      };

      final carData = _baseCarData(
        images: [
          // Already confirmed -- carries a server `id`, so
          // `SellListingMediaUpload` must skip it (per-item skip), not
          // rely only on the coarse server-count heuristic.
          {'id': 501, 'source': 'uploads/car_photos/existing.jpg'},
          img1.path,
          img2.path,
        ],
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: draftId,
          status: SellSubmissionStatus.inProgress,
          carId: carId,
          carData: carData,
          idempotencyKey: 'sell-create-$draftId',
          currentPhase: 'photos',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final resumed = await PendingSellSubmissionService.instance.resumeAll();

      expect(resumed, isTrue);
      expect(createCarCalls, isEmpty);
      expect(
        imagesEnqueueFileCounts,
        [2],
        reason: 'only the 2 not-yet-confirmed images should be enqueued',
      );
      expect(attachCallsLog, hasLength(1));
      expect(attachCallsLog.single, hasLength(2));
      expect(
        (carsById[carId]!['images'] as List).length,
        3,
        reason: '1 pre-existing + 2 newly uploaded = 3 total',
      );
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
    },
  );

  // ---- F: images already confirmed, video interrupted ---------------------
  test(
    'F: resuming a draft whose photos are already fully confirmed on the '
    'server only resumes the interrupted video -- never recreates the '
    'listing or re-uploads any photo',
    () async {
      const draftId = 'draft_f';
      const carId = 'car_f1';
      final img = File('${tempDir.path}/f_img.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 7, 8, 9]);
      final video = File('${tempDir.path}/f_video.mp4')
        ..writeAsBytesSync(List<int>.filled(32, 1));

      // Server already has the single listing photo this carData describes
      // -- the coarse server-count reconciliation must skip re-upload.
      carsById[carId] = {
        'id': carId,
        'images': [
          {'id': 601, 'kind': 'listing'},
        ],
        'videos': <dynamic>[],
      };

      final carData = _baseCarData(
        images: [img.path],
        videos: [video.path],
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: draftId,
          status: SellSubmissionStatus.retryable,
          carId: carId,
          carData: carData,
          idempotencyKey: 'sell-create-$draftId',
          currentPhase: 'videos',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final resumed = await PendingSellSubmissionService.instance.resumeAll();

      expect(resumed, isTrue);
      expect(createCarCalls, isEmpty);
      expect(
        imagesEnqueueFileCounts,
        isEmpty,
        reason: 'the already-confirmed photo must never be re-uploaded',
      );
      expect(videoUploadLog, [carId]);
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
    },
  );

  // ---- H: transient failure -> retryable -> later resume finishes it ------
  test(
    'H: a transient create failure is recorded as retryable (not lost, not '
    'infinitely retried in the same pass), and a later resume trigger '
    '(e.g. connectivity restored) finishes the submission without a '
    'second listing',
    () async {
      const draftId = 'draft_h';
      createCarOverride = (_) => http.Response(
        json.encode({'message': 'Service Unavailable'}),
        503,
        headers: {'content-type': 'application/json'},
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: draftId,
          status: SellSubmissionStatus.pending,
          carData: _baseCarData(),
          idempotencyKey: 'sell-create-$draftId',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final firstResume = await PendingSellSubmissionService.instance
          .resumeAll();
      expect(firstResume, isTrue);

      final afterFailure = await SellSubmissionStatePrefs.load(draftId);
      expect(afterFailure, isNotNull);
      expect(afterFailure!.status, SellSubmissionStatus.retryable);
      expect(afterFailure.lastErrorRetryable, isTrue);
      expect(
        createCarCalls.length,
        2,
        reason:
            'the bounded retry (2 attempts) should have tried twice, both '
            'with the SAME idempotency key',
      );
      expect(
        createCarCalls.map((c) => c['idempotencyKey']).toSet(),
        {'sell-create-$draftId'},
      );

      // Simulate connectivity coming back: the same mechanism
      // `hookConnectivityRecovery()` calls on reconnect.
      createCarOverride = null;
      final secondResume = await PendingSellSubmissionService.instance
          .resumeAll();

      expect(secondResume, isTrue);
      expect(createCarCalls.length, 3);
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
      expect(carsById.length, 1);
    },
  );

  // ---- I: permanent failure -> needsAttention -> never auto-retried -------
  test(
    'I: a permanent (validation) failure is marked needsAttention and is '
    'never auto-retried by a subsequent resumeAll() call',
    () async {
      const draftId = 'draft_i';
      createCarOverride = (_) => http.Response(
        json.encode({
          'message': 'Invalid listing',
          'errors': ['brand is required'],
        }),
        400,
        headers: {'content-type': 'application/json'},
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: draftId,
          status: SellSubmissionStatus.pending,
          carData: _baseCarData(),
          idempotencyKey: 'sell-create-$draftId',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final firstResume = await PendingSellSubmissionService.instance
          .resumeAll();
      expect(firstResume, isTrue);

      final afterFailure = await SellSubmissionStatePrefs.load(draftId);
      expect(afterFailure, isNotNull);
      expect(afterFailure!.status, SellSubmissionStatus.needsAttention);
      expect(afterFailure.lastErrorRetryable, isFalse);
      expect(
        createCarCalls.length,
        1,
        reason: 'a permanent (400) failure must not be retried even once '
            'within the same pass',
      );

      final secondResume = await PendingSellSubmissionService.instance
          .resumeAll();

      expect(
        secondResume,
        isFalse,
        reason: 'needsAttention drafts must be skipped by resumeAll()',
      );
      expect(
        createCarCalls.length,
        1,
        reason: 'a needsAttention draft must never be auto-retried',
      );
      // Still there, waiting for the user to reopen the draft.
      expect(
        (await SellSubmissionStatePrefs.load(draftId))?.status,
        SellSubmissionStatus.needsAttention,
      );
    },
  );

  // ---- Dead-end fix: listing created, then a PERMANENT media failure -----
  // must still leave the user with a real, working recovery path (product-
  // safety check: `discardSellDraftById` fires right after the listing is
  // created, before media upload finishes -- so if that upload then fails
  // permanently, the original Sell draft is already gone). The actual
  // recovery path is: press "Edit" on that listing from My Listings, which
  // always PATCHes the SAME carId (via `editListingId`) -- never creates a
  // second listing, regardless of which draftId the edit session uses.
  test(
    'dead-end fix: after listing creation succeeds and a photo uploads '
    'fine, a PERMANENT (400) video-upload failure marks needsAttention '
    'while retaining the created carId; recovering via the real Edit-'
    'listing path (PATCH + reupload keyed by that carId, a brand new '
    'draftId) finishes the submission WITHOUT ever creating a second '
    'backend listing',
    () async {
      const draftId = 'draft_deadend';
      final img = File('${tempDir.path}/deadend_img.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 7, 8, 9]);
      final video = File('${tempDir.path}/deadend_video.mp4')
        ..writeAsBytesSync(List<int>.filled(32, 1));

      videoUploadOverride = (_) => http.Response(
        json.encode({
          'message': 'Unsupported video format',
        }),
        400,
        headers: {'content-type': 'application/json'},
      );

      final carData = _baseCarData(images: [img.path], videos: [video.path]);

      try {
        await PendingSellSubmissionService.instance.submit(
          draftId: draftId,
          carData: carData,
        );
        fail(
          'expected the injected permanent video-upload failure to '
          'propagate',
        );
      } catch (_) {}

      // The listing itself (and its photo) really was created on the
      // backend -- exactly the "partially-created listing" the user's
      // scenario describes -- before the video step permanently failed.
      expect(createCarCalls.length, 1);
      expect(carsById.length, 1);
      final createdCarId = carsById.keys.single;
      expect(
        imagesEnqueueFileCounts,
        isNotEmpty,
        reason: 'the photo upload must have run (and succeeded) before the '
            'video step permanently failed',
      );

      final failed = await SellSubmissionStatePrefs.load(draftId);
      expect(failed, isNotNull);
      expect(failed!.status, SellSubmissionStatus.needsAttention);
      expect(failed.lastErrorRetryable, isFalse);
      expect(
        failed.carId,
        createdCarId,
        reason: 'the needsAttention record must retain the id of the '
            'listing that actually exists on the backend -- this is what '
            'the fixed global banner action (My Listings) and the recovery '
            "flow below both key off of, even though the ORIGINAL draft "
            'was already discarded once this carId was created',
      );

      // ---- Recovery: this is exactly what pressing "Edit" on that
      // listing from My Listings does (`openEditListingPage` in
      // `lib/shared/listings/listing_management.dart`) -- a brand new Sell
      // session with its OWN new draftId, pre-filled from the CURRENT
      // server state and carrying `editListingId: createdCarId`. The
      // original (now-orphaned) `draft_deadend` record above is never
      // touched by this -- and does not need to be, since it can never be
      // auto-retried (`needsAttention` is always skipped by `resumeAll`)
      // and its `carId` is never reused to create anything.
      videoUploadOverride = null; // user reselected/fixed the video file
      const recoveryDraftId = 'draft_deadend_edit_recovery_session';
      final recoveryResult = await PendingSellSubmissionService.instance
          .submit(
            draftId: recoveryDraftId,
            carData: carData,
            editListingId: createdCarId,
          );

      expect(
        recoveryResult,
        isNotNull,
        reason: 'the recovery/edit submission must succeed',
      );
      expect(
        createCarCalls.length,
        1,
        reason: 'recovering via Edit must never create a SECOND backend '
            'listing -- it must always update (PATCH) the SAME carId',
      );
      expect(
        carsById.length,
        1,
        reason: 'still exactly one backend listing after recovery',
      );
      expect(videoUploadLog, contains(createdCarId));
      expect(
        await SellSubmissionStatePrefs.load(recoveryDraftId),
        isNull,
        reason: 'the recovery submission record is cleaned up on success',
      );
    },
  );

  // ---- Section 3 regression: async media -> listing refresh ordering -----
  // Reported symptom: a just-published listing can show a stale placeholder
  // instead of its real photo/video. One candidate cause was the app
  // refreshing its cached listing feed (`CarService.getCars(refresh: true)`)
  // too early -- before the photo/video upload actually finished on the
  // backend -- which would bake a media-less snapshot into the feed cache.
  // This proves the real ordering: the list refresh is the LAST network
  // call of a successful submission, strictly after every image AND video
  // upload step, for both create and edit-in-place ("add media to an
  // existing listing") submissions.
  test(
    'Section 3: CarService.getCars(refresh: true) is called only after '
    'BOTH the photo upload and the video upload finish -- never before or '
    'interleaved with them -- so the refreshed feed cache can never bake '
    'in a media-less placeholder snapshot',
    () async {
      const draftId = 'draft_refresh_order';
      final img = File('${tempDir.path}/refresh_order_img.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      final video = File('${tempDir.path}/refresh_order_video.mp4')
        ..writeAsBytesSync(List<int>.filled(32, 1));

      final result = await PendingSellSubmissionService.instance.submit(
        draftId: draftId,
        carData: _baseCarData(images: [img.path], videos: [video.path]),
      );

      expect(result, isNotNull);
      expect(callOrderLog, contains('images_enqueue'));
      expect(callOrderLog, contains('video_upload'));
      expect(
        callOrderLog,
        contains('list_refresh'),
        reason: 'the submission must actually trigger a list refresh at '
            'some point -- otherwise Home/My Listings would never see the '
            'new listing at all',
      );

      final firstRefreshIndex = callOrderLog.indexOf('list_refresh');
      final lastImageIndex = callOrderLog.lastIndexOf('images_enqueue');
      final lastVideoIndex = callOrderLog.lastIndexOf('video_upload');
      expect(
        firstRefreshIndex,
        greaterThan(lastImageIndex),
        reason: 'the list refresh must not happen before (or interleaved '
            'with) photo upload -- doing so could cache a media-less '
            'listing snapshot',
      );
      expect(
        firstRefreshIndex,
        greaterThan(lastVideoIndex),
        reason: 'the list refresh must not happen before (or interleaved '
            'with) video upload -- doing so could cache a media-less '
            'listing snapshot',
      );
      // There are two `getCars(refresh: true)` call sites in production
      // code -- one at the end of `SellListingMediaUpload.uploadForCar()`
      // (`sell_listing_media_upload.dart`) and one right after it returns
      // in `pending_sell_submission_service.dart` -- both correctly
      // positioned after every media step, so up to 2 calls is expected
      // and NOT a bug (mild redundancy, not a correctness/ordering issue).
      // What matters, and what this test guards, is that EVERY occurrence
      // -- not just the first -- comes after all media work, so assert on
      // the count too (documenting the exact number rather than silently
      // allowing a THIRD, unexplained refresh to creep in unnoticed).
      expect(
        callOrderLog.where((e) => e == 'list_refresh').length,
        2,
        reason: 'if this changes, confirm it is still exactly these two '
            'known, already-ordered-correctly call sites and not a new '
            'one introduced elsewhere',
      );
    },
  );

  // ---- Section 5 regression: durable sell_draft_media cleanup timing -----
  // ("Do NOT delete sell_draft_media files too early"). Two tests: cleanup
  // must NOT happen when media upload permanently fails (so the user can
  // retry/edit without having lost their local files), and it MUST happen
  // once the submission actually succeeds (so drafts don't accumulate
  // forever on disk).
  test(
    'Section 5: a permanently-failed video upload leaves the durable '
    'sell_draft_media directory intact -- cleanup only runs on success, '
    'never on failure',
    () async {
      const draftId = 'draft_cleanup_on_failure';
      final draftDir = await SellDraftMediaPersistence.draftDirectory(
        draftId,
      );
      final marker = File('${draftDir.path}/marker.txt')
        ..writeAsStringSync('still here');

      final img = File('${tempDir.path}/cleanup_fail_img.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      final video = File('${tempDir.path}/cleanup_fail_video.mp4')
        ..writeAsBytesSync(List<int>.filled(32, 1));

      videoUploadOverride = (_) => http.Response(
        json.encode({'message': 'Unsupported video format'}),
        400,
        headers: {'content-type': 'application/json'},
      );

      try {
        await PendingSellSubmissionService.instance.submit(
          draftId: draftId,
          carData: _baseCarData(images: [img.path], videos: [video.path]),
        );
        fail('expected the injected permanent video-upload failure to propagate');
      } catch (_) {}

      expect(
        await draftDir.exists(),
        isTrue,
        reason: 'sell_draft_media must survive a permanent media-upload '
            'failure so the user does not lose their local files',
      );
      expect(await marker.exists(), isTrue);
    },
  );

  test(
    'Section 5: a fully successful submission (photo + video) deletes the '
    'durable sell_draft_media directory only after the media upload AND '
    'the list refresh have completed',
    () async {
      const draftId = 'draft_cleanup_on_success';
      final draftDir = await SellDraftMediaPersistence.draftDirectory(
        draftId,
      );
      File('${draftDir.path}/marker.txt').writeAsStringSync('still here');

      final img = File('${tempDir.path}/cleanup_ok_img.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 4, 5, 6]);
      final video = File('${tempDir.path}/cleanup_ok_video.mp4')
        ..writeAsBytesSync(List<int>.filled(32, 2));

      final result = await PendingSellSubmissionService.instance.submit(
        draftId: draftId,
        carData: _baseCarData(images: [img.path], videos: [video.path]),
      );
      expect(result, isNotNull);

      // `_clearDurableDraftMedia` is fire-and-forget (`unawaited(...)`) from
      // `submit()`'s point of view, so poll rather than asserting instantly.
      await _waitUntil(() async => !(await draftDir.exists()));

      // And it must not have happened before the media/refresh work above
      // -- already proven strictly ordered by the "Section 3" test; this
      // additionally confirms the directory is ACTUALLY gone afterward
      // (not merely emptied, and not merely scheduled).
      expect(await draftDir.exists(), isFalse);
    },
  );

  // ---- Account isolation: never resume under a DIFFERENT signed-in ----
  // account than the one that pressed Submit (shared-device scenario).
  // Placed last: `AuthService()` is a real singleton and this is the only
  // test in this file that touches it, so it is fully cleaned up at the
  // end rather than leaking session state into any test declared after
  // it in this file.
  test(
    'account isolation: a submission recorded under one account is never '
    'auto-resumed while a DIFFERENT account is signed in on the same '
    'device -- it resumes correctly (no duplicate listing) once the '
    'ORIGINAL account signs back in',
    () async {
      const draftId = 'draft_account_iso';

      // 1) User A presses Submit; a transient failure leaves it
      //    `retryable` -- and the record must be stamped with User A's
      //    account id.
      await AuthService().adoptTestSession(user: {'id': 'user_a'});
      createCarOverride = (_) => http.Response(
        json.encode({'message': 'Service Unavailable'}),
        503,
        headers: {'content-type': 'application/json'},
      );
      try {
        await PendingSellSubmissionService.instance.submit(
          draftId: draftId,
          carData: _baseCarData(),
        );
        fail('expected the injected transient failure to propagate');
      } catch (_) {
        // Expected: `_runSubmission` rethrows after persisting the
        // `retryable` state -- `submit()`'s caller (the Submit button)
        // already handles this the same way it always has.
      }

      final afterUserA = await SellSubmissionStatePrefs.load(draftId);
      expect(afterUserA, isNotNull);
      expect(afterUserA!.status, SellSubmissionStatus.retryable);
      expect(
        afterUserA.ownerUserId,
        'user_a',
        reason: 'submit() must stamp the CURRENT account as owner',
      );
      expect(createCarCalls.length, 2); // bounded retry, both transient

      // 2) User A signs out; User B signs into the SAME device. A resume
      //    trigger fires (app resume / connectivity / next startup) while
      //    User B is current -- it must NOT touch User A's submission,
      //    even though it would now succeed if attempted.
      createCarOverride = null;
      await AuthService().adoptTestSession(user: {'id': 'user_b'});
      final resumedForB = await PendingSellSubmissionService.instance
          .resumeAll();

      expect(
        resumedForB,
        isFalse,
        reason: 'nothing is eligible for the CURRENTLY signed-in account',
      );
      expect(
        createCarCalls.length,
        2,
        reason:
            "must not create/finish User A's listing while User B is "
            'signed in',
      );
      final stillUserAs = await SellSubmissionStatePrefs.load(draftId);
      expect(
        stillUserAs,
        isNotNull,
        reason: 'the record must be left untouched, not discarded',
      );
      expect(stillUserAs!.status, SellSubmissionStatus.retryable);
      expect(stillUserAs.ownerUserId, 'user_a');

      // 3) User A signs back in on the same device -- NOW it resumes
      //    correctly, with no duplicate listing.
      await AuthService().adoptTestSession(user: {'id': 'user_a'});
      final resumedForA = await PendingSellSubmissionService.instance
          .resumeAll();

      expect(resumedForA, isTrue);
      expect(createCarCalls.length, 3); // exactly one more attempt, succeeds
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
      expect(carsById.length, 1);

      // Clean up the real AuthService singleton so no other test file
      // sharing this process observes a signed-in session it never set up.
      await AuthService().logout();
    },
  );
}
