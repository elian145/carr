import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/config.dart';
import '../services/push_notification_service.dart'
    show PushNotificationService, firebaseMessagingBackgroundHandler;
import '../state/locale_controller.dart';
import '../data/car_catalog_loader.dart';
import '../shared/debug/app_log.dart';

const String _apiBaseOverrideKey = 'api_base_override';

Future<void> bootstrapAndRun(Widget app) async {
  final dsn = kSentryDsn.trim();
  if (dsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        options.environment = kReleaseMode ? 'production' : 'development';
        options.tracesSampleRate = 0.0;
      },
      appRunner: () => _runZonedApp(app),
    );
    return;
  }
  _runZonedApp(app);
}

void _runZonedApp(Widget app) {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      if (!kSideloadBuild || !Platform.isIOS) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      }

      FlutterError.onError = (FlutterErrorDetails details) async {
        await _captureStartupError(details.exception, details.stack);
        FlutterError.presentError(details);
      };

      // Load runtime API override early so first screen uses it.
      try {
        final sp = await SharedPreferences.getInstance();
        final override = sp.getString(_apiBaseOverrideKey);
        setRuntimeApiBaseOverride(override);
      } catch (e, st) { logNonFatal(e, st); }

      // Minimal pre-run init only (fast): load tokens if available.
      try {
        await ApiService.initializeTokens();
      } catch (e, st) { logNonFatal(e, st); }

      // Drop orphaned one-time saved-search keys if the app was killed before Home mounted.
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.remove('home_apply_filters_once_v1');
        await sp.remove('home_pending_saved_search_fetch_v1');
      } catch (e, st) { logNonFatal(e, st); }

      runApp(app);

      // Defer heavy initializations to post-frame to avoid blocking first paint.
      Future.microtask(() async {
        try {
          await CarCatalogLoader.ensureLoaded();
        } catch (e, st) { logNonFatal(e, st); }
        try {
          await PushNotificationService.initialize();
        } catch (e, st) { logNonFatal(e, st); }
        try {
          await LocaleController.loadSavedLocale();
        } catch (e, st) { logNonFatal(e, st); }
        try {
          await AuthService().initialize();
        } catch (e, st) { logNonFatal(e, st); }
        // Auth must finish before syncing FCM token to the backend.
        try {
          await PushNotificationService.syncTokenWithBackend();
        } catch (e, st) { logNonFatal(e, st); }
      });
    },
    (error, stack) async {
      await _captureStartupError(error, stack);
      if (kDebugMode) {
        // ignore: avoid_print
        print('bootstrap error: $error');
      }
    },
  );
}

Future<void> _captureStartupError(Object error, StackTrace? stack) async {
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('last_startup_error', error.toString());
  } catch (e, st) { logNonFatal(e, st); }

  if (kSentryDsn.trim().isEmpty) return;
  try {
    await Sentry.captureException(error, stackTrace: stack);
  } catch (e, st) { logNonFatal(e, st); }
}
