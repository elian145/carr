import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../globals.dart';
import '../../l10n/app_localizations.dart';
import '../car/region_specs.dart';
import '../text/pretty_title_case.dart';

String? homeFilterTranslateValue(BuildContext context, String? raw) {
  if (raw == null) return null;
  final l = raw.trim().toLowerCase();
  final loc = AppLocalizations.of(context)!;
  switch (l) {
    case 'any':
      return loc.anyOption;
    case 'new':
      return loc.value_condition_new;
    case 'used':
      return loc.value_condition_used;
    case 'certified':
      return loc.value_condition_certified;
    case 'automatic':
      return loc.value_transmission_automatic;
    case 'manual':
      return loc.value_transmission_manual;
    case 'cvt':
      return loc.value_transmission_cvt;
    case 'semi-automatic':
    case 'semi automatic':
    case 'semi auto':
      return loc.value_transmission_semi_automatic;
    case 'front wheel drive':
    case 'fwd':
      return loc.value_drive_fwd;
    case 'rear wheel drive':
    case 'rwd':
      return loc.value_drive_rwd;
    case 'all wheel drive':
    case 'awd':
      return loc.value_drive_awd;
    case '4wd':
    case '4x4':
      return loc.value_drive_4wd;
    default:
      return raw;
  }
}

String homeFilterLocalizeDigits(BuildContext context, String input) {
  final locale = Localizations.localeOf(context);
  if (locale.languageCode == 'ar' ||
      locale.languageCode == 'ku' ||
      locale.languageCode == 'ckb') {
    return input;
  }
  return input;
}

String homeFilterFormatCurrency(BuildContext context, dynamic raw) {
  num? value;
  if (raw is num) {
    value = raw;
  } else {
    value = num.tryParse(
      raw?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '',
    );
  }
  final formatter = NumberFormat.decimalPattern(
    Localizations.localeOf(context).toString(),
  );
  if (value == null) {
    return globalSymbol + homeFilterLocalizeDigits(context, '0');
  }
  return globalSymbol +
      homeFilterLocalizeDigits(context, formatter.format(value));
}

String homeFilterEngineSizeChipLabel(BuildContext context, String raw) {
  final t = raw.trim();
  if (double.tryParse(t) != null) {
    return '${homeFilterLocalizeDigits(context, t)}${AppLocalizations.of(context)!.unit_liter_suffix}';
  }
  return homeFilterLocalizeDigits(context, t);
}

String homeFilterRegionSpecLabel(String code) {
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

String homeFilterPlateTypeLabel(BuildContext context, String raw) {
  final v = raw.trim().toLowerCase().replaceAll('-', ' ').replaceAll('_', ' ');
  switch (v) {
    case 'private':
      return prettyTitleCase('Private');
    case 'commercial':
    case 'comercial':
      return prettyTitleCase('Commercial');
    case 'taxi':
      return prettyTitleCase('Taxi');
    case 'government':
      return prettyTitleCase('Government');
    case 'temporary':
      return prettyTitleCase('Temporary');
    case 'diplomatic':
      return prettyTitleCase('Diplomatic');
    case 'police':
      return prettyTitleCase('Police');
    default:
      return prettyTitleCase(raw);
  }
}

bool homeFilterIsActiveValue(dynamic value) {
  if (value == null) return false;
  final s = value.toString().trim();
  if (s.isEmpty) return false;
  return s.toLowerCase() != 'any';
}

bool homeFilterRegionActive(String? code) {
  if (code == null || code.isEmpty) return false;
  return isValidCarRegionSpecCode(code);
}
