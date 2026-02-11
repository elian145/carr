// Centralized runtime configuration for API endpoints and assets
// Values come from --dart-define so we can point to a LAN server on device

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kReleaseMode;

// Base like: https://api.example.com (NO trailing slash)
// - Debug: can use http:// for local development
// - Release: must be https://
const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: '',
);
const bool kForceSkipBlur = bool.fromEnvironment(
  'FORCE_SKIP_BLUR',
  defaultValue: false,
);

String apiBase() {
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
      throw StateError('In release builds, API_BASE must start with https://');
    }
    return base;
  }

  // Debug/dev defaults: local backend convenience.
  if (base.isEmpty) {
    if (Platform.isAndroid) return 'http://10.0.2.2:5003';
    return 'http://localhost:5003';
  }

  // Legacy default mapping for existing dev setups.
  if (Platform.isAndroid && base == 'http://192.168.1.7:5003') {
    return 'http://10.0.2.2:5003';
  }
  return base;
}

String apiBaseApi() {
  final base = effectiveApiBase();
  return base.endsWith('/api') ? base : '$base/api';
}

bool forceSkipBlur() {
  return kForceSkipBlur;
}

// No third-party plate API keys are exposed to the client.
// All license plate blurring is performed server-side via the backend.
