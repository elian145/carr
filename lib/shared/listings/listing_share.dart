import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'listing_share_urls.dart';

/// Anchor for the iOS/iPadOS share sheet (required on some devices).
Rect? shareOriginFromContext(BuildContext context) {
  final ro = context.findRenderObject();
  if (ro is! RenderBox || !ro.hasSize) return null;
  final offset = ro.localToGlobal(Offset.zero);
  return offset & ro.size;
}

/// Opens the system share sheet (WhatsApp, Instagram, Snapchat, Messages, etc.)
/// with the listing's public **HTTPS** URL so recipients get a normal tap-to-open link.
///
/// When Universal Links / App Links are configured for the share host, tapping the
/// link opens this listing in CARZO (`/car_detail`). Otherwise the server page
/// redirects to the app when possible.
Future<void> shareListingAsLinkOnly(
  String listingId, {
  BuildContext? context,
  String? listingTitle,
  Rect? sharePositionOrigin,
}) async {
  final link = listingShareLinkOnly(listingId).trim();
  if (link.isEmpty) return;

  final origin = sharePositionOrigin ??
      (context != null ? shareOriginFromContext(context) : null);

  final parsed = Uri.tryParse(link);
  final isHttps =
      parsed != null &&
      parsed.hasScheme &&
      (parsed.scheme == 'https' || parsed.scheme == 'http');

  if (isHttps) {
    final title = (listingTitle ?? '').trim();
    final sheetTitle =
        title.isNotEmpty ? 'CARZO – $title' : 'CARZO listing';
    await SharePlus.instance.share(
      ShareParams(
        uri: parsed,
        // Many social apps (WhatsApp, Instagram DMs, Snapchat) read `text`, not `uri`.
        text: link,
        title: sheetTitle,
        subject: sheetTitle,
        sharePositionOrigin: origin,
      ),
    );
    return;
  }

  await SharePlus.instance.share(
    ShareParams(
      text: link,
      title: 'CARZO listing',
      sharePositionOrigin: origin,
    ),
  );
}
