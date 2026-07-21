import 'package:shared_preferences/shared_preferences.dart';

/// First-run consumer onboarding (UX-04). Separate from dealer onboarding.
class FirstRunPrefs {
  FirstRunPrefs._();

  static const prefsKey = 'first_run_onboarding_v1_done';

  static Future<bool> isComplete() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool(prefsKey) == true;
    } catch (_) {
      // Fail-open: don't trap users if prefs are unreadable.
      return true;
    }
  }

  static Future<void> markComplete() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(prefsKey, true);
    } catch (_) {}
  }

  static Future<void> resetForTests() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(prefsKey);
  }
}
