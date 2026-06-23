import 'package:flutter/widgets.dart';

import 'legacy_inline_text.dart';

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
      return trLegacyText(context, 'GCC', ar: 'خليجي', ku: 'کەنداو');
    case 'us':
      return trLegacyText(context, 'US', ar: 'أمريكي', ku: 'ئەمەریکی');
    case 'iraq':
      return trLegacyText(context, 'Iraq', ar: 'عراقي', ku: 'عێراقی');
    case 'canada':
      return trLegacyText(context, 'Canada', ar: 'كندي', ku: 'کەنەدی');
    case 'eu':
      return trLegacyText(context, 'EU', ar: 'أوروبي', ku: 'ئەوروپی');
    case 'cn':
      return trLegacyText(context, 'CN', ar: 'صيني', ku: 'چینی');
    case 'korea':
      return trLegacyText(context, 'Korea', ar: 'كوري', ku: 'کۆری');
    case 'ru':
      return trLegacyText(context, 'RU', ar: 'روسي', ku: 'ڕووسی');
    case 'iran':
      return trLegacyText(context, 'Iran', ar: 'إيراني', ku: 'ئێرانی');
    default:
      return carRegionSpecDisplayLabel(code);
  }
}

bool isValidCarRegionSpecCode(String? s) {
  if (s == null || s.isEmpty) return false;
  return kCarRegionSpecCodes.contains(s.trim().toLowerCase());
}
