// Regression tests for `TrackedHttpClient` (lib/services/api/tracked_http_client.dart).
//
// Context (production Sentry bug): `ApiService.recycleProductionHttpClient`
// used to call `previous.close()` directly on the shared `http.Client`.
// `IOClient.close()` maps to `HttpClient.close(force: true)`, which
// force-aborts *every* socket on that client -- including requests that
// have nothing to do with whichever request triggered the recycle. Because
// every ApiService endpoint (GET/POST/PUT/PATCH/DELETE, JSON and
// multipart) shares one production client, this meant:
//   - a single unrelated request hitting a stale-connection error
//     (`_withStaleClientRetry`), or
//   - the app simply resuming from background
//       (`AppWithDeepLinks.didChangeAppLifecycleState`), or
//   - an unrelated retry loop recycling between attempts
//       (`SellListingMediaUpload._uploadImagesResilient`)
// could silently kill a *different*, still-streaming request (e.g. a
// multipart video upload ~78% through writing its body), surfacing in
// production as `ClientException: Content size below specified
// contentLength` on a request that was never itself retried or reused.
//
// `TrackedHttpClient` fixes this by deferring the actual `close()` of an
// outgoing client until every request already in flight on it finishes.
// These tests exercise the wrapper directly (no network, no ApiService),
// which is the cleanest way to prove the fix: `ApiService.testHttpClient`
// bypasses `recycleProductionHttpClient` entirely (it is a documented
// no-op while a test client is bound), so the *production* client-swap
// path can only be verified by testing this class in isolation.
import 'dart:async';

import 'package:car_listing_app/services/api/tracked_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Minimal fake inner [http.Client] that lets a test control exactly when
/// `send()` "completes" and observe whether/when `close()` was called --
/// standing in for a real socket that is actively streaming a request
/// body.
class _ControllableInnerClient extends http.BaseClient {
  final Map<http.BaseRequest, Completer<http.StreamedResponse>> _pending = {};
  int sendCallCount = 0;
  int closeCallCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sendCallCount++;
    // Mirrors real `IOClient.send()`, which calls `request.finalize()`
    // synchronously up front (before piping the body to the socket) --
    // this is what makes reusing an already-sent request object throw
    // `StateError` instead of quietly resending stale/empty data.
    request.finalize();
    final completer = Completer<http.StreamedResponse>();
    _pending[request] = completer;
    return completer.future;
  }

  /// Simulates one specific in-flight request finishing (e.g. its body
  /// finished streaming and a response arrived).
  void complete(http.BaseRequest request, {int statusCode = 200}) {
    final completer = _pending.remove(request)!;
    completer.complete(
      http.StreamedResponse(const Stream<List<int>>.empty(), statusCode),
    );
  }

  @override
  void close() {
    closeCallCount++;
  }
}

void main() {
  group('TrackedHttpClient.closeWhenIdle', () {
    test('closes the inner client immediately when nothing is in flight', () {
      final inner = _ControllableInnerClient();
      final tracked = TrackedHttpClient(inner);

      expect(tracked.activeRequestCount, 0);
      tracked.closeWhenIdle();

      expect(inner.closeCallCount, 1, reason: 'no active requests -> close now');
      expect(tracked.isClosed, isTrue);
    });

    test(
      'defers closing the inner client while a request is actively in '
      'flight, so an in-progress upload is never aborted just because the '
      'client is being retired',
      () async {
        final inner = _ControllableInnerClient();
        final tracked = TrackedHttpClient(inner);

        // Simulate a multipart video upload mid-stream: `send()` has been
        // called and has not returned yet.
        final uploadRequest = http.Request(
          'POST',
          Uri.parse('https://example.test/upload'),
        );
        final sendFuture = tracked.send(uploadRequest);
        await pumpEventQueue();
        expect(tracked.activeRequestCount, 1);

        // This is the exact call site pattern from
        // `ApiService.recycleProductionHttpClient`: something else (a
        // stale-client retry on an unrelated request, or an app-resume
        // event) decides to retire this client *while the upload above is
        // still running*.
        tracked.closeWhenIdle();

        // The critical assertion: the underlying socket must NOT be closed
        // while the upload is still active. Before the fix, `close()` was
        // called unconditionally here and would have force-aborted the
        // upload's connection mid-write.
        expect(
          inner.closeCallCount,
          0,
          reason:
              'closing must be deferred while a request is actively in flight',
        );
        expect(tracked.closeRequested, isTrue);
        expect(tracked.isClosed, isFalse);

        // The upload finishes naturally (full body reached the server).
        inner.complete(uploadRequest);
        final response = await sendFuture;
        expect(response.statusCode, 200);

        // Only now, once the last in-flight request has finished, does the
        // deferred close actually happen.
        expect(inner.closeCallCount, 1);
        expect(tracked.isClosed, isTrue);
      },
    );

    test(
      'multiple concurrent requests: close is deferred until the LAST one '
      'finishes, not the first',
      () async {
        final inner = _ControllableInnerClient();
        final tracked = TrackedHttpClient(inner);

        final uploadRequest = http.Request(
          'POST',
          Uri.parse('https://example.test/videos'),
        );
        final pushTokenRequest = http.Request(
          'POST',
          Uri.parse('https://example.test/push_token'),
        );
        final upload = tracked.send(uploadRequest);
        final pushToken = tracked.send(pushTokenRequest);
        await pumpEventQueue();
        expect(tracked.activeRequestCount, 2);

        tracked.closeWhenIdle();
        expect(inner.closeCallCount, 0);

        // The small push-token request finishes first; the big upload is
        // still going -- close must still be deferred.
        inner.complete(pushTokenRequest);
        await pushToken;
        expect(inner.closeCallCount, 0, reason: 'the upload is still active');

        inner.complete(uploadRequest);
        await upload;
        expect(inner.closeCallCount, 1);
      },
    );

    test(
      'a request that starts AFTER closeWhenIdle was requested is rejected '
      'instead of silently reusing a retiring client',
      () async {
        final inner = _ControllableInnerClient();
        final tracked = TrackedHttpClient(inner);
        tracked.closeWhenIdle(); // idle -> closes immediately

        expect(tracked.isClosed, isTrue);
        await expectLater(
          tracked.send(http.Request('GET', Uri.parse('https://example.test'))),
          throwsA(isA<http.ClientException>()),
        );
        expect(
          inner.sendCallCount,
          0,
          reason: 'must never forward a send() to an already-closed client',
        );
      },
    );
  });

  group('why fresh requests are required on every retry attempt', () {
    test(
      'sending the same finalized BaseRequest twice throws StateError '
      '(documents why every retry attempt must build a NEW request/body)',
      () async {
        final inner = _ControllableInnerClient();
        final tracked = TrackedHttpClient(inner);
        final request = http.Request('POST', Uri.parse('https://example.test'))
          ..body = 'hello';

        final first = tracked.send(request);
        inner.complete(request);
        await first;

        expect(
          () => tracked.send(request),
          throwsA(isA<StateError>()),
          reason:
              "package:http's BaseRequest.finalize() refuses to finalize the "
              'same request object twice -- this is why every ApiService '
              'retry path (`_withStaleClientRetry`, `_sendAuthenticatedMultipart`, '
              '`_sendWithAdaptiveTimeout`) must call a request-building '
              'closure/factory on every attempt instead of capturing one '
              'request/body outside the retry.',
        );
      },
    );
  });
}
