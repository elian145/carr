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

/// Registers the device FCM token with the backend after auth is ready.
class PushNotificationService {
  static bool _messagingReady = false;
  static bool _refreshListenerAttached = false;
  static bool _openHandlersAttached = false;
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

  static void _attachOpenHandlers() {
    if (_openHandlersAttached) return;
    _openHandlersAttached = true;

    FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessageOpen);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleRemoteMessageOpen(message);
    });
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
  static Future<void> initialize() async {
    if (kSideloadBuild && Platform.isIOS) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: Firebase init failed: $e');
      }
      return;
    }

    if (_messagingReady) return;
    _messagingReady = true;

    try {
      await _ensureLocalNotifications();

      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool('push_enabled') ?? true)) return;

      if (Platform.isAndroid) {
        await Permission.notification.request();
      }

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            'PushNotificationService: notification permission not granted '
            '(${settings.authorizationStatus})',
          );
        }
        return;
      }

      if (Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
        await _waitForApnsToken(messaging);
      }

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await TokenStore.savePushToken(token);
        await sp.remove('push_token');
        await sp.remove('push_last_sync_error');
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            'PushNotificationService: FCM token cached (${token.length} chars)',
          );
        }
        if (ApiService.isAuthenticated) {
          await syncTokenWithBackend();
        }
      } else if (kDebugMode) {
        // ignore: avoid_print
        print(
          'PushNotificationService: no FCM token (emulator without Play Services?)',
        );
      }

      if (!_refreshListenerAttached) {
        _refreshListenerAttached = true;
        messaging.onTokenRefresh.listen((newToken) async {
          if (newToken.isEmpty) return;
          await TokenStore.savePushToken(newToken);
          await sp.remove('push_token');
          await syncTokenWithBackend();
        });
      }

      if (Platform.isIOS) {
        unawaited(_scheduleIosBackendSyncRetries());
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        await _showLocalNotification(message);
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            'FCM foreground: ${message.notification?.title ?? message.data}',
          );
        }
      });

      _attachOpenHandlers();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: setup failed: $e');
      }
    }
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
    try {
      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool('push_enabled') ?? true)) return;
      if (!ApiService.isAuthenticated) return;

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
          token = (await FirebaseMessaging.instance.getToken())?.trim() ?? '';
          if (token.isNotEmpty) {
            await TokenStore.savePushToken(token);
          }
        } catch (e, st) {
          logNonFatal(e, st, 'PushNotificationService.getToken');
        }
      }
      if (token.isEmpty) return;

      await ApiService.registerPushToken(token);
      await sp.setString('push_last_sync_ok', DateTime.now().toIso8601String());
      await sp.remove('push_last_sync_error');
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: token registered with backend');
      }
    } catch (e, st) {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('push_last_sync_error', e.toString());
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: backend register failed: $e');
      }
      logNonFatal(e, st, 'PushNotificationService.syncTokenWithBackend');
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

  static Future<void> setPushEnabled(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('push_enabled', enabled);
    if (!ApiService.isAuthenticated) return;
    try {
      await ApiService.registerPushToken(
        enabled ? (sp.getString('push_token') ?? '') : '',
        enabled: enabled,
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: setPushEnabled failed: $e');
      }
    }
  }
}
