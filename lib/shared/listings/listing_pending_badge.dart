import 'package:flutter/material.dart';

String listingPendingLabel(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'قيد المراجعة';
  if (code == 'ku' || code == 'ckb') return 'چاوەڕوانی پێداچوونەوە';
  return 'PENDING';
}

/// Amber badge for listings awaiting admin approval.
Widget buildListingPendingBadge(BuildContext context, {bool large = false}) {
  final label = listingPendingLabel(context);
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: large ? 14 : 10,
      vertical: large ? 6 : 4,
    ),
    decoration: BoxDecoration(
      color: const Color(0xE6F57C00),
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
        fontSize: large ? 14 : 11,
        letterSpacing: 0.8,
      ),
    ),
  );
}

bool listingShowsPendingBadge(Map<String, dynamic>? listing) {
  final status = (listing?['status'] ?? '').toString().trim().toLowerCase();
  return status == 'pending' || status == 'draft' || status == 'hidden';
}
