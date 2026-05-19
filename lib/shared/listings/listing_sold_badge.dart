import 'package:flutter/material.dart';

String listingSoldLabel(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'مُباع';
  if (code == 'ku' || code == 'ckb') return 'فرۆشراو';
  return 'SOLD';
}

/// Compact transparent red badge for sold listings.
Widget buildListingSoldBadge(
  BuildContext context, {
  bool large = false,
}) {
  final label = listingSoldLabel(context);
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: large ? 14 : 10,
      vertical: large ? 6 : 4,
    ),
    decoration: BoxDecoration(
      color: const Color(0x22D32F2F),
      borderRadius: BorderRadius.circular(large ? 8 : 6),
      border: Border.all(color: const Color(0x99D32F2F)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: const Color(0xDDD32F2F),
        fontWeight: FontWeight.w800,
        fontSize: large ? 16 : 11,
        letterSpacing: 1.1,
      ),
    ),
  );
}
