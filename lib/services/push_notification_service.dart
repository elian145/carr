import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart' show ApiException, ApiService;
import 'config.dart';
import '../shared/auth/token_store.dart';
import '../shared/debug/app_log.dart';

const AndroidNotificationChannel _chatChannel = AndroidNotificationChannel(
  'carzo_chat',
  'Chat messages',
  description: 'New chat message alerts',
  importance: Importance.high,
);

const AndroidNotificationChannel _updatesChannel = AndroidNotificationChannel(
  'carzo_updates',
  'Account updates',
  description: 'Important account and dealership updates',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

bool _localNotificationsReady = false;

/// Background FCM handler (must be top-level).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

/// Notification permission as far as [PushNotificationService] cares.
enum PushPermissionStatus { granted, denied, notDetermined }

/// Thin seam over Firebase Messaging / OS permission / local notifications so
/// the push lifecycle (re-enable, denied-then-granted, token rotation, logout
/// cleanup) can be unit-tested without native plugins. Production always uses
/// the real implementation ([_FirebasePushPlatform]); tests inject a fake via
/// [PushNotificationService.debugPlatform].
abstract class PushMessagingPlatform {
  /// Initializes Firebase if needed. False when Firebase is unavailable.
  Future<bool> ensureFirebaseReady();
  Future<void> ensureLocalNotifications();

  /// Current permission WITHOUT prompting.
  Future<PushPermissionStatus> permissionStatus();

  /// Shows the OS permission prompt (no-op/denied when already decided).
  Future<PushPermissionStatus> requestPermission();

  /// Platform preparation required before [getToken] (iOS presentation
  /// options + waiting for the APNs token).
  Future<void> prepareForToken();
  Future<String?> getToken();

  /// Invalidates this installation's FCM token (a new one is minted on demand).
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;
  void attachForegroundDisplay();
  void attachOpenHandlers();

  /// Removes notifications already shown for the signed-out account.
  Future<void> cancelAllNotifications();
}

class _FirebasePushPlatform implements PushMessagingPlatform {
  static PushPermissionStatus _map(AuthorizationStatus s) {
    switch (s) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return PushPermissionStatus.granted;
      case AuthorizationStatus.denied:
        return PushPermissionStatus.denied;
      case AuthorizationStatus.notDetermined:
        return PushPermissionStatus.notDetermined;
    }
  }

  @override
  Future<bool> ensureFirebaseReady() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: Firebase init failed: $e');
      }
      return false;
    }
  }

  @override
  Future<void> ensureLocalNotifications() =>
      PushNotificationService._ensureLocalNotifications();

  @override
  Future<PushPermissionStatus> permissionStatus() async => _map(
    (await FirebaseMessaging.instance.getNotificationSettings())
        .authorizationStatus,
  );

  @override
  Future<PushPermissionStatus> requestPermission() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    return _map(settings.authorizationStatus);
  }

  @override
  Future<void> prepareForToken() async {
    if (!Platform.isIOS) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    await PushNotificationService._waitForApnsToken(messaging);
  }

  @override
  Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  @override
  Future<void> deleteToken() async {
    // No Firebase app => this process never obtained a token to invalidate.
    if (Firebase.apps.isEmpty) return;
    await FirebaseMessaging.instance.deleteToken();
  }

  @override
  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  void attachForegroundDisplay() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await PushNotificationService._showLocalNotification(message);
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          'FCM foreground: ${message.notification?.title ?? message.data}',
        );
      }
    });
  }

  @override
  void attachOpenHandlers() {
    FirebaseMessaging.onMessageOpenedApp.listen(
      PushNotificationService._handleRemoteMessageOpen,
    );
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        PushNotificationService._handleRemoteMessageOpen(message);
      }
    });
    // F-45: a local (foreground-shown) notification tapped while the app was
    // killed launches the app without invoking the tap callback; recover it.
    unawaited(PushNotificationService._handleLocalLaunchNotification());
  }

  @override
  Future<void> cancelAllNotifications() async {
    await PushNotificationService._ensureLocalNotifications();
    await _localNotifications.cancelAll();
  }
}

/// Registers the device FCM token with the backend after auth is ready.
class PushNotificationService {
  static bool _messagingReady = false;
  static bool _refreshListenerAttached = false;
  static bool _foregroundListenerAttached = false;
  static bool _openHandlersAttached = false;
  // F-38: notification permission may be granted AFTER the first (denied)
  // attempt, or push may be re-enabled later. The OS prompt is shown at most
  // once per process unless the user explicitly asks (toggle); later
  // re-checks only READ the current status.
  static bool _permissionRequested = false;
  static bool _recheckPending = false;
  static Future<void>? _setupInFlight;
  static Future<void>? _localCleanup;
  static PushMessagingPlatform _platform = _FirebasePushPlatform();

  /// Test seam: replaces the Firebase/OS layer (null restores the real one).
  @visibleForTesting
  static set debugPlatform(PushMessagingPlatform? platform) {
    _platform = platform ?? _FirebasePushPlatform();
  }

  /// Test hook: forget all per-process lifecycle state.
  @visibleForTesting
  static void debugResetForTests() {
    _messagingReady = false;
    _refreshListenerAttached = false;
    _foregroundListenerAttached = false;
    _openHandlersAttached = false;
    _permissionRequested = false;
    _recheckPending = false;
    _setupInFlight = null;
    _localCleanup = null;
    _platform = _FirebasePushPlatform();
  }

  @visibleForTesting
  static bool get debugMessagingReady => _messagingReady;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static Map<String, dynamic>? _pendingNavigation;

  /// Wire the app navigator so notification taps can open their destination.
  static void attachNavigator(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
    _consumePendingNavigation();
  }

  static void _consumePendingNavigation() {
    final pending = _pendingNavigation;
    if (pending == null) return;
    _pendingNavigation = null;
    _openFromNotificationData(pending);
  }

  // Item 9 (CarNet V1 batch): resolve the specific in-app destination for a
  // notification payload instead of always opening the generic `/chat` or
  // `/profile` shells. Reuses the existing named routes
  // (`/chat/conversation`, `/car_detail`) already wired in
  // `production_routes.dart` -- no new navigation infrastructure.
  //
  // Payload shapes handled (see `kk/socketio_handlers.py` for chat and
  // `kk/tasks/alert_tasks.py` for saved-search/price-drop; all FCM `data`
  // values arrive as strings -- see `kk/push.py::send_push`):
  //   - chat_message: {type: "chat_message", car_id, sender_id}
  //   - saved_search / price_drop: {car_id, ...} (no `type` key at all)
  //   - dealer_application: {type: "dealer_application"}
  //   - legacy/unknown payloads: missing or unrecognized fields
  static ({String route, Map<String, dynamic>? arguments})?
  _resolveNotificationDestination(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim();
    final carId = (data['car_id'] ?? '').toString().trim();
    final senderId = (data['sender_id'] ?? '').toString().trim();

    if (type == 'dealer_application') {
      return (route: '/profile', arguments: null);
    }

    final bool looksLikeChat =
        type == 'chat_message' || (type.isEmpty && senderId.isNotEmpty);
    if (looksLikeChat) {
      if (carId.isNotEmpty) {
        return (
          route: '/chat/conversation',
          arguments: {
            'carId': carId,
            if (senderId.isNotEmpty) 'receiverId': senderId,
          },
        );
      }
      // Chat notification with no usable car id (e.g. a stripped-down
      // local-notification payload) -- fall back to the chat list instead
      // of the conversation route's "missing id" error screen.
      return (route: '/chat', arguments: null);
    }

    if (carId.isNotEmpty) {
      // Saved-search / price-drop alerts (and any future car-id-bearing
      // notification type) open the specific listing. `/car_detail`
      // already renders its own "not found" state if the listing was
      // deleted/unpublished by the time the user taps through.
      return (route: '/car_detail', arguments: {'carId': carId});
    }

    if (type.isEmpty) {
      // Legacy payload predating per-type routing -- keep the old default.
      return (route: '/chat', arguments: null);
    }

    // Unrecognized type with no usable id: safest to do nothing rather
    // than guess a destination.
    return null;
  }

  /// Test-only hook onto the pure routing decision above -- exercised by
  /// `test/push_notification_deep_link_test.dart` without needing a real
  /// `NavigatorState`/widget tree.
  @visibleForTesting
  static ({String route, Map<String, dynamic>? arguments})?
  debugResolveNotificationDestination(Map<String, dynamic> data) =>
      _resolveNotificationDestination(data);

  static void _openFromNotificationData(Map<String, dynamic> data) {
    final destination = _resolveNotificationDestination(data);
    if (destination == null) return;
    final route = destination.route;
    final arguments = destination.arguments;

    void tryNavigate(int frame) {
      final nav = _navigatorKey?.currentState;
      if (nav == null) {
        _pendingNavigation = data;
        if (frame < 360) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => tryNavigate(frame + 1),
          );
        }
        return;
      }
      _pendingNavigation = null;
      try {
        nav.pushNamed(route, arguments: arguments);
      } catch (e, st) {
        // Never let a bad/unexpected payload crash the app on notification
        // tap -- fall back to the generic chat list, which always exists.
        logNonFatal(e, st, 'PushNotificationService._openFromNotificationData');
        if (route != '/chat') {
          nav.pushNamed('/chat');
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryNavigate(0));
  }

  static void _handleRemoteMessageOpen(RemoteMessage message) {
    _openFromNotificationData(message.data);
  }

  static void _handleLocalNotificationPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      _openFromNotificationData(const {'type': 'chat_message'});
      return;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _openFromNotificationData(
          Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
        );
        return;
      }
    } catch (e, st) {
      logNonFatal(e, st, 'PushNotificationService.localPayload');
    }
    _openFromNotificationData(const {'type': 'chat_message'});
  }

  /// F-45: cold-start handling for a tapped local notification.
  static Future<void> _handleLocalLaunchNotification() async {
    try {
      await _ensureLocalNotifications();
      handleLocalLaunchDetails(
        await _localNotifications.getNotificationAppLaunchDetails(),
      );
    } catch (e, st) {
      logNonFatal(e, st, 'PushNotificationService.localLaunch');
    }
  }

  /// Routes the notification that launched the app (if any). Public so it can
  /// be tested without the native plugin.
  @visibleForTesting
  static void handleLocalLaunchDetails(NotificationAppLaunchDetails? details) {
    if (details == null || !details.didNotificationLaunchApp) return;
    final response = details.notificationResponse;
    if (response == null) return;
    _handleLocalNotificationPayload(response.payload);
  }

  static void _attachOpenHandlers() {
    if (_openHandlersAttached) return;
    _openHandlersAttached = true;
    _platform.attachOpenHandlers();
  }

  static Future<void> _ensureLocalNotifications() async {
    if (_localNotificationsReady) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleLocalNotificationPayload(response.payload);
      },
    );
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_chatChannel);
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_updatesChannel);
    }
    _localNotificationsReady = true;
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _ensureLocalNotifications();
    final id = message.hashCode & 0x7fffffff;
    final payload = message.data.isNotEmpty
        ? jsonEncode(message.data)
        : jsonEncode(const {'type': 'chat_message'});
    final channel =
        (message.data['type'] ?? '').toString() == 'dealer_application'
        ? _updatesChannel
        : _chatChannel;
    await _localNotifications.show(
      id,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  /// Firebase + permission + local token cache. Safe to call multiple times.
  ///
  /// [userInitiated] (the Settings toggle) may show the OS permission prompt
  /// again; every other caller prompts at most once per process and afterwards
  /// only RE-READS the permission, so a user who denied first and granted later
  /// (system settings) gets handlers attached and the token registered without
  /// being nagged (F-38).
  static Future<void> initialize({bool userInitiated = false}) =>
      _runInitialize(userInitiated: userInitiated, syncAfter: true);

  static Future<void> _runInitialize({
    required bool userInitiated,
    required bool syncAfter,
  }) {
    if (kSideloadBuild && Platform.isIOS) return Future<void>.value();
    final inFlight = _setupInFlight;
    if (inFlight != null) return inFlight;
    final run = _initializeOnce(
      userInitiated: userInitiated,
      syncAfter: syncAfter,
    );
    _setupInFlight = run;
    return run.whenComplete(() {
      if (identical(_setupInFlight, run)) _setupInFlight = null;
    });
  }

  /// Whether notifications may be shown. Prompts at most once per process
  /// unless [userInitiated]; otherwise only reads the current status.
  static Future<bool> _ensurePermission({required bool userInitiated}) async {
    var status = await _platform.permissionStatus();
    if (status == PushPermissionStatus.granted) return true;
    if (userInitiated || !_permissionRequested) {
      _permissionRequested = true;
      status = await _platform.requestPermission();
    }
    return status == PushPermissionStatus.granted;
  }

  static Future<void> _initializeOnce({
    required bool userInitiated,
    required bool syncAfter,
  }) async {
    if (!await _platform.ensureFirebaseReady()) return;
    if (_messagingReady) return;

    try {
      await _platform.ensureLocalNotifications();

      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool('push_enabled') ?? true)) return;

      if (!await _ensurePermission(userInitiated: userInitiated)) {
        // Not "ready": a later initialize()/login sync re-checks the
        // permission (without prompting) and finishes the setup.
        _recheckPending = true;
        if (kDebugMode) {
          // ignore: avoid_print
          print('PushNotificationService: notification permission not granted');
        }
        return;
      }

      await _platform.prepareForToken();

      final token = (await _platform.getToken())?.trim() ?? '';
      if (token.isNotEmpty) {
        await TokenStore.savePushToken(token);
        await sp.remove('push_token');
        await sp.remove('push_last_sync_error');
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            'PushNotificationService: FCM token cached (${token.length} chars)',
          );
        }
      } else if (kDebugMode) {
        // ignore: avoid_print
        print(
          'PushNotificationService: no FCM token (emulator without Play Services?)',
        );
      }

      _attachListeners();
      _messagingReady = true;
      _recheckPending = false;

      if (token.isNotEmpty && syncAfter && ApiService.isAuthenticated) {
        await _syncTokenWithBackend();
      }

      if (Platform.isIOS) {
        unawaited(_scheduleIosBackendSyncRetries());
      }
    } catch (e) {
      _recheckPending = true;
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: setup failed: $e');
      }
    }
  }

  /// Idempotent: each handler is attached at most once per process.
  static void _attachListeners() {
    if (!_refreshListenerAttached) {
      _refreshListenerAttached = true;
      // Token rotation: persist the new token and register it for whoever is
      // signed in NOW (the server binds it to the caller's JWT only and
      // replaces that account's previous token). While signed out it is only
      // cached; the next login registers it.
      _platform.onTokenRefresh.listen((newToken) async {
        final t = newToken.trim();
        if (t.isEmpty) return;
        await TokenStore.savePushToken(t);
        final sp = await SharedPreferences.getInstance();
        await sp.remove('push_token');
        await syncTokenWithBackend();
      });
    }
    if (!_foregroundListenerAttached) {
      _foregroundListenerAttached = true;
      _platform.attachForegroundDisplay();
    }
    _attachOpenHandlers();
  }

  /// Wait until APNs token is available (TestFlight/production builds).
  static Future<void> _waitForApnsToken(FirebaseMessaging messaging) async {
    for (var attempt = 0; attempt < 15; attempt++) {
      final apns = await messaging.getAPNSToken();
      if (apns != null && apns.isNotEmpty) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  static Future<void> _scheduleIosBackendSyncRetries() async {
    for (final delay in [
      const Duration(seconds: 5),
      const Duration(seconds: 20),
      const Duration(seconds: 45),
    ]) {
      await Future<void>.delayed(delay);
      await syncTokenWithBackend();
    }
  }

  /// POST FCM token to `/api/users/push_token` when logged in.
  static Future<void> syncTokenWithBackend() async {
    // A logout/account-switch wipe of the previous account's device token must
    // finish first, or the OLD token could be registered for the new account.
    final cleanup = _localCleanup;
    if (cleanup != null) {
      try {
        await cleanup;
      } catch (_) {}
    }
    if (_recheckPending && !_messagingReady && ApiService.isAuthenticated) {
      // F-38: permission was denied (or setup failed) earlier; pick up a
      // later grant without prompting again.
      try {
        await _runInitialize(userInitiated: false, syncAfter: false);
      } catch (e, st) {
        logNonFatal(e, st, 'PushNotificationService.recheck');
      }
    }
    await _syncTokenWithBackend();
  }

  /// True when the token was registered with the backend.
  static Future<bool> _syncTokenWithBackend() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool('push_enabled') ?? true)) return false;
      if (!ApiService.isAuthenticated) return false;

      var token = (await TokenStore.readPushToken())?.trim() ?? '';
      if (token.isEmpty) {
        token = sp.getString('push_token')?.trim() ?? '';
        if (token.isNotEmpty) {
          await TokenStore.savePushToken(token);
          await sp.remove('push_token');
        }
      }
      if (token.isEmpty) {
        try {
          token = (await _platform.getToken())?.trim() ?? '';
          if (token.isNotEmpty) {
            await TokenStore.savePushToken(token);
          }
        } catch (e, st) {
          logNonFatal(e, st, 'PushNotificationService.getToken');
        }
      }
      if (token.isEmpty) return false;

      await ApiService.registerPushToken(token);
      await sp.setString('push_last_sync_ok', DateTime.now().toIso8601String());
      await sp.remove('push_last_sync_error');
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: token registered with backend');
      }
      return true;
    } catch (e, st) {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('push_last_sync_error', e.toString());
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: backend register failed: $e');
      }
      logNonFatal(e, st, 'PushNotificationService.syncTokenWithBackend');
      return false;
    }
  }

  /// Force FCM token refresh + backend registration (Settings troubleshooting).
  static Future<String> syncNowForDiagnostics() async {
    await initialize();
    await syncTokenWithBackend();
    try {
      final status = await ApiService.getPushStatus();
      final registered = status['registered'] == true;
      final serverReady = status['server_fcm_ready'] == true;
      if (!registered) {
        return 'Token not on server — log out and log in again after allowing notifications.';
      }
      if (!serverReady) {
        return 'Server cannot send push (FIREBASE_SERVICE_ACCOUNT missing or invalid on Render).';
      }
      return 'Push token registered on server.';
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: diagnostics failed: $e');
      }
      return 'Push diagnostics failed. Try again from Settings.';
    }
  }

  static Future<String> sendTestPush() async {
    try {
      final result = await ApiService.sendTestPush();
      return (result['message'] ?? 'Test sent').toString();
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Turns push on/off for the signed-in account. Returns false (and restores
  /// the previous preference) when the change could not be applied, so the
  /// caller can keep its switch truthful.
  static Future<bool> setPushEnabled(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    final previous = sp.getBool('push_enabled') ?? true;
    await sp.setBool('push_enabled', enabled);

    if (!enabled) {
      if (!ApiService.isAuthenticated) return true;
      try {
        await ApiService.registerPushToken('', enabled: false);
        return true;
      } catch (e, st) {
        await sp.setBool('push_enabled', previous);
        logNonFatal(e, st, 'PushNotificationService.setPushEnabled.disable');
        return false;
      }
    }

    // F-38: enabling used to POST `sp.getString('push_token')` -- a key that
    // was migrated into secure storage -- i.e. an empty token (HTTP 400,
    // swallowed). Resolve the token the same way every other path does
    // (secure store, else a fresh FCM token) and re-run the setup that a
    // disabled/denied start skipped (handlers + permission re-check).
    await initialize(userInitiated: true);
    if (!ApiService.isAuthenticated) return true; // registered at next login
    final ok = await _syncTokenWithBackend();
    if (!ok) await sp.setBool('push_enabled', previous);
    return ok;
  }

  /// Wipes everything push-related that belongs to the account that just
  /// signed out (explicit logout, expired/unrefreshable session, account
  /// deletion): the cached device token, push preferences/diagnostics,
  /// notifications already shown, and the FCM token itself -- so even when the
  /// server could not be told (expired session, offline) the old account's
  /// token is dead and the next account gets a fresh one. Never throws.
  static Future<void> clearLocalPushState() {
    final inFlight = _localCleanup;
    if (inFlight != null) return inFlight;
    final run = _clearLocalPushState();
    _localCleanup = run;
    return run.whenComplete(() {
      if (identical(_localCleanup, run)) _localCleanup = null;
    });
  }

  static Future<void> _clearLocalPushState() async {
    try {
      await TokenStore.savePushToken(null);
    } catch (e, st) {
      logNonFatal(e, st, 'PushNotificationService.clear.token');
    }
    try {
      final sp = await SharedPreferences.getInstance();
      for (final key in const [
        'push_token',
        'push_last_sync_ok',
        'push_last_sync_error',
        'push_enabled',
      ]) {
        await sp.remove(key);
      }
    } catch (e, st) {
      logNonFatal(e, st, 'PushNotificationService.clear.prefs');
    }
    try {
      await _platform.cancelAllNotifications();
    } catch (e, st) {
      logNonFatal(e, st, 'PushNotificationService.clear.notifications');
    }
    try {
      await _platform.deleteToken().timeout(const Duration(seconds: 10));
    } catch (e, st) {
      logNonFatal(e, st, 'PushNotificationService.clear.deleteToken');
    }
  }
}
