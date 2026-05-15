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
/// Uses the public **HTTPS** URL with [ShareParams.uri] so iOS/Android can hand off
/// via Universal / App Links when the recipient taps the link (one tap → in-app listing).
Future<void> shareListingAsLinkOnly(
  String listingId, {
  BuildContext? context,
  String? listingTitle,
  Rect? sharePositionOrigin,
}) async {
  final id = listingId.trim();
  if (id.isEmpty) return;

  final web = listingWebShareLink(id)?.trim() ?? '';
  final deep = listingDeepLink(id).trim();

  Rect? origin = sharePositionOrigin;
  if (origin == null && context != null) {
    origin = shareOriginFromContext(context);
  }

  final title = (listingTitle ?? '').trim();
  final sheetTitle = title.isNotEmpty ? 'CARZO – $title' : 'CARZO listing';

  final parsedWeb = web.isNotEmpty ? Uri.tryParse(web) : null;
  if (parsedWeb != null &&
      parsedWeb.hasScheme &&
      (parsedWeb.scheme == 'https' || parsedWeb.scheme == 'http')) {
    await SharePlus.instance.share(
      ShareParams(
        uri: parsedWeb,
        title: sheetTitle,
        sharePositionOrigin: origin,
      ),
    );
    return;
  }

  final fallback = deep.isNotEmpty ? deep : web;
  if (fallback.isEmpty) return;
  await SharePlus.instance.share(
    ShareParams(
      text: fallback,
      title: sheetTitle,
      sharePositionOrigin: origin,
    ),
  );
}
