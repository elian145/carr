// Integration-level checks that sit next to `account_isolation_regression_test`:
//
//  * the session guards must NOT break ordinary, same-account token refreshes
//    or legitimate requests (including the F-01/F-02/F-03 hotfix behaviour of
//    "transient refresh failure keeps the session"),
//  * the multipart chat path (shared pooled client) keeps authenticating,
//    refreshing and retrying correctly,
//  * AiService uploads are bound to the session they started in,
//  * the WebSocket service forgets everything queued under an ended session.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/ai_service.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/services/websocket_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';

import 'support/test_jwt.dart';

enum _Refresh { ok, transient503, reject401 }

class _Server {
  final Set<String> validAccess = <String>{};
  /// Legacy session subject -> the public id the server really knows it as
  /// (reported by /auth/me and used for refreshed tokens).
  final Map<String, String> publicIdOf = <String, String>{};
  _Refresh refresh = _Refresh.ok;
  int refreshCalls = 0;
  int _n = 0;
  final List<Map<String, String?>> multipart = [];
  Future<void> Function()? gateProcessImages;

  http.Response _j(int code, Object body) => http.Response(
        json.encode(body),
        code,
        headers: {'content-type': 'application/json'},
      );

  String? _bearer(http.BaseRequest r) {
    final h = r.headers['Authorization'] ?? r.headers['authorization'];
    if (h == null || !h.startsWith('Bearer ')) return null;
    return h.substring(7);
  }

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    final token = _bearer(r);
    if (path.endsWith('/auth/refresh')) {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      switch (refresh) {
        case _Refresh.transient503:
          return _j(503, {'message': 'busy'});
        case _Refresh.reject401:
          return _j(401, {'message': 'expired'});
        case _Refresh.ok:
          final sub = testJwtSubject(token);
          if (sub == null) return _j(401, {'message': 'bad'});
          final acct = publicIdOf[sub] ?? sub;
          final access = testJwt(acct, nonce: 'r${++_n}');
          validAccess.add(access);
          return _j(200, {
            'access_token': access,
            'refresh_token': testJwt(acct, nonce: 'rr$_n', type: 'refresh'),
          });
      }
    }
    if (token == null || !validAccess.contains(token)) {
      return _j(401, {'message': 'unauthorized'});
    }
    final sub = testJwtSubject(token)!;
    final acct = publicIdOf[sub] ?? sub;
    if (path.endsWith('/auth/me')) {
      return _j(200, {'id': acct, 'first_name': acct});
    }
    if (path.endsWith('/ping')) return _j(200, {'ok': true, 'actor': acct});
    return _j(404, {'message': 'nf $path'});
  }

  Future<http.StreamedResponse> handleStreamed(http.BaseRequest r) async {
    if (r is http.MultipartRequest) {
      final token = _bearer(r);
      // Authorisation is decided when the request ARRIVES (like a real
      // server); the gate then only delays the response.
      final authorised = token != null && validAccess.contains(token);
      if (r.url.path.endsWith('/process-car-images')) {
        final gate = gateProcessImages;
        if (gate != null) await gate();
      }
      if (!authorised) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"message":"unauthorized"}')),
          401,
          headers: {'content-type': 'application/json'},
        );
      }
      // Drain the body: proves the file was really streamed.
      final bytes = await r.finalize().toBytes();
      multipart.add({
        'actor': testJwtSubject(token),
        'path': r.url.path,
        'idem': r.headers['Idempotency-Key'],
        'size': '${bytes.length}',
      });
      final body = r.url.path.endsWith('/process-car-images')
          ? {'job_ids': ['job1']}
          : {'success': true, 'message': {'id': 'm1'}};
      return http.StreamedResponse(
        Stream.value(utf8.encode(json.encode(body))),
        r.url.path.endsWith('/process-car-images') ? 202 : 201,
        headers: {'content-type': 'application/json'},
      );
    }
    final res = await handle(r as http.Request);
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
    );
  }
}

// ignore: library_private_types_in_public_api
late _Server srv;
int _loginN = 0;

/// Logs in as [acct]; [validNow] controls whether the issued access token is
/// accepted by the server (false = "expired", forcing the refresh path).
Future<void> login(String acct, {bool validNow = true}) async {
  final access = testJwt(acct, nonce: 'l${++_loginN}');
  if (validNow) srv.validAccess.add(access);
  await ApiService.setTokens(
    accessToken: access,
    refreshToken: testJwt(acct, nonce: 'lr$_loginN', type: 'refresh'),
  );
}

Future<void> logout() => ApiService.logout();

Future<XFile> tempFile(Directory dir, String name) async {
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(List<int>.filled(2048, 7));
  return XFile(f.path);
}

void main() {
  late Directory dir;

  setUp(() async {
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    srv = _Server();
    ApiService.testHttpClient = _Mock(srv);
    SharedPreferences.setMockInitialValues({});
    ApiService.debugResetSessionForTests();
    await ApiService.clearTokens();
    dir = await Directory.systemTemp.createTemp('acct_guard_');
  });
  tearDown(() async {
    ApiService.testHttpClient = null;
    await ApiService.clearTokens();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  group('ordinary token refresh is not an account/session change', () {
    test('401 -> refresh -> retry succeeds inside the same session', () async {
      await login('A', validNow: false);
      final epoch = ApiService.sessionEpoch;
      final before = ApiService.accessToken;

      final res = await ApiService.makeAuthenticatedRequest('GET', '/ping');

      expect(res['actor'], 'A');
      expect(srv.refreshCalls, 1);
      expect(ApiService.sessionEpoch, epoch,
          reason: 'a same-account rotation must not end the session');
      expect(ApiService.accessToken, isNot(before));
      expect(ApiService.currentAccountId, 'A');
      expect(ApiService.isAuthenticated, isTrue);
    });

    test('concurrent 401s share ONE refresh and all succeed', () async {
      await login('A', validNow: false);
      final results = await Future.wait([
        ApiService.makeAuthenticatedRequest('GET', '/ping'),
        ApiService.makeAuthenticatedRequest('GET', '/ping'),
        ApiService.makeAuthenticatedRequest('GET', '/ping'),
      ]);
      expect(results.map((r) => r['actor']), ['A', 'A', 'A']);
      expect(srv.refreshCalls, 1);
    });

    test('a request in flight while another request rotates the token still '
        'delivers its result', () async {
      await login('A', validNow: false);
      // Slow request + fast request that triggers the rotation meanwhile.
      final slow = ApiService.makeAuthenticatedRequest('GET', '/ping');
      final fast = ApiService.makeAuthenticatedRequest('GET', '/ping');
      final both = await Future.wait([slow, fast]);
      expect(both.every((r) => r['ok'] == true), isTrue);
    });

    test('transient refresh failure keeps the session (F-hotfix behaviour) '
        'and recovers', () async {
      await login('A', validNow: false);
      final epoch = ApiService.sessionEpoch;
      srv.refresh = _Refresh.transient503;

      await expectLater(
        ApiService.makeAuthenticatedRequest('GET', '/ping'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 503)),
      );
      expect(ApiService.isAuthenticated, isTrue, reason: 'tokens kept');
      expect(ApiService.sessionEpoch, epoch);
      expect(ApiService.lastRefreshWasTransient, isTrue);

      srv.refresh = _Refresh.ok;
      final res = await ApiService.makeAuthenticatedRequest('GET', '/ping');
      expect(res['actor'], 'A');
      expect(ApiService.sessionEpoch, epoch);
    });

    test('definitive refresh rejection ends the session', () async {
      await login('A', validNow: false);
      srv.refresh = _Refresh.reject401;
      await expectLater(
        ApiService.makeAuthenticatedRequest('GET', '/ping'),
        throwsA(isA<Object>()),
      );
      expect(ApiService.isAuthenticated, isFalse);
      expect(ApiService.currentAccountId, isNull);
    });

    test('profile load survives a same-account rotation', () async {
      // Real public ids are UUID-like (the hotfix's SessionIdentity requires
      // that shape), so use one here.
      const id = 'a1b2c3d4-0000-4000-8000-000000000001';
      await login(id, validNow: false);
      final auth = AuthService();
      await auth.refreshProfile();
      expect(auth.isAuthenticated, isTrue,
          reason: 'profile fetched after 401 -> refresh must be applied');
      expect(auth.currentUser?['id'], id);
      expect(ApiService.currentAccountId, id);
      await logout();
    });

    test('legacy numeric-subject session is not ended by the identity check '
        'and gains its owner on the first refresh', () async {
      const uuid = 'a1b2c3d4-0000-4000-8000-000000000042';
      srv.publicIdOf['42'] = uuid;
      await login('42');
      expect(ApiService.currentAccountId, isNull,
          reason: 'a numeric subject is not a public id: no private owner');

      final auth = AuthService();
      await auth.refreshProfile();
      expect(ApiService.isAuthenticated, isTrue,
          reason: 'legacy sessions must not be signed out');
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?['id'], uuid);

      // First refresh: the new token carries the public id.
      final epoch = ApiService.sessionEpoch;
      srv.validAccess.remove(ApiService.accessToken);
      await ApiService.makeAuthenticatedRequest('GET', '/ping');
      expect(ApiService.currentAccountId, uuid);
      expect(ApiService.sessionEpoch, epoch,
          reason: 'becoming identifiable is not a different session');
      await logout();
    });

    test('rotation that changes the account id is a session change', () async {
      await login('A');
      final epoch = ApiService.sessionEpoch;
      // A server (or tampering) answering A's refresh with B's token must not
      // be treated as ordinary rotation.
      srv.validAccess.add(testJwt('B', nonce: 'x'));
      final bToken = srv.validAccess.last;
      ApiService.testHttpClient = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return http.Response(
            json.encode({
              'access_token': bToken,
              'refresh_token': testJwt('B', nonce: 'xr', type: 'refresh'),
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"message":"unauthorized"}', 401);
      });
      try {
        await ApiService.makeAuthenticatedRequest('GET', '/ping');
      } catch (_) {}
      expect(ApiService.sessionEpoch, greaterThan(epoch));
    });
  });

  group('multipart chat path (shared pooled client)', () {
    test('authenticates, streams the file and carries the idempotency key',
        () async {
      await login('A');
      final f = await tempFile(dir, 'v.m4a');
      ApiService.testHttpClient = _StreamMock(srv);
      final res = await ApiService.sendChatAudio(
        conversationId: 'car_1',
        audioFile: f,
        idempotencyKey: 'idem-1',
      );
      expect(res['success'], true);
      expect(srv.multipart.single['actor'], 'A');
      expect(srv.multipart.single['idem'], 'idem-1');
      expect(int.parse(srv.multipart.single['size']!), greaterThan(2048));
    });

    test('401 -> refresh -> rebuilt retry succeeds as the same account',
        () async {
      await login('A', validNow: false);
      final epoch = ApiService.sessionEpoch;
      final f = await tempFile(dir, 'v.m4a');
      ApiService.testHttpClient = _StreamMock(srv);
      final res = await ApiService.sendChatAudio(
        conversationId: 'car_1',
        audioFile: f,
        idempotencyKey: 'idem-2',
      );
      expect(res['success'], true);
      expect(srv.refreshCalls, 1);
      expect(srv.multipart, hasLength(1),
          reason: 'only the authorised attempt reaches the handler body');
      expect(srv.multipart.single['actor'], 'A');
      expect(ApiService.sessionEpoch, epoch);
    });

    test('transient refresh failure surfaces as a retryable error and keeps '
        'the session', () async {
      await login('A', validNow: false);
      srv.refresh = _Refresh.transient503;
      final f = await tempFile(dir, 'v.m4a');
      ApiService.testHttpClient = _StreamMock(srv);
      await expectLater(
        ApiService.sendChatAudio(conversationId: 'car_1', audioFile: f),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 503)),
      );
      expect(ApiService.isAuthenticated, isTrue);
      expect(srv.multipart, isEmpty);
    });

    test('a dead keep-alive socket is recycled and the send retried once',
        () async {
      await login('A');
      final f = await tempFile(dir, 'v.m4a');
      var calls = 0;
      final inner = _StreamMock(srv);
      ApiService.testHttpClient = _FnClient((r) {
        calls++;
        if (calls == 1) {
          throw http.ClientException('Connection closed before full header '
              'was received');
        }
        return inner.send(r);
      });
      final res = await ApiService.sendChatAudio(
        conversationId: 'car_1',
        audioFile: f,
        idempotencyKey: 'idem-3',
      );
      expect(res['success'], true);
      expect(calls, 2);
      expect(srv.multipart.single['idem'], 'idem-3');
    });
  });

  group('AiService is bound to the session it started in', () {
    test('result of an upload that outlives its session is discarded',
        () async {
      await login('A');
      final f = await tempFile(dir, 'p.jpg');
      final release = Completer<void>();
      final arrived = Completer<void>();
      srv.gateProcessImages = () async {
        if (!arrived.isCompleted) arrived.complete();
        await release.future;
      };
      ApiService.testHttpClient = _StreamMock(srv);

      final pending = AiService.enqueueCarImagesAsync([f]);
      await arrived.future.timeout(const Duration(seconds: 20));
      await logout();
      await login('B');
      release.complete();

      expect(await pending, isNull,
          reason: "A's upload result must not reach B's session");
    });

    test('same upload inside an unchanged session still returns its jobs',
        () async {
      await login('A');
      final f = await tempFile(dir, 'p.jpg');
      ApiService.testHttpClient = _StreamMock(srv);
      expect(await AiService.enqueueCarImagesAsync([f]), ['job1']);
    });

    test('a same-account token rotation during the upload does not discard '
        'it', () async {
      await login('A');
      final f = await tempFile(dir, 'p.jpg');
      final release = Completer<void>();
      final arrived = Completer<void>();
      srv.gateProcessImages = () async {
        if (!arrived.isCompleted) arrived.complete();
        await release.future;
      };
      ApiService.testHttpClient = _StreamMock(srv);
      final pending = AiService.enqueueCarImagesAsync([f]);
      await arrived.future.timeout(const Duration(seconds: 20));
      // Rotation through the real refresh path while the upload is running
      // (the old token is rejected for NEW requests, so /ping must refresh).
      final epoch = ApiService.sessionEpoch;
      final inFlightToken = ApiService.accessToken;
      srv.validAccess.remove(inFlightToken);
      await ApiService.makeAuthenticatedRequest('GET', '/ping');
      expect(ApiService.accessToken, isNot(inFlightToken));
      expect(ApiService.sessionEpoch, epoch);
      release.complete();
      expect(await pending, ['job1']);
    });
  });

  group('logout bound to the session being signed out', () {
    test('a slow logout revocation does not sign out the account that logged '
        'in meanwhile', () async {
      await login('user_a_0001');
      final gate = Completer<void>();
      ApiService.testHttpClient = MockClient((r) async {
        if (r.url.path.endsWith('/auth/logout')) {
          await gate.future;
          return http.Response('{}', 200);
        }
        return srv.handle(r);
      });
      final loggingOut = ApiService.logout();
      await pumpEventQueue();
      await login('user_b_0001');
      gate.complete();
      await loggingOut;
      expect(ApiService.isAuthenticated, isTrue,
          reason: "B's session must survive A's slow logout");
      expect(ApiService.currentAccountId, 'user_b_0001');
    });

    test('an ordinary logout still clears the session', () async {
      await login('user_a_0001');
      await ApiService.logout();
      expect(ApiService.isAuthenticated, isFalse);
      expect(ApiService.currentAccountId, isNull);
    });
  });

  group('WebSocketService', () {
    test('events queued under one session are dropped when it ends',
        () async {
      await login('A');
      WebSocketService.sendMessage('typing_start', {'car_id': 'c1'});
      WebSocketService.sendMessage('typing_stop', {'car_id': 'c1'});
      expect(WebSocketService.debugPendingEmitCount, 2);
      await logout();
      expect(WebSocketService.debugPendingEmitCount, 0,
          reason: "A's queued emits must never be flushed on B's socket");
      WebSocketService.sendMessage('typing_start', {'car_id': 'c2'});
      expect(WebSocketService.debugPendingEmitCount, 1);
      await login('B');
      expect(WebSocketService.debugPendingEmitCount, 0);
    });

    test('same-account token rotation keeps the queue', () async {
      await login('A', validNow: false);
      WebSocketService.sendMessage('typing_start', {'car_id': 'c1'});
      await ApiService.makeAuthenticatedRequest('GET', '/ping'); // rotates
      expect(WebSocketService.debugPendingEmitCount, 1);
      WebSocketService.disconnect();
    });
  });
}

/// MockClient whose multipart sends are handled by [_Server.handleStreamed].
class _Mock extends MockClient {
  _Mock(_Server s) : super(s.handle);
}

class _StreamMock extends http.BaseClient {
  _StreamMock(this.s);
  final _Server s;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      s.handleStreamed(request);
}

class _FnClient extends http.BaseClient {
  _FnClient(this.fn);
  final Future<http.StreamedResponse> Function(http.BaseRequest) fn;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      fn(request);
}
