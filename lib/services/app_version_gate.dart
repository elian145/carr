import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';
import 'config.dart';
import 'feature_flags.dart';
import '../shared/debug/app_log.dart';

/// Server-driven minimum (hard) and recommended (soft) client version gates.
class AppVersionGate {
  AppVersionGate._();

  static AppVersionRequirement? _cached;

  /// Optional override for unit tests (avoids platform channels).
  @visibleForTesting
  static PackageInfo? debugPackageInfo;

  @visibleForTesting
  static void resetCacheForTests() {
    _cached = null;
    debugPackageInfo = null;
  }

  @visibleForTesting
  static void setCachedForTests(AppVersionRequirement requirement) {
    _cached = requirement;
  }

  static Future<AppVersionRequirement> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) return _cached!;

    AppVersionRequirement fromApi = const AppVersionRequirement();
    try {
      final uri = Uri.parse('${effectiveApiBase()}/api/config/app');
      final res = await ApiService.getHttp(uri);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
          fromApi = AppVersionRequirement.fromJson(map);
          FeatureFlags.applyFromAppConfigJson(map);
        }
      }
    } catch (e, st) {
      logNonFatal(e, st, 'AppVersionGate.load');
    }

    _cached = fromApi;
    return fromApi;
  }

  /// Hard block and/or soft "update available" prompt for the installed build.
  static Future<ForceUpdateDecision> evaluate() async {
    final req = await load();
    try {
      final info = debugPackageInfo ?? await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber.trim()) ?? 0;
      final version = info.version.trim();

      final forceSemver = req.minAppVersion.isNotEmpty &&
          compareSemver(version, req.minAppVersion) < 0;
      final forceBuild = _belowMinBuild(
        build,
        android: req.minAndroidBuild,
        ios: req.minIosBuild,
      );

      if (forceSemver || forceBuild) {
        return ForceUpdateDecision(
          required: true,
          softRecommended: false,
          message: req.forceUpdateMessage.isNotEmpty
              ? req.forceUpdateMessage
              : 'Please update CarNet to continue.',
          storeUrl: storeUrlForPlatform(req),
          softPromptKey: '',
        );
      }

      final softSemver = req.recommendedAppVersion.isNotEmpty &&
          compareSemver(version, req.recommendedAppVersion) < 0;
      final softBuild = _belowMinBuild(
        build,
        android: req.recommendedAndroidBuild,
        ios: req.recommendedIosBuild,
      );

      if (softSemver || softBuild) {
        final keyParts = <String>[
          if (req.recommendedAppVersion.isNotEmpty) req.recommendedAppVersion,
          if (req.recommendedAndroidBuild != null)
            'a${req.recommendedAndroidBuild}',
          if (req.recommendedIosBuild != null) 'i${req.recommendedIosBuild}',
        ];
        return ForceUpdateDecision(
          required: false,
          softRecommended: true,
          message: req.softUpdateMessage.isNotEmpty
              ? req.softUpdateMessage
              : 'A newer version of CarNet is available.',
          storeUrl: storeUrlForPlatform(req),
          softPromptKey: keyParts.join('|'),
        );
      }
    } catch (e, st) {
      logNonFatal(e, st, 'AppVersionGate.evaluate');
    }
    return const ForceUpdateDecision(required: false);
  }

  static bool _belowMinBuild(
    int build, {
    required int? android,
    required int? ios,
  }) {
    int? minBuild;
    if (!kIsWeb && Platform.isAndroid) {
      minBuild = android;
    } else if (!kIsWeb && Platform.isIOS) {
      minBuild = ios;
    }
    return minBuild != null && minBuild > 0 && build < minBuild;
  }

  static String storeUrlForPlatform(AppVersionRequirement req) {
    if (!kIsWeb && Platform.isIOS) {
      return req.iosStoreUrl;
    }
    return req.androidStoreUrl;
  }

  /// Compare dotted semver-ish strings. Returns <0 if a < b.
  static int compareSemver(String a, String b) {
    List<int> parts(String v) => v
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9].*$'), '')) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

class AppVersionRequirement {
  final String minAppVersion;
  final int? minAndroidBuild;
  final int? minIosBuild;
  final String forceUpdateMessage;
  final String recommendedAppVersion;
  final int? recommendedAndroidBuild;
  final int? recommendedIosBuild;
  final String softUpdateMessage;
  final String androidStoreUrl;
  final String iosStoreUrl;

  const AppVersionRequirement({
    this.minAppVersion = '',
    this.minAndroidBuild,
    this.minIosBuild,
    this.forceUpdateMessage = '',
    this.recommendedAppVersion = '',
    this.recommendedAndroidBuild,
    this.recommendedIosBuild,
    this.softUpdateMessage = '',
    this.androidStoreUrl = '',
    this.iosStoreUrl = '',
  });

  factory AppVersionRequirement.fromJson(Map<String, dynamic> json) {
    String s(dynamic k) => (json[k] ?? '').toString().trim();
    int? i(dynamic k) {
      final raw = json[k];
      if (raw == null) return null;
      if (raw is int) return raw;
      return int.tryParse(raw.toString().trim());
    }

    return AppVersionRequirement(
      minAppVersion: s('min_app_version'),
      minAndroidBuild: i('min_android_build'),
      minIosBuild: i('min_ios_build'),
      forceUpdateMessage: s('force_update_message'),
      recommendedAppVersion: s('recommended_app_version'),
      recommendedAndroidBuild: i('recommended_android_build'),
      recommendedIosBuild: i('recommended_ios_build'),
      softUpdateMessage: s('soft_update_message'),
      androidStoreUrl: s('android_store_url'),
      iosStoreUrl: s('ios_store_url'),
    );
  }
}

class ForceUpdateDecision {
  /// Blocking force-update screen.
  final bool required;

  /// Dismissible “update available” prompt (ignored when [required] is true).
  final bool softRecommended;

  final String message;
  final String storeUrl;

  /// Stable key for “don’t show again until recommendation changes”.
  final String softPromptKey;

  const ForceUpdateDecision({
    required this.required,
    this.softRecommended = false,
    this.message = '',
    this.storeUrl = '',
    this.softPromptKey = '',
  });
}
