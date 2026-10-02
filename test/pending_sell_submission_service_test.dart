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
import 'package:car_listing_app/features/sell/sell_video_compression.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/listings/owner_optimistic_media_cleanup.dart';
import 'package:car_listing_app/shared/prefs/owner_optimistic_media_prefs.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show XFile;
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
  // Sell-video-compression regression (real-device evidence: 112,329,351-
  // byte .mov rejected at the exact 100MB backend limit): the filename +
  // Content-Type actually sent for the "files" multipart part of every
  // POST /api/cars/<id>/videos call, extracted best-effort from the raw
  // multipart body -- purely additive logging, never affects the response
  // any existing test asserts on.
  late List<Map<String, String>> videoUploadPartLog;
  late int jobIdCounter;
  // Section 3 regression (async media -> listing refresh ordering): records
  // the relative order of every media-upload step and the `GET /api/cars`
  // list-refresh call so a test can assert the refresh happens strictly
  // AFTER all image/video work completes, never before/interleaved.
  late List<String> callOrderLog;
  // Bug-3 regression instrumentation: EVERY DELETE request the mock server
  // observes, for any path -- resume/background/foreground/force-close
  // code must never produce a single one of these for already-attached
  // media (see the "Bug-3: resume/background/foreground never deletes"
  // group near the end of this file).
  late List<String> deleteCallsLog;

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
    videoUploadPartLog = <Map<String, String>>[];
    jobIdCounter = 0;
    callOrderLog = <String>[];
    deleteCallsLog = <String>[];

    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    // E-fix: real backoff delays (10s-300s) are impractical to wait out in
    // a unit test and are not what most of these tests exercise -- disable
    // spacing by default so pre-existing "resume again immediately"
    // scenarios keep their original zero-delay semantics. The dedicated
    // backoff/cap tests below override this per-test instead.
    debugSellSubmissionRetryBackoffOverride = (_) => Duration.zero;

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
        try {
          final bodyText = latin1.decode(request.bodyBytes);
          // Multipart part headers are lowercased by `http.MultipartFile`
          // and their order isn't guaranteed (observed:
          // "content-type" before "content-disposition") -- split into
          // per-part header blocks (up to the blank line) on any boundary
          // line, then find the one carrying `name="files"`.
          for (final part in bodyText.split(RegExp(r'--[-\w]+\r?\n'))) {
            final headerEnd = part.indexOf('\r\n\r\n');
            if (headerEnd == -1) continue;
            final headers = part.substring(0, headerEnd);
            if (!headers.contains('name="files"')) continue;
            final filenameMatch = RegExp(
              r'filename="([^"]*)"',
            ).firstMatch(headers);
            final contentTypeMatch = RegExp(
              r'content-type:\s*([^\r\n]+)',
              caseSensitive: false,
            ).firstMatch(headers);
            videoUploadPartLog.add({
              'filename': filenameMatch?.group(1) ?? '',
              'contentType': contentTypeMatch?.group(1)?.trim() ?? '',
            });
            break;
          }
        } catch (_) {
          // Best-effort diagnostics only -- must never break the fake
          // server response any other test depends on.
        }
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

      // ---- GET /api/cars/<id>/media-summary (media-readiness Phase A) -------
      // This fake server never actually registers `CarMediaItem` manifest
      // rows -- every test in this file exercises Phase B (upload/attach)
      // behavior, not Phase-A gating itself (see
      // `pending_sell_submission_fast_submit_test.dart` for THAT), so
      // Phase A is always already "complete" here, matching a listing
      // whose `expected_media` was empty/already satisfied.
      final mediaSummaryMatch = RegExp(
        r'^/api/cars/([^/]+)/media-summary$',
      ).firstMatch(path);
      if (method == 'GET' && mediaSummaryMatch != null) {
        return http.Response(
          json.encode({
            'media_status': 'ready',
            'items': <dynamic>[],
            'phase_a_complete': true,
          }),
          200,
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

      // ---- DELETE (any car image/video removal endpoint) --------------------
      // Bug-3 regression instrumentation: records EVERY delete request seen,
      // regardless of exact path shape, so a test can assert none ever
      // happen during resume/background/foreground/force-close flows.
      if (method == 'DELETE') {
        deleteCallsLog.add(path);
        // Still remove the row from the fake server state, so a test that
        // DOES want to see a real user-initiated delete succeed (unrelated
        // to this file's resume-only scope) behaves realistically.
        final delImgMatch = RegExp(
          r'^/api/cars/([^/]+)/images/(\d+)$',
        ).firstMatch(path);
        final delVidMatch = RegExp(
          r'^/api/cars/([^/]+)/videos/(\d+)$',
        ).firstMatch(path);
        if (delImgMatch != null) {
          final id = delImgMatch.group(1)!;
          final imgId = int.parse(delImgMatch.group(2)!);
          carsById[id]?['images'] =
              ((carsById[id]?['images'] as List?) ?? [])
                  .where((row) => row['id'] != imgId)
                  .toList();
        } else if (delVidMatch != null) {
          final id = delVidMatch.group(1)!;
          final vidId = int.parse(delVidMatch.group(2)!);
          carsById[id]?['videos'] =
              ((carsById[id]?['videos'] as List?) ?? [])
                  .where((row) => row['id'] != vidId)
                  .toList();
        }
        return http.Response(
          json.encode({'message': 'deleted'}),
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
    debugSellSubmissionRetryBackoffOverride = null;
    tempDir.deleteSync(recursive: true);
  });

  group('SellSubmissionRecord persistence (no HTTP)', () {
    test(
      'J-12: an old-schema record (persisted by a version of the app that '
      'predates attempts/lastError*/ownerUserId/pendingAsyncImageJobs) '
      'decodes safely with sensible defaults instead of failing to parse',
      () {
        // Exactly what `SellSubmissionStatePrefs` would have written before
        // those fields existed -- only the fields present since the very
        // first version of this record type.
        final oldSchemaJson = <String, dynamic>{
          'draftId': 'draft_old_schema',
          'status': 'retryable',
          'isEdit': false,
          'carId': 'car_old_1',
          'pendingReview': false,
          'carData': {'brand': 'kia', 'images': <dynamic>[]},
          'idempotencyKey': 'sell-create-draft_old_schema',
          'currentPhase': 'photos',
          'completedMediaCount': 0,
          'totalMediaCount': 1,
          'createdAt': 1700000000000,
          'updatedAt': 1700000000000,
          // Deliberately absent: attempts, lastErrorMessage,
          // lastErrorStatusCode, lastErrorRetryable, ownerUserId,
          // pendingAsyncImageJobs, editListingId.
        };

        final decoded = SellSubmissionRecord.fromJson(oldSchemaJson);

        expect(decoded, isNotNull);
        expect(decoded!.draftId, 'draft_old_schema');
        expect(decoded.status, SellSubmissionStatus.retryable);
        expect(decoded.carId, 'car_old_1');
        expect(
          decoded.attempts,
          0,
          reason: 'missing attempts must default to 0, not crash/null',
        );
        expect(decoded.lastErrorMessage, isNull);
        expect(decoded.lastErrorStatusCode, isNull);
        expect(decoded.lastErrorRetryable, isFalse);
        expect(
          decoded.ownerUserId,
          isNull,
          reason: 'missing ownerUserId must default to null (resumable by '
              'whichever account is current), not crash',
        );
        expect(decoded.pendingAsyncImageJobs, isEmpty);
        expect(decoded.editListingId, isNull);

        // Round-trips through toJson()/fromJson() again without loss, now
        // that the "new" fields have concrete (default) values.
        final roundTripped = SellSubmissionRecord.fromJson(
          json.decode(json.encode(decoded.toJson())),
        );
        expect(roundTripped, isNotNull);
        expect(roundTripped!.attempts, 0);
        expect(roundTripped.carId, 'car_old_1');
      },
    );

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
    'Section 5 (Critical Issue 1 rework): a fully successful submission '
    '(photo + video) does NOT delete the durable sell_draft_media '
    'directory just because the backend finished -- it stays intact, '
    'backed by a durable OwnerOptimisticMediaRecord, until every '
    'expected item is confirmed remote-display-ready on this device; '
    'only then is it actually deleted',
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
      final carId = result!.id;

      // `snapshotAtSubmissionCompleteAndMaybeFinalize` is fire-and-forget
      // (`unawaited(...)`) from `submit()`'s point of view, so poll for
      // the durable overlay record to land rather than asserting
      // instantly.
      OwnerOptimisticMediaRecord? record;
      await _waitUntil(() async {
        record = await OwnerOptimisticMediaPrefs.load(carId);
        return record != null;
      });
      expect(
        record!.items.length,
        2,
        reason: 'one image + one video expected',
      );
      expect(
        record!.items.every((i) => !i.remoteDisplayReady),
        isTrue,
        reason: 'nothing has been visually confirmed on this device yet',
      );

      // THE CORE CONTRACT (Critical Issue 1): backend success alone must
      // NEVER delete local optimistic media -- "Backend full success !=
      // remote media visibly usable on this device." Give any
      // fire-and-forget work a moment to (not) run, then assert the
      // directory is still fully intact.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        await draftDir.exists(),
        isTrue,
        reason: 'backend-done must never alone trigger local-file '
            'cleanup -- only a confirmed on-device remote decode may',
      );
      expect(await File('${draftDir.path}/marker.txt').exists(), isTrue);

      // Now simulate this device confirming the FIRST expected item's
      // remote decode/initialization (e.g. `OwnerFallbackHeroImage`'s own
      // success callback) -- only that one item becomes eligible for
      // cleanup; the whole record/directory must still survive since the
      // second item is not confirmed yet.
      await OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup(
        listingId: carId,
        clientMediaId: record!.items.first.clientMediaId,
      );
      expect(
        await draftDir.exists(),
        isTrue,
        reason: 'directory must survive while any expected item remains '
            'unconfirmed',
      );
      final partial = await OwnerOptimisticMediaPrefs.load(carId);
      expect(partial, isNotNull);
      expect(partial!.allRemoteDisplayReady, isFalse);

      // Confirming the LAST expected item finally makes whole-record
      // cleanup allowed -- only now is the durable directory actually
      // deleted, and the overlay record itself removed.
      await OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup(
        listingId: carId,
        clientMediaId: record!.items.last.clientMediaId,
      );
      expect(await draftDir.exists(), isFalse);
      expect(await OwnerOptimisticMediaPrefs.load(carId), isNull);
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

  // ---- J-12: an old-schema record on disk resumes correctly end-to-end ----
  test(
    'J-12: an old-schema record written directly to SharedPreferences (raw '
    'JSON missing every field added after the first version of this '
    'record type) is discovered and successfully resumed by resumeAll() -- '
    'not just parseable in isolation, but actually usable',
    () async {
      const draftId = 'draft_old_schema_e2e';
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        'sell_submission_state_v1',
        json.encode([
          {
            'draftId': draftId,
            'status': 'pending',
            'isEdit': false,
            'pendingReview': false,
            'carData': _baseCarData(),
            'idempotencyKey': 'sell-create-$draftId',
            'currentPhase': 'creating',
            'completedMediaCount': 0,
            'totalMediaCount': 0,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
            // No attempts / lastError* / ownerUserId /
            // pendingAsyncImageJobs -- exactly what a pre-those-fields app
            // version would have written.
          },
        ]),
      );

      final resumed = await PendingSellSubmissionService.instance
          .resumeAll();

      expect(resumed, isTrue);
      expect(createCarCalls.length, 1);
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
      expect(carsById.length, 1);
    },
  );

  // ---- F: overlapping resume triggers never duplicate work -----------------
  // Real triggers that call `resumeAll()`/`submit()` independently: app
  // bootstrap, `AppLifecycleState.resumed`, connectivity restored
  // (`hookConnectivityRecovery`), and auth/login completion
  // (`app_with_deep_links.dart`). Proves one persisted draftId can never
  // simultaneously execute two media-upload flows even when several of
  // these fire close together, via BOTH dedup layers at once
  // (`_bulkResumeRunning` for the bulk scan, `_activeRuns`/`_ensureRunning`
  // per draft).
  test(
    'F: four resumeAll() calls fired back-to-back (simulating bootstrap + '
    'lifecycle-resume + connectivity-restored + login-completion all '
    'triggering near-simultaneously) for the SAME single pending draft '
    'result in exactly ONE create call and ONE finished submission -- '
    'never a duplicate/overlapping worker',
    () async {
      const draftId = 'draft_f_overlap';
      createCarOverride = (body) {
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

      // Four independent triggers, fired without awaiting each other --
      // exactly how bootstrap/lifecycle/connectivity/login-completion fire
      // independently in production.
      final futures = <Future<bool>>[
        PendingSellSubmissionService.instance.resumeAll(),
        PendingSellSubmissionService.instance.resumeAll(),
        PendingSellSubmissionService.instance.resumeAll(),
        PendingSellSubmissionService.instance.resumeAll(),
      ];
      final results = await Future.wait(futures);

      expect(
        results.where((r) => r).length,
        greaterThanOrEqualTo(1),
        reason: 'at least the winning trigger must report success',
      );
      expect(
        createCarCalls.length,
        1,
        reason: 'four overlapping resume triggers for the SAME draft must '
            'still only create the listing ONCE -- this is the exact '
            '"two simultaneous media upload flows for one draftId" '
            'scenario Section F guards against',
      );
      expect(carsById.length, 1);
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
    },
  );

  // ---- E-fix: bounded retry / backoff (real-device evidence) --------------
  // Reported symptom: the "Uploading listing… 0 of N media uploaded" banner
  // reappeared on every app launch/resume indefinitely because a
  // `retryable` record was retried unconditionally, forever, by every
  // resumeAll() trigger with no cap and no minimum spacing.
  group('E-fix: bounded retry / backoff for retryable records', () {
    test(
      'sellSubmissionRetryBackoff() increases with attempts and caps at '
      '300s',
      () {
        expect(sellSubmissionRetryBackoff(0), const Duration(seconds: 10));
        expect(sellSubmissionRetryBackoff(1), const Duration(seconds: 20));
        expect(sellSubmissionRetryBackoff(2), const Duration(seconds: 40));
        expect(sellSubmissionRetryBackoff(3), const Duration(seconds: 80));
        expect(sellSubmissionRetryBackoff(4), const Duration(seconds: 160));
        expect(sellSubmissionRetryBackoff(5), const Duration(seconds: 300));
        expect(
          sellSubmissionRetryBackoff(20),
          const Duration(seconds: 300),
          reason: 'must cap, never grow unbounded',
        );
      },
    );

    test(
      'a retryable record whose backoff window has not elapsed yet is '
      'skipped by resumeAll() -- no new network attempt, record left '
      'untouched -- instead of retrying the same still-failing request on '
      'every trigger',
      () async {
        // Force a large backoff so "not enough time has passed" is
        // deterministic regardless of real wall-clock speed.
        debugSellSubmissionRetryBackoffOverride = (_) => const Duration(
          hours: 1,
        );
        const draftId = 'draft_backoff_skip';
        final now = DateTime.now().millisecondsSinceEpoch;
        await SellSubmissionStatePrefs.upsert(
          SellSubmissionRecord(
            draftId: draftId,
            status: SellSubmissionStatus.retryable,
            carData: _baseCarData(),
            idempotencyKey: 'sell-create-$draftId',
            attempts: 1,
            lastErrorMessage: 'Service Unavailable',
            lastErrorStatusCode: 503,
            lastErrorRetryable: true,
            createdAt: now,
            // "Just failed a moment ago" -- well within the 1-hour backoff.
            updatedAt: now,
          ),
        );

        // `resumeAll()`'s return value only signals "something was
        // eligible enough to schedule a worker for" (pre-existing
        // semantics, unchanged here) -- not "something actually changed".
        // The real proof this backoff check works is what happens (and
        // does not happen) below.
        await PendingSellSubmissionService.instance.resumeAll();

        expect(
          createCarCalls,
          isEmpty,
          reason: 'must not re-attempt before the backoff window elapses',
        );
        final still = await SellSubmissionStatePrefs.load(draftId);
        expect(still, isNotNull);
        expect(still!.status, SellSubmissionStatus.retryable);
        expect(
          still.attempts,
          1,
          reason: 'a skipped-due-to-backoff attempt must not itself count '
              'as a new attempt',
        );
      },
    );

    test(
      'once its backoff window has elapsed, the SAME retryable record is '
      'retried normally by a later resumeAll() trigger',
      () async {
        debugSellSubmissionRetryBackoffOverride = (_) =>
            const Duration(milliseconds: 1);
        const draftId = 'draft_backoff_elapsed';
        final longAgo = DateTime.now()
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch;
        await SellSubmissionStatePrefs.upsert(
          SellSubmissionRecord(
            draftId: draftId,
            status: SellSubmissionStatus.retryable,
            carData: _baseCarData(),
            idempotencyKey: 'sell-create-$draftId',
            attempts: 1,
            lastErrorRetryable: true,
            createdAt: longAgo,
            updatedAt: longAgo,
          ),
        );

        final resumed = await PendingSellSubmissionService.instance
            .resumeAll();

        expect(resumed, isTrue);
        expect(createCarCalls.length, 1);
        expect(await SellSubmissionStatePrefs.load(draftId), isNull);
      },
    );

    test(
      'a retryable record that has already been auto-retried '
      '$kSellSubmissionMaxAutoRetryAttempts times is converted to '
      'needsAttention (and excluded from all future resumeAll() calls) '
      'instead of being retried forever',
      () async {
        const draftId = 'draft_retry_exhausted';
        const carId = 'car_retry_exhausted';
        carsById[carId] = {
          'id': carId,
          'images': <dynamic>[],
          'videos': <dynamic>[],
        };
        final now = DateTime.now().millisecondsSinceEpoch;
        await SellSubmissionStatePrefs.upsert(
          SellSubmissionRecord(
            draftId: draftId,
            status: SellSubmissionStatus.retryable,
            carId: carId,
            carData: _baseCarData(),
            idempotencyKey: 'sell-create-$draftId',
            attempts: kSellSubmissionMaxAutoRetryAttempts,
            lastErrorMessage: 'Service Unavailable',
            lastErrorStatusCode: 503,
            lastErrorRetryable: true,
            createdAt: now,
            updatedAt: now,
          ),
        );

        // (`resumeAll()`'s boolean return only means "something was
        // eligible for a worker" -- unchanged pre-existing semantics; the
        // meaningful assertions are the ones below.)
        await PendingSellSubmissionService.instance.resumeAll();

        expect(
          createCarCalls,
          isEmpty,
          reason: 'must not make yet another attempt once the budget is '
              'exhausted',
        );
        final exhausted = await SellSubmissionStatePrefs.load(draftId);
        expect(exhausted, isNotNull);
        expect(exhausted!.status, SellSubmissionStatus.needsAttention);
        expect(
          exhausted.carId,
          carId,
          reason: 'the listing id must survive so My Listings can still '
              'find/fix it',
        );

        // And it is now permanently excluded from resumeAll(), matching
        // every other needsAttention record (test I above).
        final secondResume = await PendingSellSubmissionService.instance
            .resumeAll();
        expect(secondResume, isFalse);
        expect(createCarCalls, isEmpty);
      },
    );
  });

  // ---- E-fix: a required local media file that vanished can never be ------
  // retried into success -- fail closed to needsAttention immediately
  // instead of silently dropping the file or retrying forever.
  test(
    'E-fix: a retryable/resumable record referencing a local photo file '
    'that no longer exists on disk is converted to needsAttention '
    'immediately (no network attempt), instead of retrying forever or '
    'silently publishing with fewer photos than the user picked',
    () async {
      const draftId = 'draft_missing_local_media';
      final missingPath = '${tempDir.path}/this_file_was_deleted.jpg';
      // Deliberately never created -- simulates the durable copy having
      // been removed out from under a resumed draft (or a pre-durability
      // cache path that no longer resolves).
      expect(File(missingPath).existsSync(), isFalse);

      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: draftId,
          status: SellSubmissionStatus.retryable,
          carData: _baseCarData(images: [missingPath]),
          idempotencyKey: 'sell-create-$draftId',
          attempts: 1,
          lastErrorRetryable: true,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // (`resumeAll()`'s boolean return only means "something was
      // eligible for a worker" -- unchanged pre-existing semantics; the
      // meaningful assertions are the ones below.)
      await PendingSellSubmissionService.instance.resumeAll();

      expect(
        createCarCalls,
        isEmpty,
        reason: 'must fail closed before ever attempting create/upload -- '
            'a missing local file can never succeed no matter how many '
            'network attempts are made',
      );
      final failed = await SellSubmissionStatePrefs.load(draftId);
      expect(failed, isNotNull);
      expect(failed!.status, SellSubmissionStatus.needsAttention);
      expect(failed.lastErrorRetryable, isFalse);
      expect(failed.lastErrorMessage, contains(missingPath));

      // Also permanently excluded from future resumes, same as any other
      // needsAttention record.
      final secondResume = await PendingSellSubmissionService.instance
          .resumeAll();
      expect(secondResume, isFalse);
      expect(createCarCalls, isEmpty);
    },
  );

  // ---- C-fix: resuming a submission must never re-attach an already- -----
  // attached staged photo (real-device evidence: production logs showed
  // TWO successful `image attach -> 201` calls for the SAME carId, seconds
  // apart -- `attachCarImages` has no dedupe of its own, so calling it
  // again for a source the server already attached creates a duplicate
  // image row). This exercises the pre-existing `toAttach` path (staged
  // `uploads/...` sources with no server `id` yet in `carData`, as
  // `SellPhotoPrestage` leaves them) which, unlike the neighboring
  // `toUpload` path, previously had no "already on server" guard at all.
  test(
    'C-fix: resuming a draft whose staged listing photo was already '
    'attached to the server (its attach ack was lost/killed before the '
    'record could persist a server image id) does NOT call '
    'attachCarImages again for that source',
    () async {
      const draftId = 'draft_c_fix_dup_attach';
      const carId = 'car_c_fix_dup_attach';
      const stagedSource = 'uploads/car_photos/already_staged.jpg';

      // Server already has this staged photo attached (from an earlier,
      // interrupted attempt) -- but carData below still describes it with
      // NO server `id` (exactly what a resumed record whose attach ack
      // never reached the client would look like).
      carsById[carId] = {
        'id': carId,
        'images': [
          {'id': 901, 'kind': 'listing', 'image_url': stagedSource},
        ],
        'videos': <dynamic>[],
      };

      final carData = _baseCarData(images: [
        {'source': stagedSource},
      ]);
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
        attachCallsLog,
        isEmpty,
        reason: 'the already-attached staged source must be skipped, never '
            'sent to attachCarImages again',
      );
      expect(
        (carsById[carId]!['images'] as List).length,
        1,
        reason: 'still exactly one image row -- no duplicate was created',
      );
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
    },
  );

  test(
    'C-fix: resuming a draft with TWO staged photos, only ONE of which is '
    'already attached, attaches only the missing one',
    () async {
      const draftId = 'draft_c_fix_partial_attach';
      const carId = 'car_c_fix_partial_attach';
      const alreadyAttached = 'uploads/car_photos/staged_a.jpg';
      const stillMissing = 'uploads/car_photos/staged_b.jpg';

      carsById[carId] = {
        'id': carId,
        'images': [
          {'id': 902, 'kind': 'listing', 'image_url': alreadyAttached},
        ],
        'videos': <dynamic>[],
      };

      final carData = _baseCarData(images: [
        {'source': alreadyAttached},
        {'source': stillMissing},
      ]);
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
      expect(attachCallsLog, hasLength(1));
      expect(
        attachCallsLog.single,
        [stillMissing],
        reason: 'only the not-yet-attached source should be sent',
      );
      expect((carsById[carId]!['images'] as List).length, 2);
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
    },
  );

  // ---- D-fix: resumed progress banner reflects already-confirmed server ---
  // media instead of always restarting at "0 of N".
  test(
    'D-fix: resuming a draft whose listing already has 1 of 2 images '
    'confirmed on the server reports a non-zero completedMediaCount via '
    'statusNotifier during the run, never starting the visible progress '
    'back at 0',
    () async {
      const draftId = 'draft_progress_baseline';
      const carId = 'car_progress_baseline';
      final img2 = File('${tempDir.path}/progress_img2.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

      // Server already confirmed 1 of the 2 listing images this draft
      // describes (landed before a simulated kill/interruption).
      carsById[carId] = {
        'id': carId,
        'images': [
          {'id': 701, 'kind': 'listing'},
        ],
        'videos': <dynamic>[],
      };

      final carData = _baseCarData(
        images: [
          {'id': 701, 'source': 'uploads/car_photos/existing_701.jpg'},
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
          totalMediaCount: 2,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final seenCompletedCounts = <int>[];
      void onStatusChanged() {
        final status =
            PendingSellSubmissionService.instance.statusNotifier.value;
        if (status != null) {
          seenCompletedCounts.add(status.completedMediaCount);
        }
      }

      PendingSellSubmissionService.instance.statusNotifier.addListener(
        onStatusChanged,
      );

      final resumed = await PendingSellSubmissionService.instance
          .resumeAll();

      PendingSellSubmissionService.instance.statusNotifier.removeListener(
        onStatusChanged,
      );

      expect(resumed, isTrue);
      expect(
        seenCompletedCounts,
        anyElement(greaterThan(0)),
        reason: 'the resumed run must report the 1 already-confirmed image '
            'at some point during progress, not remain stuck reporting 0 '
            'throughout the entire run',
      );
      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
      expect(
        (carsById[carId]!['images'] as List).length,
        2,
        reason: '1 pre-existing + 1 newly uploaded = 2 total',
      );
    },
  );

  // ===========================================================================
  // Bug-2 regression (real-device report: "background/foreground and
  // force-close leave submission stuck at 0/N"). `_activeRuns` is private,
  // so this exercises the only externally observable behavior it can
  // affect: a concurrent trigger for the same draft while the FIRST
  // attempt's request is genuinely still pending must join that SAME
  // worker (never spawn a duplicate `POST /api/cars`), and the moment that
  // pending request actually finishes (here: with an error, simulating an
  // OS-suspended socket eventually failing), the marker must be released
  // immediately -- proving staleness can never outlive the real in-flight
  // request, which is exactly what the existing `.whenComplete()` guard in
  // `_ensureRunning` is supposed to guarantee.
  // ===========================================================================
  group(
    'Bug-2: _activeRuns dedup never outlives the real in-flight request',
    () {
      test(
        'a resumeAll() trigger firing while POST /api/cars is genuinely '
        'still pending (simulating a background/foreground overlap) joins '
        'the SAME worker -- no duplicate create call -- and the instant '
        'that pending request finally fails, a brand-new submit() for the '
        'same draft is free to start immediately (not blocked by a stale '
        'marker)',
        () async {
          const draftId = 'draft_stale_guard';
          final firstCreateGate = Completer<void>();
          var createAttempts = 0;
          final localCarsById = <String, Map<String, dynamic>>{};

          ApiService.testHttpClient = MockClient((request) async {
            final method = request.method.toUpperCase();
            final path = request.url.path;
            if (method == 'POST' && path == '/api/cars') {
              createAttempts++;
              if (createAttempts == 1) {
                // Simulate a genuinely stuck request (e.g. an
                // OS-suspended socket while the app is backgrounded):
                // never resolves until the test says so.
                await firstCreateGate.future;
                throw Exception('simulated suspended-socket failure');
              }
              carIdCounter++;
              final id = 'car_$carIdCounter';
              localCarsById[id] = {
                'id': id,
                'images': <dynamic>[],
                'videos': <dynamic>[],
              };
              return http.Response(
                json.encode({'car': localCarsById[id]}),
                201,
                headers: {'content-type': 'application/json'},
              );
            }
            if (method == 'GET' &&
                RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
              return http.Response(
                json.encode({
                  'media_status': 'ready',
                  'items': <dynamic>[],
                  'phase_a_complete': true,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              '{"cars": []}',
              200,
              headers: {'content-type': 'application/json'},
            );
          });

          final firstSubmit = PendingSellSubmissionService.instance.submit(
            draftId: draftId,
            carData: _baseCarData(),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));

          // Simulate a background->foreground trigger firing while the
          // request is still genuinely stuck.
          final joinedResume =
              PendingSellSubmissionService.instance.resumeAll();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(
            createAttempts,
            1,
            reason: 'still only ONE create attempt while genuinely stuck -- '
                'the concurrent trigger must join the same worker, never '
                'spawn a duplicate',
          );

          // Now let the stuck request finally fail (simulating the OS
          // eventually tearing down the suspended socket / a bounded
          // timeout firing).
          firstCreateGate.complete();

          // Neither await may hang forever. `resumeAll()` swallows
          // per-draft errors internally (by design, so one draft's
          // failure never stops the bulk scan), so only the direct
          // `submit()` future is expected to surface the error.
          await joinedResume;
          await expectLater(firstSubmit, throwsA(anything));

          // The marker must already be cleared -- a brand-new attempt for
          // the SAME draft starts (and succeeds) immediately, proving the
          // first, now-dead run never blocks it.
          final secondResult = await PendingSellSubmissionService.instance
              .submit(draftId: draftId, carData: _baseCarData());

          expect(
            secondResult,
            isNotNull,
            reason: 'a fresh attempt right after the stuck one finally '
                'failed must succeed normally -- _activeRuns must not '
                'still be "blocking" this draftId',
          );
          expect(
            createAttempts,
            2,
            reason: 'exactly one retry create call for the fresh attempt',
          );
        },
      );
    },
  );

  // ===========================================================================
  // Bug-3 regression (real-device report, HIGHEST RISK: "media already
  // attached to listing gets deleted" after backgrounding or force-close/
  // resume). Every client call that can mutate media during resume is
  // exercised here against a server that records every DELETE it ever
  // sees -- proving resume/background/foreground/force-close code paths
  // never issue one, even when the local pending list no longer describes
  // an already-attached item (the exact "missing local source" scenario
  // the report calls out).
  // ===========================================================================
  group('Bug-3: resume never deletes already-attached server media', () {
    test(
      'resuming a draft whose server already has an image AND a video '
      'attached, and whose carData ALSO still fully describes both (the '
      'ordinary already-attached-skip case), issues zero DELETE requests',
      () async {
        const draftId = 'draft_no_delete_normal';
        const carId = 'car_no_delete_normal';
        const stagedImage = 'uploads/car_photos/normal_img.jpg';
        carsById[carId] = {
          'id': carId,
          'images': [
            {'id': 950, 'kind': 'listing', 'image_url': stagedImage},
          ],
          'videos': [
            {'id': 5},
          ],
        };
        final carData = _baseCarData(
          images: [
            {'source': stagedImage},
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

        final resumed =
            await PendingSellSubmissionService.instance.resumeAll();

        expect(resumed, isTrue);
        expect(
          deleteCallsLog,
          isEmpty,
          reason: 'resuming an already-fully-attached draft must never '
              'issue any DELETE request',
        );
        expect((carsById[carId]!['images'] as List).length, 1);
        expect((carsById[carId]!['videos'] as List).length, 1);
      },
    );

    test(
      'resuming a draft whose carData is MISSING a local source the '
      'server already has attached (simulating a durable file that '
      'disappeared, or a resumed record whose in-memory pending list no '
      'longer lists everything) still issues zero DELETE requests, and '
      'the pre-existing server image/video rows are left completely '
      'untouched',
      () async {
        const draftId = 'draft_no_delete_missing_local';
        const carId = 'car_no_delete_missing_local';
        carsById[carId] = {
          'id': carId,
          'images': [
            {
              'id': 951,
              'kind': 'listing',
              'image_url': 'uploads/car_photos/missing_local_img.jpg',
            },
          ],
          'videos': [
            {'id': 6},
          ],
        };
        // carData describes NO images/videos at all -- the local pending
        // list "lost" every reference to what the server already has.
        final carData = _baseCarData();
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

        final resumed =
            await PendingSellSubmissionService.instance.resumeAll();

        expect(resumed, isTrue);
        expect(
          deleteCallsLog,
          isEmpty,
          reason: 'a local pending list missing a reference to '
              'already-attached server media must NEVER be interpreted as '
              '"delete it from the server" -- it must simply be left '
              'alone',
        );
        expect(
          (carsById[carId]!['images'] as List).length,
          1,
          reason: 'the pre-existing server image row must survive '
              'untouched',
        );
        expect(
          (carsById[carId]!['videos'] as List).length,
          1,
          reason: 'the pre-existing server video row must survive '
              'untouched',
        );
      },
    );

    test(
      'static: sell_listing_media_upload.dart (the module that performs '
      'ALL resume-time media attach/upload work) never issues an HTTP '
      'DELETE, and never calls ApiService.deleteCarImage/deleteCarVideo',
      () {
        final content = File(
          p.join(
            'lib',
            'features',
            'sell',
            'sell_listing_media_upload.dart',
          ),
        ).readAsStringSync();
        expect(content.contains('deleteCarImage'), isFalse);
        expect(content.contains('deleteCarVideo'), isFalse);
        expect(content.contains("method: 'DELETE'"), isFalse);
        expect(content.contains('.delete('), isFalse);
      },
    );

    test(
      'static: the ONLY two client call sites for deleteCarImage/'
      'deleteCarVideo in the entire Sell flow (sell_step4_logic.dart) are '
      'gated behind an explicit user-initiated remove action in edit mode '
      '-- never reachable from PendingSellSubmissionService resume/'
      'background/foreground/force-close code',
      () {
        final content = File(
          p.join('lib', 'features', 'sell', 'sell_step4_logic.dart'),
        ).readAsStringSync();

        final imageDeleteIdx = content.indexOf('ApiService.deleteCarImage(');
        final videoDeleteIdx = content.indexOf('ApiService.deleteCarVideo(');
        expect(imageDeleteIdx, greaterThanOrEqualTo(0));
        expect(videoDeleteIdx, greaterThanOrEqualTo(0));

        // Exactly one call site each in the whole Sell flow.
        expect(
          RegExp('ApiService.deleteCarImage\\(').allMatches(content).length,
          1,
        );
        expect(
          RegExp('ApiService.deleteCarVideo\\(').allMatches(content).length,
          1,
        );

        final removePhotoIdx = content.indexOf('_removePhotoAt(');
        final removeVideoIdx = content.indexOf('_removeExistingVideoAt(');
        expect(removePhotoIdx, greaterThanOrEqualTo(0));
        expect(removeVideoIdx, greaterThanOrEqualTo(0));
        expect(
          imageDeleteIdx,
          greaterThan(removePhotoIdx),
          reason: 'the image delete call must live inside '
              '_removePhotoAt -- the explicit, user-tap-only removal '
              'method',
        );
        expect(
          videoDeleteIdx,
          greaterThan(removeVideoIdx),
          reason: 'the video delete call must live inside '
              '_removeExistingVideoAt -- the explicit, user-tap-only '
              'removal method',
        );
      },
    );
  });

  // ===========================================================================
  // Issue 1 & 5 regression (real-device evidence: "global bulk resume lock
  // blocks lifecycle recovery" + "multiple historical submissions run
  // concurrently"). Real logs showed `bulkResumeRunning=true` staying set
  // for the ENTIRE lifetime of every dispatched upload runner (because the
  // old `resumeAll()` awaited every runner's Future *inside* the
  // `bulkResumeRunning` guard), so a second, independent, already-eligible
  // record could never even be *discovered* while an older record was
  // still (slowly) uploading. Proves the fixed structure: the bulk guard
  // only protects the short enumerate-and-dispatch loop; `_activeRuns`
  // alone prevents a duplicate runner for the SAME draft; and one
  // permanently-stalled record can never block another, independent
  // record from being discovered, started, and finished.
  // ===========================================================================
  group(
    'Issue 1 & 5: bulkResumeRunning only guards enumeration -- a stalled '
    'record never blocks an independent record, and is never duplicated',
    () {
      test(
        'record A (create request genuinely never returns) and record B '
        '(create request returns normally) are both persisted as pending; '
        'a single resumeAll() call discovers and finishes B while A is '
        'still stuck; a SECOND, overlapping resumeAll() trigger (simulating '
        'a repeated lifecycle=resumed event) joins A\'s existing runner '
        'instead of starting a duplicate create call for A; once A\'s '
        'stuck request finally resolves, A finishes too, with exactly one '
        'car created for each of A and B',
        () async {
          const slowDraftId = 'issue1_slow_record_a';
          const fastDraftId = 'issue1_fast_record_b';
          final slowGate = Completer<void>();
          var slowCreateAttempts = 0;
          var fastCreateAttempts = 0;
          final localCarsById = <String, Map<String, dynamic>>{};
          var localCarIdCounter = 0;

          ApiService.testHttpClient = MockClient((request) async {
            final method = request.method.toUpperCase();
            final path = request.url.path;
            if (method == 'POST' && path == '/api/cars') {
              String? idKey;
              request.headers.forEach((k, v) {
                if (k.toLowerCase() == 'idempotency-key') idKey = v;
              });
              if (idKey == 'sell-create-$slowDraftId') {
                slowCreateAttempts++;
                // Simulates the exact real-device shape: a record whose
                // runner is genuinely still in flight (e.g. a slow/
                // suspended upload), for a long, indeterminate time --
                // never resolves until this test says so.
                await slowGate.future;
              } else {
                fastCreateAttempts++;
              }
              localCarIdCounter++;
              final id = 'car_${idKey ?? 'unknown'}_$localCarIdCounter';
              localCarsById[id] = {
                'id': id,
                'images': <dynamic>[],
                'videos': <dynamic>[],
              };
              return http.Response(
                json.encode({'car': localCarsById[id]}),
                201,
                headers: {'content-type': 'application/json'},
              );
            }
            if (method == 'GET' &&
                RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
              return http.Response(
                json.encode({
                  'media_status': 'ready',
                  'items': <dynamic>[],
                  'phase_a_complete': true,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              '{"cars": []}',
              200,
              headers: {'content-type': 'application/json'},
            );
          });

          final now = DateTime.now().millisecondsSinceEpoch;
          await SellSubmissionStatePrefs.upsert(
            SellSubmissionRecord(
              draftId: slowDraftId,
              status: SellSubmissionStatus.pending,
              carData: _baseCarData(),
              idempotencyKey: 'sell-create-$slowDraftId',
              createdAt: now,
              updatedAt: now,
            ),
          );
          await SellSubmissionStatePrefs.upsert(
            SellSubmissionRecord(
              draftId: fastDraftId,
              status: SellSubmissionStatus.pending,
              carData: _baseCarData(),
              idempotencyKey: 'sell-create-$fastDraftId',
              createdAt: now,
              updatedAt: now,
            ),
          );

          // Trigger 1: e.g. app startup / `lifecycle=resumed`. Fired
          // without awaiting, exactly like the real callers do.
          final resumeFuture1 = PendingSellSubmissionService.instance
              .resumeAll();

          // Record B must be discovered, started, AND finish completely
          // while record A's create call is still genuinely stuck -- this
          // is the exact invariant the old code violated (bulkResumeRunning
          // stayed true for A's entire runtime, so B was never even
          // enumerated until A finished).
          await _waitUntil(
            () async =>
                (await SellSubmissionStatePrefs.load(fastDraftId)) == null,
            timeout: const Duration(seconds: 5),
          );
          expect(fastCreateAttempts, 1);
          expect(
            slowCreateAttempts,
            1,
            reason: 'A must still be genuinely stuck at this point -- only '
                'the ORIGINAL attempt, no duplicate yet',
          );
          final stillA = await SellSubmissionStatePrefs.load(slowDraftId);
          expect(
            stillA,
            isNotNull,
            reason: 'A must still be present/in-progress -- not abandoned, '
                'not age-expired, just genuinely still running',
          );

          // Trigger 2: a repeated/overlapping resumeAll() call (simulating
          // another `lifecycle=resumed`/connectivity-restored event) fired
          // WHILE record A is still stuck. With the old bug this either
          // hung waiting for the bulk lock or was silently skipped with
          // `bulk-resume-already-running` and never even looked at the
          // record list; the fix must let it enumerate immediately and
          // simply JOIN A's already-active runner instead of starting a
          // second `POST /api/cars` for A.
          final resumeFuture2 = PendingSellSubmissionService.instance
              .resumeAll();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(
            slowCreateAttempts,
            1,
            reason: 'the second, overlapping resumeAll() trigger must join '
                "A's existing runner via _activeRuns, never start a "
                'duplicate create call',
          );

          // Let A's genuinely-stuck request finally resolve (e.g. the OS
          // finally delivers the response) and let both resumeAll() calls
          // finish.
          slowGate.complete();
          await resumeFuture1;
          await resumeFuture2;

          expect(
            slowCreateAttempts,
            1,
            reason: 'record A must never be duplicated no matter how many '
                'overlapping resumeAll() triggers fired while it was stuck',
          );
          expect(
            await SellSubmissionStatePrefs.load(slowDraftId),
            isNull,
            reason: 'A must eventually finish successfully once its '
                'request resolves',
          );
          expect(
            localCarsById.length,
            2,
            reason: 'exactly one independent car for A and one for B -- '
                'never zero, never duplicated',
          );
        },
      );
    },
  );

  // ===========================================================================
  // Issue 2 regression (real-device evidence: "persisted progress
  // incorrectly resets to 0/N"). Real logs showed actual UI progress
  // ticking up correctly in memory (e.g. 0/7 -> 3/7 -> 4/7), but the
  // record PERSISTED to disk on failure always showed `progress=0/N` --
  // because the persisted record's `completedMediaCount` was never updated
  // incrementally, only ever reset via the generic failure handler. Proves
  // the fix: progress is durably persisted after EVERY confirmed
  // successful server media operation, and a later failure preserves the
  // last confirmed count instead of overwriting it with zero.
  // ===========================================================================
  group('Issue 2: persisted progress reflects every confirmed media item, '
      'never resets to 0/N', () {
    test(
      'listing photos (3), a video, and damage photos (2) are all part of '
      'one submission; the video upload permanently fails, but the '
      'persisted record still shows completedMediaCount = 5 (3 photos + 2 '
      'damage photos actually confirmed on the server), never 0, and '
      'retains the carId that really exists on the backend',
      () async {
        const draftId = 'issue2_partial_progress';
        final img1 = File('${tempDir.path}/i2_img1.jpg')
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1]);
        final img2 = File('${tempDir.path}/i2_img2.jpg')
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 2]);
        final img3 = File('${tempDir.path}/i2_img3.jpg')
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 3]);
        final video = File('${tempDir.path}/i2_video.mp4')
          ..writeAsBytesSync(List<int>.filled(16, 1));
        final dmg1 = File('${tempDir.path}/i2_dmg1.jpg')
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 4]);
        final dmg2 = File('${tempDir.path}/i2_dmg2.jpg')
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 5]);

        videoUploadOverride = (_) => http.Response(
          json.encode({'message': 'Unsupported video format'}),
          400,
          headers: {'content-type': 'application/json'},
        );

        final carData = _baseCarData(
          images: [img1.path, img2.path, img3.path],
          videos: [video.path],
          damageImages: [dmg1.path, dmg2.path],
        );

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

        final failed = await SellSubmissionStatePrefs.load(draftId);
        expect(failed, isNotNull);
        expect(failed!.status, SellSubmissionStatus.needsAttention);
        expect(
          failed.completedMediaCount,
          5,
          reason: '3 confirmed listing photos + 2 confirmed damage photos '
              '= 5 truly-attached media items, even though the video '
              'failed -- must never be reported/persisted as 0',
        );
        expect(failed.totalMediaCount, 6);
        expect(
          failed.carId,
          isNotNull,
          reason: 'the listing that really exists on the backend must be '
              'preserved',
        );
        expect(failed.carId, isNotEmpty);
      },
    );

    test(
      'resuming a draft with an existing carId that already has 2 of 3 '
      'listing images confirmed on the server durably persists that '
      'server-confirmed baseline (completedMediaCount=2) to disk -- not '
      'just in an in-memory variable -- before the remaining upload work '
      'even finishes, so a process kill immediately after resume starts '
      'still reconstructs progress from server state rather than 0',
      () async {
        const draftId = 'issue2_baseline_persisted';
        const carId = 'car_issue2_baseline';
        final img3 = File('${tempDir.path}/i2b_img3.jpg')
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 9]);
        final video = File('${tempDir.path}/i2b_video.mp4')
          ..writeAsBytesSync(List<int>.filled(16, 2));

        // Server already confirmed 2 of the 3 listing images this draft
        // describes.
        carsById[carId] = {
          'id': carId,
          'images': [
            {'id': 801, 'kind': 'listing'},
            {'id': 802, 'kind': 'listing'},
          ],
          'videos': <dynamic>[],
        };

        // Media-readiness contract fix: Phase A now runs (and must fully
        // complete, for every media kind) BEFORE Phase B's own poll/attach
        // work starts -- so stalling the video's atomic upload call (which
        // is itself Phase A for a normal video) would block Phase A
        // globally, and this test's photo-processing Phase B work (whose
        // progress it wants to observe WHILE something is still stalled)
        // would never even start. Stall the image PROCESSING JOB POLL
        // (`GET /api/jobs/<id>`, a Phase-B-only step) instead -- the video
        // upload now succeeds normally/fast, so Phase A finishes quickly
        // for every item, and the run reaches Phase B (where img3's poll
        // hangs) exactly as before.
        final jobPollGate = Completer<void>();
        ApiService.testHttpClient = MockClient((request) async {
          final method = request.method.toUpperCase();
          final path = request.url.path;
          final videoMatch = RegExp(
            r'^/api/cars/([^/]+)/videos$',
          ).firstMatch(path);
          if (method == 'POST' && videoMatch != null) {
            // Real backend contract: a genuinely-confirmed video upload
            // returns a `videos` array with one entry per successfully
            // attached file (see `kk/routes/media.py::upload_car_videos`).
            // The Flutter media-confirmation crediting logic now credits
            // strictly off THIS array's length -- never the blindly-
            // assumed request count -- so this mock must actually report
            // the video it just "received" as confirmed, or the test's
            // own claim that "the video is credited immediately" (its
            // Phase A IS its full atomic attach) can never hold.
            final vid = videoMatch.group(1)!;
            final vcar = carsById.putIfAbsent(
              vid,
              () => {'id': vid, 'images': <dynamic>[], 'videos': <dynamic>[]},
            );
            final vrow = {'id': 901, 'kind': 'listing'};
            (vcar['videos'] as List).add(vrow);
            return http.Response(
              json.encode({'videos': [vrow]}),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          if (method == 'GET' &&
              RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
            return http.Response(
              json.encode({
                'media_status': 'processing',
                'items': <dynamic>[],
                'phase_a_complete': true,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          final getMatch = RegExp(r'^/api/cars/([^/]+)$').firstMatch(path);
          if (method == 'GET' && getMatch != null) {
            final id = getMatch.group(1)!;
            return http.Response(
              json.encode({'car': carsById[id]}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          final attachMatch = RegExp(
            r'^/api/cars/([^/]+)/images/attach$',
          ).firstMatch(path);
          if (method == 'POST' && attachMatch != null) {
            final id = attachMatch.group(1)!;
            final decoded = json.decode(request.body) as Map;
            final paths = List<String>.from(decoded['paths'] as List);
            final car = carsById.putIfAbsent(
              id,
              () => {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]},
            );
            final rows = <Map<String, dynamic>>[];
            for (final p in paths) {
              imageRowIdCounter++;
              final row = {
                'id': imageRowIdCounter,
                'kind': 'listing',
                'source': p,
              };
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
          if (method == 'POST' && path == '/api/cars/$carId/images') {
            final bodyText = latin1.decode(request.bodyBytes);
            final fileCount = RegExp(
              'name="images"',
            ).allMatches(bodyText).length;
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
          if (method == 'GET' && path.startsWith('/api/jobs/')) {
            await jobPollGate.future;
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
          return http.Response(
            '{"cars": []}',
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final carData = _baseCarData(
          images: [
            {'id': 801, 'source': 'uploads/car_photos/existing_801.jpg'},
            {'id': 802, 'source': 'uploads/car_photos/existing_802.jpg'},
            img3.path,
          ],
          videos: [video.path],
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
            totalMediaCount: 4,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final resumeFuture = PendingSellSubmissionService.instance
            .resumeAll();

        // Poll the ON-DISK record (not just statusNotifier) until it
        // reflects at least the server-confirmed baseline of 2 -- proving
        // this was durably persisted, not just held in memory -- and then
        // until it reaches 3 once the video's Phase-A atomic upload+attach
        // also gets confirmed/credited, all while the new photo's own
        // processing-job poll is still stalled and the run has not
        // finished.
        await _waitUntil(() async {
          final r = await SellSubmissionStatePrefs.load(draftId);
          return r != null && r.completedMediaCount >= 2;
        });
        final duringBaseline = await SellSubmissionStatePrefs.load(draftId);
        expect(duringBaseline, isNotNull);
        expect(
          duringBaseline!.status,
          SellSubmissionStatus.inProgress,
          reason: 'the run has not finished yet -- the new photo\'s '
              'processing-job poll is still stalled',
        );

        await _waitUntil(() async {
          final r = await SellSubmissionStatePrefs.load(draftId);
          return r != null && r.completedMediaCount >= 3;
        });
        final afterNewPhoto = await SellSubmissionStatePrefs.load(draftId);
        expect(
          afterNewPhoto!.completedMediaCount,
          3,
          reason: '2 pre-existing photos + 1 confirmed video (its Phase A '
              'IS its full atomic attach, so it is credited immediately, '
              'before Phase B even starts) = 3, durably persisted to disk '
              'while the new (3rd) photo\'s own processing job is still '
              'stalled and has not yet had any chance to finish/credit '
              'its own count',
        );

        // Let the stalled poll finish so the test can clean up without a
        // dangling stalled future.
        jobPollGate.complete();
        await resumeFuture;
      },
    );

    // ---- Crash-window follow-up: reconcile from SERVER state, not the ----
    // stale locally-persisted count. Real gap: server attach succeeds ->
    // process is killed BEFORE persistProgress() runs -> the on-disk
    // record still shows the OLD (stale) completedMediaCount. Proves
    // `SellListingMediaUpload.confirmedServerMediaCount()` (identity-based,
    // same semantics `uploadForCar` itself uses to skip already-attached
    // media) is used to recompute -- and durably re-persist -- the correct
    // count from the server BEFORE any further upload work, every time a
    // record with an existing carId is resumed.
    test(
      'crash-window fix: a record whose LOCAL persisted completedMediaCount '
      'is stale (1/5) because the process died before persistProgress() '
      'ran is reconciled from ACTUAL SERVER state (2 listing photos + 1 '
      'video already confirmed = 3/5) BEFORE any further upload work; the '
      'already-confirmed photos and video are never re-attached/re-'
      'uploaded, and only the 2 remaining damage photos upload to reach '
      '5/5',
      () async {
        const draftId = 'issue2_reconcile_from_server';
        const carId = 'car_issue2_reconcile';
        final video = File('${tempDir.path}/reconcile_video.mp4')
          ..writeAsBytesSync(List<int>.filled(16, 1));
        final dmg1 = File('${tempDir.path}/reconcile_dmg1.jpg')
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1]);
        final dmg2 = File('${tempDir.path}/reconcile_dmg2.jpg')
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 2]);

        // Server ALREADY has both listing images and the video confirmed
        // (landed before a simulated crash) -- 3 of the eventual 5 media
        // items -- but zero damage photos yet.
        carsById[carId] = {
          'id': carId,
          'images': [
            {'id': 701, 'kind': 'listing'},
            {'id': 702, 'kind': 'listing'},
          ],
          'videos': [
            {'id': 9},
          ],
        };

        final carData = _baseCarData(
          images: [
            {'id': 701, 'source': 'uploads/car_photos/e701.jpg'},
            {'id': 702, 'source': 'uploads/car_photos/e702.jpg'},
          ],
          videos: [video.path],
          damageImages: [dmg1.path, dmg2.path],
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
            // Stale: a crash after the server-side attach succeeded but
            // BEFORE this record's own persistProgress() call ever landed.
            completedMediaCount: 1,
            totalMediaCount: 5,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final seenCompletedCounts = <int>[];
        void onStatusChanged() {
          final status =
              PendingSellSubmissionService.instance.statusNotifier.value;
          if (status != null) {
            seenCompletedCounts.add(status.completedMediaCount);
          }
        }

        PendingSellSubmissionService.instance.statusNotifier.addListener(
          onStatusChanged,
        );

        final resumed = await PendingSellSubmissionService.instance
            .resumeAll();

        PendingSellSubmissionService.instance.statusNotifier.removeListener(
          onStatusChanged,
        );

        expect(resumed, isTrue);
        expect(
          seenCompletedCounts,
          contains(3),
          reason: 'the server-confirmed baseline (2 photos + 1 video = 3) '
              'must be reported/persisted BEFORE the remaining damage '
              'photos upload -- never left at the stale local value of 1',
        );
        expect(
          seenCompletedCounts.any((c) => c < 1),
          isFalse,
          reason: 'progress must never regress below the previously-'
              'persisted value, even transiently',
        );

        // The 2 already-confirmed listing photos must never be re-
        // attached/re-uploaded -- only the 2 damage photos go through the
        // attach endpoint (via the async job pipeline).
        expect(attachCallsLog, hasLength(1));
        expect(attachCallsLog.single, hasLength(2));
        // The already-confirmed video must never be re-uploaded.
        expect(videoUploadLog, isEmpty);
        // Only the 2 NOT-yet-confirmed damage photos are enqueued.
        expect(imagesEnqueueFileCounts, [2]);

        expect(await SellSubmissionStatePrefs.load(draftId), isNull);
        expect(
          (carsById[carId]!['images'] as List).length,
          4,
          reason: '2 pre-existing listing + 2 newly uploaded damage = 4 '
              'image rows',
        );
        expect((carsById[carId]!['videos'] as List).length, 1);
      },
    );

    test(
      'crash-window fix: a record whose local completedMediaCount is still '
      '0 because the process was killed right after the FIRST-EVER server '
      'attach succeeded (before persistProgress() ever ran even once) is '
      'reconciled to the correct server-derived count (1/1) by the next '
      'resumeAll() -- simulating a fresh app launch / new service instance '
      '-- and never re-attaches the already-confirmed photo',
      () async {
        const draftId = 'issue2_crash_before_first_persist';
        const carId = 'car_issue2_crash_before_first_persist';

        // The server really does already have this photo attached -- as
        // if the attach HTTP call succeeded right before the process
        // died, with no chance for the client to ever call
        // persistProgress() even a single time.
        carsById[carId] = {
          'id': carId,
          'images': [
            {'id': 801, 'kind': 'listing'},
          ],
          'videos': <dynamic>[],
        };

        final carData = _baseCarData(
          images: [
            {'id': 801, 'source': 'uploads/car_photos/crash801.jpg'},
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
            completedMediaCount: 0,
            totalMediaCount: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final resumed = await PendingSellSubmissionService.instance
            .resumeAll();

        expect(resumed, isTrue);
        expect(
          attachCallsLog,
          isEmpty,
          reason: 'the already-confirmed photo must never be re-attached',
        );
        expect(await SellSubmissionStatePrefs.load(draftId), isNull);
        expect((carsById[carId]!['images'] as List).length, 1);
      },
    );
  });

  // ---- K. Sell-video compression durability -------------------------------
  // Real-device evidence: a 6s .mov at 112,329,351 bytes was rejected by the
  // backend's exact 100MB `validate_file_upload(..., max_size_mb=100)`
  // check. `SellVideoCompression.prepare()` (see
  // `lib/features/sell/sell_video_compression.dart`) now runs BEFORE this
  // service ever sees the file, replacing the oversized source with a
  // compressed `.mp4`. These tests prove the replacement is transparent to
  // `PendingSellSubmissionService`: the compressed file is uploaded with
  // the correct (re-encoded) extension/MIME -- never the original picker
  // extension -- and a completed submission is never re-uploaded on a
  // later resume.
  group('K. Sell-video compression durability', () {
    test(
      'a video that went through SellVideoCompression.prepare() (source '
      '.mov -> compressed .mp4) is uploaded with the RE-ENCODED container\'s '
      'filename/Content-Type ("*.mp4" / "video/mp4"), never the original '
      '.mov picker extension -- and a later resumeAll() never re-uploads it '
      '(no duplicate video on resume)',
      () async {
        const draftId = 'video_compression_durable';

        // The "oversized .mov" from the picker -- content doesn't matter,
        // only that `prepare()` decides to compress because of declared
        // probe size/bitrate, exactly like the real 112,329,351-byte case.
        final sourceMov = File('${tempDir.path}/original_source.mov')
          ..writeAsBytesSync(List<int>.filled(64, 7));

        SellVideoCompression.debugProberOverride = (path) async => SellVideoProbe(
          sizeBytes: 112329351,
          width: 1920,
          height: 1080,
          bitrateBps: 20 * 1000 * 1000,
          durationMs: 6000,
        );
        addTearDown(() => SellVideoCompression.debugProberOverride = null);

        final compressedOut = File('${tempDir.path}/compressed_output.mp4')
          ..writeAsBytesSync(List<int>.filled(32, 9));
        SellVideoCompression.debugCompressorOverride = (req) async =>
            SellVideoCompressOutput(compressedOut.path);
        addTearDown(() => SellVideoCompression.debugCompressorOverride = null);

        final prepared = await SellVideoCompression.prepare(
          XFile(sourceMov.path),
        );
        expect(
          prepared.status,
          SellVideoPrepareStatus.compressed,
          reason: 'the 112,329,351-byte / 20Mbps probe must trigger '
              'compression, mirroring the real-device report',
        );
        expect(prepared.file, isNotNull);
        expect(
          p.extension(prepared.file!.path),
          '.mp4',
          reason: 'the compressed output container is .mp4, regardless of '
              'the original .mov source extension',
        );

        // Exactly the state right after `_pickVideos()` -- the compressed
        // file is what goes into `carData['videos']`, not the original
        // `.mov` source path.
        final result = await PendingSellSubmissionService.instance.submit(
          draftId: draftId,
          carData: _baseCarData(videos: [prepared.file!.path]),
        );
        expect(result, isNotNull);

        expect(videoUploadLog.length, 1);
        expect(
          videoUploadPartLog.length,
          1,
          reason: 'the multipart "files" part for the video upload must '
              'have been captured',
        );
        expect(
          videoUploadPartLog.single['filename'],
          endsWith('.mp4'),
          reason: 'the uploaded filename must reflect the RE-ENCODED '
              'container, never the original .mov picker extension',
        );
        expect(
          videoUploadPartLog.single['contentType'],
          'video/mp4',
          reason: 'the correct MIME type for the compressed container '
              'must reach the uploader',
        );

        // Simulate a later resume (e.g. a stray background/foreground
        // trigger, or an app relaunch that still had the draftId around).
        // The submission already completed and its record was removed --
        // resuming again must be a no-op, never re-uploading the video.
        final resumedAgain = await PendingSellSubmissionService.instance
            .resumeAll();
        expect(resumedAgain, isFalse);
        expect(
          videoUploadLog.length,
          1,
          reason: 'no duplicate video upload must happen on a later '
              'resume of an already-completed submission',
        );
      },
    );
  });
}
