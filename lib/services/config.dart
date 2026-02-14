// Centralized runtime configuration for API endpoints and assets
// Values come from --dart-define so we can point to a LAN server on device

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kReleaseMode;

// Base like: https://api.example.com (NO trailing slash)
// - Debug: can use http:// for local development
// - Release: must be https:// (unless SIDELOAD_BUILD=true on iOS)
const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: '',
);
const bool kSideloadBuild = bool.fromEnvironment(
  'SIDELOAD_BUILD',
  defaultValue: false,
);
const bool kForceSkipBlur = bool.fromEnvironment(
  'FORCE_SKIP_BLUR',
  defaultValue: false,
);

String? _runtimeApiBaseOverride;

/// Allow changing API base at runtime (for sideload/local dev scenarios).
///
/// - Debug/Profile: allowed
/// - Release: only allowed for iOS sideload builds (SIDELOAD_BUILD=true)
bool allowRuntimeApiBaseOverride() {
  if (!kReleaseMode) return true;
  return kSideloadBuild && Platform.isIOS;
}

/// Set a runtime override (persist it yourself if needed).
void setRuntimeApiBaseOverride(String? base) {
  if (!allowRuntimeApiBaseOverride()) return;
  final v = (base ?? '').trim();
  _runtimeApiBaseOverride = v.isEmpty ? null : v;
}

String? runtimeApiBaseOverride() {
  return allowRuntimeApiBaseOverride() ? _runtimeApiBaseOverride : null;
}

String apiBase() {
  final o = runtimeApiBaseOverride();
  if (o != null && o.trim().isNotEmpty) return o.trim();
  return kApiBase.trim();
}

/// On Android emulator, 10.0.2.2 maps to the host machine.
/// Keep port consistent with the default API base unless overridden via --dart-define.
String effectiveApiBase() {
  final base = apiBase();

  if (kReleaseMode) {
    if (base.isEmpty) {
      throw StateError(
        'Missing API_BASE. Provide --dart-define=API_BASE=https://<your-domain>',
      );
    }
    if (!base.startsWith('https://')) {
      // Sideload builds (typically for Sideloadly) may need to call a LAN HTTP API.
      // This is only allowed on iOS when explicitly opted-in at compile time.
      if (!(kSideloadBuild && Platform.isIOS && base.startsWith('http://'))) {
        throw StateError('In release builds, API_BASE must start with https://');
      }
    }
    return base;
  }

  // Debug/dev defaults: local backend convenience.
  if (base.isEmpty) {
    if (Platform.isAndroid) return 'http://10.0.2.2:5003';
    return 'http://localhost:5003';
  }

  // Legacy default mapping for existing dev setups.
  if (Platform.isAndroid &&
      (base == 'http://192.168.1.7:5003' || base == 'http://192.168.1.8:5003')) {
    return 'http://10.0.2.2:5003';
  }
  return base;
}

String apiBaseApi() {
  final base = effectiveApiBase();
  return base.endsWith('/api') ? base : '$base/api';
}

/// Socket.IO is currently served by the listings backend (kk) on port 5000 in dev,
/// while the API proxy runs on 5003. In production, you should front both behind
/// the same domain and reverse-proxy `/socket.io/` to the backend.
String effectiveSocketIoBase() {
  final base = effectiveApiBase().trim();
  if (base.isEmpty) {
    if (Platform.isAndroid) return 'http://10.0.2.2:5000';
    return 'http://localhost:5000';
  }
  try {
    final uri = Uri.parse(base);
    if (uri.hasPort && uri.port == 5003) {
      return uri.replace(port: 5000).toString();
    }
  } catch (_) {}
  return base;
}

bool forceSkipBlur() {
  return kForceSkipBlur;
}

// No third-party plate API keys are exposed to the client.
// All license plate blurring is performed server-side via the backend.
