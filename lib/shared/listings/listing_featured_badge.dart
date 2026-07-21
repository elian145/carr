import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

const Color kFeaturedListingAccent = Color(0xFFFF6B00);

String listingFeaturedLabel(BuildContext context) {
  return AppLocalizations.of(context)!.featured;
}

bool listingIsFeatured(Map car) {
  final value = car['is_featured'];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

/// Compact orange FEATURED chip for normal listing cards.
Widget buildListingFeaturedBadge(
  BuildContext context, {
  bool compact = false,
}) {
  final label = listingFeaturedLabel(context);
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 8 : 10,
      vertical: compact ? 4 : 5,
    ),
    decoration: BoxDecoration(
      color: kFeaturedListingAccent,
      borderRadius: BorderRadius.circular(compact ? 6 : 8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.star_rounded,
          color: Colors.white,
          size: compact ? 12 : 14,
        ),
        SizedBox(width: compact ? 3 : 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: compact ? 10 : 11,
            letterSpacing: 0.5,
            height: 1.1,
          ),
        ),
      ],
    ),
  );
}

/// Soft orange rim glow that follows rounded corners (stroke-only, no fill wash).
Widget wrapListingFeaturedGlow({
  required Widget child,
  double radius = 20,
}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius + 3),
      border: Border.all(
        color: kFeaturedListingAccent.withValues(alpha: 0.18),
        width: 3,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(1.5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius + 1.5),
          border: Border.all(
            color: kFeaturedListingAccent.withValues(alpha: 0.35),
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: kFeaturedListingAccent.withValues(alpha: 0.9),
                width: 1.25,
              ),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}
