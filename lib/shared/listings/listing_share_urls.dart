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

/// When [kListingShareWebBase] is empty, use the API origin from [effectiveApiBase]
/// so shares are normal `https://` URLs (tap-to-open in chat apps), e.g.
/// `https://<api-host>/listing/<id>`. Your server must handle that path or set
/// [kListingShareWebBase] to your public marketing domain.
String? _inferredShareWebBase() {
  try {
    final api = effectiveApiBase().trim();
    if (api.isEmpty) return null;
    final uri = Uri.parse(api);
    // Prefer HTTPS for shared links; skip local/LAN API hosts.
    if (uri.scheme != 'https') return null;
    final host = uri.host;
    if (host.isEmpty || _isNonPublicApiHost(host)) return null;
    return uri.origin;
  } catch (_) {
    return null;
  }
}

String _normalizedPathSegment(String raw) {
  return raw.trim().replaceAll(RegExp(r'^/+|/+$'), '');
}

/// Path between share base and listing id (e.g. `listing`, or `en/redirect`).
String _sharePathSegment() {
  final p = _normalizedPathSegment(kListingShareUrlPath);
  return p.isEmpty ? 'listing' : p;
}

String? _resolvedShareWebBase() {
  final explicit = kListingShareWebBase.trim();
  if (explicit.isNotEmpty) return explicit;
  return _inferredShareWebBase();
}

/// Public web URL: [kListingShareWebBase] if set, else inferred API origin, plus path.
String? listingWebShareLink(String listingId) {
  final id = listingId.trim();
  if (id.isEmpty) return null;
  final base = (_resolvedShareWebBase() ?? '').trim();
  if (base.isEmpty) return null;
  final normalized =
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final path = _sharePathSegment();
  if (path.isEmpty) {
    return '$normalized/${Uri.encodeComponent(id)}';
  }
  return '$normalized/$path/${Uri.encodeComponent(id)}';
}

/// Single URL for sharing: HTTPS when a web base is set or inferred, else `carzo://`.
String listingShareLinkOnly(String listingId) {
  final web = listingWebShareLink(listingId);
  if (web != null && web.isNotEmpty) return web;
  return listingDeepLink(listingId);
}
