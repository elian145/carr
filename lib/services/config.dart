// Centralized runtime configuration for API endpoints and assets
// Values come from --dart-define so we can point to a LAN server on device

// Base like: http://192.168.1.50:5000 (NO trailing slash)
const String kApiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:5000');

String apiBase() {
  return kApiBase;
}

String apiBaseApi() {
  final base = apiBase();
  return base.endsWith('/api') ? base : base + '/api';
}

/// Resolves a media path (relative) or URL (absolute) to a fetchable URL.
///
/// Supports:
/// - Absolute URLs (http/https): returned as-is
/// - Relative paths like:
///   - `car_photos/foo.jpg`         -> `$API_BASE/static/uploads/car_photos/foo.jpg`
///   - `uploads/car_photos/foo.jpg` -> `$API_BASE/static/uploads/car_photos/foo.jpg`
String resolveMediaUrl(String relOrAbs) {
  final s = relOrAbs.trim();
  if (s.isEmpty) return s;
  final lower = s.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return s;

  final base = apiBase();
  var p = s;
  if (p.startsWith('/')) p = p.substring(1);

  // Already a fully qualified static path.
  if (p.startsWith('static/')) return '$base/$p';

  // Backend can return `uploads/...` relative to the static root.
  if (p.startsWith('uploads/')) return '$base/static/$p';

  // Default: assume it's under static/uploads/...
  return '$base/static/uploads/$p';
}

/// Extracts a usable image path from various API shapes.
///
/// Accepts:
/// - `String` entries (already a path or URL)
/// - `{ image_url: "..." }` entries
String? coerceImagePath(dynamic entry) {
  if (entry == null) return null;
  if (entry is String) return entry.trim();
  if (entry is Map) {
    final v = entry['image_url'] ??
        entry['imageUrl'] ??
        entry['video_url'] ??
        entry['videoUrl'] ??
        entry['url'];
    if (v is String) return v.trim();
  }
  return entry.toString().trim();
}

