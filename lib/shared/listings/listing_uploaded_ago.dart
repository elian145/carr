import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// Human-readable "time since listing was created" for card and detail UI.
String listingUploadedAgo(BuildContext context, Map car) {
  final loc = AppLocalizations.of(context);
  if (loc == null) return '';
  dynamic raw = car['created_at'];
  if (raw == null || raw.toString().trim().isEmpty) {
    raw = car['posted_at'] ?? car['listed_at'];
  }
  if (raw == null) return '';
  final dt = DateTime.tryParse(raw.toString().trim());
  if (dt == null) return '';
  final now = DateTime.now();
  var diff = now.difference(dt);
  if (diff.isNegative) diff = Duration.zero;
  if (diff.inMinutes < 1) return loc.justNow;

  var years = now.year - dt.year;
  var months = now.month - dt.month;
  if (now.day < dt.day) months -= 1;
  if (months < 0) {
    years -= 1;
    months += 12;
  }
  if (years >= 1) return loc.timeYearsAgo(years);
  if (months >= 1) return loc.timeMonthsAgo(months);

  if (diff.inHours < 24) {
    if (diff.inHours < 1) {
      return loc.timeMinutesAgo(diff.inMinutes < 1 ? 1 : diff.inMinutes);
    }
    return loc.timeHoursAgo(diff.inHours);
  }
  final days = diff.inDays;
  return loc.timeDaysAgo(days < 1 ? 1 : days);
}
