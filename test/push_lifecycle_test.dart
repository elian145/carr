// Regression tests for F-38 (push registration lifecycle) -- the client half of
// F-06 (a device push token must never stay associated with another account).
//
// Covered, with a fake Firebase/OS layer ([PushMessagingPlatform]) and a
// [MockClient] (no native plugins, no network):
//   * re-enabling push reads the SAME store the token is written to (it used
//     to POST an empty token read from a migrated-away SharedPreferences key)
//     and surfaces failures instead of swallowing them;
//   * notification permission denied first, granted later: handlers get
//     attached and the token registered without prompting again;
//   * FCM token rotation registers the new token for the CURRENT account only;
//   * logout / expired-session logout / unrefreshable session always wipe the
//     local push state even when the server call fails or returns 401, and an
//     expired access token is renewed with the refresh token so the server can
//     still release the account's token;
//   * account switch / re-login never re-registers the previous account's
//     token.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/push_notification_service.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/debug/app_log.dart';

class FakePushPlatform implements PushMessagingPlatform {
  bool firebaseReady = true;
  PushPermissionStatus status = PushPermissionStatus.granted;

  /// What the OS answers when the permission prompt is shown.
  PushPermissionStatus statusAfterPrompt = PushPermissionStatus.denied;
  int generation = 1;
  bool tokenAvailable = true;
  bool failDelete = false;

  /// When set, [deleteToken] waits for it (simulates a slow Firebase call).
  Completer<void>? deleteGate;

  int requestCount = 0;
  int deleteCount = 0;
  int cancelAllCount = 0;
  int foregroundAttachCount = 0;
  int openAttachCount = 0;
  final refresh = StreamController<String>.broadcast();

  String get token => 'fcm-$generation';

  @override
  Future<bool> ensureFirebaseReady() async => firebaseReady;

  @override
  Future<void> ensureLocalNotifications() async {}

  @override
  Future<PushPermissionStatus> permissionStatus() async => status;

  @override
  Future<PushPermissionStatus> requestPermission() async {
    requestCount++;
    status = statusAfterPrompt;
    return status;
  }

  @override
  Future<void> prepareForToken() async {}

  @override
  Future<String?> getToken() async => tokenAvailable ? token : null;

  @override
  Future<void> deleteToken() async {
    deleteCount++;
    final gate = deleteGate;
    if (gate != null) await gate.future;
    if (failDelete) throw StateError('deleteToken failed');
    generation++;
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  void attachForegroundDisplay() => foregroundAttachCount++;

  @override
  void attachOpenHandlers() => openAttachCount++;

  @override
  Future<void> cancelAllNotifications() async => cancelAllCount++;
}

class _Req {
  _Req(this.method, this.path, this.auth, this.body);
  final String method;
  final String path;
  final String? auth;
  final Map<String, dynamic> body;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePushPlatform platform;
  late List<_Req> requests;

  http.Response jsonResponse(int status, Object body) => http.Response(
    json.encode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  /// Installs a MockClient that records every request and answers through
  /// [respond] (default: 200 for everything).
  void useServer([http.Response Function(_Req req)? respond]) {
    ApiService.testHttpClient = MockClient((request) async {
      Map<String, dynamic> body = const {};
      if (request.body.isNotEmpty) {
        final decoded = json.decode(request.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      }
      final req = _Req(
        request.method,
        request.url.path,
        request.headers['Authorization'],
        body,
      );
      requests.add(req);
      return (respond ?? (_) => jsonResponse(200, {'message': 'ok'}))(req);
    });
  }

  Iterable<_Req> pushPosts() =>
      requests.where((r) => r.path == '/api/users/push_token');

  Future<void> pump() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> signInAs(String name) => ApiService.setTokens(
    accessToken: 'access_$name',
    refreshToken: 'refresh_$name',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugLogNonFatalOverride = (error, stackTrace, context) {};
    TokenStore.testMode = true;
    TokenStore.resetForTests();
    AuthService().resetTestSession();
    await ApiService.clearTokens();
    requests = [];
    PushNotificationService.debugResetForTests();
    platform = FakePushPlatform();
    PushNotificationService.debugPlatform = platform;
    useServer();
  });

  tearDown(() async {
    await ApiService.clearTokens();
    await pump();
    debugLogNonFatalOverride = null;
    ApiService.testHttpClient = null;
    PushNotificationService.debugResetForTests();
    AuthService().resetTestSession();
    TokenStore.resetForTests();
    TokenStore.testMode = false;
  });

  group('F-38.1 re-enabling push', () {
    test('registers the token from the secure store, not the legacy prefs key',
        () async {
      platform.firebaseReady = false; // isolate the token-resolution path
      SharedPreferences.setMockInitialValues({'push_enabled': false});
      await TokenStore.savePushToken('secure-store-token');
      await signInAs('A');

      final ok = await PushNotificationService.setPushEnabled(true);

      expect(ok, isTrue);
      final posts = pushPosts().toList();
      expect(posts, hasLength(1));
      expect(posts.single.body, {'token': 'secure-store-token'});
      expect(posts.single.auth, 'Bearer access_A');
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('push_enabled'), isTrue);
    });

    test('falls back to a fresh FCM token when the store is empty', () async {
      SharedPreferences.setMockInitialValues({'push_enabled': false});
      await signInAs('A');

      final ok = await PushNotificationService.setPushEnabled(true);

      expect(ok, isTrue);
      expect(pushPosts().map((r) => r.body['token']), everyElement('fcm-1'));
      expect(pushPosts(), isNotEmpty);
      expect(await TokenStore.readPushToken(), 'fcm-1');
    });

    test('never POSTs an empty token', () async {
      platform.tokenAvailable = false; // no store entry, FCM yields nothing
      SharedPreferences.setMockInitialValues({'push_enabled': false});
      await signInAs('A');

      final ok = await PushNotificationService.setPushEnabled(true);

      expect(ok, isFalse);
      expect(pushPosts(), isEmpty);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('push_enabled'), isFalse);
    });

    test('a failing registration is surfaced and the preference restored',
        () async {
      SharedPreferences.setMockInitialValues({'push_enabled': false});
      await TokenStore.savePushToken('tok');
      await signInAs('A');
      useServer((req) => jsonResponse(500, {'message': 'boom'}));

      final ok = await PushNotificationService.setPushEnabled(true);

      expect(ok, isFalse);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('push_enabled'), isFalse);
      expect(sp.getString('push_last_sync_error'), contains('boom'));
    });

    test('disabling clears the server token; a failure keeps the switch honest',
        () async {
      await signInAs('A');
      expect(await PushNotificationService.setPushEnabled(false), isTrue);
      expect(pushPosts().single.body, {'enabled': false});

      // Server down while turning push off again: the switch must stay on.
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('push_enabled', true);
      useServer((req) => jsonResponse(500, {'message': 'boom'}));
      expect(await PushNotificationService.setPushEnabled(false), isFalse);
      expect(sp.getBool('push_enabled'), isTrue);
    });

    test('re-enabling re-runs the setup that a disabled start skipped',
        () async {
      SharedPreferences.setMockInitialValues({'push_enabled': false});
      platform.status = PushPermissionStatus.granted;
      await PushNotificationService.initialize();
      expect(PushNotificationService.debugMessagingReady, isFalse);
      expect(platform.foregroundAttachCount, 0);

      await PushNotificationService.setPushEnabled(true);

      expect(PushNotificationService.debugMessagingReady, isTrue);
      expect(platform.foregroundAttachCount, 1);
      expect(platform.openAttachCount, 1);
    });
  });

  group('F-38.3 permission denied first, granted later', () {
    test('handlers attach after a later grant, with no repeated prompt',
        () async {
      platform.status = PushPermissionStatus.notDetermined;
      platform.statusAfterPrompt = PushPermissionStatus.denied;
      await signInAs('A');

      await PushNotificationService.initialize();
      expect(platform.requestCount, 1);
      expect(PushNotificationService.debugMessagingReady, isFalse);
      expect(platform.foregroundAttachCount, 0);
      expect(platform.openAttachCount, 0);

      // Still denied: later calls only re-read the status, never prompt.
      await PushNotificationService.initialize();
      await PushNotificationService.syncTokenWithBackend();
      expect(platform.requestCount, 1);
      expect(platform.foregroundAttachCount, 0);

      // The user grants the permission in system settings.
      platform.status = PushPermissionStatus.granted;
      await PushNotificationService.syncTokenWithBackend();

      expect(platform.requestCount, 1);
      expect(PushNotificationService.debugMessagingReady, isTrue);
      expect(platform.foregroundAttachCount, 1);
      expect(platform.openAttachCount, 1);
      expect(pushPosts().last.body, {'token': 'fcm-1'});

      // Idempotent: nothing attaches twice.
      await PushNotificationService.syncTokenWithBackend();
      await PushNotificationService.initialize();
      expect(platform.foregroundAttachCount, 1);
      expect(platform.openAttachCount, 1);
    });

    test('an explicit user action (Settings toggle) may prompt again', () async {
      platform.status = PushPermissionStatus.notDetermined;
      platform.statusAfterPrompt = PushPermissionStatus.denied;
      await PushNotificationService.initialize();
      expect(platform.requestCount, 1);

      platform.statusAfterPrompt = PushPermissionStatus.granted;
      await PushNotificationService.setPushEnabled(true);

      expect(platform.requestCount, 2);
      expect(PushNotificationService.debugMessagingReady, isTrue);
    });
  });

  group('token rotation (onTokenRefresh)', () {
    test('registers the new token for the CURRENT account only', () async {
      await PushNotificationService.initialize();
      await signInAs('A');

      platform.refresh.add('rot-1');
      await pump();
      expect(pushPosts().last.body, {'token': 'rot-1'});
      expect(pushPosts().last.auth, 'Bearer access_A');

      // Account switch without a logout in between.
      await signInAs('B');
      platform.refresh.add('rot-2');
      await pump();
      expect(pushPosts().last.body, {'token': 'rot-2'});
      expect(pushPosts().last.auth, 'Bearer access_B');
      expect(
        pushPosts().where((r) => r.body['token'] == 'rot-2').every(
          (r) => r.auth == 'Bearer access_B',
        ),
        isTrue,
      );

      // Signed out: cached for the next login, never sent anonymously.
      await ApiService.clearTokens();
      final before = pushPosts().length;
      platform.refresh.add('rot-3');
      await pump();
      expect(pushPosts().length, before);
      expect(await TokenStore.readPushToken(), 'rot-3');

      await signInAs('B');
      await PushNotificationService.syncTokenWithBackend();
      expect(pushPosts().last.body, {'token': 'rot-3'});
      expect(pushPosts().last.auth, 'Bearer access_B');
    });

    test('blank rotations are ignored', () async {
      await PushNotificationService.initialize();
      await signInAs('A');
      final before = pushPosts().length;
      platform.refresh.add('   ');
      await pump();
      expect(pushPosts().length, before);
    });
  });

  group('logout / expired session / account switch', () {
    Future<void> signInWithPushState() async {
      SharedPreferences.setMockInitialValues({
        'push_enabled': true,
        'push_last_sync_ok': 'yesterday',
        'push_last_sync_error': 'old',
      });
      await AuthService().adoptTestSession();
      await TokenStore.savePushToken('fcm-1');
    }

    Future<void> expectLocalPushStateWiped() async {
      await pump();
      expect(await TokenStore.readPushToken(), isNull);
      expect(platform.deleteCount, 1);
      expect(platform.cancelAllCount, 1);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('push_last_sync_ok'), isNull);
      expect(sp.getString('push_last_sync_error'), isNull);
      expect(ApiService.isAuthenticated, isFalse);
    }

    test('logout wipes local push state when the server logout fails (500)',
        () async {
      await signInWithPushState();
      useServer((req) => jsonResponse(500, {'message': 'down'}));

      await AuthService().logout();

      await expectLocalPushStateWiped();
    });

    test('logout wipes local push state when offline', () async {
      await signInWithPushState();
      ApiService.testHttpClient = MockClient(
        (request) async => throw const SocketException('offline'),
      );

      await AuthService().logout();

      await expectLocalPushStateWiped();
    });

    test('a failing FCM deleteToken never breaks logout or the rest of cleanup',
        () async {
      await signInWithPushState();
      platform.failDelete = true;

      await AuthService().logout();

      await expectLocalPushStateWiped();
    });

    test('expired access token: refresh, then logout with the NEW tokens',
        () async {
      await signInWithPushState();
      useServer((req) {
        if (req.path == '/api/auth/logout' &&
            req.auth == 'Bearer test_access_token') {
          return jsonResponse(401, {'message': 'Token has expired'});
        }
        if (req.path == '/api/auth/refresh') {
          return jsonResponse(200, {
            'access_token': 'access_new',
            'refresh_token': 'refresh_new',
          });
        }
        return jsonResponse(200, {'message': 'Logout successful'});
      });

      await AuthService().logout();

      final calls = requests.map((r) => '${r.path} ${r.auth}').toList();
      expect(calls, [
        '/api/auth/logout Bearer test_access_token',
        '/api/auth/refresh Bearer test_refresh_token',
        '/api/auth/logout Bearer access_new',
      ]);
      // The server is asked to revoke the ROTATED refresh token.
      expect(requests.last.body['refresh_token'], 'refresh_new');
      await expectLocalPushStateWiped();
    });

    test('dead refresh token: no further server calls, local state still wiped',
        () async {
      await signInWithPushState();
      useServer((req) => jsonResponse(401, {'message': 'expired'}));

      await AuthService().logout();

      expect(requests.map((r) => r.path), [
        '/api/auth/logout',
        '/api/auth/refresh',
      ]);
      await expectLocalPushStateWiped();
    });

    test('transient refresh failure: logout still completes locally', () async {
      await signInWithPushState();
      useServer((req) {
        if (req.path == '/api/auth/refresh') {
          return jsonResponse(503, {'message': 'busy'});
        }
        return jsonResponse(401, {'message': 'expired'});
      });

      await AuthService().logout();

      expect(requests.where((r) => r.path == '/api/auth/logout'), hasLength(1));
      await expectLocalPushStateWiped();
    });

    test('a session rejected out-of-band (401, unrefreshable) wipes push state',
        () async {
      await signInWithPushState();

      // What ApiService does when a request 401s and the refresh fails.
      await ApiService.clearTokens();

      await expectLocalPushStateWiped();
    });

    test('a guest never churns the FCM token or the shown notifications',
        () async {
      await ApiService.clearTokens();
      await AuthService().logout();
      await pump();
      expect(platform.deleteCount, 0);
      expect(platform.cancelAllCount, 0);
    });

    test('logout then login as another account registers a FRESH token only',
        () async {
      await PushNotificationService.initialize();
      await AuthService().adoptTestSession(); // signed in as "test"
      await PushNotificationService.syncTokenWithBackend();
      expect(pushPosts().last.body, {'token': 'fcm-1'});
      expect(pushPosts().last.auth, 'Bearer test_access_token');

      // Slow Firebase deleteToken: the next account must wait for it.
      platform.deleteGate = Completer<void>();
      await AuthService().logout();
      await signInAs('B');
      final sync = PushNotificationService.syncTokenWithBackend();
      await pump();
      final postsBeforeCleanup = pushPosts().length;
      expect(
        pushPosts().skip(1).where((r) => r.body['token'] == 'fcm-1'),
        isEmpty,
      );

      platform.deleteGate!.complete();
      await sync;

      expect(pushPosts().length, postsBeforeCleanup + 1);
      expect(pushPosts().last.body, {'token': 'fcm-2'});
      expect(pushPosts().last.auth, 'Bearer access_B');
      expect(
        pushPosts().skip(1).where((r) => r.body['token'] == 'fcm-1'),
        isEmpty,
      );
    });

    test('account switch without logout re-registers the device token for the '
        'new account (server de-duplicates it away from the old one)',
        () async {
      await PushNotificationService.initialize();
      await signInAs('A');
      await PushNotificationService.syncTokenWithBackend();
      await signInAs('B');
      await PushNotificationService.syncTokenWithBackend();

      final posts = pushPosts().toList();
      expect(posts.map((r) => r.auth), [
        'Bearer access_A',
        'Bearer access_B',
      ]);
      expect(posts.map((r) => r.body['token']).toSet(), {'fcm-1'});
    });
  });
}
