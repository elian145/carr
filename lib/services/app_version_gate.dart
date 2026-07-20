import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';
import 'config.dart';
import '../shared/debug/app_log.dart';

/// Server-driven minimum client version / force-update gate.
class AppVersionGate {
  AppVersionGate._();

  static AppVersionRequirement? _cached;

  @visibleForTesting
  static void resetCacheForTests() {
    _cached = null;
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
          fromApi = AppVersionRequirement.fromJson(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
        }
      }
    } catch (e, st) {
      logNonFatal(e, st, 'AppVersionGate.load');
    }

    _cached = fromApi;
    return fromApi;
  }

  /// Returns a blocking requirement when the installed build is too old.
  static Future<ForceUpdateDecision> evaluate() async {
    final req = await load();
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber.trim()) ?? 0;
      final version = info.version.trim();

      final needsBySemver = req.minAppVersion.isNotEmpty &&
          _compareSemver(version, req.minAppVersion) < 0;

      int? minBuild;
      if (!kIsWeb && Platform.isAndroid) {
        minBuild = req.minAndroidBuild;
      } else if (!kIsWeb && Platform.isIOS) {
        minBuild = req.minIosBuild;
      }

      final needsByBuild = minBuild != null && minBuild > 0 && build < minBuild;

      if (needsBySemver || needsByBuild) {
        return ForceUpdateDecision(
          required: true,
          message: req.forceUpdateMessage.isNotEmpty
              ? req.forceUpdateMessage
              : 'Please update CarNet to continue.',
          storeUrl: _storeUrlForPlatform(req),
        );
      }
    } catch (e, st) {
      logNonFatal(e, st, 'AppVersionGate.evaluate');
    }
    return const ForceUpdateDecision(required: false);
  }

  static String _storeUrlForPlatform(AppVersionRequirement req) {
    if (!kIsWeb && Platform.isIOS) {
      return req.iosStoreUrl;
    }
    return req.androidStoreUrl;
  }

  /// Compare dotted semver-ish strings. Returns <0 if a < b.
  static int _compareSemver(String a, String b) {
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
  final String androidStoreUrl;
  final String iosStoreUrl;

  const AppVersionRequirement({
    this.minAppVersion = '',
    this.minAndroidBuild,
    this.minIosBuild,
    this.forceUpdateMessage = '',
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
      androidStoreUrl: s('android_store_url'),
      iosStoreUrl: s('ios_store_url'),
    );
  }
}

class ForceUpdateDecision {
  final bool required;
  final String message;
  final String storeUrl;

  const ForceUpdateDecision({
    required this.required,
    this.message = '',
    this.storeUrl = '',
  });
}
