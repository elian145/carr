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

/// HTTPS URL for Universal Links / web preview (Messages, Safari, etc.).
String? listingHttpsShareLink(String listingId) => listingWebShareLink(listingId);

/// Link to put on the share sheet.
///
/// Uses ``carzo://listing?id=…`` so a tap in chat can open CARZO directly without a
/// web page. Social in-app browsers (Snapchat, Instagram) cannot open the app from a
/// button on that web page — the chat link must be the deep link.
String listingShareLinkOnly(String listingId) {
  final deep = listingDeepLink(listingId).trim();
  if (deep.isNotEmpty) return deep;
  final web = listingWebShareLink(listingId);
  if (web != null && web.isNotEmpty) return web;
  return '';
}

bool _isListingPublicId(String id) {
  if (id.isEmpty || id.length > 128) return false;
  return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id);
}

/// Hosts used in shared HTTPS listing URLs (explicit share base or API origin).
bool isHostUsedForListingShareLinks(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return false;
  final share = kListingShareWebBase.trim();
  if (share.isNotEmpty) {
    try {
      if (Uri.parse(share).host.toLowerCase() == h) return true;
    } catch (_) {}
  }
  try {
    final apiHost = Uri.parse(effectiveApiBase()).host.toLowerCase();
    if (apiHost.isNotEmpty && apiHost == h) return true;
  } catch (_) {}
  return false;
}

/// Parses shared HTTPS listing path: `/<LISTING_SHARE_URL_PATH>/<id>` (default `/listing/<id>`).
String? listingIdFromSharedHttpsUri(Uri uri) {
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  if (!isHostUsedForListingShareLinks(uri.host)) return null;
  final segs = uri.pathSegments;
  if (segs.isEmpty) return null;

  final pathSeg = _sharePathSegment();
  final prefixParts = pathSeg.split('/').where((p) => p.isNotEmpty).toList();
  if (segs.length == prefixParts.length + 1) {
    for (var i = 0; i < prefixParts.length; i++) {
      if (segs[i] != prefixParts[i]) return null;
    }
    final id = segs.last.trim();
    return _isListingPublicId(id) ? id : null;
  }
  // Back-compat: `/listing/<id>` when configured path is not `listing`.
  if (pathSeg != 'listing' &&
      segs.length >= 2 &&
      segs[0] == 'listing') {
    final id = segs[1].trim();
    return _isListingPublicId(id) ? id : null;
  }
  return null;
}
