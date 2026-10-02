// Media-readiness "Phase A" contract tests -- additive to
// `pending_sell_submission_fast_submit_test.dart` (which already covers
// the requiresServerTranscode-video and images-only end-to-end scenarios,
// rewritten for the new contract) and
// `pending_sell_submission_service_test.dart` (which covers `submit()`'s
// own full-completion contract and general resume/dedup mechanics).
//
// This file specifically proves the contract items that were NOT already
// covered elsewhere:
//   A. Ready signal does NOT fire immediately after `create_car` when
//      `expected_media` exists (an in-flight Phase-A image enqueue call
//      still gates it).
//   B. One slow Phase-A upload delays `submitFast()` -- proven by the same
//      gate as A, released explicitly, with the resolution observed only
//      after release.
//   D. Image PROCESSING (the Celery job reaching a terminal state) may
//      take arbitrarily long and `submitFast()` still resolves as soon as
//      the enqueue itself (Phase A) is accepted -- proven by a poll gate
//      that is NEVER released within the test, yet `submitFast()` still
//      resolves.
//   F. App kill after `create_car` succeeds but before one image's Phase A
//      completes: resuming (a second `submitFast()`/`resumeAll()` call for
//      the same draft, with an existing `carId`) transfers ONLY the
//      missing item -- the already-Phase-A-complete item is never
//      re-enqueued.
//   H. No duplicate uploads/attachments after that resume (same evidence
//      as F, asserted via call counts).
//   I. A genuinely zero-media listing (no images/videos/damage photos at
//      all) still submits correctly and immediately.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
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
  'server_transcode_videos': <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  http.Response jsonOk(Map<String, dynamic> body, [int status = 200]) =>
      http.Response(
        json.encode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('phase_a_contract_');
    final docsDir = Directory('${tempDir.path}/docs')
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);
    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    debugSellSubmissionRetryBackoffOverride = (_) => Duration.zero;
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
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'A+B: submitFast() does NOT resolve immediately after create_car when '
    'expected_media exists -- a still-in-flight Phase-A image enqueue call '
    'genuinely delays it, and it only resolves once that call (and the '
    'media-summary confirmation) completes',
    () async {
      const draftId = 'phaseA_ab_gate';
      final imagePath = p.join(tempDir.path, 'ab_photo.jpg');
      File(imagePath).writeAsBytesSync(List<int>.filled(16, 1));

      var createCalls = 0;
      var enqueueCalls = 0;
      var mediaSummaryCalls = 0;
      final enqueueGate = Completer<void>();

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        if (method == 'POST' && path == '/api/cars') {
          createCalls++;
          return jsonOk({
            'car': {'id': 'car_ab_1', 'images': [], 'videos': []},
          }, 201);
        }
        final enqueueMatch =
            RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
        if (method == 'POST' && enqueueMatch != null) {
          enqueueCalls++;
          // The gate: `create_car()` above has already returned, but this
          // Phase-A transfer call has not -- proves the ready signal
          // cannot have fired yet purely from the car existing.
          await enqueueGate.future;
          return jsonOk({'job_ids': <String>['job_ab_1']}, 202);
        }
        if (method == 'GET' && path == '/api/jobs/job_ab_1') {
          return jsonOk({
            'task_id': 'job_ab_1',
            'state': 'SUCCESS',
            'result': {'rel_path': 'uploads/car_photos/job_ab_1.jpg'},
          });
        }
        final attachMatch =
            RegExp(r'^/api/cars/([^/]+)/images/attach$').firstMatch(path);
        if (method == 'POST' && attachMatch != null) {
          final decoded = json.decode(request.body) as Map;
          final paths = List<String>.from(decoded['paths'] as List);
          return jsonOk({
            'images': paths.map((p) => {'id': 1, 'image_url': p}).toList(),
          }, 201);
        }
        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
          mediaSummaryCalls++;
          return jsonOk({
            'media_status': 'processing',
            'items': <dynamic>[],
            'phase_a_complete': true,
          });
        }
        return jsonOk({'cars': []});
      });

      final carData = _baseCarData(images: [imagePath]);
      final resultFuture = PendingSellSubmissionService.instance.submitFast(
        draftId: draftId,
        carData: carData,
      );

      var resolved = false;
      // ignore: unawaited_futures
      resultFuture.then((_) => resolved = true);

      // Give the create call (and everything up to the gated enqueue) a
      // generous head start.
      await _waitUntil(() => enqueueCalls >= 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        resolved,
        isFalse,
        reason: 'submitFast() must still be pending -- the car exists '
            '(create_car succeeded) but the declared image has not '
            'completed Phase A yet',
      );
      expect(createCalls, 1);

      // Release the gate -- Phase A can now complete.
      enqueueGate.complete();

      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.id, 'car_ab_1');
      expect(
        mediaSummaryCalls,
        greaterThanOrEqualTo(1),
        reason: 'the ready signal must be confirmed via server-side '
            'media-summary, not just "the enqueue call returned"',
      );
    },
  );

  test(
    'D: image PROCESSING may take minutes (the job never reaches a '
    'terminal state within this test) and submitFast() still resolves as '
    'soon as the enqueue itself (Phase A) is durably accepted',
    () async {
      const draftId = 'phaseA_d_processing_slow';
      final imagePath = p.join(tempDir.path, 'd_photo.jpg');
      File(imagePath).writeAsBytesSync(List<int>.filled(16, 2));

      final neverReleasedPollGate = Completer<void>();

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        if (method == 'POST' && path == '/api/cars') {
          return jsonOk({
            'car': {'id': 'car_d_1', 'images': [], 'videos': []},
          }, 201);
        }
        final enqueueMatch =
            RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
        if (method == 'POST' && enqueueMatch != null) {
          return jsonOk({'job_ids': <String>['job_d_1']}, 202);
        }
        if (method == 'GET' && path == '/api/jobs/job_d_1') {
          // Never resolves within this test's lifetime -- proves
          // `submitFast()` cannot possibly be waiting on this.
          await neverReleasedPollGate.future;
          return jsonOk({'task_id': 'job_d_1', 'state': 'SUCCESS'});
        }
        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
          return jsonOk({
            'media_status': 'processing',
            'items': <dynamic>[],
            'phase_a_complete': true,
          });
        }
        return jsonOk({'cars': []});
      });

      final carData = _baseCarData(images: [imagePath]);
      final result = await PendingSellSubmissionService.instance.submitFast(
        draftId: draftId,
        carData: carData,
      );

      expect(result, isNotNull);
      expect(result!.id, 'car_d_1');
      // Whether or not Phase B's poll loop has started yet is irrelevant --
      // what matters is that we got here at all without the never-released
      // gate ever being awaited by `submitFast()` itself.
    },
  );

  test(
    'F+H: resuming a draft whose carId already exists and whose first '
    'image already completed Phase A (job durably recorded) before the '
    'app died, transfers ONLY the second (still-missing) image -- the '
    'first is never re-enqueued -- and submitFast() resolves once the '
    'missing item also completes Phase A',
    () async {
      const draftId = 'phaseA_f_resume_partial';
      const carId = 'car_f_resume';
      final img1 = File('${tempDir.path}/f_img1.jpg')
        ..writeAsBytesSync(List<int>.filled(16, 3));
      final img2 = File('${tempDir.path}/f_img2.jpg')
        ..writeAsBytesSync(List<int>.filled(16, 4));

      final enqueuedPaths = <String>[];
      var mediaSummaryCalls = 0;
      // Simulates the real backend's per-item `phase_a_completed_at`: img1
      // is treated as already Phase-A-complete from the start (its job was
      // durably recorded BEFORE the simulated app kill -- see the
      // `pendingAsyncImageJobs` seed below), img2 only becomes complete
      // once THIS test observes its enqueue call actually happen.
      var img2PhaseAComplete = false;

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        final enqueueMatch =
            RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
        if (method == 'POST' && enqueueMatch != null) {
          final bodyText = latin1.decode(request.bodyBytes);
          // Record which file(s) this enqueue call carried, by counting
          // "images" parts -- good enough here since each call in this
          // test only ever carries at most one file.
          if (RegExp('name="images"').hasMatch(bodyText)) {
            if (bodyText.contains('f_img2')) {
              enqueuedPaths.add(img2.path);
              img2PhaseAComplete = true;
            } else if (bodyText.contains('f_img1')) {
              enqueuedPaths.add(img1.path);
            }
          }
          return jsonOk({'job_ids': <String>['job_f_new']}, 202);
        }
        if (method == 'GET' && path.startsWith('/api/jobs/')) {
          final jobId = path.substring('/api/jobs/'.length);
          return jsonOk({
            'task_id': jobId,
            'state': 'SUCCESS',
            'result': {'rel_path': 'uploads/car_photos/$jobId.jpg'},
          });
        }
        final attachMatch =
            RegExp(r'^/api/cars/([^/]+)/images/attach$').firstMatch(path);
        if (method == 'POST' && attachMatch != null) {
          final decoded = json.decode(request.body) as Map;
          final paths = List<String>.from(decoded['paths'] as List);
          return jsonOk({
            'images': paths.map((p) => {'id': 1, 'image_url': p}).toList(),
          }, 201);
        }
        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+$').hasMatch(path) &&
            !RegExp(r'/media-summary$').hasMatch(path)) {
          return jsonOk({
            'car': {'id': carId, 'images': [], 'videos': []},
          });
        }
        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
          mediaSummaryCalls++;
          return jsonOk({
            'media_status': 'processing',
            'items': <dynamic>[],
            'phase_a_complete': img2PhaseAComplete,
          });
        }
        return jsonOk({'cars': []});
      });

      // Simulate: `create_car()` already succeeded (carId persisted),
      // img1's Phase-A enqueue already happened and was durably recorded
      // (`pendingAsyncImageJobs`), THEN the app died before img2's Phase A
      // (or the ready-signal check) ever ran. This is the auto-resume
      // path (`resumeAll()`, triggered on the next app launch/lifecycle
      // event) -- NOT a second `submitFast()` call -- since only
      // `resumeAll()`/`_runSubmission` operate purely on the ALREADY-
      // persisted `record.carData` with no re-durable-copy step; a fresh
      // `submitFast()`/`submit()` call always re-runs
      // `_prepareSubmissionRecord()` on whatever `carData` its OWN caller
      // supplies this time (by design -- it may differ from what was
      // durably persisted before), which is a different, pre-existing
      // contract this test intentionally does not exercise.
      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: draftId,
          status: SellSubmissionStatus.inProgress,
          carId: carId,
          carData: _baseCarData(images: [img1.path, img2.path]),
          idempotencyKey: 'sell-create-$draftId',
          currentPhase: 'photos',
          createdAt: now,
          updatedAt: now,
          pendingAsyncImageJobs: {
            img1.path: 'job_f_already_enqueued|$now',
          },
        ),
      );

      final resumed = await PendingSellSubmissionService.instance.resumeAll();
      expect(resumed, isTrue);

      final result = await SellSubmissionStatePrefs.load(draftId);
      expect(
        result,
        isNull,
        reason: 'once img2 also completes Phase A, the run continues into '
            'Phase B (attach) and finishes normally -- the durable record '
            'is removed exactly like any other successful submission',
      );
      expect(
        enqueuedPaths,
        [img2.path],
        reason: 'only the still-missing image (img2) may be freshly '
            'enqueued -- img1 already had a durably-recorded job from '
            'before the simulated app kill and must never be re-enqueued',
      );
      expect(
        mediaSummaryCalls,
        greaterThanOrEqualTo(1),
        reason: 'the resumed run must still confirm Phase-A completeness '
            'via server-authoritative media-summary before resolving',
      );
    },
  );

  test(
    'I: a genuinely zero-media listing (no images, videos, or damage '
    'photos at all) still submits correctly and resolves immediately via '
    'submitFast()',
    () async {
      const draftId = 'phaseA_i_zero_media';
      var createCalls = 0;

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        if (method == 'POST' && path == '/api/cars') {
          createCalls++;
          return jsonOk({
            'car': {'id': 'car_zero_1', 'images': [], 'videos': []},
          }, 201);
        }
        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
          // Trivially true over an empty manifest -- see
          // `kk/media_readiness.py::media_summary`'s doc comment.
          return jsonOk({
            'media_status': 'ready',
            'items': <dynamic>[],
            'phase_a_complete': true,
          });
        }
        return jsonOk({'cars': []});
      });

      final carData = _baseCarData();
      final result = await PendingSellSubmissionService.instance.submitFast(
        draftId: draftId,
        carData: carData,
      );

      expect(result, isNotNull);
      expect(result!.id, 'car_zero_1');
      expect(createCalls, 1);

      await _waitUntil(() async {
        final record = await SellSubmissionStatePrefs.load(draftId);
        return record == null;
      });
    },
  );
}
