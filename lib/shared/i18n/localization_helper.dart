import 'package:flutter/material.dart';

/// Returns the localized name for an item from the database.
/// Expects the item to have optional keys: name_en, name_ar, name_ku.
/// Falls back to name_en, then the first non-null name_* value, then empty string.
String getLocalizedName(BuildContext context, Map<String, dynamic>? item) {
  if (item == null) return '';
  final locale = Localizations.localeOf(context).languageCode;
  final String? localized = item['name_$locale']?.toString().trim();
  if (localized != null && localized.isNotEmpty) return localized;
  final String? en = item['name_en']?.toString().trim();
  if (en != null && en.isNotEmpty) return en;
  for (final key in ['name_ar', 'name_ku']) {
    final v = item[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return item['name']?.toString().trim() ?? '';
}

/// Returns whether the current locale is RTL (Arabic or Kurdish).
bool isRtlLocale(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  return code == 'ar' || code == 'ku';
}
