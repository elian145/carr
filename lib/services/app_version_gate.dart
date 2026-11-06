import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';
import 'config.dart';
import 'feature_flags.dart';
import '../l10n/app_localizations.dart';
import '../shared/debug/app_log.dart';
import '../state/locale_controller.dart';

/// Server-driven minimum (hard) and recommended (soft) client version gates.
///
/// Safety model (force-update hardening):
///  * A failed / timed-out / malformed fetch is NEVER cached as a result. Only
///    successfully parsed responses are cached, with a TTL ([cacheTtl]).
///  * While the server is unreachable the last KNOWN-GOOD requirement is kept
///    for at most [staleMax]; with no known-good value the gate is open.
///  * Every floor is parsed defensively ([AppVersionRequirement.fromJson]):
///    garbage, wrong types, absurd or negative values and a floor above the
///    server's own `latest_app_version` are treated as "no floor".
///  * A device that already meets/exceeds `latest_app_version` is never
///    hard-blocked (the stores have nothing newer to offer).
///  * "Try again" and app-resume bypass the cache ([load] `forceRefresh`), so
///    lowering the server floor releases blocked users without a reinstall.
class AppVersionGate {
  AppVersionGate._();

  /// How long a successful response is reused by non-forced [load] calls.
  static const Duration cacheTtl = Duration(minutes: 15);

  /// After a failed fetch, non-forced [load] calls do not hit the network
  /// again for this long (prevents refetch loops while offline).
  static const Duration failureBackoff = Duration(seconds: 30);

  /// Resume re-checks of a currently blocked user are spaced at least this far
  /// apart (a blocked user otherwise re-checks on every resume).
  static const Duration minResumeGap = Duration(seconds: 10);

  /// Longest time a last known-good requirement is still honoured while every
  /// refetch fails. Afterwards the gate fails open.
  static const Duration staleMax = Duration(hours: 24);

  /// Highest plausible major version for a floor/latest value (e.g. 999.0.0
  /// is a typo, not a release). Mirrors the backend's `MAX_VERSION_MAJOR`.
  static const int maxVersionMajor = 99;
  static const int maxAndroidBuild = 2100000000;
  static const int maxIosBuild = 999999999999999999;

  static AppVersionRequirement? _lastGood;
  static DateTime? _lastGoodAt;
  static DateTime? _lastAttemptAt;
  static DateTime? _lastFailureAt;
  static Future<AppVersionRequirement?>? _inflight;

  /// Clock used for TTL / throttling (overridable in tests).
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Optional override for unit tests (avoids platform channels).
  @visibleForTesting
  static PackageInfo? debugPackageInfo;

  /// Optional override for tests (`defaultTargetPlatform` otherwise).
  @visibleForTesting
  static TargetPlatform? debugPlatform;

  @visibleForTesting
  static void resetCacheForTests() {
    _lastGood = null;
    _lastGoodAt = null;
    _lastAttemptAt = null;
    _lastFailureAt = null;
    _inflight = null;
    debugPackageInfo = null;
    debugPlatform = null;
    clock = DateTime.now;
  }

  @visibleForTesting
  static void setCachedForTests(AppVersionRequirement requirement) {
    _lastGood = requirement;
    _lastGoodAt = clock();
    _lastFailureAt = null;
  }

  /// When the last successful, parsed fetch happened (null = never).
  static DateTime? get lastSuccessAt => _lastGoodAt;

  /// When the last network attempt started (null = never).
  static DateTime? get lastAttemptAt => _lastAttemptAt;

  /// Whether an app-resume should re-check the gate now.
  ///
  /// * never within [minResumeGap] of the previous attempt (no loops);
  /// * always when the user is currently [blocked] (so a lowered floor
  ///   releases them as soon as they come back);
  /// * otherwise only when there is no successful fetch yet or the last
  ///   success is at least [cacheTtl] old.
  static bool shouldRecheckOnResume({required bool blocked}) {
    final now = clock();
    final lastAttempt = _lastAttemptAt;
    if (lastAttempt != null && now.difference(lastAttempt) < minResumeGap) {
      return false;
    }
    if (blocked) return true;
    final lastOk = _lastGoodAt;
    if (lastOk == null) return true;
    return now.difference(lastOk) >= cacheTtl;
  }

  /// MI-03/U-01: localized strings for the malformed/legacy-response
  /// fallback messages below, without needing a `BuildContext` -- mirrors
  /// `bootstrap.dart`'s `_StartupCrashMessage` fix (generated
  /// `lookupAppLocalizations` + the already-resolved app locale).
  static AppLocalizations _fallbackL10n() =>
      lookupAppLocalizations(Locale(LocaleController.resolveCode()));

  /// Current requirement.
  ///
  /// Reuses a fresh successful response unless [forceRefresh]. Never throws
  /// and never returns a failure as if it were a result: on any failure it
  /// returns the last known-good requirement (<= [staleMax] old) or the empty
  /// "no gate" requirement, WITHOUT caching it.
  static Future<AppVersionRequirement> load({bool forceRefresh = false}) async {
    final now = clock();
    final good = _lastGood;
    final goodAt = _lastGoodAt;
    if (!forceRefresh &&
        good != null &&
        goodAt != null &&
        now.difference(goodAt) < cacheTtl) {
      return good;
    }
    final failedAt = _lastFailureAt;
    if (!forceRefresh &&
        failedAt != null &&
        now.difference(failedAt) < failureBackoff) {
      return _fallbackAfterFailure(now);
    }
    final fetched = await (_inflight ??= _fetch().whenComplete(() {
      _inflight = null;
    }));
    return fetched ?? _fallbackAfterFailure(clock());
  }

  static AppVersionRequirement _fallbackAfterFailure(DateTime now) {
    final good = _lastGood;
    final goodAt = _lastGoodAt;
    if (good != null && goodAt != null && now.difference(goodAt) < staleMax) {
      return good;
    }
    return const AppVersionRequirement();
  }

  /// One network attempt. Returns the parsed requirement, or null on ANY
  /// failure (timeout, transport error, non-200, non-JSON, non-object).
  static Future<AppVersionRequirement?> _fetch() async {
    _lastAttemptAt = clock();
    try {
      final uri = Uri.parse('${effectiveApiBase()}/api/config/app');
      // MI-03: Accept-Language so the backend can localize
      // force_update_message/soft_update_message before/without auth.
      final res = await ApiService.getHttp(
        uri,
        headers: ApiService.defaultHeaders(),
      );
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
          final parsed = AppVersionRequirement.fromJson(map);
          try {
            FeatureFlags.applyFromAppConfigJson(map);
          } catch (e, st) {
            logNonFatal(e, st, 'AppVersionGate.applyFlags');
          }
          _lastGood = parsed;
          _lastGoodAt = clock();
          _lastFailureAt = null;
          return parsed;
        }
      }
      appLog('AppVersionGate.load: unusable response (${res.statusCode})');
    } on TimeoutException catch (e) {
      appLog('AppVersionGate.load timed out: $e');
    } catch (e, st) {
      logNonFatal(e, st, 'AppVersionGate.load');
    }
    _lastFailureAt = clock();
    return null;
  }

  /// Hard block and/or soft "update available" prompt for the installed build.
  ///
  /// [forceRefresh] bypasses the TTL cache (used by "Try again" / resume).
  static Future<ForceUpdateDecision> evaluate({bool forceRefresh = false}) async {
    final req = await load(forceRefresh: forceRefresh);
    try {
      final info = debugPackageInfo ?? await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber.trim()) ?? 0;
      final version = info.version.trim();
      // An installed version we cannot parse can neither satisfy nor violate a
      // floor: fail open instead of treating it as 0.0.0.
      final versionKnown = _leadingVersion(version) != null;

      // Latest-aware escape: a device already on (or beyond) the latest
      // published version cannot update any further, so never hard-block it.
      final atLatest = versionKnown &&
          req.latestAppVersion.isNotEmpty &&
          compareSemver(version, req.latestAppVersion) >= 0;

      final forceSemver = versionKnown &&
          req.minAppVersion.isNotEmpty &&
          compareSemver(version, req.minAppVersion) < 0;
      final forceBuild = build > 0 &&
          _belowMinBuild(
            build,
            android: req.minAndroidBuild,
            ios: req.minIosBuild,
          );

      if ((forceSemver || forceBuild) && !atLatest) {
        return ForceUpdateDecision(
          required: true,
          softRecommended: false,
          // MI-03: the backend now always returns a non-empty, localized
          // `force_update_message` (Accept-Language; see
          // kk.app_settings.get_localized_platform_message), so this is a
          // last-resort fallback only for a malformed/legacy response.
          // This class has no BuildContext, but `lookupAppLocalizations`
          // (generated by flutter gen-l10n) doesn't need one -- combined
          // with the already-resolved app locale (`LocaleController`,
          // loaded from prefs before this can ever run), Arabic/Kurdish
          // users still get a localized string instead of English even in
          // this edge case, with no manual locale branching.
          message: req.forceUpdateMessage.isNotEmpty
              ? req.forceUpdateMessage
              : _fallbackL10n().forceUpdateFallbackMessage,
          storeUrl: storeUrlForPlatform(req),
          softPromptKey: '',
        );
      }

      final softSemver = versionKnown &&
          req.recommendedAppVersion.isNotEmpty &&
          compareSemver(version, req.recommendedAppVersion) < 0;
      final softBuild = build > 0 &&
          _belowMinBuild(
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
          // MI-03: same reasoning as the force-update message above.
          message: req.softUpdateMessage.isNotEmpty
              ? req.softUpdateMessage
              : _fallbackL10n().softUpdateFallbackMessage,
          storeUrl: storeUrlForPlatform(req),
          softPromptKey: keyParts.join('|'),
        );
      }
    } catch (e, st) {
      logNonFatal(e, st, 'AppVersionGate.evaluate');
    }
    return const ForceUpdateDecision(required: false);
  }

  static TargetPlatform get _platform => debugPlatform ?? defaultTargetPlatform;

  static bool _belowMinBuild(
    int build, {
    required int? android,
    required int? ios,
  }) {
    int? minBuild;
    if (!kIsWeb && _platform == TargetPlatform.android) {
      minBuild = android;
    } else if (!kIsWeb && _platform == TargetPlatform.iOS) {
      minBuild = ios;
    }
    return minBuild != null && minBuild > 0 && build < minBuild;
  }

  static String storeUrlForPlatform(AppVersionRequirement req) {
    if (!kIsWeb && _platform == TargetPlatform.iOS) {
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

  /// Tolerant parse of the INSTALLED version: leading `N[.N...]`, optional
  /// `v` prefix, any `-dev` / `+7` style suffix ignored. Null if unparseable.
  static String? _leadingVersion(String raw) {
    final m = RegExp(r'^[vV]?([0-9]+(?:\.[0-9]+){0,3})').firstMatch(raw.trim());
    return m?.group(1);
  }

  /// Strict parse of a SERVER floor/latest/recommended value: only real
  /// strings of 1-4 dot-separated numbers (1-4 digits each), major <=
  /// [maxVersionMajor]. Returns the canonical string or null (= unset).
  static String? parseServerVersion(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    if (!RegExp(r'^[0-9]{1,4}(\.[0-9]{1,4}){0,3}$').hasMatch(text)) {
      return null;
    }
    final parts = text.split('.').map(int.parse).toList();
    if (parts.first > maxVersionMajor) return null;
    return parts.join('.');
  }

  /// Strict parse of a server build number: int or digit-only string, within
  /// `0..max`. Null otherwise (wrong type, negative, huge, garbage).
  static int? parseServerBuild(Object? raw, int max) {
    int? n;
    if (raw is int) {
      n = raw;
    } else if (raw is String) {
      final t = raw.trim();
      if (!RegExp(r'^[0-9]{1,18}$').hasMatch(t)) return null;
      n = int.tryParse(t);
    }
    if (n == null || n < 0 || n > max) return null;
    return n;
  }

  /// Only well-formed http(s) / market / itms-apps URLs are ever opened.
  static String sanitizeStoreUrl(Object? raw) {
    if (raw is! String) return '';
    final text = raw.trim();
    if (text.isEmpty || text.length > 2048) return '';
    if (RegExp(r'\s').hasMatch(text)) return '';
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return '';
    const schemes = {'http', 'https', 'market', 'itms-apps', 'itms-appss'};
    if (!schemes.contains(uri.scheme.toLowerCase())) return '';
    if (uri.host.isEmpty && uri.authority.isEmpty) return '';
    return text;
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

  /// Latest published version (additive server field; empty = unknown).
  final String latestAppVersion;
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
    this.latestAppVersion = '',
    this.softUpdateMessage = '',
    this.androidStoreUrl = '',
    this.iosStoreUrl = '',
  });

  /// Defensive parse: nothing in [json] can throw or yield a bogus floor.
  /// Unparseable / wrong-typed / absurd values become "unset" (fail open).
  factory AppVersionRequirement.fromJson(Map<String, dynamic> json) {
    String text(String k) {
      final v = json[k];
      return v is String ? v.trim() : '';
    }

    final dropped = <String>[];
    String version(String k) {
      final raw = json[k];
      if (raw == null || (raw is String && raw.trim().isEmpty)) return '';
      final parsed = AppVersionGate.parseServerVersion(raw);
      if (parsed == null) dropped.add(k);
      return parsed ?? '';
    }

    int? build(String k, int max) {
      final raw = json[k];
      if (raw == null || (raw is String && raw.trim().isEmpty)) return null;
      final parsed = AppVersionGate.parseServerBuild(raw, max);
      if (parsed == null) dropped.add(k);
      return parsed;
    }

    final latest = version('latest_app_version');
    var floor = version('min_app_version');
    if (floor.isNotEmpty &&
        latest.isNotEmpty &&
        AppVersionGate.compareSemver(floor, latest) > 0) {
      // A floor above the server's own latest release can never be met.
      dropped.add('min_app_version(>latest)');
      floor = '';
    }
    if (dropped.isNotEmpty) {
      // Names only: never log/telemetry the raw (possibly hostile) values.
      appLog('AppVersionRequirement: ignoring invalid fields $dropped');
    }

    return AppVersionRequirement(
      minAppVersion: floor,
      minAndroidBuild:
          build('min_android_build', AppVersionGate.maxAndroidBuild),
      minIosBuild: build('min_ios_build', AppVersionGate.maxIosBuild),
      forceUpdateMessage: text('force_update_message'),
      recommendedAppVersion: version('recommended_app_version'),
      recommendedAndroidBuild:
          build('recommended_android_build', AppVersionGate.maxAndroidBuild),
      recommendedIosBuild:
          build('recommended_ios_build', AppVersionGate.maxIosBuild),
      latestAppVersion: latest,
      softUpdateMessage: text('soft_update_message'),
      androidStoreUrl: AppVersionGate.sanitizeStoreUrl(json['android_store_url']),
      iosStoreUrl: AppVersionGate.sanitizeStoreUrl(json['ios_store_url']),
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
