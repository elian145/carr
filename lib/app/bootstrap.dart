import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/config.dart';
import '../services/push_notification_service.dart'
    show PushNotificationService, firebaseMessagingBackgroundHandler;
import '../state/locale_controller.dart';

const String _apiBaseOverrideKey = 'api_base_override';

Future<void> bootstrapAndRun(Widget app) async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      if (!kSideloadBuild || !Platform.isIOS) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      }

      FlutterError.onError = (FlutterErrorDetails details) async {
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.setString('last_startup_error', details.exceptionAsString());
        } catch (_) {}
        FlutterError.presentError(details);
      };

      // Load runtime API override early so first screen uses it.
      try {
        final sp = await SharedPreferences.getInstance();
        final override = sp.getString(_apiBaseOverrideKey);
        setRuntimeApiBaseOverride(override);
      } catch (_) {}

      // Minimal pre-run init only (fast): load tokens if available.
      try {
        await ApiService.initializeTokens();
      } catch (_) {}

      // Drop orphaned one-time saved-search keys if the app was killed before Home mounted.
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.remove('home_apply_filters_once_v1');
        await sp.remove('home_pending_saved_search_fetch_v1');
      } catch (_) {}

      runApp(app);

      // Defer heavy initializations to post-frame to avoid blocking first paint.
      Future.microtask(() async {
        try {
          await PushNotificationService.initialize();
        } catch (_) {}
        try {
          await LocaleController.loadSavedLocale();
        } catch (_) {}
        try {
          await AuthService().initialize();
        } catch (_) {}
        // Auth must finish before syncing FCM token to the backend.
        try {
          await PushNotificationService.syncTokenWithBackend();
        } catch (_) {}
      });
    },
    (error, stack) async {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('last_startup_error', error.toString());
      } catch (_) {}
      if (kDebugMode) {
        // ignore: avoid_print
        print('bootstrap error: $error');
      }
    },
  );
}
