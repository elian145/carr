// Data-integrity regression tests for the Sell submission lifecycle.
//
// Real-device (TestFlight) bugs these pin down:
//   BUG 1: pressing Submit on a listing WITH photos finished immediately and
//          the listing appeared with ZERO images.
//   BUG 2: backgrounding the app mid-submission and reopening made the
//          listing disappear from the UI.
//
// Root causes (see the final report):
//   * the durable-copy step silently DROPPED any photo it could not copy
//     (tombstoned draft folder, cold documents path, missing file) and the
//     shortened list REPLACED the user's selection -> `expected_media` was
//     empty -> the server published the car `active` with media "ready" ->
//     the client saw "nothing to upload" and marked it COMPLETED;
//   * both draft entry points hid the draft whenever ANY submission record
//     existed while My Listings rendered no entry for a record at all.
//
// Every test here uses controlled async completion (Completers) -- no sleeps
// that race real work -- against a fake server that models the real
// `CarMediaItem` manifest and `Idempotency-Key` replay. No real network, no
// real uploads.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/features/sell/sell_media_identity.dart';
import 'package:car_listing_app/features/sell/sell_submission_visibility.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/prefs/owner_optimistic_media_prefs.dart';
import 'package:car_listing_app/shared/prefs/sell_draft_media_persistence.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_media_summary.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Future<void> _waitUntil(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  String what = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (await condition()) return;
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Map<String, dynamic> _carData(List<String> images, {List<String>? videos}) => {
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
  'videos': videos ?? <String>[],
  'damage_images': <String>[],
};

/// Fake backend: create_car (+ Idempotency-Key replay), image enqueue, jobs,
/// media-summary (real manifest semantics) and the car read.
class _FakeServer {
  final manifest = FakeMediaManifest();
  final createBodies = <Map<String, dynamic>>[];
  final enqueueCarIds = <String>[];
  final cars = <String, Map<String, dynamic>>{};
  final _carByIdemKey = <String, String>{};
  int _carCounter = 0;
  int _jobCounter = 0;

  /// While non-null, `POST /api/cars/<id>/images` waits on it.
  Completer<void>? enqueueGate;

  /// While non-null, `POST /api/cars/<id>/images` fails with this status.
  int? enqueueFailStatus;

  /// The next N `POST /api/cars/<id>/images` calls fail with 503 (a socket
  /// the OS killed while the app was backgrounded), then succeed.
  int enqueueFailCountdown = 0;

  /// The next N media-summary reads report every item as not accepted yet.
  int summaryNotReadyCountdown = 0;

  /// When set, a create call returns this EXISTING car (idempotent replay of
  /// a car created earlier with NO declared media) instead of a new one.
  String? replayCarId;

  /// First create is applied server-side but its response is "lost".
  bool dropNextCreateResponse = false;

  /// This many idempotent REPLAYS of an already-created key lose their
  /// response too (transport error), so the client stays without a carId.
  int lostReplayResponses = 0;

  /// When set, a create call is definitively refused with this status
  /// (nothing is stored, no key is remembered).
  int? createFailStatus;

  /// `client_media_id`s the server really received an upload for, per car
  /// (parsed from the multipart body, like the real endpoint reads them).
  final uploadedIds = <String, List<String>>{};

  /// Invoked with (carId, expected_media ids) right after a car is created.
  void Function(String carId, List<String> ids)? onCreated;

  int get carCount => cars.length;

  List<String> expectedIdsOf(Map<String, dynamic> body) => [
    for (final e in (body['expected_media'] as List? ?? const []))
      (e as Map)['client_media_id'].toString(),
  ];

  http.Response _json(Object body, int status) => http.Response(
    json.encode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> handle(http.Request request) async {
    final method = request.method.toUpperCase();
    final path = request.url.path;

    if (method == 'POST' && path == '/api/cars') {
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(json.decode(request.body) as Map);
      createBodies.add(body);
      String? key;
      request.headers.forEach((k, v) {
        if (k.toLowerCase() == 'idempotency-key') key = v;
      });
      final refuse = createFailStatus;
      if (refuse != null) {
        return _json({'message': 'Validation failed'}, refuse);
      }
      final replay = replayCarId;
      if (replay != null) {
        cars.putIfAbsent(
          replay,
          () => {'id': replay, 'images': [], 'videos': []},
        );
        manifest.clear(replay);
        return _json({'car': cars[replay]}, 200);
      }
      if (key != null && _carByIdemKey.containsKey(key)) {
        // Real server: stored response is replayed, nothing re-registered.
        if (lostReplayResponses > 0) {
          lostReplayResponses--;
          throw const SocketException('connection lost on replay');
        }
        return _json({'car': cars[_carByIdemKey[key]]}, 200);
      }
      _carCounter++;
      final id = 'car_$_carCounter';
      cars[id] = {'id': id, 'images': <dynamic>[], 'videos': <dynamic>[]};
      if (key != null) _carByIdemKey[key!] = id;
      manifest.registerCreate(id, body);
      onCreated?.call(id, expectedIdsOf(body));
      if (dropNextCreateResponse) {
        dropNextCreateResponse = false;
        throw const SocketException('connection lost after server commit');
      }
      return _json({'car': cars[id]}, 201);
    }

    final enqueue = RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
    if (method == 'POST' && enqueue != null) {
      final carId = enqueue.group(1)!;
      enqueueCarIds.add(carId);
      final gate = enqueueGate;
      if (gate != null) await gate.future;
      if (enqueueFailCountdown > 0) {
        enqueueFailCountdown--;
        return _json({'message': 'injected transient failure'}, 503);
      }
      final fail = enqueueFailStatus;
      if (fail != null) return _json({'message': 'injected failure'}, fail);
      manifest.noteUpload(carId, 'image');
      final bodyText = latin1.decode(request.bodyBytes);
      uploadedIds.putIfAbsent(carId, () => <String>[]).addAll([
        for (final m in RegExp(
          r'name="client_media_id"\r\n\r\n([^\r\n]*)\r\n',
        ).allMatches(bodyText))
          m.group(1)!,
      ]);
      final count = RegExp('name="images"').allMatches(bodyText).length;
      return _json({
        'job_ids': [for (var i = 0; i < count; i++) 'job_${++_jobCounter}'],
      }, 202);
    }

    if (method == 'GET' && path.startsWith('/api/jobs/')) {
      final jobId = path.substring('/api/jobs/'.length);
      return _json({
        'task_id': jobId,
        'state': 'SUCCESS',
        'result': {'rel_path': 'uploads/car_photos/$jobId.jpg'},
      }, 200);
    }

    final summary = RegExp(
      r'^/api/cars/([^/]+)/media-summary$',
    ).firstMatch(path);
    if (method == 'GET' && summary != null) {
      final s = await manifest.summary(summary.group(1)!);
      if (summaryNotReadyCountdown > 0) {
        // The server has not (yet) accepted any item: what Phase A sees
        // right after the app comes back from the background.
        summaryNotReadyCountdown--;
        for (final item in (s['items'] as List)) {
          (item as Map<String, dynamic>)['phase_a_complete'] = false;
          item['status'] = 'awaiting_upload';
        }
        s['phase_a_complete'] = false;
      }
      return _json(s, 200);
    }

    final getCar = RegExp(r'^/api/cars/([^/]+)$').firstMatch(path);
    if (method == 'GET' && getCar != null) {
      final id = getCar.group(1)!;
      return _json({
        'car': cars[id] ?? {'id': id, 'images': [], 'videos': []},
      }, 200);
    }

    return _json({'cars': <dynamic>[]}, 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeServer server;
  final svc = PendingSellSubmissionService.instance;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sell_integrity_');
    final docs = Directory('${tempDir.path}/docs')..createSync(recursive: true);
    PathProviderPlatform.instance = _FakeDocsPathProvider(docs.path);
    SellDraftMediaPersistence.debugBeforeCopyOverride = null;
    SellDraftMediaPersistence.debugResetMediaLifecycleForTest();
    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    debugSellSubmissionRetryBackoffOverride = (_) => Duration.zero;
    server = _FakeServer();
    ApiService.testHttpClient = MockClient(server.handle);
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
    await AuthService().adoptTestSession(user: {'id': 'sell_test_owner'});
  });

  tearDown(() async {
    SellDraftMediaPersistence.debugBeforeCopyOverride = null;
    SellDraftMediaPersistence.debugResetMediaLifecycleForTest();
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    ApiService.testHttpClient = null;
    setRuntimeApiBaseOverride(null);
    TokenStore.testMode = false;
    TokenStore.resetForTests();
    debugSellSubmissionRetryBackoffOverride = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // `seed` keeps the CONTENT of different batches distinct (the durable
  // layer deduplicates byte-identical photos).
  List<String> makePhotos(int n, {String prefix = 'p', int seed = 0}) => [
    for (var i = 0; i < n; i++)
      (File('${tempDir.path}/${prefix}_$i.jpg')
            ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, i + 1 + seed, 7, 7, 7]))
          .path,
  ];

  /// Starts a submit and returns its future with errors captured, so a test
  /// can drive the controlled gates before awaiting the outcome.
  Future<Object?> startSubmit(String draftId, List<String> images) => svc
      .submit(draftId: draftId, carData: _carData(images))
      .then<Object?>((_) => null, onError: (Object e) => e);

  List<String> durablePathsOf(SellSubmissionRecord r) => [
    for (final raw in (r.carData['images'] as List? ?? const []))
      if (raw is String)
        raw
      else if (raw is Map)
        (raw['source'] ?? '').toString(),
  ];

  // ---------------------------------------------------------------------------
  // Scenario 1: create succeeds, upload has not started yet.
  // ---------------------------------------------------------------------------
  test(
    '1. create_car succeeded but the upload has not been accepted: the '
    'listing is NOT complete, its record + durable photos remain, it has a '
    'visible pending entry, and submitFast does not report "ready"',
    () async {
      const draftId = 'int_1';
      server.enqueueGate = Completer<void>();
      final photos = makePhotos(2);

      var fastResolved = false;
      final fast = svc
          .submitFast(draftId: draftId, carData: _carData(photos))
          .then((_) => fastResolved = true, onError: (Object _) => false);

      await _waitUntil(
        () => server.enqueueCarIds.isNotEmpty,
        what: 'enqueue request reached the gated server',
      );

      // create_car already succeeded and declared BOTH photos up front.
      expect(server.createBodies, hasLength(1));
      expect(server.createBodies.single['expected_media'], hasLength(2));
      expect(server.createBodies.single['media_required_count'], 2);

      final rec = await svc.peek(draftId);
      expect(rec, isNotNull, reason: 'record must survive until verified');
      expect(rec!.status, isNot(SellSubmissionStatus.completed));
      expect(rec.carId, 'car_1');
      expect(rec.expectedMedia, hasLength(2));
      expect(sellSubmissionShowsPendingEntry(rec), isTrue);
      for (final path in durablePathsOf(rec)) {
        expect(File(path).existsSync(), isTrue, reason: 'durable photo kept');
      }

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        fastResolved,
        isFalse,
        reason: 'Phase A (upload accepted) has not happened: not ready',
      );

      server.enqueueGate!.complete();
      expect(await fast, isTrue);
      await _waitUntil(
        () async => await svc.peek(draftId) == null,
        what: 'submission verified and cleaned up',
      );
      expect(server.carCount, 1);
    },
  );

  // ---------------------------------------------------------------------------
  // Scenario 2: create succeeds, photo upload fails.
  // ---------------------------------------------------------------------------
  test('2. create_car succeeded then the photo upload fails: never completed, '
      'record keeps carId + frozen manifest + durable photos, and a later '
      'resume finishes it WITHOUT a second car', () async {
    const draftId = 'int_2';
    server.enqueueFailStatus = 503;
    final photos = makePhotos(2);

    final failure = await startSubmit(draftId, photos);
    expect(failure, isNotNull, reason: 'the failure must surface');

    final rec = await svc.peek(draftId);
    expect(rec, isNotNull);
    expect(rec!.status, SellSubmissionStatus.retryable);
    expect(rec.carId, 'car_1');
    expect(rec.expectedMedia, hasLength(2));
    expect(sellSubmissionShowsPendingEntry(rec), isTrue);
    for (final path in durablePathsOf(rec)) {
      expect(File(path).existsSync(), isTrue);
    }

    server.enqueueFailStatus = null;
    expect(await svc.resumeAll(), isTrue);
    expect(await svc.peek(draftId), isNull);
    expect(server.createBodies, hasLength(1), reason: 'no duplicate create');
    expect(server.carCount, 1);
  });

  // ---------------------------------------------------------------------------
  // Scenario 3: only 1 of 3 photos is accepted by the server.
  // ---------------------------------------------------------------------------
  test('3. only 1 of 3 photos is accepted: the submission is NOT completed '
      '(retryable, record kept); once the server accepts the rest a resume '
      'completes it', () async {
    const draftId = 'int_3';
    server.onCreated = (carId, ids) {
      server.manifest.setPhaseAComplete(ids[1], false);
      server.manifest.setPhaseAComplete(ids[2], false);
    };
    final photos = makePhotos(3);

    final failure = await startSubmit(draftId, photos);
    expect(failure, isNotNull, reason: 'incomplete must never look done');

    final rec = await svc.peek(draftId);
    expect(rec, isNotNull, reason: 'must not be cleaned up while incomplete');
    expect(
      rec!.status,
      anyOf(
        SellSubmissionStatus.retryable,
        SellSubmissionStatus.needsAttention,
      ),
      reason: 'recoverable, never completed',
    );
    expect(rec.carId, 'car_1');
    expect(rec.expectedMedia, hasLength(3));
    expect(sellSubmissionShowsPendingEntry(rec), isTrue);

    for (final id in server.expectedIdsOf(server.createBodies.single)) {
      server.manifest.setPhaseAComplete(id, true);
    }
    // The user taps Retry on the pending entry (or auto-retry fires).
    expect(await svc.retryNow(draftId), isTrue);
    await _waitUntil(
      () async => await svc.peek(draftId) == null,
      what: 'retry completes once the server confirms all 3',
    );
    expect(server.createBodies, hasLength(1), reason: 'no second car');
  });

  // ---------------------------------------------------------------------------
  // Scenario 4: expected media unexpectedly empty.
  // ---------------------------------------------------------------------------
  test('4. the user selected photos but the payload would declare none: the '
      'create call is NEVER made and the submission needs attention '
      '(previously: a zero-image listing was published)', () async {
    const draftId = 'int_4';
    final now = DateTime.now().millisecondsSinceEpoch;
    await SellSubmissionStatePrefs.upsert(
      SellSubmissionRecord(
        draftId: draftId,
        status: SellSubmissionStatus.pending,
        carData: _carData(const []), // selection lost
        ownerUserId: 'sell_test_owner',
        idempotencyKey: 'sell-create-$draftId',
        requiredMediaCount: 3, // ...but the user did pick 3
        createdAt: now,
        updatedAt: now,
      ),
    );

    await svc.resumeAll();

    expect(server.createBodies, isEmpty, reason: 'must not create it');
    final rec = await svc.peek(draftId);
    expect(rec, isNotNull);
    expect(rec!.status, SellSubmissionStatus.needsAttention);
    expect(rec.lastErrorMessage, contains('missing'));
    expect(sellSubmissionShowsPendingEntry(rec), isTrue);
  });

  // ---------------------------------------------------------------------------
  // Scenario 5: background during photo preparation.
  // ---------------------------------------------------------------------------
  test('5. app backgrounded/foregrounded (resumeAll) while photos are still '
      'being prepared: no second worker starts, no duplicate create, and the '
      'full manifest is declared once preparation finishes', () async {
    const draftId = 'int_5';
    final prepGate = Completer<void>();
    SellDraftMediaPersistence.debugBeforeCopyOverride = (_) => prepGate.future;
    final photos = makePhotos(2);

    final outcome = startSubmit(draftId, photos);
    await _waitUntil(
      () async => svc.isPreparing(draftId) && await svc.peek(draftId) != null,
      what: 'durable-copy preparation in flight with the intent persisted',
    );

    // The intent record is already durable and visible...
    final during = await svc.peek(draftId);
    expect(during, isNotNull);
    expect(sellSubmissionShowsPendingEntry(during!), isTrue);

    // ...and lifecycle "resumed" events fire repeatedly mid-copy.
    for (var i = 0; i < 5; i++) {
      await svc.resumeAll();
    }
    expect(server.createBodies, isEmpty, reason: 'no worker mid-prepare');

    prepGate.complete();
    expect(await outcome, isNull);
    expect(server.createBodies, hasLength(1));
    expect(server.createBodies.single['expected_media'], hasLength(2));
    expect(server.carCount, 1);
    expect(await svc.peek(draftId), isNull);
  });

  // ---------------------------------------------------------------------------
  // Scenario 6: background during media upload.
  // ---------------------------------------------------------------------------
  test('6. app backgrounded while the media upload is in flight: the resume '
      'trigger joins/ignores the live run (no restart, no cancel, no second '
      'upload) and the submission still completes', () async {
    const draftId = 'int_6';
    server.enqueueGate = Completer<void>();
    final photos = makePhotos(2);

    final outcome = startSubmit(draftId, photos);
    await _waitUntil(() => server.enqueueCarIds.isNotEmpty, what: 'upload');

    // `resumeAll()` joins a live run (it resolves when that run does), so
    // it must NOT be awaited while the upload is still gated.
    final resumes = [for (var i = 0; i < 4; i++) svc.resumeAll()];
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(server.createBodies, hasLength(1));
    expect(
      server.enqueueCarIds,
      hasLength(1),
      reason: 'the in-flight upload must not be restarted',
    );
    expect(await svc.peek(draftId), isNotNull);

    server.enqueueGate!.complete();
    expect(await outcome, isNull);
    await Future.wait(resumes);
    expect(server.createBodies, hasLength(1));
    expect(server.enqueueCarIds, hasLength(1));
    expect(await svc.peek(draftId), isNull);
    expect(server.carCount, 1);
  });

  // ---------------------------------------------------------------------------
  // Scenario 7: app killed right after create_car succeeds.
  // ---------------------------------------------------------------------------
  test('7. the process died right after create_car succeeded (record has the '
      'carId + frozen manifest, nothing uploaded): the next resume uploads '
      'only the media, never re-creates the listing, and completes', () async {
    const draftId = 'int_7';
    final photos = makePhotos(2);
    final carData = _carData(photos);
    final expected = SellMediaIdentity.buildExpectedMedia(carData);
    expect(expected, hasLength(2));
    server.cars['car_k'] = {'id': 'car_k', 'images': [], 'videos': []};
    server.manifest.registerCreate('car_k', {'expected_media': expected});

    final now = DateTime.now().millisecondsSinceEpoch;
    await SellSubmissionStatePrefs.upsert(
      SellSubmissionRecord(
        draftId: draftId,
        status: SellSubmissionStatus.inProgress,
        carId: 'car_k',
        carData: carData,
        ownerUserId: 'sell_test_owner',
        idempotencyKey: 'sell-create-$draftId',
        requiredMediaCount: 2,
        expectedMedia: expected,
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(await svc.resumeAll(), isTrue);
    expect(server.createBodies, isEmpty, reason: 'never re-create');
    expect(server.enqueueCarIds, isNotEmpty);
    expect(await svc.peek(draftId), isNull);
  });

  // ---------------------------------------------------------------------------
  // Scenario 8: cold restart with pending submissions of every state.
  // ---------------------------------------------------------------------------
  test('8. cold restart with durable submissions in every non-completed state: '
      'each one is represented by a visible pending entry (never absent), and '
      'only a completed/edit/foreign-account record is not', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    SellSubmissionRecord rec(
      String id,
      SellSubmissionStatus status, {
      bool isEdit = false,
      String? owner,
      String? carId,
    }) => SellSubmissionRecord(
      draftId: id,
      status: status,
      isEdit: isEdit,
      carId: carId,
      ownerUserId: owner ?? 'me',
      carData: _carData(const []),
      idempotencyKey: 'sell-create-$id',
      createdAt: now,
      updatedAt: now,
    );

    final all = [
      rec('s_pending', SellSubmissionStatus.pending),
      rec('s_progress', SellSubmissionStatus.inProgress, carId: 'c1'),
      rec('s_retry', SellSubmissionStatus.retryable),
      rec('s_attention', SellSubmissionStatus.needsAttention),
      rec('s_done', SellSubmissionStatus.completed),
      rec('s_edit', SellSubmissionStatus.pending, isEdit: true),
      rec('s_foreign', SellSubmissionStatus.pending, owner: 'other_user'),
    ];
    for (final r in all) {
      await SellSubmissionStatePrefs.upsert(r);
    }

    final loaded = await SellSubmissionStatePrefs.loadAll();
    final entries = sellSubmissionPendingEntries(
      loaded,
      currentOwnerId: 'me',
    ).map((r) => r.draftId).toSet();
    expect(entries, {'s_pending', 's_progress', 's_retry', 's_attention'});

    // A draft may only be hidden when its record shows as an entry (never
    // hide without a visible replacement)...
    for (final r in loaded) {
      if (sellSubmissionHidesDraft(r, currentOwnerId: 'me')) {
        expect(
          entries,
          contains(r.draftId),
          reason: '${r.draftId}: never hide a draft without a replacement',
        );
      }
    }
    // ...and a needsAttention record without a listing keeps its draft
    // visible so the user can fix (e.g. replace) what blocks it.
    final attention = loaded.firstWhere((r) => r.draftId == 's_attention');
    expect(sellSubmissionHidesDraft(attention, currentOwnerId: 'me'), isFalse);

    // A listing already present on the server is represented by its real
    // card, not duplicated by a pending entry.
    expect(
      sellSubmissionPendingEntries(
        loaded,
        currentOwnerId: 'me',
        serverListingIds: {'c1'},
      ).map((r) => r.draftId),
      isNot(contains('s_progress')),
    );
  });

  // ---------------------------------------------------------------------------
  // Scenario 9: idempotency replay returns an existing car without images.
  // ---------------------------------------------------------------------------
  test('9. an idempotent create_car replay returns an EXISTING car whose '
      'manifest does not contain this submission\'s media: the client must '
      'NOT mark it complete and keeps its record and photos', () async {
    const draftId = 'int_9';
    server.replayCarId = 'car_old_without_images';
    final photos = makePhotos(2);

    final failure = await startSubmit(draftId, photos);

    expect(failure, isA<SellMediaIntegrityException>());
    expect(
      (failure as SellMediaIntegrityException).message,
      contains('not confirmed'),
    );
    final rec = await svc.peek(draftId);
    expect(rec, isNotNull, reason: 'never cleaned up on a false success');
    expect(rec!.status, SellSubmissionStatus.needsAttention);
    expect(rec.carId, 'car_old_without_images');
    expect(sellSubmissionShowsPendingEntry(rec), isTrue);
    for (final path in durablePathsOf(rec)) {
      expect(File(path).existsSync(), isTrue, reason: 'photos retained');
    }
  });

  // ---------------------------------------------------------------------------
  // Scenario 10: profile/auth not loaded during recovery.
  // ---------------------------------------------------------------------------
  test('10. recovery while the profile has not loaded: the owned submission is '
      'deferred (never deleted, never run under the wrong identity), stays '
      'visible, and completes once the same account is known', () async {
    const draftId = 'int_10';
    final now = DateTime.now().millisecondsSinceEpoch;
    await SellSubmissionStatePrefs.upsert(
      SellSubmissionRecord(
        draftId: draftId,
        status: SellSubmissionStatus.pending,
        carData: _carData(makePhotos(1)),
        idempotencyKey: 'sell-create-$draftId',
        requiredMediaCount: 1,
        ownerUserId: 'user_10',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await AuthService().logout();
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );

    expect(await svc.resumeAll(), isFalse);
    expect(server.createBodies, isEmpty);
    final deferred = await svc.peek(draftId);
    expect(deferred, isNotNull, reason: 'deferral never deletes');
    expect(
      sellSubmissionShowsPendingEntry(deferred!, currentOwnerId: ''),
      isTrue,
      reason: 'still visible while the profile is unknown',
    );

    await AuthService().adoptTestSession(user: {'id': 'user_10'});
    expect(await svc.resumeAll(), isTrue);
    expect(await svc.peek(draftId), isNull);
    expect(server.createBodies, hasLength(1));
    await AuthService().logout();
  });

  test('10b. an OWNERLESS legacy record is quarantined: never stamped with, '
      'shown to or run under whichever account signs in', () async {
    const draftId = 'int_10b';
    await AuthService().adoptTestSession(user: {'id': 'user_10b'});
    final now = DateTime.now().millisecondsSinceEpoch;
    await SellSubmissionStatePrefs.upsert(
      SellSubmissionRecord(
        draftId: draftId,
        status: SellSubmissionStatus.pending,
        carData: _carData(makePhotos(1)),
        idempotencyKey: 'sell-create-$draftId',
        requiredMediaCount: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await svc.resumeAll();

    expect(server.createBodies, isEmpty, reason: 'must never run');
    final rec = await svc.peek(draftId);
    expect(rec, isNotNull, reason: 'quarantine never deletes');
    expect(rec!.ownerUserId, isNull, reason: 'must never be adopted');
    expect(sellSubmissionShowsPendingEntry(rec, currentOwnerId: 'user_10b'),
        isFalse);
    await AuthService().logout();
  });

  // ---------------------------------------------------------------------------
  // Scenario 11: pending submission coexists with a local draft (widget level
  // coverage in test/my_listings_pending_submission_entry_test.dart); here the
  // underlying never-hide-without-replacement contract plus data safety.
  // ---------------------------------------------------------------------------
  test('11. a pending submission and an unrelated local draft coexist: the '
      'unrelated draft stays visible, the superseded one is replaced by an '
      'entry, and nothing is deleted', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final submitted = SellSubmissionRecord(
      draftId: 'draft_submitted',
      status: SellSubmissionStatus.needsAttention,
      carData: _carData(const []),
      ownerUserId: 'sell_test_owner',
      idempotencyKey: 'sell-create-draft_submitted',
      createdAt: now,
      updatedAt: now,
    );
    await SellSubmissionStatePrefs.upsert(submitted);

    // The entry is shown; the draft stays visible next to it because it is
    // the user's way to replace unavailable photos (never hidden unless a
    // visible replacement exists AND nothing is left for the user to fix).
    expect(sellSubmissionShowsPendingEntry(submitted), isTrue);
    expect(sellSubmissionHidesDraft(submitted), isFalse);
    expect(
      sellSubmissionHidesDraft(
        submitted.copyWith(status: SellSubmissionStatus.retryable),
      ),
      isTrue,
      reason: 'an in-flight submission supersedes its draft',
    );
    expect(
      sellSubmissionHidesDraft(submitted.copyWith(carId: 'car_9')),
      isTrue,
      reason: 'once the listing exists the draft was consumed',
    );
    final other = await svc.peek('draft_unrelated');
    expect(other, isNull, reason: 'no record -> its draft is not hidden');
    // The record itself is untouched by reading/visibility checks.
    expect(await svc.peek('draft_submitted'), isNotNull);
  });

  // ---------------------------------------------------------------------------
  // Scenario 12: photos temporarily unreadable.
  // ---------------------------------------------------------------------------
  test('12a. a selected photo is unreadable at Submit: the create call is NOT '
      'made, the user\'s FULL selection is kept in a recoverable record, and '
      'once the photo is readable again a retry creates the listing with ALL '
      'photos declared', () async {
    const draftId = 'int_12a';
    final photos = makePhotos(2);
    final hidden = File('${tempDir.path}/hidden_copy.jpg');
    File(photos[1]).copySync(hidden.path);
    File(photos[1]).deleteSync(); // temporarily unreadable

    final failure = await startSubmit(draftId, photos);
    expect(failure, isA<SellMediaIntegrityException>());

    expect(server.createBodies, isEmpty, reason: 'never create short');
    final rec = await svc.peek(draftId);
    expect(rec, isNotNull);
    expect(rec!.status, SellSubmissionStatus.needsAttention);
    expect(rec.requiredMediaCount, 2);
    expect(
      (rec.carData['images'] as List),
      hasLength(2),
      reason: 'the selection must not be replaced by a shortened list',
    );
    expect(sellSubmissionShowsPendingEntry(rec), isTrue);

    hidden.copySync(photos[1]); // readable again
    expect(await svc.retryNow(draftId), isTrue);
    await _waitUntil(
      () async => await svc.peek(draftId) == null,
      what: 'retry completes',
    );
    expect(server.createBodies, hasLength(1));
    expect(server.createBodies.single['expected_media'], hasLength(2));
  });

  test('12b. REPRO of the instant zero-image listing: the draft folder was '
      'discarded earlier in the process (tombstoned) and the user then submits '
      'photos. It used to declare expected_media=[] and "succeed"; now every '
      'selected photo is declared and uploaded', () async {
    const draftId = 'int_12b';
    await SellDraftMediaPersistence.deleteLocalDraftFolder(draftId);
    final photos = makePhotos(3);

    final failure = await startSubmit(draftId, photos);

    expect(failure, isNull);
    expect(server.createBodies, hasLength(1));
    expect(
      server.createBodies.single['expected_media'],
      hasLength(3),
      reason: 'previously []: the car was published with zero images',
    );
    expect(server.enqueueCarIds, isNotEmpty, reason: 'photos were uploaded');
    expect(await svc.peek(draftId), isNull);
  });

  // ---------------------------------------------------------------------------
  // Scenario 13: rapid repeated lifecycle resume calls.
  // ---------------------------------------------------------------------------
  test(
    '13. rapid repeated lifecycle resume calls during a live submission '
    'never start a second worker, a second create, or a second upload',
    () async {
      const draftId = 'int_13';
      server.enqueueGate = Completer<void>();
      final outcome = startSubmit(draftId, makePhotos(2));
      await _waitUntil(() => server.enqueueCarIds.isNotEmpty, what: 'upload');

      final resumes = <Future<bool>>[];
      for (var round = 0; round < 5; round++) {
        resumes.addAll([for (var i = 0; i < 10; i++) svc.resumeAll()]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(server.createBodies, hasLength(1));
      expect(server.enqueueCarIds, hasLength(1));

      server.enqueueGate!.complete();
      expect(await outcome, isNull);
      await Future.wait(resumes);
      await svc.resumeAll(); // after completion: nothing left to do
      expect(server.createBodies, hasLength(1));
      expect(server.carCount, 1);
    },
  );

  // ---------------------------------------------------------------------------
  // Scenario 14: completes only after every expected image is verified.
  // ---------------------------------------------------------------------------
  test('14. COMPLETED (record + durable photos released) happens only after '
      'the server confirms EVERY expected image', () async {
    const draftId = 'int_14';
    List<String> ids = const [];
    server.onCreated = (carId, created) {
      ids = created;
      for (final id in created) {
        server.manifest.setPhaseAComplete(id, false);
      }
    };
    final photos = makePhotos(3);
    final outcome = startSubmit(draftId, photos);

    await _waitUntil(() => server.enqueueCarIds.isNotEmpty, what: 'upload');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(ids, hasLength(3));
    final stillThere = await svc.peek(draftId);
    expect(
      stillThere,
      isNotNull,
      reason: 'server has not confirmed any image: must not be completed',
    );
    expect(stillThere!.status, isNot(SellSubmissionStatus.completed));

    // The server now confirms all three.
    for (final id in ids) {
      server.manifest.setPhaseAComplete(id, true);
    }
    expect(await outcome, isNull);
    expect(await svc.peek(draftId), isNull);
    expect(server.carCount, 1);
  });

  // ---------------------------------------------------------------------------
  // Mapping preservation / idempotency.
  // ---------------------------------------------------------------------------
  test('H/I. create succeeded server-side but its response was lost: the '
      'resume replays the SAME idempotency key with the SAME frozen '
      'client_media_ids, producing ONE car and completing', () async {
    const draftId = 'int_hi';
    server.dropNextCreateResponse = true;
    final photos = makePhotos(2);

    // The transport layer may replay the create inside this very call, or
    // surface the error and leave a resumable record; both must converge
    // on exactly one car with an identical manifest.
    await startSubmit(draftId, photos);
    final afterFirst = await svc.peek(draftId);
    if (afterFirst != null) {
      expect(afterFirst.expectedMedia, hasLength(2), reason: 'frozen pre-send');
      expect(await svc.resumeAll(), isTrue);
    }

    expect(server.createBodies, hasLength(2), reason: 'replayed once');
    expect(
      server.expectedIdsOf(server.createBodies[1]),
      server.expectedIdsOf(server.createBodies[0]),
      reason: 'identical manifest on replay',
    );
    expect(server.carCount, 1, reason: 'idempotent: one car');
    expect(await svc.peek(draftId), isNull);
  });

  // ---------------------------------------------------------------------------
  // NEEDS_ATTENTION retry: replacing missing photos must not change the
  // manifest bound to the (reused) create idempotency key.
  // ---------------------------------------------------------------------------

  /// create_car is committed server-side but the client never learns the
  /// carId (the response AND the in-call replay are lost): the record is left
  /// with a frozen 3-photo manifest and no carId. Returns that record.
  Future<SellSubmissionRecord> strandAfterLostCreate(
    String draftId,
    List<String> photos,
  ) async {
    server.dropNextCreateResponse = true;
    server.lostReplayResponses = 1;
    final failure = await startSubmit(draftId, photos);
    expect(failure, isNotNull, reason: 'the transport failure must surface');
    final rec = (await svc.peek(draftId))!;
    expect(rec.carId ?? '', isEmpty, reason: 'the client never saw the carId');
    expect(rec.expectedMedia, hasLength(photos.length), reason: 'frozen');
    expect(server.carCount, 1, reason: 'the server DID commit the create');
    expect(sellSubmissionShowsPendingEntry(rec), isTrue);
    return rec;
  }

  List<String> idsOf(List<Map<String, String>> manifest) => [
    for (final e in manifest) e['client_media_id']!,
  ];

  Future<void> replaceMissingPhotoAndFinish({
    required bool keptAsDurable,
  }) async {
    const draftId = 'int_replace';
    final photos = makePhotos(3);
    final stranded = await strandAfterLostCreate(draftId, photos);
    final frozenIds = idsOf(stranded.expectedMedia!);
    final durable = durablePathsOf(stranded);

    // One selected photo becomes unreadable before the next attempt.
    File(durable[2]).deleteSync();
    expect(await svc.retryNow(draftId), isTrue);
    await _waitUntil(
      () async =>
          (await svc.peek(draftId))?.status ==
          SellSubmissionStatus.needsAttention,
      what: 'retry fails closed on the missing photo',
    );
    final blocked = (await svc.peek(draftId))!;
    expect(blocked.lastErrorMessage, contains('no longer available'));
    expect(
      blocked.expectedMedia,
      stranded.expectedMedia,
      reason: 'still frozen',
    );
    expect(sellSubmissionShowsPendingEntry(blocked), isTrue);
    expect(
      sellSubmissionHidesDraft(blocked),
      isFalse,
      reason: 'the draft must stay available so the photo can be replaced',
    );
    final bodiesBeforeReplace = server.createBodies.length;

    // The user replaces the missing photo and submits again.
    final replacement = makePhotos(1, prefix: 'replacement', seed: 50).single;
    final selection = keptAsDurable
        ? [durable[0], durable[1], replacement]
        : [photos[0], photos[1], replacement];
    final outcome = await startSubmit(draftId, selection);
    expect(outcome, isNull, reason: 'the retry must finish the submission');

    // Idempotency was NOT bypassed: the same key replayed the same car with
    // the very same manifest; no second listing exists.
    expect(server.carCount, 1, reason: 'no duplicate server listing');
    expect(server.createBodies.length, bodiesBeforeReplace + 1);
    expect(
      server.expectedIdsOf(server.createBodies.last),
      frozenIds,
      reason: 'the replay must declare the frozen manifest, never a new one',
    );
    // Mapping preserved: every frozen id -- including the slot of the
    // replaced photo -- received exactly one upload under ITS id.
    final uploaded = server.uploadedIds['car_1'] ?? const <String>[];
    expect(uploaded.toSet(), frozenIds.toSet());
    expect(
      uploaded,
      hasLength(frozenIds.length),
      reason: 'no id uploaded twice',
    );
    // Completion is server-verified, and only then is the record released.
    expect(await svc.peek(draftId), isNull);
  }

  test(
    'R1. a created-but-unacknowledged listing loses a photo; after the user '
    'replaces it (re-picking the other photos) Retry finishes with ONE car, '
    'the frozen manifest and the replacement bound to the replaced slot',
    () => replaceMissingPhotoAndFinish(keptAsDurable: false),
  );

  test(
    'R2. same as R1 but the wizard resubmits the already-durable photos',
    () => replaceMissingPhotoAndFinish(keptAsDurable: true),
  );

  test(
    'R3. changing the NUMBER of photos while the create may have committed '
    'is rejected before any network call (idempotency is not bypassed); the '
    'listing stays recoverable and finishes once the count matches again',
    () async {
      const draftId = 'int_count';
      final photos = makePhotos(3);
      final stranded = await strandAfterLostCreate(draftId, photos);
      final bodiesBefore = server.createBodies.length;

      final tooMany = await startSubmit(
        draftId,
        makePhotos(4, prefix: 'many', seed: 100),
      );
      expect(tooMany, isA<SellMediaIntegrityException>());
      final tooFew = await startSubmit(
        draftId,
        makePhotos(2, prefix: 'few', seed: 110),
      );
      expect(tooFew, isA<SellMediaIntegrityException>());

      expect(
        server.createBodies.length,
        bodiesBefore,
        reason: 'rejected before the network: no create with another manifest',
      );
      final rec = (await svc.peek(draftId))!;
      expect(rec.status, SellSubmissionStatus.needsAttention);
      expect(rec.expectedMedia, stranded.expectedMedia, reason: 'unchanged');
      expect(sellSubmissionShowsPendingEntry(rec), isTrue);
      expect(server.carCount, 1);

      final ok = await startSubmit(draftId, makePhotos(3, prefix: 'ok'));
      expect(ok, isNull);
      expect(server.carCount, 1);
      expect(
        server.expectedIdsOf(server.createBodies.last),
        idsOf(stranded.expectedMedia!),
      );
      expect(
        (server.uploadedIds['car_1'] ?? const <String>[]).toSet(),
        idsOf(stranded.expectedMedia!).toSet(),
      );
      expect(await svc.peek(draftId), isNull);
    },
  );

  test('R4. when the server DEFINITIVELY refuses the create (4xx) nothing is '
      'bound to the idempotency key, so the media may change freely and the '
      'retry declares the new manifest', () async {
    const draftId = 'int_4xx';
    server.createFailStatus = 400;
    final failure = await startSubmit(draftId, makePhotos(3));
    expect(failure, isNotNull);
    final rec = (await svc.peek(draftId))!;
    expect(rec.status, SellSubmissionStatus.needsAttention);
    expect(rec.expectedMedia, isNull, reason: 'un-frozen after a 4xx');
    expect(server.carCount, 0);

    server.createFailStatus = null;
    final outcome = await startSubmit(
      draftId,
      makePhotos(4, prefix: 'more', seed: 120),
    );
    expect(outcome, isNull);
    expect(server.carCount, 1);
    expect(server.expectedIdsOf(server.createBodies.last), hasLength(4));
    expect(
      (server.uploadedIds['car_1'] ?? const <String>[]).toSet(),
      server.expectedIdsOf(server.createBodies.last).toSet(),
    );
    expect(await svc.peek(draftId), isNull);
  });

  test(
    'R5. success means the server owns and has accepted every photo, NOT '
    'that processing is finished: while the images are still processing the '
    'owner keeps the local photos plus an optimistic record (the '
    '"Processing media" state), so the listing never shows missing photos',
    () async {
      const draftId = 'int_r5';
      // Accepted (phase_a_complete) but not attached/visible yet.
      server.onCreated = (carId, created) {
        for (final id in created) {
          server.manifest.setItemStatus(id, 'processing');
        }
      };
      final outcome = await startSubmit(draftId, makePhotos(2));
      expect(outcome, isNull);
      expect(await svc.peek(draftId), isNull);

      final optimistic = await OwnerOptimisticMediaPrefs.load('car_1');
      expect(
        optimistic,
        isNotNull,
        reason: 'local media must stay available while the server processes',
      );
      final draftDir = Directory(
        '${tempDir.path}/docs/sell_draft_media/$draftId',
      );
      expect(draftDir.existsSync(), isTrue, reason: 'durable photos kept');
      expect(draftDir.listSync().whereType<File>(), hasLength(2));
    },
  );

  // ---------------------------------------------------------------------------
  // "False upload failure after backgrounding" (Galaxy A17).
  // The listing exists and its images are uploaded, yet the Submit page showed
  // the red "created, but we couldn't finish uploading it" banner.
  // ---------------------------------------------------------------------------
  group('false upload failure after backgrounding', () {
    late List<SellSubmissionEvent> events;
    late StreamSubscription<SellSubmissionEvent> eventSub;

    setUp(() {
      events = <SellSubmissionEvent>[];
      eventSub = svc.events.listen(events.add);
    });

    tearDown(() async {
      await eventSub.cancel();
    });

    test(
      'BG1. a transient "not accepted yet" read while backgrounded is NOT '
      'rejected to the Submit caller as a failure: the same run finishes, '
      'success is '
      'reported only after verification, one car, no failure event',
      () async {
        const draftId = 'bg_1';
        // Phase A's verification reads see "not accepted yet" (transient),
        // exactly what a freshly foregrounded app observes.
        server.summaryNotReadyCountdown = 6;
        final photos = makePhotos(2);

        final result = await svc.submitFast(
          draftId: draftId,
          carData: _carData(photos),
        );
        expect(
          result,
          isNotNull,
          reason: 'transient hiccup must not look like a failed submission',
        );
        expect(result!.id, 'car_1');

        await _waitUntil(
          () async => await svc.peek(draftId) == null,
          what: 'verified completion + record cleanup',
        );
        expect(server.carCount, 1);
        expect(server.createBodies, hasLength(1));
        expect(
          events.where((e) => !e.success && e.needsAttention),
          isEmpty,
          reason: 'no "needs attention" event for a submission that succeeded',
        );
        expect(events.any((e) => e.success && e.carId == 'car_1'), isTrue);
        // Server really owns every frozen id (success is server-verified).
        final ids = server.expectedIdsOf(server.createBodies.single);
        expect(server.uploadedIds['car_1']?.toSet(), ids.toSet());
      },
    );

    test(
      'BG1b. Phase A itself fails on the transport (dropped connection after '
      'backgrounding): recorded as RETRYABLE with the real cause (never a '
      'permanent needs-attention), visible, no failure event, and the next '
      'resume completes it with ONE car',
      () async {
        const draftId = 'bg_1b';
        server.enqueueFailCountdown = 3;
        final failure = await startSubmit(draftId, makePhotos(2));
        expect(failure, isNotNull);
        expect(isRetryableSellSubmissionError(failure!), isTrue);

        final rec = await svc.peek(draftId);
        expect(rec, isNotNull);
        expect(rec!.status, SellSubmissionStatus.retryable);
        expect(sellSubmissionShowsPendingEntry(rec), isTrue);
        expect(events.where((e) => e.needsAttention), isEmpty);
        expect(
          (await svc.outcomeFor(draftId)).kind,
          SellSubmissionOutcomeKind.recovering,
        );

        expect(await svc.resumeAll(), isTrue);
        expect(await svc.peek(draftId), isNull);
        expect(server.carCount, 1);
        expect(server.createBodies, hasLength(1));
        expect(events.where((e) => e.needsAttention), isEmpty);
      },
    );

    test(
      'BG2. every attempt fails transiently (still backgrounded): the Submit '
      'caller sees a RETRYABLE failure, the service reports "recovering" '
      '(not needs-attention, not completed), nothing is cleaned up, and the '
      'later resume completes it with ONE car',
      () async {
        const draftId = 'bg_2';
        server.enqueueFailStatus = 503;
        final failure = await startSubmit(draftId, makePhotos(2));
        expect(failure, isNotNull);
        expect(isRetryableSellSubmissionError(failure!), isTrue);

        final outcome = await svc.outcomeFor(draftId);
        expect(
          outcome.kind,
          SellSubmissionOutcomeKind.recovering,
          reason: 'the UI must not show a permanent failure while retrying',
        );
        final rec = await svc.peek(draftId);
        expect(rec, isNotNull);
        expect(rec!.status, SellSubmissionStatus.retryable);
        expect(events.where((e) => e.success), isEmpty);
        expect(
          events.where((e) => e.needsAttention),
          isEmpty,
          reason: 'retryable is informational only',
        );

        server.enqueueFailStatus = null;
        expect(await svc.resumeAll(), isTrue);
        expect(await svc.peek(draftId), isNull);
        expect(server.carCount, 1);
        expect(server.createBodies, hasLength(1));

        final done = await svc.outcomeFor(draftId);
        expect(done.kind, SellSubmissionOutcomeKind.completed);
        expect(done.result?.id, 'car_1');
      },
    );

    test(
      'BG3. a verified-complete submission is reported as completed, so a '
      'late/stale failure delivered to a waiter can never be shown as a '
      'failure',
      () async {
        const draftId = 'bg_3';
        expect(await startSubmit(draftId, makePhotos(2)), isNull);
        await _waitUntil(
          () async => await svc.peek(draftId) == null,
          what: 'completion',
        );
        final done = await svc.outcomeFor(draftId);
        expect(done.kind, SellSubmissionOutcomeKind.completed);
        expect(done.result?.id, 'car_1');
      },
    );

    test(
      'BG4. genuine failures are preserved: a permanent upload failure is '
      'needs-attention (visible pending entry, record + photos kept, event '
      'emitted) and is NOT silently auto-resumed; a refused create has no '
      'listing at all',
      () async {
        const draftId = 'bg_4';
        server.enqueueFailStatus = 403;
        final failure = await startSubmit(draftId, makePhotos(2));
        expect(failure, isNotNull);
        expect(isRetryableSellSubmissionError(failure!), isFalse);

        final outcome = await svc.outcomeFor(draftId);
        expect(outcome.kind, SellSubmissionOutcomeKind.needsAttention);
        final rec = await svc.peek(draftId);
        expect(rec, isNotNull);
        expect(rec!.status, SellSubmissionStatus.needsAttention);
        expect(sellSubmissionShowsPendingEntry(rec), isTrue);
        for (final path in durablePathsOf(rec)) {
          expect(File(path).existsSync(), isTrue);
        }
        expect(
          events.any((e) => e.needsAttention && e.carId == 'car_1'),
          isTrue,
          reason: 'a real failure must still be announced',
        );

        final before = server.enqueueCarIds.length;
        await svc.resumeAll();
        expect(
          server.enqueueCarIds.length,
          before,
          reason: 'needsAttention is never auto-retried',
        );

        // No listing was created: plain failure, nothing to recover.
        server.createFailStatus = 422;
        final refused = await startSubmit('bg_4b', makePhotos(1, seed: 90));
        expect(refused, isNotNull);
        expect(
          (await svc.outcomeFor('bg_4b')).kind,
          SellSubmissionOutcomeKind.none,
        );
      },
    );

    test(
      'BG5. duplicate resume triggers (lifecycle resumed + connectivity + '
      'auth-changed firing together) never start two workers: one car, no '
      'duplicate create, no media id uploaded twice',
      () async {
        const draftId = 'bg_5';
        server.enqueueFailStatus = 503;
        expect(await startSubmit(draftId, makePhotos(2)), isNotNull);
        server.enqueueFailStatus = null;
        server.enqueueGate = Completer<void>();
        server.uploadedIds.clear();

        final resumes = Future.wait([
          svc.resumeAll(),
          svc.resumeAll(),
          svc.resumeAll(),
          svc.retryNow(draftId),
        ]);
        await _waitUntil(
          () => server.enqueueCarIds.isNotEmpty,
          what: 'a worker reached the gated server',
        );
        // Give any (wrongly started) second worker time to show up.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        server.enqueueGate!.complete();
        await resumes;

        expect(await svc.peek(draftId), isNull);
        expect(server.carCount, 1);
        expect(server.createBodies, hasLength(1));
        final uploaded = server.uploadedIds['car_1'] ?? const <String>[];
        expect(
          uploaded.toSet().length,
          uploaded.length,
          reason: 'no media id may be uploaded twice: $uploaded',
        );
        expect(
          uploaded.toSet(),
          server.expectedIdsOf(server.createBodies.single).toSet(),
        );
        expect(
          events.where((e) => e.success && e.carId == 'car_1'),
          hasLength(1),
          reason: 'exactly one success notification',
        );
        expect(events.where((e) => e.needsAttention), isEmpty);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Cover photo selection (real-device bug: the starred photo was ignored and
  // the cover was whichever photo the backend happened to finish first).
  // The cover/order are declared on the create-time `expected_media`
  // manifest, so they are server-owned from the moment the listing exists.
  // ---------------------------------------------------------------------------
  group('cover photo selection', () {
    Map<String, dynamic> withCover(List<String> photos, int? primary) => {
      ..._carData(photos),
      if (primary != null) 'primary_image_index': primary,
    };

    List<Map<String, dynamic>> manifestOf(Map<String, dynamic> body) => [
      for (final e in (body['expected_media'] as List)) Map<String, dynamic>.from(e as Map),
    ];

    List<int> coverIdx(List<Map<String, dynamic>> m) => [
      for (var i = 0; i < m.length; i++)
        if (m[i]['is_cover'] == true) i,
    ];

    test('4. submit: the starred photo 3 of 5 is declared as the cover '
        '(exactly one), in cover-first order, and every photo is uploaded',
        () async {
      const draftId = 'cov_submit';
      final photos = makePhotos(5);
      final err = await svc
          .submit(draftId: draftId, carData: withCover(photos, 2))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(err, isNull);
      expect(server.createBodies, hasLength(1));
      final m = manifestOf(server.createBodies.single);
      expect(m, hasLength(5));
      expect(coverIdx(m), [2], reason: 'only the starred photo is the cover');
      expect([for (final e in m) e['sort_order']], [1, 2, 0, 3, 4]);
      // Nothing duplicated or lost: every declared id was uploaded once.
      final uploaded = server.uploadedIds['car_1'] ?? const <String>[];
      expect(uploaded.toSet(), server.expectedIdsOf(server.createBodies.single).toSet());
      expect(uploaded.toSet().length, uploaded.length);
    });

    test('4b. submit without ever starring: the first photo is the declared '
        'cover (so completion order can never decide it)', () async {
      const draftId = 'cov_default';
      final photos = makePhotos(3);
      await svc.submit(draftId: draftId, carData: withCover(photos, null));
      final m = manifestOf(server.createBodies.single);
      expect(coverIdx(m), [0]);
      expect([for (final e in m) e['sort_order']], [0, 1, 2]);
    });

    test('5. uploads/processing finish in any order: the client never makes '
        'a completion-order-dependent cover call for a new listing', () async {
      const draftId = 'cov_no_client_primary';
      final requests = <String>[];
      ApiService.testHttpClient = MockClient((request) {
        requests.add('${request.method} ${request.url.path}');
        return server.handle(request);
      });
      final photos = makePhotos(5);
      await svc.submit(draftId: draftId, carData: withCover(photos, 3));
      expect(
        requests.where(
          (r) => r.startsWith('PUT') &&
              (r.endsWith('/images/primary') || r.endsWith('/images/layout')),
        ),
        isEmpty,
        reason: 'the server applies the declared cover itself: $requests',
      );
      expect(coverIdx(manifestOf(server.createBodies.single)), [3]);
    });

    test('6. background/restart: the frozen manifest keeps the cover, and a '
        'replayed create declares the SAME cover even if the star changed '
        'in the meantime', () async {
      const draftId = 'cov_restart';
      final photos = makePhotos(4);
      server.dropNextCreateResponse = true;
      server.lostReplayResponses = 1;
      final first = await svc
          .submit(draftId: draftId, carData: withCover(photos, 2))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(first, isNotNull, reason: 'the transport failure surfaces');

      // peek() reads the durable record back through prefs JSON (restart).
      final stranded = (await svc.peek(draftId))!;
      expect(stranded.carId ?? '', isEmpty);
      final frozen = stranded.expectedMedia!;
      expect([
        for (var i = 0; i < frozen.length; i++)
          if (frozen[i]['is_cover'] == 'true') i
      ], [2], reason: 'cover frozen with the manifest and persisted');

      // The seller re-opens the draft and stars a DIFFERENT photo, then
      // resubmits. The server-bound manifest is not negotiable.
      final outcome = await svc
          .submit(draftId: draftId, carData: withCover(photos, 0))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(outcome, isNull);
      expect(server.carCount, 1, reason: 'idempotent: one car');
      final bodies = server.createBodies;
      expect(bodies.length, greaterThanOrEqualTo(2));
      expect(coverIdx(manifestOf(bodies.last)), [2],
          reason: 'the replay re-declares the frozen cover, not the new star');
      expect(manifestOf(bodies.last), manifestOf(bodies.first));
    });

    test('7. a cold restart resumes the submission with the frozen cover and '
        'creates no second car', () async {
      const draftId = 'cov_resume';
      final photos = makePhotos(3);
      server.enqueueFailStatus = 503;
      await svc
          .submit(draftId: draftId, carData: withCover(photos, 1))
          .then<Object?>((_) => null, onError: (Object e) => e);
      final rec = await svc.peek(draftId);
      expect(rec, isNotNull);
      expect([
        for (final e in rec!.expectedMedia!) e['is_cover'] == 'true'
      ], [false, true, false]);
      server.enqueueFailStatus = null;
      expect(await svc.resumeAll(), isTrue);
      expect(server.carCount, 1);
      expect(server.createBodies, hasLength(1), reason: 'never re-created');
      expect(await svc.peek(draftId), isNull);
    });
  });
}
