import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/car_name_translations.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/config.dart';
import '../services/connectivity_service.dart';
import '../services/push_notification_service.dart'
    show PushNotificationService, firebaseMessagingBackgroundHandler;
import '../state/locale_controller.dart';
import '../features/saved_searches/saved_search_home_bridge.dart';
import '../features/sell/sell_pending_media_resume.dart';
import '../services/outgoing_chat_send_service.dart';
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

      // MI-03(A): wire the locale-change -> backend-sync hook once, early.
      // Kept as a callback (not a direct import) so LocaleController has
      // no dependency on networking/auth code -- see locale_controller.dart.
      LocaleController.onLocaleChanged = (code) =>
          AuthService().syncLocaleIfAuthenticated(code);

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
        // MI-03/U-01: `ErrorWidget.builder` itself gets no `BuildContext`,
        // so this defers the localized-string lookup to a `Builder`, which
        // *is* given a context once actually inserted into the live tree
        // (normally still under the app's `Localizations` ancestor, since
        // this replaces whatever widget failed to build). If a build error
        // happens above/at `MaterialApp` itself (e.g. inside `MyApp.build()`
        // before it returns `MaterialApp` -- see production_app.dart), that
        // context has no `Localizations` ancestor at all, and this is
        // realistically reachable (any provider/route-table constructor
        // throwing there does it). `_StartupCrashMessage` below handles that
        // case with the generated `lookupAppLocalizations` lookup + the
        // already-resolved app locale instead of a hardcoded literal.
        return const Material(
          color: Color(0xFFF7F7F8),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: _StartupCrashMessage(),
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

      // MT-11: also load the Arabic/Kurdish car brand/model display-name
      // pack (`CarNameTranslations`) before `runApp`, not just the app
      // locale above. Previously this only happened in the post-`runApp`
      // microtask below (`LocaleController.loadSavedLocale()`), which let
      // the Home feed's very first paint race the async JSON asset load:
      // cards rendered immediately (from disk/memory cache or the first
      // network response) with correct RTL/AppLocalizations strings
      // (locale was already applied above) but still-English brand/model
      // names, because `CarNameTranslations`'s ar/ku pack hadn't finished
      // loading yet -- and nothing rebuilds the feed once it does, until
      // some unrelated `setState` (e.g. pull-to-refresh) happens to fire
      // after the pack has since finished loading. Loading it here closes
      // that race the same way the locale-prefs read above already was
      // moved earlier for the identical reason. No-op / effectively
      // instant for `en` (see `CarNameTranslations.ensureLoadedForLocale`'s
      // early return for untranslated locales); `loadSavedLocale()` below
      // still runs afterward as a cheap, idempotent no-op (cache hit) --
      // kept in case the resolved locale ever legitimately changes between
      // this point and then.
      try {
        await CarNameTranslations.ensureLoadedForLocale(
          LocaleController.resolveCode(),
        );
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
        // Authentication starts immediately and is intentionally NOT
        // awaited here first: Firebase/FCM setup (which can sit behind a
        // native notification-permission dialog), connectivity checks, and
        // locale/asset loading have no bearing on whether the user is
        // logged in, so none of them may gate `/auth/me`. Protected pages
        // are gated by AuthService's own isLoading/isAuthenticated (see
        // AuthGuard + AuthService._initializeOnce), which now resolves as
        // soon as the profile fetch itself is decided — independent of the
        // unrelated startup work below.
        Future<void> initAuth() async {
          try {
            await AuthService().initialize();
          } catch (e, st) { logNonFatal(e, st); }
        }

        final authInit = initAuth();

        try {
          await PushNotificationService.initialize();
        } catch (e, st) { logNonFatal(e, st); }
        try {
          await ConnectivityService.instance.start();
        } catch (e, st) { logNonFatal(e, st); }
        // F-11: retry durable pending chat sends automatically once
        // connectivity returns (bounded — see OutgoingChatSendService).
        OutgoingChatSendService.instance.hookConnectivityRecovery();
        try {
          await LocaleController.loadSavedLocale();
        } catch (e, st) { logNonFatal(e, st); }

        // These two read auth/token state, so they still wait for the
        // authentication decision above — but that decision (and therefore
        // AuthGuard releasing) no longer waits for any of the unrelated
        // startup work this ran concurrently with.
        await authInit;
        // Finish media upload if the app was killed mid-submit.
        try {
          await SellPendingMediaResume.tryResume();
        } catch (e, st) { logNonFatal(e, st); }
        // F-11: resume any durable pending chat sends left over from a
        // prior app session (retryable REST-send failures only).
        try {
          await OutgoingChatSendService.instance.recoverPendingSends();
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

/// MI-03/U-01: separated out so the localized-string lookup only happens
/// once this is actually built with a real `BuildContext` (see
/// `ErrorWidget.builder` above for why a plain top-level string can't do
/// this directly).
///
/// `AppLocalizations.of(context)` returns null when there is no
/// `Localizations` ancestor -- realistically reachable here, since this
/// widget can end up as the very root of the tree (a build error inside
/// `MyApp.build()` itself, above `MaterialApp`). Rather than fall back to a
/// hardcoded English literal in that case, `lookupAppLocalizations`
/// (generated by `flutter gen-l10n`) resolves a full `AppLocalizations`
/// instance directly from a `Locale`, with no `BuildContext` needed, and
/// `LocaleController.resolveCode()` (already loaded from prefs before
/// `runApp()` -- see above) supplies that `Locale` -- so Arabic/Kurdish
/// users still see their own language even with no localization tree.
class _StartupCrashMessage extends StatelessWidget {
  const _StartupCrashMessage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ??
        lookupAppLocalizations(Locale(LocaleController.resolveCode()));
    return Text(
      l10n.somethingWentWrongRestart,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A)),
    );
  }
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
