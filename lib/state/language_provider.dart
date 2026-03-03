import 'package:flutter/material.dart';

import 'locale_controller.dart';

/// Provides app locale for the widget tree. Delegates persistence to
/// [LocaleController] so bootstrap and existing code keep working.
/// Use with Provider so MaterialApp and language switcher stay in sync.
class LanguageProvider extends ChangeNotifier {
  LanguageProvider() {
    LocaleController.currentLocale.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() => notifyListeners();

  Locale? get locale => LocaleController.currentLocale.value;

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ar'),
    Locale('ku'),
  ];

  Future<void> setLocale(Locale? newLocale) async {
    await LocaleController.setLocale(newLocale);
    notifyListeners();
  }

  bool get isRtl =>
      locale != null &&
      (locale!.languageCode == 'ar' || locale!.languageCode == 'ku');

  @override
  void dispose() {
    LocaleController.currentLocale.removeListener(_onLocaleChanged);
    super.dispose();
  }
}
