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

/// Opens the system share sheet with a link that opens this listing in CARZO.
///
/// Shares ``carzo://listing?id=…`` so recipients can open the listing in one tap from
/// chat apps that allow custom URL schemes. Does not use an HTTPS preview link,
/// because that opens an in-app browser (e.g. Snapchat) where an "open app" button
/// cannot work.
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

  await SharePlus.instance.share(
    ShareParams(
      text: link,
      title: sheetTitle,
      subject: sheetTitle,
      sharePositionOrigin: origin,
    ),
  );
}
