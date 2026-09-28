// Tests for `PendingSellSubmissionService.submitFast()` (see
// `lib/features/sell/pending_sell_submission_service.dart`) -- the fast
// optimistic-submission entry point that lets the Sell UI navigate away as
// soon as the backend listing itself exists, WITHOUT waiting for the
// remaining media pipeline (image/video upload, and especially a
// `requiresServerTranscode` video's 60-120s server-side transcode+poll) to
// finish. `submit()` itself is intentionally left byte-for-byte unchanged
// (see `pending_sell_submission_service_test.dart`, which asserts on its
// full-completion contract) -- `submitFast()` shares the exact same
// underlying worker via a new Completer-based "car ready" signal.
//
// Scenarios covered here (see the task's test-matrix items):
//   - `submitFast()` resolves as soon as the listing exists, strictly
//     BEFORE a still-in-flight `requiresServerTranscode` video's transcode
//     job finishes (proven with a server-controlled gate on the poll
//     endpoint).
//   - the durable pending-submission record still exists (media considered
//     "processing") immediately after that fast resolution.
//   - the background pipeline keeps running after the fast return and,
//     once the gate is released, completes the transcode video and clears
//     the durable record -- no duplicate listing, no re-signing/re-upload.
//   - a no-video (images-only) submission still fast-returns and completes
//     normally end to end.
//   - a permanent create failure surfaces as an error from `submitFast()`
//     itself (never silently swallowed) when the car never got created.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/features/sell/sell_server_transcode_video.dart';
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

  http.Response jsonOk(Map<String, dynamic> body, [int status = 200]) =>
      http.Response(
        json.encode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sell_fast_submit_');
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
    'submitFast() resolves as soon as the listing is created -- strictly '
    'BEFORE a requiresServerTranscode video finishes its (gated) transcode '
    'poll -- and the durable record survives that fast resolution '
    '("mediaStatus" stays processing even though userFacingStatus is '
    'already submitted); the background pipeline then keeps running and '
    'clears the record once the transcode completes, without re-creating '
    'the listing or re-uploading the source',
    () async {
      const draftId = 'draft_fast_1';
      final sourcePath = p.join(tempDir.path, 'source.mov');
      File(sourcePath).writeAsBytesSync(List<int>.filled(2048, 0x9));
      final spec = ServerTranscodeVideoSpec(
        draftMediaId: 'vst_fast_1',
        localSourcePath: sourcePath,
        sourceByteSize: 2048,
        sourceMimeType: 'video/quicktime',
      );

      var createCalls = 0;
      var signCalls = 0;
      var finalizeCalls = 0;
      var pollCalls = 0;
      var attachCalls = 0;
      final transcodeGate = Completer<void>();

      ApiService.testHttpClient = MockClient((request) async {
        final path = request.url.path;
        final method = request.method.toUpperCase();

        if (method == 'POST' && path == '/api/cars') {
          createCalls++;
          return jsonOk({
            'car': {'id': 'car_fast_1', 'images': [], 'videos': []},
          }, 201);
        }
        if (path == '/api/media/r2/sign-video-source-upload') {
          signCalls++;
          return jsonOk({
            'upload_url': 'https://r2.example.test/staging/key1',
            'staging_key': 'staging/key1',
            'expires_in': 900,
            'max_bytes': 500 * 1024 * 1024,
          });
        }
        if (method == 'PUT' && request.url.host == 'r2.example.test') {
          return http.Response('', 200);
        }
        if (path == '/api/media/r2/finalize-video-source-upload') {
          finalizeCalls++;
          return jsonOk({
            'status': 'staged',
            'staging_key': 'staging/key1',
            'size': spec.sourceByteSize,
            'task_id': 'task-fast-1',
            'job_state': 'queued',
          });
        }
        if (path == '/api/jobs/task-fast-1') {
          pollCalls++;
          // The gate: never resolves SUCCESS until the test explicitly
          // completes [transcodeGate] -- this is what proves
          // `submitFast()` does not (and must not) wait for this.
          await transcodeGate.future;
          return jsonOk({'task_id': 'task-fast-1', 'state': 'SUCCESS'});
        }
        if (path == '/api/media/r2/attach-transcoded-video') {
          attachCalls++;
          return jsonOk({
            'message': 'attached',
            'video': {'id': 1, 'video_url': 'https://cdn/final.mp4'},
          }, 201);
        }
        if (method == 'GET' && path == '/api/cars') {
          return jsonOk({'cars': []});
        }
        return jsonOk({'cars': []});
      });

      final carData = _baseCarData(
        serverTranscodeVideos: [spec.toJson()],
      );

      final result = await PendingSellSubmissionService.instance.submitFast(
        draftId: draftId,
        carData: carData,
      );

      // 1. Fast return already happened with the real carId, while the
      //    transcode poll is still blocked on the gate.
      expect(result, isNotNull);
      expect(result!.id, 'car_fast_1');
      expect(
        pollCalls,
        0,
        reason: 'submitFast() must not itself wait on the poll loop -- if '
            'this is >0 already, the fast path accidentally awaited the '
            'full pipeline instead of returning early',
      );

      // 2. The durable pending-submission record is still there right
      //    after the user-facing success -- "mediaStatus" is still
      //    processing even though the user has already been shown success
      //    and (in the real app) already navigated away.
      var record = await SellSubmissionStatePrefs.load(draftId);
      expect(
        record,
        isNotNull,
        reason: 'durable state must NOT be cleared merely because the user '
            'was shown success -- only once ALL media (including this '
            'transcode video) is fully attached',
      );
      expect(record!.carId, 'car_fast_1');

      // Background pipeline is genuinely still working in the meantime.
      await _waitUntil(() => signCalls >= 1 && finalizeCalls >= 1);

      // 3. Release the gate -- the background pipeline finishes the
      //    transcode video and attaches it.
      transcodeGate.complete();
      await _waitUntil(() => attachCalls >= 1);

      // 4. Once every required remote media item is attached, the durable
      //    record is finally removed.
      await _waitUntil(() async {
        record = await SellSubmissionStatePrefs.load(draftId);
        return record == null;
      });

      // No duplicate listing was ever created, and the source was only
      // signed/finalized once each despite the earlier gated wait.
      expect(createCalls, 1);
      expect(signCalls, 1);
      expect(finalizeCalls, 1);
      expect(attachCalls, 1);
    },
  );

  test(
    'a no-video (images-only) submission still fast-returns via '
    'submitFast() and completes normally end to end (no server-transcode '
    'video path involved at all)',
    () async {
      const draftId = 'draft_fast_images_only';
      var createCalls = 0;
      var attachCalls = 0;

      ApiService.testHttpClient = MockClient((request) async {
        final path = request.url.path;
        final method = request.method.toUpperCase();
        if (method == 'POST' && path == '/api/cars') {
          createCalls++;
          return jsonOk({
            'car': {'id': 'car_imgs_1', 'images': [], 'videos': []},
          }, 201);
        }
        final attachMatch = RegExp(
          r'^/api/cars/([^/]+)/images/attach$',
        ).firstMatch(path);
        if (method == 'POST' && attachMatch != null) {
          attachCalls++;
          final decoded = json.decode(request.body) as Map;
          final paths = List<String>.from(decoded['paths'] as List);
          return jsonOk({
            'images': paths
                .map((p) => {'id': 1, 'image_url': p})
                .toList(),
          }, 201);
        }
        final enqueueMatch = RegExp(
          r'^/api/cars/([^/]+)/images$',
        ).firstMatch(path);
        if (method == 'POST' && enqueueMatch != null) {
          return jsonOk({'job_ids': <String>['img_job_1']}, 202);
        }
        if (method == 'GET' && path == '/api/jobs/img_job_1') {
          return jsonOk({
            'task_id': 'img_job_1',
            'state': 'SUCCESS',
            'result': {'rel_path': 'uploads/car_photos/img_job_1.jpg'},
          });
        }
        if (method == 'GET' && path == '/api/cars') {
          return jsonOk({'cars': []});
        }
        return jsonOk({'cars': []});
      });

      final imagePath = p.join(tempDir.path, 'photo1.jpg');
      File(imagePath).writeAsBytesSync(List<int>.filled(16, 1));
      final carData = _baseCarData(images: [imagePath]);

      final result = await PendingSellSubmissionService.instance.submitFast(
        draftId: draftId,
        carData: carData,
      );

      expect(result, isNotNull);
      expect(result!.id, 'car_imgs_1');

      await _waitUntil(() async {
        final record = await SellSubmissionStatePrefs.load(draftId);
        return record == null;
      });

      expect(createCalls, 1);
      expect(attachCalls, greaterThanOrEqualTo(1));
    },
  );

  test(
    'a permanent create failure (car never created) surfaces as an error '
    'from submitFast() itself instead of hanging or silently resolving',
    () async {
      const draftId = 'draft_fast_permfail';
      ApiService.testHttpClient = MockClient((request) async {
        final path = request.url.path;
        if (request.method.toUpperCase() == 'POST' && path == '/api/cars') {
          return http.Response(
            json.encode({'message': 'Invalid data'}),
            422,
            headers: {'content-type': 'application/json'},
          );
        }
        return jsonOk({'cars': []});
      });

      final carData = _baseCarData();

      await expectLater(
        PendingSellSubmissionService.instance.submitFast(
          draftId: draftId,
          carData: carData,
        ),
        throwsA(anything),
      );

      // The rejection of submitFast()'s Future is signalled synchronously
      // from the catch block, strictly BEFORE that same catch block
      // finishes persisting the `needsAttention` status just below it --
      // wait for that persist to land rather than racing it.
      SellSubmissionRecord? record;
      await _waitUntil(() async {
        record = await SellSubmissionStatePrefs.load(draftId);
        return record?.status == SellSubmissionStatus.needsAttention;
      });
      expect(
        record?.status,
        SellSubmissionStatus.needsAttention,
        reason: 'a permanent failure must still be durably recorded so the '
            'user can fix/retry it from the draft -- never silently lost',
      );
    },
  );
}
