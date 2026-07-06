import 'package:flutter/material.dart';

/// Parses a single opening-hours time token such as `9:00 AM`, `9:00 pm`,
/// `9:00 م`, or `11:30 ص`.
TimeOfDay? parseHourTimeToken(String raw) {
  var token = raw.trim();
  if (token.isEmpty) return null;

  token = token.replaceAll(RegExp(r'\s*ص\.?\s*$'), ' am');
  token = token.replaceAll(RegExp(r'\s*م\.?\s*$'), ' pm');

  final m = RegExp(
    r'^\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*$',
    caseSensitive: false,
  ).firstMatch(token);
  if (m == null) return null;

  int? h = int.tryParse(m.group(1) ?? '');
  final min = int.tryParse(m.group(2) ?? '0') ?? 0;
  final ap = (m.group(3) ?? '').toLowerCase();
  if (h == null || min < 0 || min > 59) return null;

  if (ap.isNotEmpty) {
    if (h < 1 || h > 12) return null;
    if (ap == 'am') {
      h = h == 12 ? 0 : h;
    } else if (ap == 'pm') {
      h = h == 12 ? 12 : h + 12;
    }
  } else {
    if (h < 0 || h > 23) return null;
  }

  return TimeOfDay(hour: h, minute: min);
}
