import 'package:flutter/foundation.dart';

/// Cross-route hooks for the Home tab inside [MainShell] (avoids import cycles).
class HomeTabActions {
  HomeTabActions._();

  static VoidCallback? onScrollToTop;

  /// Applies a saved-search filter map onto the live Home feed state and
  /// starts a refresh. Registered by [HomePage] while the feed host is
  /// mounted. Returns `true` only when Home actually restored filters and
  /// initiated fetch.
  static Future<bool> Function(Map<String, dynamic> normalized)?
      onApplySavedSearchFilters;

  /// Consumes one-time prefs written by [SavedSearchHomeBridge] and applies
  /// them on Home (cold-start / late-registration fallback).
  static Future<bool> Function()? onConsumePendingSavedSearch;

  static void scrollToTop() => onScrollToTop?.call();

  /// Delivers [normalized] filters to the live Home host. Retries briefly
  /// when Home has not registered yet (e.g. shell still mounting).
  static Future<bool> applySavedSearchFilters(
    Map<String, dynamic> normalized, {
    int maxAttempts = 40,
    Duration interval = const Duration(milliseconds: 50),
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final fn = onApplySavedSearchFilters;
      if (fn != null) {
        return fn(normalized);
      }
      await Future<void>.delayed(interval);
    }
    // Fallback: Home may only expose the prefs-consume path.
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final fn = onConsumePendingSavedSearch;
      if (fn != null) {
        return fn();
      }
      await Future<void>.delayed(interval);
    }
    return false;
  }
}
