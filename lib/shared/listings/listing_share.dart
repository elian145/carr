import 'package:share_plus/share_plus.dart';

import 'listing_share_urls.dart';

/// Opens the share sheet with a single URL. For `http`/`https` links, uses
/// [ShareParams.uri] so the system and chat apps treat it as a proper clickable
/// link (similar to native “share URL” behavior). Custom schemes fall back to
/// plain text.
Future<void> shareListingAsLinkOnly(String listingId) async {
  final link = listingShareLinkOnly(listingId).trim();
  if (link.isEmpty) return;
  final parsed = Uri.tryParse(link);
  if (parsed != null &&
      parsed.hasScheme &&
      (parsed.scheme == 'https' || parsed.scheme == 'http')) {
    await SharePlus.instance.share(ShareParams(uri: parsed));
    return;
  }
  await SharePlus.instance.share(ShareParams(text: link));
}
