import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../globals.dart';
import 'digits.dart';
import '../../shared/debug/app_log.dart';

NumberFormat decimalFormatterForLocale(BuildContext context) {
  String tag = Localizations.localeOf(context).toLanguageTag();
  if (tag.startsWith('ku')) tag = 'ar';
  try {
    return NumberFormat.decimalPattern(tag);
  } catch (e, st) { logNonFatal(e, st); 
    return NumberFormat.decimalPattern('en');
  }
}

num? tryParseCurrencyValue(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw > 0 ? raw : null;
  final cleaned = raw.toString().trim().replaceAll(RegExp(r'[^0-9.-]'), '');
  if (cleaned.isEmpty) return null;
  final parsed = num.tryParse(cleaned);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

/// Locale-aware currency formatting with digit localization.
String formatCurrency(BuildContext context, dynamic raw, {String? symbol}) {
  final sym = symbol ?? globalSymbol;
  final value = tryParseCurrencyValue(raw);
  if (value == null) {
    return '';
  }
  final formatter = decimalFormatterForLocale(context);
  return sym + localizeDigits(context, formatter.format(value));
}
