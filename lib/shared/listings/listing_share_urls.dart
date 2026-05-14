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

/// Public web URL when [kListingShareWebBase] is set (no trailing slash), e.g.
/// `https://www.example.com` → `https://www.example.com/listing/<id>`.
String? listingWebShareLink(String listingId) {
  final base = kListingShareWebBase.trim();
  final id = listingId.trim();
  if (base.isEmpty || id.isEmpty) return null;
  final normalized =
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$normalized/listing/${Uri.encodeComponent(id)}';
}

/// Share sheet text: optional description lines, then web link (if configured), then app link.
String buildListingShareMessage({
  required String listingId,
  required List<String> bodyLines,
}) {
  final lines = <String>[
    ...bodyLines.map((s) => s.trim()).where((s) => s.isNotEmpty),
  ];
  final web = listingWebShareLink(listingId);
  if (web != null) lines.add(web);
  final deep = listingDeepLink(listingId);
  if (deep.isNotEmpty) lines.add(deep);
  return lines.join('\n');
}
