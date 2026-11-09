// F-37 regression tests: a timed-out (or otherwise ambiguous) WRITE request
// must never be sent a second time automatically.
//
// Before the fix `_sendWithAdaptiveTimeout` re-sent ANY request (POST / PUT /
// PATCH / DELETE included) with the cold-start timeout after the warm 20s
// timeout fired, so a server that was merely slow processed the write twice
// (double favorite toggle, duplicate report, "not found" on a delete that had
// already succeeded, ...). Only requests that carry an `Idempotency-Key` (the
// server de-duplicates those) and safe reads (GET) may be retried.
//
// Time is virtual: every test runs inside `testWidgets` (fake async clock) and
// advances the 20s / 55s timeouts with `tester.pump`, so the suite is fast.
import 'dart:async';
import 'dart:convert';

import 'package:car_listing_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _warm = Duration(seconds: 20);
const _cold = Duration(seconds: 55);

http.Response _ok([int status = 200]) => http.Response(
      json.encode({'ok': true}),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Records every request that reaches the "server".
class _Server {
  _Server(this.onRequest);

  /// Called with the 1-based attempt number; decides how the server behaves.
  final Future<http.Response> Function(int attempt, http.BaseRequest r)
      onRequest;
  final List<http.BaseRequest> received = <http.BaseRequest>[];

  MockClient get client => MockClient.streaming((request, bodyStream) async {
        // Drain the body like a real server would, then record the request.
        final bytes = await bodyStream.toBytes();
        final copy = http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..bodyBytes = bytes;
        received.add(copy);
        final response = await onRequest(received.length, request);
        return http.StreamedResponse(
          Stream.value(response.bodyBytes),
          response.statusCode,
          headers: response.headers,
        );
      });
}

/// Starts [call] and captures its outcome without leaking an unhandled error.
class _Outcome {
  _Outcome(Future<Map<String, dynamic>> call) {
    call.then<void>(
      (v) {
        done = true;
        value = v;
      },
      onError: (Object e) {
        done = true;
        error = e;
      },
    );
  }
  bool done = false;
  Map<String, dynamic>? value;
  Object? error;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    ApiService.debugResetTimeoutPolicy();
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    ApiService.testHttpClient = null;
    ApiService.debugResetTimeoutPolicy();
    await ApiService.clearTokens();
  });

  void bind(_Server server) => ApiService.testHttpClient = server.client;
  void markWarm() => ApiService.debugMarkRequestSuccessAt(DateTime.now());

  Future<Map<String, dynamic>> send(String method, {String path = '/x'}) =>
      ApiService.makeAuthenticatedRequest(
        method,
        path,
        body: method == 'DELETE' ? null : {'k': 'v'},
      );

  Future<void> elapse(WidgetTester t, Duration d) async {
    await t.pump(d);
    await t.pump();
  }

  group('reads (GET) keep the adaptive cold-start retry', () {
    testWidgets('warm GET timeout -> retried once with the cold timeout',
        (tester) async {
      markWarm();
      final server = _Server((attempt, _) {
        // 1st attempt never answers; 2nd answers after 30s (> warm, < cold).
        if (attempt == 1) return Completer<http.Response>().future;
        return Future<http.Response>.delayed(
          const Duration(seconds: 30),
          _ok,
        );
      });
      bind(server);

      final outcome = _Outcome(send('GET'));
      await elapse(tester, _warm + const Duration(seconds: 1));
      expect(server.received, hasLength(2), reason: 'one cold retry');
      expect(outcome.done, isFalse);
      await elapse(tester, const Duration(seconds: 31));
      expect(outcome.error, isNull);
      expect(outcome.value, {'ok': true});
      expect(server.received, hasLength(2));
    });

    testWidgets('GET that times out in the cold window is NOT retried again',
        (tester) async {
      // Cold (no recent success): the first attempt already uses 55s.
      final server = _Server((_, _) => Completer<http.Response>().future);
      bind(server);

      final outcome = _Outcome(send('GET'));
      await elapse(tester, _cold + const Duration(seconds: 1));
      expect(outcome.error, isA<TimeoutException>());
      expect(server.received, hasLength(1));
    });
  });

  group('writes are never re-sent after a timeout', () {
    for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
      testWidgets('$method: no response -> exactly one request, timeout error',
          (tester) async {
        markWarm(); // warm => old code used a 20s first attempt then resent
        final server = _Server((_, _) => Completer<http.Response>().future);
        bind(server);

        final outcome = _Outcome(send(method));
        await elapse(tester, _warm + const Duration(seconds: 1));
        // The old code had already fired a duplicate here.
        expect(server.received, hasLength(1));
        await elapse(tester, _cold);
        expect(outcome.error, isA<TimeoutException>(),
            reason: 'a genuine timeout still surfaces as TimeoutException');
        expect(server.received, hasLength(1),
            reason: '$method must never be automatically re-sent');
        expect(server.received.single.method, method);
      });

      testWidgets(
          '$method: server applies the write but answers after the warm '
          'timeout -> applied exactly once and success is surfaced',
          (tester) async {
        markWarm();
        var applied = 0;
        final server = _Server((_, _) {
          applied++; // the write happens when the request arrives
          return Future<http.Response>.delayed(
            const Duration(seconds: 30),
            () => _ok(method == 'POST' ? 201 : 200),
          );
        });
        bind(server);

        final outcome = _Outcome(send(method));
        await elapse(tester, const Duration(seconds: 31));
        expect(outcome.error, isNull);
        expect(outcome.value, {'ok': true});
        expect(applied, 1, reason: 'no duplicate write');
        expect(server.received, hasLength(1));
      });
    }

    testWidgets('cold POST: single attempt, times out at the cold timeout',
        (tester) async {
      final server = _Server((_, _) => Completer<http.Response>().future);
      bind(server);
      final outcome = _Outcome(send('POST'));
      await elapse(tester, _cold - const Duration(seconds: 1));
      expect(outcome.done, isFalse);
      await elapse(tester, const Duration(seconds: 2));
      expect(outcome.error, isA<TimeoutException>());
      expect(server.received, hasLength(1));
    });

    testWidgets('a non-2xx answer to a write is not retried either',
        (tester) async {
      markWarm();
      final server = _Server((_, _) async => http.Response('{}', 500));
      bind(server);
      final outcome = _Outcome(send('POST'));
      await elapse(tester, const Duration(seconds: 1));
      expect(outcome.error, isNotNull);
      expect(server.received, hasLength(1));
    });
  });

  group('writes carrying an Idempotency-Key keep the timeout retry', () {
    testWidgets('createCar(idempotencyKey) is re-sent with the SAME key',
        (tester) async {
      markWarm();
      final server = _Server((attempt, _) {
        if (attempt == 1) return Completer<http.Response>().future;
        return Future<http.Response>.delayed(
          const Duration(seconds: 30),
          () => _ok(201),
        );
      });
      bind(server);

      final outcome = _Outcome(
        ApiService.createCar({'brand': 'toyota'}, idempotencyKey: 'key-123'),
      );
      await elapse(tester, _warm + const Duration(seconds: 1));
      expect(server.received, hasLength(2));
      await elapse(tester, const Duration(seconds: 31));
      expect(outcome.error, isNull);
      expect(outcome.value, {'ok': true});
      final keys = server.received
          .map((r) => r.headers['Idempotency-Key'])
          .toList();
      expect(keys, ['key-123', 'key-123']);
    });

    testWidgets('idempotency-key header match is case-insensitive',
        (tester) async {
      markWarm();
      final server = _Server((attempt, _) {
        if (attempt == 1) return Completer<http.Response>().future;
        return Future<http.Response>.value(_ok());
      });
      bind(server);
      final outcome = _Outcome(
        ApiService.makeAuthenticatedRequest(
          'POST',
          '/x',
          body: {'a': 1},
          headers: {'idempotency-key': 'abc'},
        ),
      );
      await elapse(tester, _warm + const Duration(seconds: 1));
      expect(server.received, hasLength(2));
      expect(outcome.value, {'ok': true});
    });

    testWidgets('a blank Idempotency-Key does not make a write retryable',
        (tester) async {
      markWarm();
      final server = _Server((_, _) => Completer<http.Response>().future);
      bind(server);
      final outcome = _Outcome(
        ApiService.makeAuthenticatedRequest(
          'POST',
          '/x',
          body: {'a': 1},
          headers: {'Idempotency-Key': '  '},
        ),
      );
      await elapse(tester, _warm + _cold + const Duration(seconds: 1));
      expect(outcome.error, isA<TimeoutException>());
      expect(server.received, hasLength(1));
    });
  });

  group('stale keep-alive socket errors', () {
    // None of these errors proves the request never reached the server (for
    // example `dart:io` raises "Bad file descriptor" when it fails to READ the
    // response of a request the server already processed), so an unkeyed
    // write must never be replayed -- including on "Bad file descriptor".
    for (final msg in [
      'Connection reset by peer',
      'Connection closed before full header was received',
      'Broken pipe',
      'Software caused connection abort',
      'Bad file descriptor',
    ]) {
      testWidgets('unkeyed POST + "$msg" -> surfaced, not re-sent',
          (tester) async {
        final server = _Server((_, r) async {
          throw http.ClientException(msg, r.url);
        });
        bind(server);
        final outcome = _Outcome(send('POST'));
        await elapse(tester, const Duration(seconds: 1));
        expect(outcome.error, isA<http.ClientException>());
        expect(server.received, hasLength(1));
      });
    }

    for (final method in ['PUT', 'PATCH', 'DELETE']) {
      testWidgets('unkeyed $method + "Bad file descriptor" -> surfaced, not re-sent',
          (tester) async {
        final server = _Server((_, r) async {
          throw http.ClientException('Bad file descriptor', r.url);
        });
        bind(server);
        final outcome = _Outcome(send(method));
        await elapse(tester, const Duration(seconds: 1));
        expect(outcome.error, isA<http.ClientException>());
        expect(server.received, hasLength(1));
      });
    }

    testWidgets('keyed POST + "Bad file descriptor" -> retried with the SAME key',
        (tester) async {
      final server = _Server((attempt, r) async {
        if (attempt == 1) throw http.ClientException('Bad file descriptor', r.url);
        return _ok(201);
      });
      bind(server);
      final outcome = _Outcome(
        ApiService.createCar({'brand': 'bmw'}, idempotencyKey: 'k-bfd'),
      );
      await elapse(tester, const Duration(seconds: 1));
      expect(outcome.error, isNull);
      expect(server.received, hasLength(2));
      expect(server.received.map((r) => r.headers['Idempotency-Key']),
          ['k-bfd', 'k-bfd']);
    });

    testWidgets('keyed POST + ambiguous stale error -> retried (deduped)',
        (tester) async {
      final server = _Server((attempt, r) async {
        if (attempt == 1) {
          throw http.ClientException('Connection reset by peer', r.url);
        }
        return _ok(201);
      });
      bind(server);
      final outcome = _Outcome(
        ApiService.createCar({'brand': 'bmw'}, idempotencyKey: 'k-9'),
      );
      await elapse(tester, const Duration(seconds: 1));
      expect(outcome.error, isNull);
      expect(server.received, hasLength(2));
      expect(server.received.map((r) => r.headers['Idempotency-Key']),
          ['k-9', 'k-9']);
    });

    testWidgets('GET + ambiguous stale error -> retried', (tester) async {
      final server = _Server((attempt, r) async {
        if (attempt == 1) {
          throw http.ClientException('Connection reset by peer', r.url);
        }
        return _ok();
      });
      bind(server);
      final outcome = _Outcome(send('GET'));
      await elapse(tester, const Duration(seconds: 1));
      expect(outcome.error, isNull);
      expect(server.received, hasLength(2));
    });
  });

  // The 401 -> refresh -> re-send path is intentionally unchanged (a 401 means
  // the server rejected the request before processing it). It persists tokens
  // through platform channels, which cannot run under the fake clock used
  // here, so it stays covered by `http_retry_regression_test.dart`
  // ("401 followed by a successful refresh retries a POST ...").

  group('session guards are unchanged', () {
    testWidgets(
        'a write answered after the session ended is dropped; still ONE send',
        (tester) async {
      markWarm();
      final server = _Server((_, _) => Future<http.Response>.delayed(
            const Duration(seconds: 30),
            _ok,
          ));
      bind(server);
      final outcome = _Outcome(send('POST'));
      await elapse(tester, const Duration(seconds: 5));
      ApiService.debugResetSessionForTests(); // account switch / logout
      await elapse(tester, const Duration(seconds: 30));
      expect(outcome.error, isA<ApiSessionChangedException>());
      expect(outcome.value, isNull);
      expect(server.received, hasLength(1));
    });

    testWidgets('a GET answered after the session ended is dropped',
        (tester) async {
      markWarm();
      final server = _Server((_, _) => Future<http.Response>.delayed(
            const Duration(seconds: 5),
            _ok,
          ));
      bind(server);
      final outcome = _Outcome(send('GET'));
      await elapse(tester, const Duration(seconds: 1));
      ApiService.debugResetSessionForTests();
      await elapse(tester, const Duration(seconds: 10));
      expect(outcome.error, isA<ApiSessionChangedException>());
    });
  });
}
