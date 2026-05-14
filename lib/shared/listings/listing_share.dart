import 'package:share_plus/share_plus.dart';

import 'listing_share_urls.dart';

/// Opens the share sheet with a single URL (HTTPS listing page when configured,
/// otherwise the `carzo://` deep link). No extra caption or image attachments.
Future<void> shareListingAsLinkOnly(String listingId) async {
  final link = listingShareLinkOnly(listingId).trim();
  if (link.isEmpty) return;
  await SharePlus.instance.share(ShareParams(text: link));
}
