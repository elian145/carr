import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'config.dart';

/// Registers the device FCM token with the backend after auth is ready.
class PushNotificationService {
  static bool _messagingReady = false;
  static bool _refreshListenerAttached = false;

  /// Firebase + permission + local token cache. Safe to call multiple times.
  static Future<void> initialize() async {
    if (kSideloadBuild && Platform.isIOS) return;

    try {
      await Firebase.initializeApp();
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
        await sp.setString('push_token', token);
        if (kDebugMode) {
          // ignore: avoid_print
          print('PushNotificationService: FCM token cached (${token.length} chars)');
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
          await sp.setString('push_token', newToken);
          await syncTokenWithBackend();
        });
      }

      // iOS often links APNs to FCM after the first getToken(); retry backend sync.
      if (Platform.isIOS) {
        unawaited(_scheduleIosBackendSyncRetries());
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            'FCM foreground: ${message.notification?.title ?? message.data}',
          );
        }
      });
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
    for (final delay in [const Duration(seconds: 5), const Duration(seconds: 20)]) {
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

      var token = sp.getString('push_token')?.trim() ?? '';
      if (token.isEmpty) {
        try {
          token = (await FirebaseMessaging.instance.getToken())?.trim() ?? '';
          if (token.isNotEmpty) {
            await sp.setString('push_token', token);
          }
        } catch (_) {}
      }
      if (token.isEmpty) return;

      await ApiService.registerPushToken(token);
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: token registered with backend');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('PushNotificationService: backend register failed: $e');
      }
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
