// Section F.6 (multi-video/photo audit): "app kill/resume where photo A
// complete, photo B incomplete, video A complete, video B incomplete --
// Resume must only re-drive photo B + video B."
//
// Seeds a durable `SellSubmissionRecord` directly (simulating "the app was
// killed mid-submission, after A of each kind already landed on the
// server") -- the SAME technique
// `pending_sell_submission_service_test.dart`'s group-F test
// ("images already confirmed, video interrupted") uses -- then calls
// `resumeAll()` and proves:
//   * photo A and video A are NEVER re-uploaded/re-enqueued,
//   * photo B and video B ARE uploaded (exactly once each),
//   * the car ends up with exactly one row for each of the 4 items (no
//     duplicates), and
//   * the record is fully cleared once resume finishes.
//
// This also exercises the fix this session added to
// `SellListingMediaUpload.uploadForCar`'s LISTING-PHOTO path: the manifest
// (`media-summary`) now filters `toUpload` by exact `client_media_id`
// BEFORE the old coarse `remoteListingCount >= toUpload.length` check,
// mirroring the video-side `_excludeAlreadyAttachedVideos` fix from
// earlier in this session -- without it, a 2-photo resume where only 1 of
// 2 already landed would re-send BOTH photos (remote count 1 is still
// less than toUpload.length 2, so the old coarse check never fired).
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/features/sell/sell_media_identity.dart';
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

http.Response _jsonOk(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Extracts every `name="client_media_id"` (or [fieldName]) multipart
/// field value from [request], using the EXACT boundary from its own
/// `Content-Type` header (never a guessed charset -- see
/// `two_video_partial_failure_regression_test.dart`'s identical helper
/// for why).
List<String> _multipartFieldValues(http.Request request, String fieldName) {
  final contentType = request.headers['content-type'] ?? '';
  final boundaryMatch = RegExp('boundary=([^;]+)').firstMatch(contentType);
  final boundary = boundaryMatch?.group(1)?.trim();
  if (boundary == null || boundary.isEmpty) return const [];
  final text = latin1.decode(request.bodyBytes);
  final out = <String>[];
  for (final part in text.split('--$boundary')) {
    final headerEnd = part.indexOf('\r\n\r\n');
    if (headerEnd == -1) continue;
    final headers = part.substring(0, headerEnd);
    if (!headers.contains('name="$fieldName"')) continue;
    final rest = part.substring(headerEnd + 4);
    final value = rest.split('\r\n').first.trim();
    out.add(value);
  }
  return out;
}

Map<String, dynamic> _baseCarData({
  required List<String> images,
  required List<String> videos,
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
  'images': images,
  'videos': videos,
  'damage_images': <dynamic>[],
  'server_transcode_videos': <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mixed_partial_resume_');
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
    'F.6: photo A + video A already attached (app killed right after), '
    'photo B + video B still local-only -- resumeAll() re-drives ONLY B '
    'of each kind, never re-sends A, and the car ends up with exactly one '
    'row per item',
    () async {
      const draftId = 'mixed_partial_draft';
      const carId = 'car_mixed_partial';

      final imgA = File(p.join(tempDir.path, 'photoA.jpg'))
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      final imgB = File(p.join(tempDir.path, 'photoB.jpg'))
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 4, 5, 6]);
      final vidA = File(p.join(tempDir.path, 'videoA.mp4'))
        ..writeAsBytesSync(List<int>.filled(32, 1));
      final vidB = File(p.join(tempDir.path, 'videoB.mp4'))
        ..writeAsBytesSync(List<int>.filled(32, 2));

      final idImgA = SellMediaIdentity.forImageItem(
        imgA.path,
        kind: 'listing',
      )!;
      final idImgB = SellMediaIdentity.forImageItem(
        imgB.path,
        kind: 'listing',
      )!;
      final idVidA = SellMediaIdentity.forNormalVideoItem(vidA.path)!;
      final idVidB = SellMediaIdentity.forNormalVideoItem(vidB.path)!;

      // Server-side state: A of each kind is already attached (simulating
      // the app being killed right after those two calls succeeded, but
      // before B of either kind was ever attempted).
      final carImages = <Map<String, dynamic>>[
        {'id': 601, 'kind': 'listing', 'image_url': 'uploads/car_photos/a.jpg'},
      ];
      final carVideos = <Map<String, dynamic>>[
        {'id': 701, 'video_url': 'uploads/car_videos/a.mp4'},
      ];

      final imageEnqueueIdsLog = <List<String>>[];
      final videoUploadIdsLog = <List<String>>[];
      var jobIdCounter = 0;
      // Dynamic (not static) manifest state -- starts with A of each kind
      // already attached, and grows as the mock's handlers below actually
      // confirm B of each kind, so `media-summary` always reflects
      // reality instead of a fixed snapshot that never advances.
      final attachedClientMediaIds = <String>{idImgA, idVidA};

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;

        if (method == 'POST' && path == '/api/cars') {
          return _jsonOk({
            'car': {'id': carId, 'images': carImages, 'videos': carVideos},
          }, 201);
        }

        // ---- POST /api/cars/<id>/images (async enqueue) -----------------
        final enqueueMatch =
            RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
        if (method == 'POST' && enqueueMatch != null) {
          final ids = _multipartFieldValues(request, 'client_media_id');
          imageEnqueueIdsLog.add(ids);
          final jobIds = <String>[];
          for (final id in ids) {
            jobIdCounter++;
            // Embeds the client_media_id in the job id so the job-poll
            // and attach handlers below can trace a rel_path back to
            // exactly which item it came from.
            jobIds.add('job_${id}_$jobIdCounter');
          }
          return _jsonOk({'job_ids': jobIds}, 202);
        }

        // ---- GET /api/jobs/<job_id> --------------------------------------
        if (method == 'GET' && path.startsWith('/api/jobs/')) {
          final jobId = path.substring('/api/jobs/'.length);
          return _jsonOk({
            'task_id': jobId,
            'state': 'SUCCESS',
            'result': {'rel_path': 'uploads/car_photos/$jobId.jpg'},
          });
        }

        // ---- POST /api/cars/<id>/images/attach ---------------------------
        final attachMatch =
            RegExp(r'^/api/cars/([^/]+)/images/attach$').firstMatch(path);
        if (method == 'POST' && attachMatch != null) {
          final decoded = json.decode(request.body) as Map;
          final paths = List<String>.from(decoded['paths'] as List);
          final rows = <Map<String, dynamic>>[];
          for (final src in paths) {
            // This mock's `job_ids`/rel_paths are derived from
            // `idImgB` (see the enqueue handler below), so recognizing
            // that substring here is enough to know this attach call is
            // for B specifically, and mark it attached in the manifest.
            if (src.contains(idImgB)) attachedClientMediaIds.add(idImgB);
            final row = {
              'id': 900 + carImages.length,
              'kind': 'listing',
              'image_url': src,
            };
            rows.add(row);
            carImages.add(row);
          }
          return _jsonOk({
            'images': rows
                .map((r) => {'id': r['id'], 'image_url': r['image_url']})
                .toList(),
          }, 201);
        }

        // ---- POST /api/cars/<id>/videos ----------------------------------
        final videoMatch =
            RegExp(r'^/api/cars/([^/]+)/videos$').firstMatch(path);
        if (method == 'POST' && videoMatch != null) {
          final ids = _multipartFieldValues(request, 'client_media_id');
          videoUploadIdsLog.add(ids);
          final videos = <Map<String, dynamic>>[];
          for (final id in ids) {
            attachedClientMediaIds.add(id);
            final row = {
              'id': 800 + carVideos.length,
              'video_url': 'uploads/car_videos/$id.mp4',
            };
            videos.add(row);
            carVideos.add(row);
          }
          return _jsonOk({'videos': videos, 'rejected': <dynamic>[]}, 201);
        }

        // ---- GET /api/cars/<id>/media-summary -----------------------------
        // Dynamic -- always reflects `attachedClientMediaIds`'s CURRENT
        // state (starts with A of each kind, grows to include B once the
        // handlers above actually confirm it), never a fixed snapshot.
        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+/media-summary$').hasMatch(path)) {
          Map<String, dynamic> item(String id, String kind) => {
            'client_media_id': id,
            'kind': kind,
            'status': attachedClientMediaIds.contains(id)
                ? 'attached'
                : 'awaiting_upload',
            'phase_a_complete': attachedClientMediaIds.contains(id),
          };
          final items = [
            item(idImgA, 'image'),
            item(idImgB, 'image'),
            item(idVidA, 'video'),
            item(idVidB, 'video'),
          ];
          return _jsonOk({
            'media_status':
                items.every((it) => it['phase_a_complete'] == true)
                ? 'ready'
                : 'processing',
            'items': items,
            'phase_a_complete':
                items.every((it) => it['phase_a_complete'] == true),
          });
        }

        // ---- GET /api/cars/<id> ------------------------------------------
        if (method == 'GET' && RegExp(r'^/api/cars/[^/]+$').hasMatch(path)) {
          return _jsonOk({
            'car': {'id': carId, 'images': carImages, 'videos': carVideos},
          });
        }

        if (method == 'GET' && path == '/api/cars') {
          return _jsonOk({'cars': []});
        }

        // ---- PUT /api/cars/<id>/images/layout, /images/primary, and any
        // other listing-metadata PUT/PATCH call this flow makes after
        // media upload -- not under test here, just needs to not 404.
        if ((method == 'PUT' || method == 'PATCH') &&
            RegExp(r'^/api/cars/[^/]+').hasMatch(path)) {
          return _jsonOk({'message': 'ok'});
        }

        return _jsonOk({}, 404);
      });

      final carData = _baseCarData(
        images: [imgA.path, imgB.path],
        videos: [vidA.path, vidB.path],
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

      // Photo A must never be re-enqueued; photo B must be, exactly once.
      final allEnqueuedImageIds = imageEnqueueIdsLog.expand((l) => l).toList();
      expect(
        allEnqueuedImageIds,
        isNot(contains(idImgA)),
        reason: 'already-attached photo A must never be re-uploaded',
      );
      expect(
        allEnqueuedImageIds.where((id) => id == idImgB).length,
        1,
        reason: 'photo B must be uploaded exactly once',
      );

      // Video A must never be re-sent; video B must be, exactly once.
      final allUploadedVideoIds = videoUploadIdsLog.expand((l) => l).toList();
      expect(
        allUploadedVideoIds,
        isNot(contains(idVidA)),
        reason: 'already-attached video A must never be re-uploaded',
      );
      expect(
        allUploadedVideoIds.where((id) => id == idVidB).length,
        1,
        reason: 'video B must be uploaded exactly once',
      );

      // Exactly one row per item on the "server" -- no duplicates for A,
      // exactly one new row for B.
      expect(carImages.length, 2);
      expect(carVideos.length, 2);

      expect(await SellSubmissionStatePrefs.load(draftId), isNull);
    },
  );
}
