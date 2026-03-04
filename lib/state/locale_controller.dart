import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController {
  static final ValueNotifier<Locale?> currentLocale = ValueNotifier<Locale?>(
    null,
  );

  static Future<void> loadSavedLocale() async {
    final sp = await SharedPreferences.getInstance();
    final code = sp.getString('app_locale');
    if (code != null && code.isNotEmpty) {
      currentLocale.value = Locale(code);
    }
  }

  static Future<void> setLocale(Locale? locale) async {
    currentLocale.value = locale;
    final sp = await SharedPreferences.getInstance();
    if (locale == null) {
      await sp.remove('app_locale');
    } else {
      await sp.setString('app_locale', locale.languageCode);
    }
  }
}
