import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

/// Brightness for chat list + conversation only (not [ThemeProvider]).
class ChatUiThemeController extends ChangeNotifier {
  static const String _prefsKey = 'chat_ui_dark';

  bool _isDark = true;

  bool get isDark => _isDark;

  ThemeData get themeData =>
      _isDark ? AppThemes.darkTheme : AppThemes.lightTheme;

  ChatUiThemeController() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_prefsKey)) return;
      final v = prefs.getBool(_prefsKey);
      if (v != null && v != _isDark) {
        _isDark = v;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setDark(bool value) async {
    if (_isDark == value) return;
    _isDark = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, _isDark);
    } catch (_) {}
  }

  void toggle() {
    setDark(!_isDark);
  }
}
