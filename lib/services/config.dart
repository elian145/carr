// Centralized runtime configuration for API endpoints and assets
// Values come from --dart-define so we can point to a LAN server on device

// Base like: http://10.0.2.2:5000 (NO trailing slash)
// Use 10.0.2.2 for Android emulator, which maps to host's localhost
const String kApiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:5000');
const bool kForceSkipBlur = bool.fromEnvironment('FORCE_SKIP_BLUR', defaultValue: false);

String apiBase() {
  return kApiBase;
}

String apiBaseApi() {
  final base = apiBase();
  return base.endsWith('/api') ? base : base + '/api';
}

bool forceSkipBlur() {
  return kForceSkipBlur;
}

// No third-party plate API keys are exposed to the client.
// All license plate blurring is performed server-side via the backend.
