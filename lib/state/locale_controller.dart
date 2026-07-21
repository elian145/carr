import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/car_name_translations.dart';

class LocaleController {
  static final ValueNotifier<Locale?> currentLocale = ValueNotifier<Locale?>(
    null,
  );

  static Future<void> loadSavedLocale() async {
    final sp = await SharedPreferences.getInstance();
    final code = sp.getString('app_locale');
    if (code != null && code.isNotEmpty) {
      await CarNameTranslations.ensureLoadedForLocale(code);
      currentLocale.value = Locale(code);
      return;
    }
    // Follow system language: warm pack for device locale when ar/ku.
    final deviceCode =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    await CarNameTranslations.ensureLoadedForLocale(deviceCode);
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
  }
}
