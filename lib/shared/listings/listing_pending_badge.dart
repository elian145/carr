import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'listing_status.dart';

String listingPendingLabel(BuildContext context) {
  final loc = AppLocalizations.of(context);
  if (loc != null) return loc.listingPendingBadge;
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'قيد المراجعة';
  if (code == 'ku' || code == 'ckb') return 'لە ژێر پێداچوونەوە';
  return 'Under review';
}

String listingHiddenLabel(BuildContext context) {
  final loc = AppLocalizations.of(context);
  if (loc != null) return loc.listingHiddenBadge;
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'مخفي';
  if (code == 'ku' || code == 'ckb') return 'شاردراوەتەوە';
  return 'Hidden';
}

/// Amber badge for listings awaiting their first admin review.
Widget buildListingPendingBadge(BuildContext context, {bool large = false}) {
  return _buildStatusBadge(
    context,
    label: listingPendingLabel(context),
    color: const Color(0xE6F57C00),
    large: large,
  );
}

/// Red badge for listings an admin hid from public view after moderation --
/// visually distinct from [buildListingPendingBadge] so a seller never
/// mistakes "hidden by moderation" for "still awaiting first review".
Widget buildListingHiddenBadge(BuildContext context, {bool large = false}) {
  return _buildStatusBadge(
    context,
    label: listingHiddenLabel(context),
    color: const Color(0xE6C62828),
    large: large,
  );
}

Widget _buildStatusBadge(
  BuildContext context, {
  required String label,
  required Color color,
  bool large = false,
}) {
  return Semantics(
    label: label,
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 10,
        vertical: large ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(large ? 8 : 6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: large ? 13 : 11,
          letterSpacing: 0.2,
        ),
      ),
    ),
  );
}

/// Renders [buildListingHiddenBadge] for a hidden listing,
/// [buildListingPendingBadge] for a pending/draft one, or nothing for an
/// active/sold listing.
Widget? buildListingStatusBadge(
  BuildContext context,
  Map<String, dynamic>? listing, {
  bool large = false,
}) {
  if (isListingHidden(listing)) {
    return buildListingHiddenBadge(context, large: large);
  }
  if (isListingPending(listing)) {
    return buildListingPendingBadge(context, large: large);
  }
  return null;
}

bool listingShowsPendingBadge(Map<String, dynamic>? listing) =>
    isListingPendingReview(listing);
