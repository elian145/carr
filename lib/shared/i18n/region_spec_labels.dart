import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// Canonical codes for listing / filter "region specs" (lowercase API / DB values).
const List<String> kCarRegionSpecCodes = [
  'us',
  'gcc',
  'iraq',
  'canada',
  'eu',
  'cn',
  'korea',
  'ru',
  'iran',
];

String carRegionSpecDisplayLabel(String code) {
  switch (code.trim().toLowerCase()) {
    case 'us':
      return 'US';
    case 'gcc':
      return 'GCC';
    case 'iraq':
      return 'Iraq';
    case 'canada':
      return 'Canada';
    case 'eu':
      return 'EU';
    case 'cn':
      return 'CN';
    case 'korea':
      return 'Korea';
    case 'ru':
      return 'RU';
    case 'iran':
      return 'Iran';
    default:
      return code;
  }
}

String carRegionSpecDisplayLabelLocalized(BuildContext context, String code) {
  switch (code.trim().toLowerCase()) {
    case 'gcc':
      return AppLocalizations.of(context)!.regionSpecGcc;
    case 'us':
      return AppLocalizations.of(context)!.regionSpecUs;
    case 'iraq':
      return AppLocalizations.of(context)!.regionSpecIraq;
    case 'canada':
      return AppLocalizations.of(context)!.regionSpecCanada;
    case 'eu':
      return AppLocalizations.of(context)!.regionSpecEu;
    case 'cn':
      return AppLocalizations.of(context)!.regionSpecCn;
    case 'korea':
      return AppLocalizations.of(context)!.regionSpecKorea;
    case 'ru':
      return AppLocalizations.of(context)!.regionSpecRu;
    case 'iran':
      return AppLocalizations.of(context)!.regionSpecIran;
    default:
      return carRegionSpecDisplayLabel(code);
  }
}

bool isValidCarRegionSpecCode(String? s) {
  if (s == null || s.isEmpty) return false;
  return kCarRegionSpecCodes.contains(s.trim().toLowerCase());
}
