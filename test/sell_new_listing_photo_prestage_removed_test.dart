// Media-readiness contract follow-up: `SellPhotoPrestage` (the pre-create
// "upload now, poll to full backend processing, rewrite `carData` to a
// remote URL" step) used to run INSIDE
// `PendingSellSubmissionService._runSubmission`, awaited, BEFORE
// `create_car()` for every new-listing submission -- so the seller waited
// on full backend image processing before the listing even existed,
// directly violating the Phase-A contract (`create_car()` -> Phase A ->
// `submitFast()` resolves, all without ever waiting on image
// resize/blur/processing completion).
//
// These tests prove, for NEW LISTING creation specifically:
//   1. `create_car()` fires immediately -- it does not wait on (or even
//      call) the pre-create prestage/processing endpoint at all.
//   2. `submitFast()` still resolves promptly even while that endpoint
//      (mocked to hang forever) is never touched.
//   3. The seller's local image path is preserved (never rewritten to an
//      empty/remote placeholder) through `create_car()` and while Phase A
//      is in flight, so local preview keeps working the whole time.
//   4. Edit-mode submissions are UNCHANGED -- this fix is create-mode
//      only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/listings/listing_image_media.dart';
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

Map<String, dynamic> _baseCarData({
  List<dynamic>? images,
  List<dynamic>? videos,
  bool isEdit = false,
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
  if (isEdit) 'is_edit': true,
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
    tempDir = Directory.systemTemp.createTempSync('no_prestage_');
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
    'new-listing submitFast() calls create_car immediately and NEVER '
    'calls the pre-create photo-processing endpoint '
    '(/api/process-car-images) at all -- not even once, and not even '
    'after create_car succeeds -- proving the blocking prestage step was '
    'fully removed from the new-listing path, not merely made async',
    () async {
      const draftId = 'no_prestage_new_listing';
      final imagePath = p.join(tempDir.path, 'photo1.jpg');
      File(imagePath).writeAsBytesSync(List<int>.filled(16, 1));

      var createCarCalls = 0;
      var processCarImagesCalls = 0;
      var phaseAEnqueueCalls = 0;
      final processCarImagesGate = Completer<void>();

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;

        if (method == 'POST' && path == '/api/cars') {
          createCarCalls++;
          return jsonOk({
            'car': {'id': 'car_no_prestage_1', 'images': [], 'videos': []},
          }, 201);
        }
        if (path == '/api/process-car-images') {
          // Never resolves within this test's lifetime. If new-listing
          // submission still called this endpoint and awaited it (the
          // pre-fix behavior), `submitFast()` below would hang forever
          // and this test would time out.
          processCarImagesCalls++;
          await processCarImagesGate.future;
          return jsonOk({'job_ids': <String>['never_used']}, 202);
        }
        final enqueueMatch =
            RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
        if (method == 'POST' && enqueueMatch != null) {
          phaseAEnqueueCalls++;
          return jsonOk({'job_ids': <String>['job_photo1']}, 202);
        }
        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
          return jsonOk({
            'media_status': 'processing',
            'items': <dynamic>[],
            'phase_a_complete': true,
          });
        }
        if (method == 'GET' && path.startsWith('/api/jobs/')) {
          // Phase B's own processing poll -- never resolves either, but
          // `submitFast()` must not be waiting on this.
          return jsonOk({'task_id': 'job_photo1', 'state': 'PENDING'});
        }
        return jsonOk({'cars': []});
      });

      final carData = _baseCarData(images: [imagePath]);
      final result = await PendingSellSubmissionService.instance.submitFast(
        draftId: draftId,
        carData: carData,
      );

      expect(result, isNotNull);
      expect(result!.id, 'car_no_prestage_1');
      expect(
        createCarCalls,
        1,
        reason: 'create_car must run exactly once, immediately',
      );
      expect(
        processCarImagesCalls,
        0,
        reason: 'the pre-create prestage/processing endpoint must never '
            'be called at all for a new-listing submission',
      );
      expect(
        phaseAEnqueueCalls,
        greaterThanOrEqualTo(1),
        reason: 'the still-local photo must instead go through Phase A '
            '(POST /api/cars/<id>/images?async=1) AFTER create_car',
      );
    },
  );

  test(
    'the seller\'s local image path survives create_car and the Phase-A '
    'window unchanged -- the durably-persisted record still resolves the '
    'exact same local file for preview while remote processing is still '
    'pending (image job poll gated forever)',
    () async {
      const draftId = 'no_prestage_preview';
      final imagePath = p.join(tempDir.path, 'preview.jpg');
      File(imagePath).writeAsBytesSync(List<int>.filled(16, 2));

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        if (method == 'POST' && path == '/api/cars') {
          return jsonOk({
            'car': {'id': 'car_preview_1', 'images': [], 'videos': []},
          }, 201);
        }
        final enqueueMatch =
            RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
        if (method == 'POST' && enqueueMatch != null) {
          return jsonOk({'job_ids': <String>['job_preview']}, 202);
        }
        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
          return jsonOk({
            'media_status': 'processing',
            'items': <dynamic>[],
            'phase_a_complete': true,
          });
        }
        if (method == 'GET' && path.startsWith('/api/jobs/')) {
          // Processing never finishes within this test -- the local
          // preview must still be resolvable regardless.
          return jsonOk({'task_id': 'job_preview', 'state': 'PENDING'});
        }
        return jsonOk({'cars': []});
      });

      final carData = _baseCarData(images: [imagePath]);
      final result = await PendingSellSubmissionService.instance.submitFast(
        draftId: draftId,
        carData: carData,
      );
      expect(result, isNotNull);

      final record = await SellSubmissionStatePrefs.load(draftId);
      expect(record, isNotNull);
      final persistedImages = record!.carData['images'];
      expect(persistedImages, isA<List>());
      expect((persistedImages as List), isNotEmpty);

      // The persisted entry must still resolve to a REAL local file (the
      // durable copy `SellDraftMediaPersistence` made), never an empty/
      // remote placeholder -- that local file is exactly what Sell media
      // step / Review & Submit / the optimistic My Listings card render
      // for preview while Phase B is still pending.
      final local = ListingImageMedia.localFile(persistedImages.first);
      expect(
        local,
        isNotNull,
        reason: 'a resolvable local file must remain available for '
            'immediate seller-side preview even though remote image '
            'processing has not completed',
      );
      expect(File(local!.path).existsSync(), isTrue);
    },
  );

  test(
    'edit-mode submissions are unaffected by this fix -- an edit never '
    'calls create_car, and its still-local photo continues to upload via '
    'the SAME pre-existing async enqueue+poll+attach mechanism as before, '
    'never through the new-listing Phase-A gate',
    () async {
      const draftId = 'no_prestage_edit_unaffected';
      const editId = 'car_being_edited';
      final imagePath = p.join(tempDir.path, 'edit_photo.jpg');
      File(imagePath).writeAsBytesSync(List<int>.filled(16, 3));

      var createCarCalls = 0;
      var enqueueCalls = 0;
      var jobPollCalls = 0;

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        if (method == 'POST' && path == '/api/cars') {
          createCarCalls++;
          return jsonOk({
            'car': {'id': 'should_not_happen', 'images': [], 'videos': []},
          }, 201);
        }
        if ((method == 'PUT' || method == 'PATCH') &&
            path == '/api/cars/$editId') {
          return jsonOk({
            'car': {'id': editId, 'images': [], 'videos': []},
          });
        }
        if (method == 'GET' && path == '/api/cars/$editId') {
          return jsonOk({
            'car': {'id': editId, 'images': [], 'videos': []},
          });
        }
        final attachMatch =
            RegExp(r'^/api/cars/([^/]+)/images/attach$').firstMatch(path);
        if (method == 'POST' && attachMatch != null) {
          return jsonOk({
            'images': [
              {'id': 1, 'image_url': imagePath},
            ],
          }, 201);
        }
        // Edit mode's own (pre-existing, unrelated to Phase A) local-image
        // upload path -- a still-local image goes through the SAME async
        // enqueue-then-poll-then-attach mechanism `uploadForCar`'s Phase B
        // step always used for edit mode, unaffected by this fix (edit
        // mode never runs `runPhaseAOnly` at all -- see `!record.isEdit`
        // in `_runSubmission`).
        final enqueueMatch =
            RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
        if (method == 'POST' && enqueueMatch != null) {
          enqueueCalls++;
          return jsonOk({'job_ids': <String>['job_edit_photo']}, 202);
        }
        if (method == 'GET' && path == '/api/jobs/job_edit_photo') {
          jobPollCalls++;
          return jsonOk({
            'task_id': 'job_edit_photo',
            'state': 'SUCCESS',
            'result': {'rel_path': 'uploads/car_photos/job_edit_photo.jpg'},
          });
        }
        return jsonOk({'cars': []});
      });

      final carData = _baseCarData(images: [imagePath]);
      final result = await PendingSellSubmissionService.instance.submit(
        draftId: draftId,
        carData: carData,
        editListingId: editId,
      );

      expect(result, isNotNull);
      expect(result!.id, editId);
      expect(createCarCalls, 0, reason: 'an edit must never call create_car');
      expect(
        enqueueCalls,
        1,
        reason: 'the edit\'s still-local photo must still upload via the '
            'pre-existing async mechanism, unaffected by this fix',
      );
      expect(jobPollCalls, greaterThanOrEqualTo(1));
    },
  );
}
