// Regression tests for the production Sentry bug:
//
//   ClientException: Content size below specified contentLength.
//   44796611 bytes written but expected 57599520.     (multipart video upload)
//   ClientException: Content size below specified contentLength.
//   0 bytes written but expected 154.                 (POST /api/users/push_token)
//
// Root cause (see `lib/services/api/tracked_http_client.dart` for the full
// writeup): `ApiService.recycleProductionHttpClient()` used to call
// `previous.close()` directly, which force-aborts EVERY socket on the
// shared production `http.Client` -- not just the one request that
// triggered the recycle. Because that client is shared across every
// endpoint (GET/POST/PUT/PATCH/DELETE and multipart uploads), an unrelated
// stale-connection retry, an app-resume lifecycle event, or an unrelated
// resilience loop could force-abort a *different*, still-streaming request
// mid-write.
//
// This file proves the retry/request-construction contract at the
// `ApiService` level: every retry attempt (stale-client retry, 401 ->
// refresh -> retry) builds a completely fresh request/body, so a retried
// attempt always carries the full, correct payload. Combined with
// `test/tracked_http_client_test.dart` (which proves the client-swap half
// of the fix in isolation), this covers requirement 7 A/B/D from the
// audit. Requirement 7C (client swap never aborts an active request) is
// covered in `tracked_http_client_test.dart` because
// `ApiService.recycleProductionHttpClient()` is a documented no-op while a
// test client is bound (see its doc comment), so it cannot be observed
// through `ApiService.testHttpClient`.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import 'fake_api_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('http_retry_regression_');
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    ApiService.testHttpClient = null;
    tempDir.deleteSync(recursive: true);
  });

  /// Swaps in a one-off [MockClient] for a single test (mirrors the
  /// `useClient` helper already used by `api_car_detail_test.dart`).
  void useClient(MockClient client) {
    ApiService.testHttpClient = client;
  }

  group('A: normal (JSON) request retry -- push_token symptom', () {
    test(
      'a stale-client error on the first attempt is retried with a brand '
      'new request that carries the FULL body (regression for "0 bytes '
      'written but expected 154")',
      () async {
        var callCount = 0;
        final receivedBodyLengths = <int>[];
        String? secondAttemptBody;

        useClient(
          MockClient((request) async {
            callCount++;
            receivedBodyLengths.add(request.bodyBytes.length);
            if (callCount == 1) {
              // Simulates the "iOS reclaimed the keep-alive socket while
              // backgrounded" failure that `isStaleHttpClientError`
              // classifies and `_withStaleClientRetry` retries.
              throw http.ClientException(
                'Software caused connection abort',
                request.url,
              );
            }
            secondAttemptBody = utf8.decode(request.bodyBytes);
            return http.Response(
              '{}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        const pushToken = 'fcm-test-token-1234567890abcdef';
        await ApiService.registerPushToken(pushToken);

        expect(
          callCount,
          2,
          reason:
              'exactly one stale-client retry should have happened (the '
              'first attempt failed, the retry succeeded)',
        );
        // The bug: on a naive implementation that reused an
        // already-finalized request/body, the retried attempt would send 0
        // bytes (the body stream is single-subscription and was already
        // drained). Every attempt here must see the full, correct body.
        expect(
          receivedBodyLengths[0],
          greaterThan(0),
          reason: 'even the failing first attempt must have built a real body',
        );
        expect(
          receivedBodyLengths[1],
          receivedBodyLengths[0],
          reason:
              'the retried attempt must carry exactly as many bytes as the '
              'first attempt -- proving a fresh request/body was built, not '
              'a reused, already-drained one',
        );
        expect(secondAttemptBody, isNotNull);
        final decoded = json.decode(secondAttemptBody!) as Map;
        expect(
          decoded['token'],
          pushToken,
          reason: 'the retried request must carry the real push token, not '
              'an empty/stale body',
        );
      },
    );

    test(
      '401 followed by a successful refresh retries a POST with a fresh, '
      'fully-populated body (not the pre-refresh request object)',
      () async {
        var carCalls = 0;
        String? secondAttemptBody;

        useClient(
          MockClient((request) async {
            if (request.url.path == '/api/auth/refresh') {
              return http.Response(
                json.encode({
                  'access_token': 'new_access_token',
                  'refresh_token': 'new_refresh_token',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/api/cars/car123') {
              carCalls++;
              if (carCalls == 1) {
                return http.Response(
                  json.encode({'message': 'Token has expired'}),
                  401,
                  headers: {'content-type': 'application/json'},
                );
              }
              secondAttemptBody = utf8.decode(request.bodyBytes);
              return http.Response(
                json.encode({'car': {'id': 'car123'}}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('{}', 200);
          }),
        );

        await ApiService.updateCar('car123', {
          'brand': 'toyota',
          'price': 25000,
        });

        expect(carCalls, 2);
        expect(secondAttemptBody, isNotNull);
        final decoded = json.decode(secondAttemptBody!) as Map;
        expect(decoded['brand'], 'toyota');
        expect(decoded['price'], 25000);
      },
    );
  });

  group('B: multipart request retry -- video upload symptom', () {
    test(
      'a stale-client error after the multipart request is built is '
      'retried with a brand-new MultipartRequest and fresh MultipartFile '
      'streams, so the retry carries the COMPLETE payload (regression for '
      '"44796611 bytes written but expected 57599520")',
      () async {
        // A few KB is plenty to prove the byte-for-byte contract without
        // making the test slow; the production numbers (44.8MB/57.6MB)
        // differ only in scale, not mechanism.
        final videoBytes = List<int>.generate(20000, (i) => i % 256);
        final videoFile = File('${tempDir.path}/clip.mp4');
        videoFile.writeAsBytesSync(videoBytes);
        final xFile = XFile(videoFile.path);

        var buildFileCallCount = 0;
        var sendCallCount = 0;
        List<int>? secondAttemptBody;

        Future<http.MultipartFile> countingBuilder(XFile file) {
          buildFileCallCount++;
          // Mirrors `sell_video_helpers.dart::buildVideoMultipartFile`: a
          // fresh `http.MultipartFile.fromPath` call (fresh file stream,
          // freshly-recalculated length) on every invocation.
          return http.MultipartFile.fromPath('files', file.path);
        }

        useClient(
          MockClient((request) async {
            sendCallCount++;
            if (sendCallCount == 1) {
              throw http.ClientException(
                'Connection reset by peer',
                request.url,
              );
            }
            secondAttemptBody = request.bodyBytes;
            return http.Response(
              json.encode({'videos': <dynamic>[]}),
              201,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        await ApiService.uploadCarVideos(
          'car_video_1',
          [xFile],
          multipartFileBuilder: countingBuilder,
        );

        expect(
          sendCallCount,
          2,
          reason: 'exactly one stale-client retry for the multipart upload',
        );
        expect(
          buildFileCallCount,
          2,
          reason:
              'the multipart-file builder must run again on retry -- proof '
              'that a brand new MultipartFile/file stream is created per '
              'attempt instead of reusing one that was already finalized '
              'and drained on the first attempt',
        );
        expect(secondAttemptBody, isNotNull);
        // The finalized multipart body must contain the full video byte
        // sequence intact (not truncated, not empty, not corrupted by a
        // half-consumed stream from a previous attempt).
        expect(
          _containsSubsequence(secondAttemptBody!, videoBytes),
          isTrue,
          reason:
              'the retried multipart request must carry the COMPLETE, '
              'byte-identical file content -- a truncated/empty stream '
              'here is exactly the production "Content size below '
              'specified contentLength" failure mode',
        );
      },
    );

    test(
      'every attempt (not just the first) gets its own fresh '
      'MultipartRequest instance -- proves uploadCarVideos never captures '
      'a request object outside the retry closure',
      () async {
        final videoFile = File('${tempDir.path}/clip2.mp4');
        videoFile.writeAsBytesSync(List<int>.generate(500, (i) => i));
        final xFile = XFile(videoFile.path);

        var sendCallCount = 0;
        final seenContentLengths = <int?>[];

        useClient(
          MockClient((request) async {
            sendCallCount++;
            seenContentLengths.add(request.contentLength);
            if (sendCallCount == 1) {
              throw http.ClientException('Broken pipe', request.url);
            }
            return http.Response(
              json.encode({'videos': <dynamic>[]}),
              201,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        await ApiService.uploadCarVideos('car_video_2', [xFile]);

        expect(sendCallCount, 2);
        expect(seenContentLengths, hasLength(2));
        expect(
          seenContentLengths[0],
          seenContentLengths[1],
          reason:
              'both attempts describe the same real payload size -- if the '
              'retry had reused an already-finalized request it would '
              'either throw StateError immediately or (for a body driven '
              'by a drained stream) describe a shorter/zero length',
        );
        expect(seenContentLengths[0], greaterThan(0));
      },
    );
  });

  group('D: auth-refresh retry for multipart uploads', () {
    test(
      '401 on a multipart upload triggers a refresh, then retries with a '
      'brand new MultipartRequest carrying the full file again',
      () async {
        final videoFile = File('${tempDir.path}/clip3.mp4');
        final fileBytes = List<int>.generate(4000, (i) => (i * 7) % 256);
        videoFile.writeAsBytesSync(fileBytes);
        final xFile = XFile(videoFile.path);

        var uploadAttempts = 0;
        var buildFileCallCount = 0;

        useClient(
          MockClient((request) async {
            if (request.url.path == '/api/auth/refresh') {
              return http.Response(
                json.encode({
                  'access_token': 'new_access_token',
                  'refresh_token': 'new_refresh_token',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            uploadAttempts++;
            if (uploadAttempts == 1) {
              return http.Response(
                json.encode({'message': 'Token has expired'}),
                401,
                headers: {'content-type': 'application/json'},
              );
            }
            expect(
              _containsSubsequence(request.bodyBytes, fileBytes),
              isTrue,
              reason:
                  'the post-refresh retry must still carry the full file',
            );
            return http.Response(
              json.encode({'videos': <dynamic>[]}),
              201,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        await ApiService.uploadCarVideos(
          'car_video_3',
          [xFile],
          multipartFileBuilder: (file) {
            buildFileCallCount++;
            return http.MultipartFile.fromPath('files', file.path);
          },
        );

        expect(uploadAttempts, 2);
        expect(
          buildFileCallCount,
          2,
          reason:
              'the 401 -> refresh -> retry path must rebuild the multipart '
              'file, not resend the same (already-finalized) one',
        );
      },
    );
  });
}

/// Whether [haystack] contains [needle] as a contiguous run of bytes.
bool _containsSubsequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  if (needle.length > haystack.length) return false;
  final firstByte = needle.first;
  for (var start = 0; start <= haystack.length - needle.length; start++) {
    if (haystack[start] != firstByte) continue;
    var matched = true;
    for (var i = 1; i < needle.length; i++) {
      if (haystack[start + i] != needle[i]) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}
