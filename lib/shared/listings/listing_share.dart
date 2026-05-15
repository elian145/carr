import 'dart:async';

import 'package:airbridge_flutter_sdk/airbridge_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/config.dart';
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

/// Opens the system share sheet with an Airbridge short link when configured
/// ([kAirbridgeDartConfigured]), otherwise the HTTPS listing URL (Universal / App Links).
Future<void> shareListingAsLinkOnly(
  String listingId, {
  BuildContext? context,
  String? listingTitle,
  Rect? sharePositionOrigin,
}) async {
  if (kAirbridgeDartConfigured) {
    await _shareListingViaAirbridge(
      listingId,
      context: context,
      listingTitle: listingTitle,
      sharePositionOrigin: sharePositionOrigin,
    );
    return;
  }
  await _shareListingDirect(
    listingId,
    context: context,
    listingTitle: listingTitle,
    sharePositionOrigin: sharePositionOrigin,
  );
}

Future<void> _shareListingViaAirbridge(
  String listingId, {
  BuildContext? context,
  String? listingTitle,
  Rect? sharePositionOrigin,
}) async {
  final id = listingId.trim();
  if (id.isEmpty) return;

  Rect? origin = sharePositionOrigin;
  if (origin == null && context != null) {
    origin = shareOriginFromContext(context);
  }
  final title = (listingTitle ?? '').trim();
  final sheetTitle = title.isNotEmpty ? 'CARZO – $title' : 'CARZO listing';

  final deep = listingDeepLink(id);
  final fallback = listingWebShareLinkWebPreview(id) ?? listingWebShareLink(id);
  if (fallback == null || fallback.isEmpty) {
    await _shareListingDirect(
      id,
      context: context,
      listingTitle: listingTitle,
      sharePositionOrigin: sharePositionOrigin,
    );
    return;
  }

  final completer = Completer<void>();
  var completed = false;

  void completeOnce() {
    if (completed) return;
    completed = true;
    if (!completer.isCompleted) completer.complete();
  }

  Airbridge.createTrackingLink(
    channel: kAirbridgeListingChannel.trim().isEmpty
        ? 'listing_share'
        : kAirbridgeListingChannel.trim(),
    option: <String, dynamic>{
      AirbridgeTrackingLinkOption.DEEPLINK_URL: deep,
      AirbridgeTrackingLinkOption.FALLBACK_IOS: fallback,
      AirbridgeTrackingLinkOption.FALLBACK_ANDROID: fallback,
      AirbridgeTrackingLinkOption.FALLBACK_DESKTOP: fallback,
    },
    onSuccess: (AirbridgeTrackingLink link) async {
      try {
        final parsed = Uri.tryParse(link.shortURL.trim());
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
        } else {
          await SharePlus.instance.share(
            ShareParams(
              text: link.shortURL.trim(),
              title: sheetTitle,
              sharePositionOrigin: origin,
            ),
          );
        }
      } finally {
        completeOnce();
      }
    },
    onFailure: (_) {
      _shareListingDirect(
        id,
        listingTitle: listingTitle,
        sharePositionOrigin: origin,
      ).whenComplete(completeOnce);
    },
  );

  await completer.future.timeout(
    const Duration(seconds: 12),
    onTimeout: () {
      if (!completed) {
        _shareListingDirect(
          id,
          listingTitle: listingTitle,
          sharePositionOrigin: origin,
        ).whenComplete(completeOnce);
      }
    },
  );
}

Future<void> _shareListingDirect(
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
