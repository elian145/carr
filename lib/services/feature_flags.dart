import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'config.dart';
import '../shared/debug/app_log.dart';

/// Server-driven feature kill-switches from GET `/api/config/app`.
///
/// Fail-open: unknown/offline → features stay enabled so a config outage
/// does not brick the app. See `docs/FEATURE_FLAGS.md`.
class FeatureFlags {
  FeatureFlags._();

  static FeatureFlagsSnapshot _cached = FeatureFlagsSnapshot.defaults();
  static bool _loaded = false;

  @visibleForTesting
  static void resetCacheForTests() {
    _cached = FeatureFlagsSnapshot.defaults();
    _loaded = false;
  }

  @visibleForTesting
  static void setCachedForTests(FeatureFlagsSnapshot snapshot) {
    _cached = snapshot;
    _loaded = true;
  }

  /// Apply `feature_flags` from an `/api/config/app` JSON body (no network).
  static void applyFromAppConfigJson(Map<String, dynamic> json) {
    _cached = FeatureFlagsSnapshot.fromJson(json);
    _loaded = true;
  }

  static FeatureFlagsSnapshot get current => _cached;

  static Future<FeatureFlagsSnapshot> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _loaded) return _cached;

    try {
      final uri = Uri.parse('${effectiveApiBase()}/api/config/app');
      final res = await ApiService.getHttp(uri);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (decoded is Map) {
          applyFromAppConfigJson(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
          return _cached;
        }
      }
    } catch (e, st) {
      logNonFatal(e, st, 'FeatureFlags.load');
    }

    // Keep previous cache on failure; never disable by default.
    _loaded = true;
    return _cached;
  }

  static Future<bool> isEnabled(String key) async {
    final snap = await load();
    return snap.isEnabled(key);
  }
}

class FeatureFlagsSnapshot {
  final Map<String, bool> flags;

  const FeatureFlagsSnapshot(this.flags);

  factory FeatureFlagsSnapshot.defaults() => FeatureFlagsSnapshot({
        'sell': true,
        'chat': true,
        'dealers': true,
        'comparison': true,
        'saved_searches': true,
      });

  factory FeatureFlagsSnapshot.fromJson(Map<String, dynamic> json) {
    final base = Map<String, bool>.from(FeatureFlagsSnapshot.defaults().flags);
    final raw = json['feature_flags'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        base[key] = _asBool(entry.value, defaultValue: base[key] ?? true);
      }
    }
    return FeatureFlagsSnapshot(Map<String, bool>.unmodifiable(base));
  }

  bool isEnabled(String key) => flags[key] ?? true;

  bool get sellEnabled => isEnabled('sell');
  bool get chatEnabled => isEnabled('chat');
  bool get dealersEnabled => isEnabled('dealers');
  bool get comparisonEnabled => isEnabled('comparison');
  bool get savedSearchesEnabled => isEnabled('saved_searches');

  static bool _asBool(dynamic value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes' || text == 'on') {
      return true;
    }
    if (text == '0' || text == 'false' || text == 'no' || text == 'off') {
      return false;
    }
    return defaultValue;
  }
}
