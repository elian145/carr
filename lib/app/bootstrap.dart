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
import '../services/connectivity_service.dart';
import '../services/push_notification_service.dart'
    show PushNotificationService, firebaseMessagingBackgroundHandler;
import '../state/locale_controller.dart';
import '../features/saved_searches/saved_search_home_bridge.dart';
import '../features/sell/sell_pending_media_resume.dart';
import '../shared/debug/app_log.dart';
import '../shared/debug/expected_client_noise.dart';
import '../shared/ui/device_performance.dart';
import '../shared/ui/system_display_lock.dart';

const String _apiBaseOverrideKey = 'api_base_override';

Future<void> bootstrapAndRun(Widget app) async {
  final dsn = kSentryDsn.trim();
  if (dsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        options.environment = kReleaseMode ? 'production' : 'development';
        options.tracesSampleRate = 0.0;
        options.beforeSend = (event, hint) {
          final throwable = event.throwable;
          if (throwable != null && isExpectedClientNoise(throwable)) {
            return null;
          }
          final exceptions = event.exceptions;
          if (exceptions != null) {
            for (final ex in exceptions) {
              final value = ex.value;
              if (value != null && isExpectedClientNoise(value)) {
                return null;
              }
            }
          }
          return event;
        };
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
        if (isExpectedClientNoise(details.exception)) return;
        await _captureStartupError(details.exception, details.stack);
        FlutterError.presentError(details);
      };

      ErrorWidget.builder = (FlutterErrorDetails details) {
        if (kDebugMode) {
          return ErrorWidget(details.exception);
        }
        return const Material(
          color: Color(0xFFF7F7F8),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Something went wrong. Please restart the app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Color(0xFF1A1A1A)),
              ),
            ),
          ),
        );
      };

      // Load runtime API override and saved locale early so the first frame
      // uses them. Deferred locale load flashed English (and LTR) for ar/ku.
      try {
        final sp = await SharedPreferences.getInstance();
        final override = sp.getString(_apiBaseOverrideKey);
        setRuntimeApiBaseOverride(override);
        LocaleController.applyFromPrefs(sp);
      } catch (e, st) { logNonFatal(e, st); }

      // Minimal pre-run init only (fast): load tokens if available.
      try {
        await ApiService.initializeTokens();
      } catch (e, st) { logNonFatal(e, st); }

      // Drop orphaned one-time saved-search keys if the app was killed before Home mounted.
      try {
        await SavedSearchHomeBridge.clearOrphanedStartupKeys();
      } catch (e, st) { logNonFatal(e, st); }

      // Brand/model catalog loads lazily on home/sell (see CarCatalogLoader.ensureLoaded).
      // Embedded brands cover the UI until models load — do not block cold start.

      await SystemDisplayLock.init();
      DevicePerformance.configureImageCache();
      runApp(app);

      // Defer heavy initializations to post-frame to avoid blocking first paint.
      Future.microtask(() async {
        try {
          await PushNotificationService.initialize();
        } catch (e, st) { logNonFatal(e, st); }
        try {
          await ConnectivityService.instance.start();
        } catch (e, st) { logNonFatal(e, st); }
        try {
          await LocaleController.loadSavedLocale();
        } catch (e, st) { logNonFatal(e, st); }
        try {
          await AuthService().initialize();
        } catch (e, st) { logNonFatal(e, st); }
        // Finish media upload if the app was killed mid-submit.
        try {
          await SellPendingMediaResume.tryResume();
        } catch (e, st) { logNonFatal(e, st); }
        // Auth must finish before syncing FCM token to the backend.
        try {
          await PushNotificationService.syncTokenWithBackend();
        } catch (e, st) { logNonFatal(e, st); }
      });
    },
    (error, stack) async {
      if (isExpectedClientNoise(error)) return;
      await _captureStartupError(error, stack);
      if (kDebugMode) {
        // ignore: avoid_print
        print('bootstrap error: $error');
      }
    },
  );
}

Future<void> _captureStartupError(Object error, StackTrace? stack) async {
  if (isExpectedClientNoise(error)) return;
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('last_startup_error', error.toString());
  } catch (e, st) { logNonFatal(e, st); }

  if (kSentryDsn.trim().isEmpty) return;
  try {
    await Sentry.captureException(error, stackTrace: stack);
  } catch (e, st) { logNonFatal(e, st); }
}
