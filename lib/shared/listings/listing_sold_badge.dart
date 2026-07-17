import 'package:flutter/material.dart';

String listingSoldLabel(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'مُباع';
  if (code == 'ku' || code == 'ckb') return 'فرۆشراو';
  return 'SOLD';
}

/// High-contrast red badge for sold listings.
Widget buildListingSoldBadge(BuildContext context, {bool large = false}) {
  final label = listingSoldLabel(context);
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: large ? 14 : 10,
      vertical: large ? 6 : 4,
    ),
    decoration: BoxDecoration(
      color: const Color(0xE6C62828),
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
        fontSize: large ? 16 : 11,
        letterSpacing: 1.1,
      ),
    ),
  );
}
