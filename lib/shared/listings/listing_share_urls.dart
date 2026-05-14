import '../../services/config.dart';

/// Opens this listing in CARZO when the link is opened on a device with the app.
String listingDeepLink(String listingId) {
  final id = listingId.trim();
  if (id.isEmpty) return '';
  return Uri(
    scheme: 'carzo',
    host: 'listing',
    queryParameters: {'id': id},
  ).toString();
}

bool _isNonPublicApiHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h == '127.0.0.1' || h == '0.0.0.0') return true;
  if (h == '10.0.2.2') return true;
  if (h.startsWith('192.168.')) return true;
  if (h.startsWith('10.')) return true;
  if (RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.\d+\.\d+$').hasMatch(h)) {
    return true;
  }
  return false;
}

/// When [kListingShareWebBase] is empty, derive an HTTPS origin from [effectiveApiBase]
/// so shares are normal `https://` links (not `carzo://`) for known production APIs.
String? _inferredShareWebBase() {
  try {
    final api = effectiveApiBase().trim();
    if (api.isEmpty) return null;
    final uri = Uri.parse(api);
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    final host = uri.host;
    if (host.isEmpty || _isNonPublicApiHost(host)) return null;
    final lower = host.toLowerCase();
    // Default Render deployment for this project → public redirect site (universal link style).
    if (lower == 'carr-5hrm.onrender.com') {
      return 'https://www.iqcars.net';
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).origin;
  } catch (_) {
    return null;
  }
}

String _normalizedPathSegment(String raw) {
  return raw.trim().replaceAll(RegExp(r'^/+|/+$'), '');
}

/// Path segment between share base and listing id.
String _resolvedSharePath(String resolvedWebBase) {
  final explicitBase = kListingShareWebBase.trim();
  if (explicitBase.isNotEmpty) {
    return _normalizedPathSegment(kListingShareUrlPath);
  }
  final lower = resolvedWebBase.toLowerCase();
  if (lower.contains('iqcars.net')) {
    return 'en/redirect';
  }
  final fromEnv = _normalizedPathSegment(kListingShareUrlPath);
  return fromEnv.isEmpty ? 'listing' : fromEnv;
}

String? _resolvedShareWebBase() {
  final explicit = kListingShareWebBase.trim();
  if (explicit.isNotEmpty) return explicit;
  return _inferredShareWebBase();
}

/// Public web URL: explicit [kListingShareWebBase], or inferred from API base, plus path.
String? listingWebShareLink(String listingId) {
  final id = listingId.trim();
  if (id.isEmpty) return null;
  final base = (_resolvedShareWebBase() ?? '').trim();
  if (base.isEmpty) return null;
  final normalized =
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  var path = _resolvedSharePath(normalized);
  if (path.isEmpty) {
    return '$normalized/${Uri.encodeComponent(id)}';
  }
  return '$normalized/$path/${Uri.encodeComponent(id)}';
}

/// Single URL for sharing: HTTPS when web base is set or can be inferred, else `carzo://`.
String listingShareLinkOnly(String listingId) {
  final web = listingWebShareLink(listingId);
  if (web != null && web.isNotEmpty) return web;
  return listingDeepLink(listingId);
}
