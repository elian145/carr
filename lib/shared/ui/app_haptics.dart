import 'package:flutter/services.dart';

/// Centralized haptic helpers for key user actions (L-02).
///
/// Safe no-ops when the platform does not support haptics (web / some desktops).
class AppHaptics {
  AppHaptics._();

  static Future<void> selection() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  static Future<void> light() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  static Future<void> medium() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  static Future<void> heavy() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Soft confirmation (favorite on, send, publish success).
  static Future<void> success() => medium();

  /// Stronger cue for destructive / error-adjacent actions.
  static Future<void> warning() => heavy();
}
