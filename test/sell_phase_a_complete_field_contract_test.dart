// Media-readiness contract fix: `_phaseAAcceptedClientMediaIds` (used by
// `SellListingMediaUpload.uploadForCar`'s new-listing Phase-B exclusion,
// see `sell_new_listing_unblurred_upload_bytes_test.dart`) MUST derive
// "Phase A already owns this item" from the server-authoritative
// `items[].phase_a_complete` boolean (itself derived server-side from the
// write-once `phase_a_completed_at` timestamp -- see
// `kk/media_readiness.py`'s module docstring and
// `CarMediaItem.to_dict()`/`phase_a_completed_at` in `kk/models.py`), and
// NEVER from `items[].status`.
//
// `status` is NOT a reliable proxy: the backend's own contract explicitly
// says Phase-A completeness is tracked SEPARATELY from `status`. This file
// proves the six boundary cases the task spec calls out, each by directly
// exercising `SellListingMediaUpload.uploadForCar(isNewListing: true)` for
// a single new-listing photo and observing whether the image-enqueue
// endpoint (`POST /api/cars/<id>/images`) is called a second time:
//   - called again  => item was NOT recognized as Phase-A-owned (correct
//                       when `phase_a_complete` is not `true`, regardless
//                       of `status`).
//   - NOT called again => item WAS recognized as Phase-A-owned (correct
//                       only when `phase_a_complete == true`).
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
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String photoPath;
  late String clientMediaId;

  http.Response jsonOk(Map<String, dynamic> body, [int status = 200]) =>
      http.Response(
        json.encode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('phase_a_complete_field_');
    final docsDir = Directory('${tempDir.path}/docs')
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);
    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );

    photoPath = '${tempDir.path}/photo.jpg';
    File(photoPath).writeAsBytesSync(List<int>.filled(32, 7));
    // Same derivation `uploadForCar` itself uses (`ListingImageMedia.id`
    // is null for this plain-Map local item, so this is exactly the id
    // the fake server below must key its per-item response on).
    clientMediaId = SellMediaIdentity.forImageItem(
      {'source': photoPath},
      kind: 'listing',
    )!;
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

  /// Runs `uploadForCar(isNewListing: true)` for the single fixture photo,
  /// with `GET .../media-summary` reporting exactly one manifest item
  /// (`status: status`, and `phase_a_complete` set to [phaseAComplete] --
  /// or omitted entirely when [phaseAComplete] is null, modeling "the
  /// field is absent"). Returns how many times the image-enqueue endpoint
  /// was called.
  Future<int> runScenario({
    required String status,
    required bool? phaseAComplete,
  }) async {
    const carId = 'car_contract_1';
    var enqueueCalls = 0;

    ApiService.testHttpClient = MockClient((request) async {
      final method = request.method.toUpperCase();
      final path = request.url.path;

      if (method == 'GET' &&
          RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
        final item = <String, dynamic>{
          'client_media_id': clientMediaId,
          'status': status,
        };
        if (phaseAComplete != null) item['phase_a_complete'] = phaseAComplete;
        return jsonOk({
          'media_status': 'processing',
          'items': [item],
          'phase_a_complete': phaseAComplete ?? false,
        });
      }

      final enqueueMatch =
          RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
      if (method == 'POST' && enqueueMatch != null) {
        enqueueCalls++;
        return jsonOk({'job_ids': <String>['job_contract_1']}, 202);
      }
      if (method == 'GET' && path == '/api/jobs/job_contract_1') {
        return jsonOk({
          'task_id': 'job_contract_1',
          'state': 'SUCCESS',
          'result': {'rel_path': 'uploads/car_photos/job_contract_1.jpg'},
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
      // GET /api/cars/<id> (plain car map, used by the coarse
      // `_remoteImageCount` fallback) -- no images yet.
      if (method == 'GET' &&
          RegExp(r'^/api/cars/[^/]+$').hasMatch(path) &&
          !path.contains('media-summary')) {
        return jsonOk({
          'car': {'id': carId, 'images': [], 'videos': []},
        });
      }
      // Layout/primary-image/list-refresh -- irrelevant to this contract.
      return jsonOk({'cars': []});
    });

    final carData = <String, dynamic>{
      'images': [
        {'source': photoPath},
      ],
      'original_images': [
        {'source': photoPath},
      ],
      'videos': <dynamic>[],
      'damage_images': <dynamic>[],
      'use_blurred_plates': false,
    };

    await SellListingMediaUpload.uploadForCar(
      carId: carId,
      carData: carData,
      isNewListing: true,
    );

    return enqueueCalls;
  }

  group('phase_a_complete is the ONLY authoritative Phase-A predicate', () {
    test(
      '1. status=processing + phase_a_complete=false '
      '=> NOT considered Phase-A accepted (still re-driven)',
      () async {
        final calls = await runScenario(
          status: 'processing',
          phaseAComplete: false,
        );
        expect(
          calls,
          1,
          reason: '`processing` alone must never be treated as Phase-A '
              'complete -- only `phase_a_complete: true` may suppress '
              "Phase B's re-drive",
        );
      },
    );

    test(
      '2. status=processing + phase_a_complete=true '
      '=> considered accepted (never re-driven)',
      () async {
        final calls = await runScenario(
          status: 'processing',
          phaseAComplete: true,
        );
        expect(
          calls,
          0,
          reason: 'phase_a_complete=true must suppress the re-drive even '
              'while status is still the non-terminal `processing`',
        );
      },
    );

    test(
      '3. status=failed + phase_a_complete=true '
      '=> considered accepted (never re-driven)',
      () async {
        final calls = await runScenario(
          status: 'failed',
          phaseAComplete: true,
        );
        expect(
          calls,
          0,
          reason: 'a `failed` status must not override phase_a_complete: '
              'true -- the backend explicitly forbids inferring '
              'completion from status',
        );
      },
    );

    test(
      '4. status=attached + phase_a_complete=true '
      '=> considered accepted (never re-driven)',
      () async {
        final calls = await runScenario(
          status: 'attached',
          phaseAComplete: true,
        );
        expect(calls, 0);
      },
    );

    test(
      '5. status=awaiting_upload + phase_a_complete=false '
      '=> NOT accepted (still re-driven)',
      () async {
        final calls = await runScenario(
          status: 'awaiting_upload',
          phaseAComplete: false,
        );
        expect(calls, 1);
      },
    );

    test(
      '6. phase_a_complete field ABSENT entirely (e.g. an older server '
      'response shape) => must NOT fall back to status; a non-'
      "awaiting_upload status alone is NEVER enough to skip the re-drive",
      () async {
        final calls = await runScenario(
          status: 'processing',
          phaseAComplete: null,
        );
        expect(
          calls,
          1,
          reason: 'when `phase_a_complete` is absent, the predicate must '
              'default to "not accepted" -- it must never fall back to '
              'inferring completion from `status` (here `processing`, '
              'which is NOT `awaiting_upload` and would have been '
              'wrongly treated as accepted under the old, reverted '
              'status-based predicate)',
        );
      },
    );
  });
}
