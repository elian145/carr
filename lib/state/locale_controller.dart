import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/car_name_translations.dart';

class LocaleController {
  /// MI-03/U-01: locales the app currently ships translations for. Kept in
  /// sync with `lib/app/production_app.dart`'s `supportedLocales` and the
  /// backend's `kk/localization.py::SUPPORTED_LOCALES`. `ckb` is tracked
  /// separately (U-07) and intentionally not included here.
  static const List<String> supportedCodes = ['en', 'ar', 'ku'];

  static final ValueNotifier<Locale?> currentLocale = ValueNotifier<Locale?>(
    null,
  );

  /// Effective locale code for the CURRENT session, without needing a
  /// `BuildContext`. Mirrors `production_app.dart`'s
  /// `localeResolutionCallback`: an explicit in-app selection wins,
  /// otherwise the device locale if supported, otherwise `en`. Used to send
  /// `Accept-Language` on every API request (see `api_http.dart`) so the
  /// backend can localize responses even before this value is persisted to
  /// `User.locale`.
  static String resolveCode() {
    final explicit = currentLocale.value?.languageCode;
    if (explicit != null && supportedCodes.contains(explicit)) {
      return explicit;
    }
    final device =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    if (supportedCodes.contains(device)) return device;
    return 'en';
  }

  /// MI-03(A): best-effort backend sync hook, wired up in `bootstrap.dart`
  /// to `AuthService().syncLocaleIfAuthenticated`. Deliberately a plain
  /// callback (not a direct import of `ApiService`/`AuthService`) so this
  /// low-level state class has no dependency on networking/auth code.
  /// `null` before wiring or in tests -- callers must treat it as optional.
  static Future<void> Function(String code)? onLocaleChanged;

  /// Apply persisted locale with no extra I/O. Call after SharedPreferences
  /// is already loaded so the first frame can use ar/ku instead of English.
  static void applyFromPrefs(SharedPreferences sp) {
    final code = sp.getString('app_locale');
    if (code != null && code.isNotEmpty) {
      currentLocale.value = Locale(code);
    }
  }

  static Future<void> loadSavedLocale() async {
    final sp = await SharedPreferences.getInstance();
    applyFromPrefs(sp);
    final code = currentLocale.value?.languageCode ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    await CarNameTranslations.ensureLoadedForLocale(code);
  }

  static Future<void> setLocale(Locale? locale) async {
    // Load JSON before notifying so the first rebuild can translate names.
    await CarNameTranslations.ensureLoadedForLocale(locale?.languageCode);
    currentLocale.value = locale;
    final sp = await SharedPreferences.getInstance();
    if (locale == null) {
      await sp.remove('app_locale');
      final deviceCode =
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      await CarNameTranslations.ensureLoadedForLocale(deviceCode);
    } else {
      await sp.setString('app_locale', locale.languageCode);
    }

    // MI-03(A): sync to the backend AFTER the local change is fully
    // applied/persisted above, and never let a sync failure undo or block
    // it -- `onLocaleChanged` is fire-and-forget and swallows its own
    // errors (see AuthService.syncLocaleIfAuthenticated).
    final callback = onLocaleChanged;
    if (callback != null) {
      unawaited(callback(resolveCode()));
    }
  }
}
