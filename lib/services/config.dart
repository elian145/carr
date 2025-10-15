// Centralized runtime configuration for API endpoints and assets
// Values come from --dart-define so we can point to a LAN server on device

// Base like: http://192.168.1.50:5000 (NO trailing slash)
const String kApiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://192.168.1.16:5000');

String apiBase() {
  return kApiBase;
}

String apiBaseApi() {
  final base = apiBase();
  return base.endsWith('/api') ? base : base + '/api';
}

