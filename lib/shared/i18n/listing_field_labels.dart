import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../text/pretty_title_case.dart';

String translatePlateTypeLabel(BuildContext context, String raw) {
  final v = raw.trim().toLowerCase().replaceAll('-', ' ').replaceAll('_', ' ');
  switch (v) {
    case 'private':
      return AppLocalizations.of(context)!.plateTypePrivate;
    case 'commercial':
    case 'comercial':
      return AppLocalizations.of(context)!.plateTypeCommercial;
    case 'taxi':
      return AppLocalizations.of(context)!.plateTypeTaxi;
    case 'government':
      return AppLocalizations.of(context)!.plateTypeGovernment;
    case 'temporary':
      return AppLocalizations.of(context)!.plateTypeTemporary;
    case 'diplomatic':
      return AppLocalizations.of(context)!.plateTypeDiplomatic;
    case 'police':
      return AppLocalizations.of(context)!.plateTypePolice;
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
