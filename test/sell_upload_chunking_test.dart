// F-41: multi-photo uploads are sent in small chunks with per-chunk retry,
// so one flaky request no longer forces the whole batch to be re-sent.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/sell_listing_media_upload.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
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

List<String> _fileParts(http.Request request) {
  final contentType = request.headers['content-type'] ?? '';
  final m = RegExp(r'boundary=([^\s;]+)').firstMatch(contentType);
  if (m == null) return const [];
  final boundary = m.group(1)!.replaceAll('"', '');
  final out = <String>[];
  for (final part in latin1.decode(request.bodyBytes).split('--$boundary')) {
    if (!part.contains('name="images"')) continue;
    final i = part.indexOf('\r\n\r\n');
    if (i == -1) continue;
    var c = part.substring(i + 4);
    if (c.endsWith('\r\n')) c = c.substring(0, c.length - 2);
    out.add(c);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<String> photoPaths;
  late List<List<String>> enqueueCalls; // file contents per request
  late List<String> attached;
  late int Function(int callIndex) statusForCall;
  late List<int> statuses;
  final images = <dynamic>[];

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sell_chunking_');
    PathProviderPlatform.instance = _FakeDocsPathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    photoPaths = [];
    images.clear();
    for (var i = 0; i < 7; i++) {
      final p = '${tempDir.path}/p$i.jpg';
      File(p).writeAsStringSync('PHOTO_$i');
      photoPaths.add(p);
      images.add({'source': p});
    }
    enqueueCalls = [];
    attached = [];
    statuses = [];
    statusForCall = (_) => 202;
    var jobCounter = 0;
    final jobRel = <String, String>{};

    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    SellListingMediaUpload.uploadChunkRetryDelay = (_) => Duration.zero;

    ApiService.testHttpClient = MockClient((request) async {
      final method = request.method.toUpperCase();
      final path = request.url.path;
      http.Response j(Object body, int code) => http.Response(
        json.encode(body),
        code,
        headers: {'content-type': 'application/json'},
      );
      if (method == 'POST' && RegExp(r'^/api/cars/[^/]+/images$').hasMatch(path)) {
        final contents = _fileParts(request);
        enqueueCalls.add(contents);
        final status = statusForCall(enqueueCalls.length - 1);
        statuses.add(status);
        if (status != 202) return j({'message': 'fail'}, status);
        final ids = <String>[];
        for (final c in contents) {
          final id = 'job_${++jobCounter}';
          jobRel[id] = 'uploads/car_photos/$c.jpg';
          ids.add(id);
        }
        return j({'job_ids': ids}, 202);
      }
      if (method == 'GET' && path.startsWith('/api/jobs/')) {
        final id = path.substring('/api/jobs/'.length);
        return j({
          'task_id': id,
          'state': 'SUCCESS',
          'result': {'rel_path': jobRel[id]},
        }, 200);
      }
      if (method == 'POST' && path.endsWith('/images/attach')) {
        final paths = List<String>.from(
          (json.decode(request.body) as Map)['paths'] as List,
        );
        attached.addAll(paths);
        return j({
          'images': [
            for (var i = 0; i < paths.length; i++)
              {'id': attached.length - paths.length + i + 1, 'image_url': paths[i]},
          ],
        }, 201);
      }
      if (method == 'GET' && RegExp(r'^/api/cars/[^/]+$').hasMatch(path)) {
        return j({
          'car': {'id': 'car_1', 'images': <dynamic>[], 'videos': <dynamic>[]},
        }, 200);
      }
      return j({'cars': []}, 200);
    });
    await ApiService.setTokens(accessToken: 'a', refreshToken: 'r');
    await AuthService().adoptTestSession(user: {'id': 'owner'});
  });

  tearDown(() async {
    SellListingMediaUpload.clearCancelFor('car_1');
    SellListingMediaUpload.uploadChunkSize = 3;
    SellListingMediaUpload.uploadChunkAttempts = 2;
    SellListingMediaUpload.uploadChunkRetryDelay =
        (a) => Duration(seconds: (a + 1) * 2);
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    ApiService.testHttpClient = null;
    setRuntimeApiBaseOverride(null);
    TokenStore.testMode = false;
    TokenStore.resetForTests();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> run() => SellListingMediaUpload.uploadForCar(
    carId: 'car_1',
    carData: {
      'images': List<dynamic>.from(images),
      'videos': <dynamic>[],
      'damage_images': <dynamic>[],
    },
  );

  test('7 photos go out as 3 chunked requests (3,3,1) and all attach', () async {
    await run();
    expect(enqueueCalls.map((c) => c.length).toList(), [3, 3, 1]);
    expect(attached, hasLength(7));
  });

  test('negative control: chunk size above photo count => single request', () async {
    SellListingMediaUpload.uploadChunkSize = 100;
    await run();
    expect(enqueueCalls.map((c) => c.length).toList(), [7]);
    expect(attached, hasLength(7));
  });

  test('transient failure of one chunk is retried; only that chunk re-sent', () async {
    statusForCall = (i) => i == 1 ? 503 : 202; // 2nd request fails once
    await run();
    expect(statuses, [202, 503, 202, 202]);
    expect(enqueueCalls.map((c) => c.length).toList(), [3, 3, 3, 1]);
    expect(attached, hasLength(7));
    // Chunk 1 photos were never re-sent.
    expect(enqueueCalls[0], ['PHOTO_0', 'PHOTO_1', 'PHOTO_2']);
  });

  test('a chunk that keeps failing does not discard other chunks', () async {
    // 2nd chunk (calls 1 and 2) fails on both attempts.
    statusForCall = (i) => (i == 1 || i == 2) ? 503 : 202;
    try {
      await run();
    } catch (_) {
      // Partial completion may be reported as an error; the point is what
      // reached the server.
    }
    expect(attached.toSet(), containsAll([
      'uploads/car_photos/PHOTO_0.jpg',
      'uploads/car_photos/PHOTO_6.jpg',
    ]));
    expect(attached, isNot(contains('uploads/car_photos/PHOTO_3.jpg')));
  });

  test('negative control: non-transient 400 fails fast without chunk retry', () async {
    statusForCall = (_) => 400;
    await expectLater(run(), throwsA(anything));
    expect(enqueueCalls, hasLength(1));
  });

  // F-41: SAFE cancel -- never another request after the user cancels.
  test('cancel after the first chunk stops the rest of the batch', () async {
    statusForCall = (i) {
      if (i == 0) SellListingMediaUpload.cancelUploadsFor('car_1');
      return 202;
    };
    await expectLater(
      run(),
      throwsA(isA<SellSubmissionCancelledException>()),
    );
    // Only the in-flight chunk went out; chunks 2 and 3 were never sent.
    expect(enqueueCalls, hasLength(1));
  });

  test('cancel while a chunk is failing does not retry it', () async {
    statusForCall = (i) {
      SellListingMediaUpload.cancelUploadsFor('car_1');
      return 503;
    };
    await expectLater(
      run(),
      throwsA(isA<SellSubmissionCancelledException>()),
    );
    expect(enqueueCalls, hasLength(1)); // no retry, no further chunks
  });

  test('negative control: clearing the cancel lets uploads proceed', () async {
    SellListingMediaUpload.cancelUploadsFor('car_1');
    SellListingMediaUpload.clearCancelFor('car_1');
    await run();
    expect(attached, hasLength(7));
    expect(SellListingMediaUpload.isCancelled('car_1'), isFalse);
  });
}
