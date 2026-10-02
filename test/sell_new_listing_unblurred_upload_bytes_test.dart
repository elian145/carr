// Real-device regression: brand-new listing, 2 local photos, single pick
// batch, user explicitly chooses UNBLURRED, submits -- and the FINAL
// attached image is still the BLURRED one.
//
// The previous investigation in this session proved, by static trace, that
// every layer of BOTH the backend (`skip_blur` threading, self-attach
// idempotency) and the Flutter service layer (`applySellPlateBlurChoice`,
// `SellMediaIdentity`, `SellListingMediaUpload`) is internally consistent
// for exactly this scenario. This file turns that trace into an executable
// proof by intercepting the REAL multipart HTTP request `uploadForCar`/
// `runPhaseAOnly` sends and reading the ACTUAL BYTES of the file each
// `images` multipart part carries -- not just the `skip_blur` query
// parameter, which the user correctly points out could be right while the
// wrong file is attached underneath it.
//
// Fixture design: `originalA`/`originalB` are real local files on disk
// whose CONTENT is the literal string `ORIGINAL_A` / `ORIGINAL_B`.
// `blurred_images` entries are, by construction of this app's own
// architecture (see `sell_car_page_plate_blur.dart`'s doc comment).
// This is why the "blurred" case
// asserts by REFERENCE (the exact rel_path/URL attached) rather than by
// re-reading bytes from a multipart upload that structurally never
// happens for that choice -- attaching the wrong reference would be just
// as real a bug as uploading the wrong bytes, and this test would catch
// either.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/features/sell/sell_flow.dart'
    show applySellPlateBlurChoice;
import 'package:car_listing_app/features/sell/sell_media_identity.dart';
import 'package:car_listing_app/services/api_service.dart';
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

/// One captured `POST /api/cars/<id>/images` (async enqueue) call: the
/// `skip_blur` query param actually sent, and the RAW CONTENT of every
/// `images` multipart part, in the exact order `http.MultipartRequest`
/// attached them -- i.e. exactly what a receiving server would decode as
/// each uploaded file's bytes.
class _ImageEnqueueCall {
  _ImageEnqueueCall({
    required this.skipBlur,
    required this.fileContents,
    required this.clientMediaIds,
  });
  final String? skipBlur;
  final List<String> fileContents;
  final List<String> clientMediaIds;
}

/// Extracts the raw byte content (decoded as latin1 -- lossless for the
/// ASCII fixture bytes this file uses, and never throws on arbitrary
/// bytes) of every multipart part named [fieldName], in attachment order.
/// [http.testing.MockClient] hands the callback a synthetic [http.Request]
/// with the FULLY ENCODED multipart/form-data body already collapsed into
/// `bodyBytes` (see `test/fake_api_server.dart`'s `_countMultipartParts`
/// for the same underlying technique, extended here to also recover each
/// part's CONTENT, not just its count).
List<String> _multipartFieldContents(http.Request request, String fieldName) {
  final contentType = request.headers['content-type'] ?? '';
  if (!contentType.contains('multipart/form-data')) return const [];
  final boundaryMatch = RegExp(r'boundary=([^\s;]+)').firstMatch(contentType);
  if (boundaryMatch == null) return const [];
  final boundary = boundaryMatch.group(1)!.replaceAll('"', '');
  final bodyText = latin1.decode(request.bodyBytes);
  final out = <String>[];
  for (final rawPart in bodyText.split('--$boundary')) {
    if (!rawPart.contains('name="$fieldName"')) continue;
    final headerEnd = rawPart.indexOf('\r\n\r\n');
    if (headerEnd == -1) continue;
    var content = rawPart.substring(headerEnd + 4);
    if (content.endsWith('\r\n')) {
      content = content.substring(0, content.length - 2);
    }
    out.add(content);
  }
  return out;
}

Map<String, dynamic> _baseCarData({required List<dynamic> images}) => {
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
  'images': images,
  'videos': <dynamic>[],
  'damage_images': <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String originalAPath;
  late String originalBPath;

  // ---- Fake server state, reset per test ---------------------------------
  late List<Map<String, dynamic>> createCarCalls;
  late Map<String, Map<String, dynamic>> carsById;
  late int carIdCounter;
  late int imageRowIdCounter;
  late int jobIdCounter;
  late List<_ImageEnqueueCall> imageEnqueueCalls;
  late List<List<String>> attachCallsLog;
  late Map<String, String> jobRelPathByJobId;
  // Architecture-fix support: mirrors the REAL backend's media-readiness
  // manifest (`kk/media_readiness.py`) closely enough to exercise
  // `uploadForCar`'s new "Phase A already owns this item" skip -- every
  // `client_media_id` Phase A's enqueue call sends is recorded here as
  // `processing` (exactly like `mark_item_phase_a_accepted` does
  // server-side), and `GET .../media-summary` reports it back. Without
  // this, the fake server's old hardcoded `items: []` response would make
  // every item look un-owned to Phase B, causing a spurious duplicate
  // enqueue that has nothing to do with the blur/bytes bug these tests
  // exist to prove fixed.
  late Map<String, String> manifestStatusByClientMediaId;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sell_unblurred_bytes_');
    final docsDir = Directory('${tempDir.path}/docs')
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);

    // Deliberately distinct byte content per fixture so a test can prove
    // WHICH file's bytes actually crossed the wire, not just that "a"
    // file of the right count was sent.
    originalAPath = '${tempDir.path}/originalA.jpg';
    originalBPath = '${tempDir.path}/originalB.jpg';
    File(originalAPath).writeAsStringSync('ORIGINAL_A');
    File(originalBPath).writeAsStringSync('ORIGINAL_B');

    createCarCalls = <Map<String, dynamic>>[];
    carsById = <String, Map<String, dynamic>>{};
    carIdCounter = 0;
    imageRowIdCounter = 0;
    jobIdCounter = 0;
    imageEnqueueCalls = <_ImageEnqueueCall>[];
    attachCallsLog = <List<String>>[];
    jobRelPathByJobId = <String, String>{};
    manifestStatusByClientMediaId = <String, String>{};

    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    debugSellSubmissionRetryBackoffOverride = (_) => Duration.zero;

    ApiService.testHttpClient = MockClient((request) async {
      final method = request.method.toUpperCase();
      final path = request.url.path;

      // ---- POST /api/cars (create) --------------------------------------
      if (method == 'POST' && path == '/api/cars') {
        Map<String, dynamic> body = <String, dynamic>{};
        try {
          if (request.body.isNotEmpty) {
            body = Map<String, dynamic>.from(json.decode(request.body) as Map);
          }
        } catch (_) {}
        createCarCalls.add({'body': body});
        carIdCounter++;
        final id = 'car_$carIdCounter';
        carsById[id] = {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]};
        return http.Response(
          json.encode({'car': carsById[id]}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- POST /api/cars/<id>/images (async enqueue) -------------------
      final enqueueMatch =
          RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
      if (method == 'POST' && enqueueMatch != null) {
        final fileContents = _multipartFieldContents(request, 'images');
        final clientMediaIds =
            _multipartFieldContents(request, 'client_media_id');
        imageEnqueueCalls.add(
          _ImageEnqueueCall(
            skipBlur: request.url.queryParameters['skip_blur'],
            fileContents: fileContents,
            clientMediaIds: clientMediaIds,
          ),
        );
        for (final id in clientMediaIds) {
          if (id.isNotEmpty) manifestStatusByClientMediaId[id] = 'processing';
        }
        final jobIds = <String>[];
        for (var i = 0; i < fileContents.length; i++) {
          jobIdCounter++;
          final jobId = 'job_$jobIdCounter';
          // The processed rel_path deliberately carries the SAME content
          // marker forward (e.g. "ORIGINAL_A" -> "processed_ORIGINAL_A")
          // purely so a test/log reader can see which upload produced
          // which job -- the actual assertions below never depend on
          // parsing this string, only on `fileContents` captured above.
          jobRelPathByJobId[jobId] =
              'uploads/car_photos/processed_${fileContents[i]}.jpg';
          jobIds.add(jobId);
        }
        return http.Response(
          json.encode({'job_ids': jobIds}),
          202,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- GET /api/jobs/<task_id> ---------------------------------------
      if (method == 'GET' && path.startsWith('/api/jobs/')) {
        final jobId = path.substring('/api/jobs/'.length);
        final relPath = jobRelPathByJobId[jobId] ?? 'uploads/car_photos/$jobId.jpg';
        return http.Response(
          json.encode({
            'task_id': jobId,
            'state': 'SUCCESS',
            'result': {'rel_path': relPath},
          }),
          200,
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
        attachCallsLog.add(paths);
        final car = carsById.putIfAbsent(
          id,
          () => {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]},
        );
        final rows = <Map<String, dynamic>>[];
        for (final p in paths) {
          imageRowIdCounter++;
          final row = {'id': imageRowIdCounter, 'image_url': p};
          rows.add(row);
          (car['images'] as List).add(row);
        }
        return http.Response(
          json.encode({'images': rows}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- GET /api/cars/<id>/media-summary ------------------------------
      final mediaSummaryMatch =
          RegExp(r'^/api/cars/([^/]+)/media-summary$').firstMatch(path);
      if (method == 'GET' && mediaSummaryMatch != null) {
        return http.Response(
          json.encode({
            'media_status': 'ready',
            'items': [
              // Mirrors the REAL backend's `CarMediaItem.to_dict()`
              // (`kk/models.py`): the per-item `phase_a_complete` boolean
              // is derived from the write-once `phase_a_completed_at`
              // timestamp, NOT `status` -- any status other than
              // `awaiting_upload` in this fake server's own bookkeeping
              // implies Phase A was durably accepted (see
              // `mark_item_phase_a_accepted` in `kk/media_readiness.py`),
              // so `phase_a_complete` tracks the SAME condition here, but
              // the app code under test must read `phase_a_complete`,
              // never `status` (see the regression tests in
              // `sell_phase_a_complete_field_contract_test.dart` for the
              // cases where they'd disagree).
              for (final entry in manifestStatusByClientMediaId.entries)
                {
                  'client_media_id': entry.key,
                  'status': entry.value,
                  'phase_a_complete': entry.value != 'awaiting_upload',
                },
            ],
            'phase_a_complete': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // ---- GET /api/cars/<id> ---------------------------------------------
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

      // ---- Everything else (layout PUT, primary-image, list refresh...) --
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

  /// Waits until this draft's durable record disappears (the exact
  /// signal `_runSubmission` uses for "fully done": see
  /// `SellSubmissionStatePrefs.remove` at the end of a successful run) --
  /// i.e. Phase B has finished, not just `submitFast`'s early Phase-A
  /// return. Fails the test on timeout rather than hanging forever.
  Future<void> waitForFullCompletion(String draftId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      final record = await SellSubmissionStatePrefs.load(draftId);
      if (record == null) return;
      if (record.status == SellSubmissionStatus.needsAttention) {
        fail(
          'Submission $draftId ended needsAttention: '
          '${record.lastErrorMessage}',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for submission $draftId to finish');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  group('new listing, 2 local photos, single batch -- byte-level proof', () {
    test(
      '1. UNBLURRED chosen: the actual multipart bytes enqueued are the '
      'ORIGINAL file contents, not any blurred variant',
      () async {
        const draftId = 'draft_unblurred_bytes';
        SharedPreferences.setMockInitialValues({});

        final carData = _baseCarData(
          images: [
            {'source': originalAPath},
            {'source': originalBPath},
          ],
        );
        // Simulate the preview-blur job having already run (as it always
        // does automatically on photo pick -- see
        // `sell_car_page_plate_blur.dart`) and produced remote blurred
        // outputs BEFORE the user made their choice.
        carData['original_images'] = List<dynamic>.from(carData['images']);
        carData['blurred_images'] = [
          {'source': 'uploads/blurred_a.jpg'},
          {'source': 'uploads/blurred_b.jpg'},
        ];
        // The user's explicit choice: UNBLURRED.
        applySellPlateBlurChoice(carData, false);

        expect(carData['use_blurred_plates'], isFalse);
        expect(
          (carData['images'] as List).map((e) => e['source']).toList(),
          [originalAPath, originalBPath],
          reason: 'sanity check: applySellPlateBlurChoice(false) must '
              'select the original local paths before submission even '
              'starts',
        );

        final result = await PendingSellSubmissionService.instance
            .submitFast(draftId: draftId, carData: carData);
        expect(result, isNotNull);
        await waitForFullCompletion(draftId);

        expect(
          imageEnqueueCalls,
          hasLength(1),
          reason: 'exactly one enqueue call for the 2-photo batch',
        );
        final call = imageEnqueueCalls.single;
        expect(
          call.skipBlur,
          '1',
          reason: 'skip_blur=1 must be sent for the unblurred choice',
        );
        expect(
          call.fileContents,
          ['ORIGINAL_A', 'ORIGINAL_B'],
          reason:
              'THE KEY ASSERTION: the actual bytes read off disk and sent '
              'in the multipart body must be the ORIGINAL file contents -- '
              'skip_blur=1 being correct is not enough on its own (this is '
              'exactly the failure mode the real-device bug report '
              'describes: skip_blur=1 sent correctly while the wrong file '
              'is uploaded underneath it).',
        );

        // The blurred remote references must never be attached for this
        // choice -- if they were, that would be an equally real instance
        // of this bug (attaching the wrong reference instead of uploading
        // the wrong bytes).
        for (final paths in attachCallsLog) {
          expect(
            paths,
            isNot(anyElement(anyOf(['uploads/blurred_a.jpg', 'uploads/blurred_b.jpg']))),
            reason: 'the blurred preview outputs must never be attached '
                'when the user chose unblurred',
          );
        }
      },
    );

    test(
      '2. BLURRED chosen: the ORIGINAL bytes are still uploaded (never the '
      'stale blurred-preview reference), with skip_blur=0 so the backend '
      'worker produces + self-attaches the blurred output itself -- the '
      'client never attaches the preview-only blurred_images reference',
      () async {
        // Architecture fix (real-device evidence: "chose UNBLURRED, final '
        // listing still shows blurred"): the OLD version of this test
        // asserted the very legacy behavior that caused the bug family --
        // attaching `carData['blurred_images']`'s stale PREVIEW reference
        // directly, bypassing skip_blur/Phase-A/the worker's self-attach
        // entirely. Final submission now ALWAYS transfers the original
        // bytes and lets the backend decide whether to blur them, per
        // `SellMediaIdentity.finalListingImages`/
        // `skipBlurForFinalSubmission`.
        const draftId = 'draft_blurred_bytes';
        SharedPreferences.setMockInitialValues({});

        final carData = _baseCarData(
          images: [
            {'source': originalAPath},
            {'source': originalBPath},
          ],
        );
        carData['original_images'] = List<dynamic>.from(carData['images']);
        carData['blurred_images'] = [
          {'source': 'uploads/blurred_a.jpg'},
          {'source': 'uploads/blurred_b.jpg'},
        ];
        // The user's explicit choice: BLURRED. `carData['images']` (the
        // PREVIEW list) still swaps to the blurred remote references --
        // that swap is intentionally irrelevant to final submission now.
        applySellPlateBlurChoice(carData, true);

        expect(carData['use_blurred_plates'], isTrue);
        expect(
          (carData['images'] as List).map((e) => e['source']).toList(),
          ['uploads/blurred_a.jpg', 'uploads/blurred_b.jpg'],
          reason: 'sanity check: applySellPlateBlurChoice(true) still '
              'swaps the PREVIEW list -- this must have no bearing on the '
              'final submission source asserted below',
        );

        final result = await PendingSellSubmissionService.instance
            .submitFast(draftId: draftId, carData: carData);
        expect(result, isNotNull);
        await waitForFullCompletion(draftId);

        expect(
          imageEnqueueCalls,
          hasLength(1),
          reason: 'exactly one enqueue call for the 2-photo batch -- Phase '
              'B must not redundantly re-enqueue what Phase A already '
              'durably accepted',
        );
        final call = imageEnqueueCalls.single;
        expect(
          call.skipBlur,
          isNull,
          reason: 'no skip_blur=1 query param must be sent for the blurred '
              'choice (see ApiService.uploadCarImages: the param is only '
              'ever added when skipBlur is true), so the backend worker '
              'actually produces + self-attaches a blurred output from '
              'these bytes',
        );
        expect(
          call.fileContents,
          ['ORIGINAL_A', 'ORIGINAL_B'],
          reason: 'THE KEY ASSERTION: choosing BLURRED must still upload '
              'the ORIGINAL bytes -- the stale client-side blurred_images '
              'preview reference must never be what gets submitted',
        );

        // The stale preview reference must never be attached by the
        // client for a new listing -- the backend worker owns the final
        // attach.
        expect(
          attachCallsLog,
          isEmpty,
          reason: 'the client must never attach the blurred_images preview '
              'reference (or anything else) for a new listing -- the '
              'backend worker self-attaches the processed result',
        );
      },
    );

    test(
      '3. Draft persisted + reloaded before submit, unblurred chosen: the '
      'DURABLE JSON-safe snapshot (what a killed-and-restarted process '
      'would actually resume from) still resolves to the original local '
      'paths, and a resume from exactly that snapshot uploads the '
      'ORIGINAL bytes',
      () async {
        const draftId = 'draft_unblurred_persist_reload';
        SharedPreferences.setMockInitialValues({});

        final carData = _baseCarData(
          images: [
            {'source': originalAPath},
            {'source': originalBPath},
          ],
        );
        carData['original_images'] = List<dynamic>.from(carData['images']);
        carData['blurred_images'] = [
          {'source': 'uploads/blurred_a.jpg'},
          {'source': 'uploads/blurred_b.jpg'},
        ];
        applySellPlateBlurChoice(carData, false);

        // `_prepareSubmissionRecord` (the first thing `submitFast`/
        // `submit` do, before any network call) runs `carData` through
        // exactly these two steps to build the record it persists --
        // reproduced directly here (no race against `submitFast`'s own
        // internals) so this test can assert on the DURABLE snapshot
        // itself, then round-trip it through JSON exactly like
        // `SellSubmissionStatePrefs` does on disk (proving the
        // serialize/deserialize cycle a real app-kill-and-restart goes
        // through never swaps in the blurred variant).
        final safeCarData = sellSubmissionJsonSafeCarData(carData);
        final roundTripped = Map<String, dynamic>.from(
          json.decode(json.encode(safeCarData)) as Map,
        );
        final persistedImages = roundTripped['images'] as List;
        expect(
          persistedImages.map((e) => e['source']).toList(),
          [originalAPath, originalBPath],
          reason: 'the durable, JSON-round-tripped snapshot must still '
              'reflect the unblurred (original-path) choice -- neither '
              'the JSON-safety conversion nor a disk round-trip may '
              'silently swap in the blurred variant',
        );

        final now = DateTime.now().millisecondsSinceEpoch;
        await SellSubmissionStatePrefs.upsert(
          SellSubmissionRecord(
            draftId: draftId,
            status: SellSubmissionStatus.pending,
            carData: roundTripped,
            idempotencyKey: 'sell-create-$draftId',
            createdAt: now,
            updatedAt: now,
          ),
        );

        final resumed =
            await PendingSellSubmissionService.instance.resumeAll();
        expect(resumed, isTrue);
        await waitForFullCompletion(draftId);

        expect(imageEnqueueCalls, hasLength(1));
        expect(
          imageEnqueueCalls.single.fileContents,
          ['ORIGINAL_A', 'ORIGINAL_B'],
          reason: 'a submission resumed from the persisted/reloaded '
              'snapshot must still upload the original bytes',
        );
      },
    );

    test(
      '4. Process-death simulation (record durably written, carId still '
      'null, before create_car/Phase A ever ran) then resumeAll(): still '
      'uploads the ORIGINAL bytes for the unblurred choice',
      () async {
        const draftId = 'draft_unblurred_resume_before_phase_a';
        SharedPreferences.setMockInitialValues({});

        final carData = _baseCarData(
          images: [
            {'source': originalAPath},
            {'source': originalBPath},
          ],
        );
        carData['original_images'] = List<dynamic>.from(carData['images']);
        carData['blurred_images'] = [
          {'source': 'uploads/blurred_a.jpg'},
          {'source': 'uploads/blurred_b.jpg'},
        ];
        applySellPlateBlurChoice(carData, false);

        final now = DateTime.now().millisecondsSinceEpoch;
        // Manually writes the durable record directly -- exactly what
        // would be on disk if the process were killed the instant after
        // Submit was pressed (`_prepareSubmissionRecord` already ran and
        // persisted) but before `create_car`/Phase A got a chance to run
        // (`carId` still null, `status: pending`).
        await SellSubmissionStatePrefs.upsert(
          SellSubmissionRecord(
            draftId: draftId,
            status: SellSubmissionStatus.pending,
            carData: carData,
            idempotencyKey: 'sell-create-$draftId',
            createdAt: now,
            updatedAt: now,
          ),
        );

        final resumed =
            await PendingSellSubmissionService.instance.resumeAll();
        expect(resumed, isTrue);
        await waitForFullCompletion(draftId);

        expect(createCarCalls, hasLength(1));
        expect(imageEnqueueCalls, hasLength(1));
        expect(
          imageEnqueueCalls.single.fileContents,
          ['ORIGINAL_A', 'ORIGINAL_B'],
          reason: 'a resume from a pre-create-mode crash must still '
              'upload the ORIGINAL bytes for the unblurred choice -- the '
              'kill/resume path must never silently switch to the '
              'blurred variant',
        );
        expect(
          imageEnqueueCalls.single.skipBlur,
          '1',
          reason: 'skip_blur=1 must still be sent on this resumed run',
        );
      },
    );

    test(
      '5. expected_media/client_media_id mapping: the ids declared in '
      'create_car\'s expected_media match the ids actually sent with each '
      'photo\'s upload, and both are derived from the ORIGINAL local path '
      '(never the blurred remote path) when unblurred is chosen',
      () async {
        const draftId = 'draft_unblurred_identity';
        SharedPreferences.setMockInitialValues({});

        final carData = _baseCarData(
          images: [
            {'source': originalAPath},
            {'source': originalBPath},
          ],
        );
        carData['original_images'] = List<dynamic>.from(carData['images']);
        carData['blurred_images'] = [
          {'source': 'uploads/blurred_a.jpg'},
          {'source': 'uploads/blurred_b.jpg'},
        ];
        applySellPlateBlurChoice(carData, false);

        // `client_media_id` is derived from each item's `source` AFTER
        // `SellDraftMediaPersistence.prepareCarDataForStorage` has copied
        // it to its final durable path (see `SellMediaIdentity`'s doc
        // comment) -- reproducing that step directly here (rather than
        // hand-computing an id from the pre-copy tempDir path) is what
        // makes this test's expected ids match what the real submission
        // pipeline actually computes, instead of a stale/pre-copy path.
        //
        // Architecture fix: ids are now derived from `original_images`
        // (see `SellMediaIdentity.finalListingImages`), NOT the preview
        // `images` list -- `prepareCarDataForStorage` durably copies each
        // logical photo to TWO distinct destination filenames (one for
        // `images`, one for `original_images`), so asserting against the
        // wrong list's copy would compare against a path the real
        // pipeline never actually uploads.
        final durableCarData = await SellDraftMediaPersistence
            .prepareCarDataForStorage(carData, draftId: draftId);
        final durableImages = durableCarData['original_images'] as List;
        final expectedIdA = SellMediaIdentity.forImageItem(
          durableImages[0],
          kind: 'listing',
        );
        final expectedIdB = SellMediaIdentity.forImageItem(
          durableImages[1],
          kind: 'listing',
        );
        expect(expectedIdA, isNotNull);
        expect(expectedIdB, isNotNull);
        expect(
          expectedIdA,
          isNot(equals(expectedIdB)),
          reason: 'two distinct source photos must never collide onto '
              'the same client_media_id',
        );

        // Submitting the ALREADY-durable carData makes `submitFast`'s own
        // (idempotent, no-op-on-already-durable-paths) internal
        // `prepareCarDataForStorage` call resolve to the exact same
        // paths/ids computed above, so this test asserts on the SAME
        // identity the real pipeline uses end-to-end, not a re-derived
        // approximation of it.
        final result = await PendingSellSubmissionService.instance
            .submitFast(draftId: draftId, carData: durableCarData);
        expect(result, isNotNull);
        await waitForFullCompletion(draftId);

        expect(createCarCalls, hasLength(1));
        final expectedMedia =
            createCarCalls.single['body']['expected_media'] as List;
        final declaredIds =
            expectedMedia.map((e) => e['client_media_id']).toSet();
        expect(
          declaredIds,
          {expectedIdA, expectedIdB},
          reason: 'expected_media must declare exactly the ids derived '
              'from the ORIGINAL (unblurred) local paths',
        );

        expect(imageEnqueueCalls, hasLength(1));
        final sentIds = imageEnqueueCalls.single.clientMediaIds.toSet();
        expect(
          sentIds,
          declaredIds,
          reason: 'the client_media_id sent with the actual upload must '
              'match exactly what create_car declared in expected_media '
              '-- no drift between the two independent computations',
        );
      },
    );
  });
}
