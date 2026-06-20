import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../globals.dart';
import 'digits.dart';

NumberFormat decimalFormatterForLocale(BuildContext context) {
  String tag = Localizations.localeOf(context).toLanguageTag();
  if (tag.startsWith('ku')) tag = 'ar';
  try {
    return NumberFormat.decimalPattern(tag);
  } catch (_) {
    return NumberFormat.decimalPattern('en');
  }
}

/// Locale-aware currency formatting with digit localization.
String formatCurrency(BuildContext context, dynamic raw, {String? symbol}) {
  final sym = symbol ?? globalSymbol;
  num? value;
  if (raw is num) {
    value = raw;
  } else {
    value = num.tryParse(
      raw?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '',
    );
  }
  if (value == null) {
    return sym + localizeDigits(context, '0');
  }
  final formatter = decimalFormatterForLocale(context);
  return sym + localizeDigits(context, formatter.format(value));
}
