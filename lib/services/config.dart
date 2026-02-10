// Centralized runtime configuration for API endpoints and assets
// Values come from --dart-define so we can point to a LAN server on device

import 'dart:io' show Platform;

// Base like: http://192.168.1.7:5003 (NO trailing slash)
// Default to this PC's LAN IP; override with --dart-define for emulator (10.0.2.2) or other device
const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://192.168.1.7:5003',
);
const bool kForceSkipBlur = bool.fromEnvironment(
  'FORCE_SKIP_BLUR',
  defaultValue: false,
);

String apiBase() {
  return kApiBase;
}

/// Same as getApiBase() in main: on Android emulator use host 10.0.2.2:5000 so blur/API reach backend.
String effectiveApiBase() {
  final base = apiBase();
  if (Platform.isAndroid && base == 'http://192.168.1.7:5003') {
    return 'http://10.0.2.2:5000';
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
