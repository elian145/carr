import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

String? translateListingValue(BuildContext context, String? raw) {
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
    case 'base':
    case 'standard':
      return loc.value_trim_base;
    case 'sport':
      return loc.value_trim_sport;
    case 'luxury':
      return loc.value_trim_luxury;
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
    case 'gasoline':
      return loc.value_fuel_gasoline;
    case 'diesel':
      return loc.value_fuel_diesel;
    case 'electric':
      return loc.value_fuel_electric;
    case 'hybrid':
      return loc.value_fuel_hybrid;
    case 'lpg':
      return loc.value_fuel_lpg;
    case 'plug-in hybrid':
    case 'plugin hybrid':
    case 'plug in hybrid':
      return loc.value_fuel_plugin_hybrid;
    case 'clean':
      return loc.value_title_clean;
    case 'damaged':
      return loc.value_title_damaged;
    case 'fwd':
      return loc.value_drive_fwd;
    case 'rwd':
      return loc.value_drive_rwd;
    case 'awd':
      return loc.value_drive_awd;
    case '4wd':
      return loc.value_drive_4wd;
    case 'sedan':
      return loc.value_body_sedan;
    case 'suv':
      return loc.value_body_suv;
    case 'hatchback':
      return loc.value_body_hatchback;
    case 'coupe':
      return loc.value_body_coupe;
    case 'pickup':
      return loc.value_body_pickup;
    case 'van':
      return loc.value_body_van;
    case 'minivan':
      return loc.value_body_minivan;
    case 'motorcycle':
      return loc.value_body_motorcycle;
    case 'truck':
      return loc.value_body_truck;
    case 'cabriolet':
      return loc.value_body_cabriolet;
    case 'convertible':
      return loc.value_body_cabriolet;
    case 'roadster':
      return loc.value_body_roadster;
    case 'micro':
      return loc.value_body_micro;
    case 'cuv':
      return loc.value_body_cuv;
    case 'wagon':
      return loc.value_body_wagon;
    case 'minitruck':
      return loc.value_body_minitruck;
    case 'bigtruck':
      return loc.value_body_bigtruck;
    case 'supercar':
      return loc.value_body_supercar;
    case 'utv':
      return loc.value_body_utv;
    case 'atv':
      return loc.value_body_atv;
    case 'scooter':
      return loc.value_body_scooter;
    case 'super bike':
      return loc.value_body_super_bike;
    // Colors
    case 'black':
      return loc.value_color_black;
    case 'white':
      return loc.value_color_white;
    case 'silver':
      return loc.value_color_silver;
    case 'gray':
    case 'grey':
      return loc.value_color_gray;
    case 'red':
      return loc.value_color_red;
    case 'blue':
      return loc.value_color_blue;
    case 'green':
      return loc.value_color_green;
    case 'yellow':
      return loc.value_color_yellow;
    case 'orange':
      return loc.value_color_orange;
    case 'purple':
      return loc.value_color_purple;
    case 'brown':
      return loc.value_color_brown;
    case 'beige':
      return loc.value_color_beige;
    case 'gold':
      return loc.value_color_gold;
    // Cities
    case 'baghdad':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_baghdad
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_baghdad
          : 'Baghdad';
    case 'basra':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_basra
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_basra
          : 'Basra';
    case 'erbil':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_erbil
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_erbil
          : 'Erbil';
    case 'najaf':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_najaf
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_najaf
          : 'Najaf';
    case 'karbala':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_karbala
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_karbala
          : 'Karbala';
    case 'kirkuk':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_kirkuk
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_kirkuk
          : 'Kirkuk';
    case 'mosul':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_mosul
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_mosul
          : 'Mosul';
    case 'sulaymaniyah':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_sulaymaniyah
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_sulaymaniyah
          : 'Sulaymaniyah';
    case 'dohuk':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_dohuk
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_dohuk
          : 'Dohuk';
    case 'anbar':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_anbar
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_anbar
          : 'Anbar';
    case 'halabja':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_halabja
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_halabja
          : 'Halabja';
    case 'diyala':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_diyala
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_diyala
          : 'Diyala';
    case 'diyarbakir':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_diyarbakir
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_diyarbakir
          : 'Diyarbakir';
    case 'maysan':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_maysan
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_maysan
          : 'Maysan';
    case 'muthanna':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_muthanna
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_muthanna
          : 'Muthanna';
    case 'dhi qar':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_dhi_qar
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_dhi_qar
          : 'Dhi Qar';
    case 'salaheldeen':
      return Localizations.localeOf(context).languageCode == 'ar'
          ? loc.city_salaheldeen
          : Localizations.localeOf(context).languageCode == 'ku'
          ? loc.city_salaheldeen
          : 'Salaheldeen';
  }
  return raw;
}
