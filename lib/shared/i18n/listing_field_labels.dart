import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../text/pretty_title_case.dart';
import 'legacy_inline_text.dart';

String translatePlateTypeLabel(BuildContext context, String raw) {
  final v = raw.trim().toLowerCase().replaceAll('-', ' ').replaceAll('_', ' ');
  switch (v) {
    case 'private':
      return trLegacyText(context, 'Private', ar: 'خصوصي', ku: 'تایبەت');
    case 'commercial':
    case 'comercial':
      return trLegacyText(context, 'Commercial', ar: 'تجاري', ku: 'بازرگانی');
    case 'taxi':
      return trLegacyText(context, 'Taxi', ar: 'تاكسي', ku: 'تەکسی');
    case 'government':
      return trLegacyText(context, 'Government', ar: 'حكومي', ku: 'حکومی');
    case 'temporary':
      return trLegacyText(context, 'Temporary', ar: 'مؤقت', ku: 'کاتی');
    case 'diplomatic':
      return trLegacyText(context, 'Diplomatic', ar: 'دبلوماسي', ku: 'دیبلۆماسی');
    case 'police':
      return trLegacyText(context, 'Police', ar: 'شرطة', ku: 'پۆلیس');
    default:
      return prettyTitleCase(raw);
  }
}

/// Bare number `3.0` → localized + liter unit; values with badges (`3.0 D`) unchanged.
String engineSizeChipLabel(BuildContext context, String raw) {
  final t = raw.trim();
  if (double.tryParse(t) != null) {
    return '$t${AppLocalizations.of(context)!.unit_liter_suffix}';
  }
  return t;
}

String engineSizeSellRowLabel(BuildContext context, String raw) {
  final t = raw.trim();
  if (double.tryParse(t) != null) {
    return '$t ${AppLocalizations.of(context)!.unit_liter_suffix}';
  }
  return t;
}
