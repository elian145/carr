import '../../services/config.dart';

/// Normalize a relative backend media path into an absolute URL that works across
/// emulator/device and across backend response variants.
///
/// Supports:
/// - absolute URLs (rewrites `/static/*` to use `effectiveApiBase()` for emulator reachability)
/// - `static/*`
/// - `uploads/*` (maps to `/static/uploads/*`)
/// - `car_photos/*` (maps to `/static/uploads/*`)
/// - bare filenames or nested paths (assumed under `/static/uploads/*`)
String buildMediaUrl(String rel) {
  String s = (rel).toString().trim().replaceAll(r'\', '/');
  if (s.isEmpty) return '';
  final lower = s.toLowerCase();
  if (lower == 'null' || lower == 'none') return '';

  final base = effectiveApiBase().trim(); // no /api
  if (s.startsWith('http://') || s.startsWith('https://')) {
    try {
      final uri = Uri.parse(s);
      if (uri.path.startsWith('/static/') && base.isNotEmpty) {
        final path = uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : '');
        return '$base$path';
      }
    } catch (_) {}
    return s;
  }

  if (s.startsWith('/')) s = s.substring(1);
  if (s.startsWith('static/')) return '$base/$s';
  if (s.startsWith('uploads/')) return '$base/static/$s';
  if (s.startsWith('car_photos/')) return '$base/static/uploads/$s';
  // Bare filename (e.g. from backend) usually lives under car_photos
  if (!s.contains('/')) return '$base/static/uploads/car_photos/$s';
  return '$base/static/uploads/$s';
}

