import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'listing_share_urls.dart';

/// Anchor for the iOS/iPadOS share sheet popover (optional).
Rect? shareOriginFromContext(BuildContext context) {
  final ro = context.findRenderObject();
  if (ro is! RenderBox || !ro.hasSize) return null;
  final size = ro.size;
  if (size.width <= 0 || size.height <= 0) return null;
  final offset = ro.localToGlobal(Offset.zero);
  return offset & size;
}

/// Opens the system share sheet with the listing HTTPS URL (Universal / App Links).
///
/// When configured, tapping the shared link in chat opens CARZO on this listing
/// without a manual copy/paste step.
Future<void> shareListingAsLinkOnly(
  String listingId, {
  BuildContext? context,
  String? listingTitle,
  Rect? sharePositionOrigin,
}) async {
  final link = listingShareLinkOnly(listingId).trim();
  if (link.isEmpty) return;

  Rect? origin = sharePositionOrigin;
  if (origin == null && context != null) {
    origin = shareOriginFromContext(context);
  }

  final title = (listingTitle ?? '').trim();
  final sheetTitle = title.isNotEmpty ? 'CARZO – $title' : 'CARZO listing';

  final parsed = Uri.tryParse(link);
  if (parsed != null &&
      parsed.hasScheme &&
      (parsed.scheme == 'https' || parsed.scheme == 'http')) {
    await SharePlus.instance.share(
      ShareParams(
        uri: parsed,
        title: sheetTitle,
        sharePositionOrigin: origin,
      ),
    );
    return;
  }

  await SharePlus.instance.share(
    ShareParams(
      text: link,
      title: sheetTitle,
      sharePositionOrigin: origin,
    ),
  );
}
