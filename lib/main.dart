import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart' as services;
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'services/analytics_service.dart';
import 'services/api_service.dart';
import 'models/analytics_model.dart';
import 'pages/analytics_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'widgets/theme_toggle_widget.dart';
import 'services/config.dart';
// Sideload build flag to disable services that require entitlements on iOS
const bool kSideloadBuild = bool.fromEnvironment('SIDELOAD_BUILD', defaultValue: false);
// Build commit SHA for on-device verification
const String kBuildSha = String.fromEnvironment('BUILD_COMMIT_SHA', defaultValue: 'dev');

// Fallback delegates to provide Material/Cupertino/Widgets localizations for 'ku'
class KuMaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const KuMaterialLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<MaterialLocalizations> load(Locale locale) {
    // Reuse Arabic material localizations for Kurdish
    return GlobalMaterialLocalizations.delegate.load(const Locale('ar'));
  }
  @override
  bool shouldReload(covariant LocalizationsDelegate<MaterialLocalizations> old) => false;
}

class KuCupertinoLocalizationsDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const KuCupertinoLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    // Reuse Arabic cupertino localizations for Kurdish
    return GlobalCupertinoLocalizations.delegate.load(const Locale('ar'));
  }
  @override
  bool shouldReload(covariant LocalizationsDelegate<CupertinoLocalizations> old) => false;
}

class KuWidgetsLocalizationsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const KuWidgetsLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    // Reuse Arabic widgets localizations for Kurdish
    return GlobalWidgetsLocalizations.delegate.load(const Locale('ar'));
  }
  @override
  bool shouldReload(covariant LocalizationsDelegate<WidgetsLocalizations> old) => false;
}
 

String getApiBase() {
  return apiBase();
}

String _localizeDigitsGlobal(BuildContext context, String input) {
  final locale = Localizations.localeOf(context);
  if (locale.languageCode == 'ar' || locale.languageCode == 'ku') {
    const western = ['0','1','2','3','4','5','6','7','8','9',','];
    const eastern = ['Ù ','Ù¡','Ù¢','Ù£','Ù¤','Ù¥','Ù¦','Ù§','Ù¨','Ù©','Ù¬'];
    String out = input;
    for (int i = 0; i < western.length; i++) {
      out = out.replaceAll(western[i], eastern[i]);
    }
    return out;
  }
  return input;
}

// Locale-aware currency formatting with digit localization
String _formatCurrencyGlobal(BuildContext context, dynamic raw) {
  final symbol = AppLocalizations.of(context)!.currencySymbol;
  num? value;
  if (raw is num) {
    value = raw;
  } else {
    value = num.tryParse(raw?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '');
  }
  if (value == null) {
    return symbol + _localizeDigitsGlobal(context, '0');
  }
  final formatter = _decimalFormatterGlobal(context);
  return symbol + _localizeDigitsGlobal(context, formatter.format(value));
}

// Fancy selector tile used in Sell page pickers
Widget buildFancySelector(BuildContext context, {IconData? icon, required String label, required String? value, Widget? leading, bool isError = false}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color accent = const Color(0xFFFF6B00);
  final List<Color> bg = isDark
      ? [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.03)]
      : [Colors.white, const Color(0xFFFFF1E6)];
  final Color borderColor = isError ? Colors.redAccent : (isDark ? Colors.white12 : accent.withOpacity(0.25));
  final Color labelColor = isError ? Colors.redAccent : (isDark ? Colors.white70 : Colors.grey[600]!);
  final Color valueColor = (value == null || value.isEmpty)
      ? (isError ? Colors.redAccent : (isDark ? Colors.white38 : Colors.grey))
      : (isError ? Colors.redAccent : (isDark ? Colors.white : Colors.grey[900]!));
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: bg, begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 6))],
    ),
    child: Row(
      children: [
        Container(width: 4, height: 44, decoration: BoxDecoration(color: (isError ? Colors.redAccent : accent).withOpacity(0.9), borderRadius: BorderRadius.circular(999))),
        const SizedBox(width: 10),
        leading ?? Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: (isError ? Colors.redAccent : accent).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: icon != null ? Icon(icon, color: isError ? Colors.redAccent : accent) : const SizedBox.shrink(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: labelColor, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              value == null || value.isEmpty ? _tapToSelectTextGlobal(context) : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: valueColor),
            ),
          ]),
        ),
      ],
    ),
  );
}

String _cancelTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ø¥Ù„ØºØ§Ø¡';
  if (code == 'ku') return 'Ù¾Ø§Ø´Ú¯Û•Ø²Ø¨ÙˆÙˆÙ†Û•ÙˆÛ•';
  return 'Cancel';
}

String _contactForPriceGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ø§ØªØµÙ„ Ù„Ù„Ø³Ø¹Ø±';
  if (code == 'ku') return 'Ù†Ø±Ø® Ø¨Ù¾Ø±Ø³Û• Ø¨Û• Ù¾Û•ÛŒÙˆÛ•Ù†Ø¯ÛŒ';
  return 'Contact for price';
}

String _pleaseFillRequiredGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'ÙŠØ±Ø¬Ù‰ Ø¥ÙƒÙ…Ø§Ù„';
  if (code == 'ku') return 'ØªÚ©Ø§ÛŒÛ• Ù¾Ú• Ø¨Ú©Û•Ø±Û•ÙˆÛ•';
  return 'Please complete';
}

NumberFormat _decimalFormatterGlobal(BuildContext context) {
  String tag = Localizations.localeOf(context).toLanguageTag();
  if (tag.startsWith('ku')) tag = 'ar';
  try {
    return NumberFormat.decimalPattern(tag);
  } catch (_) {
    return NumberFormat.decimalPattern('en');
  }
}

// Lightweight helpers for translating UI snippets not covered by AppLocalizations
String _yesTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ù†Ø¹Ù…';
  if (code == 'ku') return 'Ø¨Û•ÚµÛŽ';
  return 'Yes';
}

String _noTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ù„Ø§';
  if (code == 'ku') return 'Ù†Û•Ø®ÛŽØ±';
  return 'No';
}

String _removedFromComparisonTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'ØªÙ…Øª Ø§Ù„Ø¥Ø²Ø§Ù„Ø© Ù…Ù† Ø§Ù„Ù…Ù‚Ø§Ø±Ù†Ø©';
  if (code == 'ku') return 'Ù„Û• Ø¨Û•Ø±Û•ÙˆØ±Ø¯Ù† Ù„Ø§Ø¨Ø±Ø§';
  return 'Removed from comparison';
}

String _addedToComparisonTextGlobal(BuildContext context, int count) {
  final code = Localizations.localeOf(context).languageCode;
  final cnt = _localizeDigitsGlobal(context, count.toString());
  final max = _localizeDigitsGlobal(context, '5');
  if (code == 'ar') return 'ØªÙ…Øª Ø§Ù„Ø¥Ø¶Ø§ÙØ© Ø¥Ù„Ù‰ Ø§Ù„Ù…Ù‚Ø§Ø±Ù†Ø© ($cnt/$max)';
  if (code == 'ku') return 'Ø²ÛŒØ§Ø¯ Ú©Ø±Ø§ Ø¨Û† Ø¨Û•Ø±Û•ÙˆØ±Ø¯Ù† ($cnt/$max)';
  return 'Added to comparison ($cnt/$max)';
}

String _comparisonMaxLimitTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  final five = _localizeDigitsGlobal(context, '5');
  if (code == 'ar') return 'ÙŠÙ…ÙƒÙ† Ù…Ù‚Ø§Ø±Ù†Ø© $five Ø³ÙŠØ§Ø±Ø§Øª ÙƒØ­Ø¯ Ø£Ù‚ØµÙ‰';
  if (code == 'ku') return 'Ø²Û†Ø±ØªØ±ÛŒÙ† $five Ø¦Û†ØªÛ†Ù…Ø¨ÛŽÙ„ Ø¯Û•ØªÙˆØ§Ù†Ø±ÛŽØª Ø¨Û•Ø±Û•ÙˆØ±Ø¯ Ø¨Ú©Ø±ÛŽÙ†';
  return 'Maximum $five cars can be compared';
}

String _compareLabelGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ù‚Ø§Ø±Ù† +';
  if (code == 'ku') return 'Ø¨Û•Ø±Ø§ÙˆØ±Ø¯Ú©Ø±Ø¯Ù† +';
  return 'compare +';
}

String _addedLabelGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'ØªÙ…Øª Ø§Ù„Ø¥Ø¶Ø§ÙØ©';
  if (code == 'ku') return 'Ø²ÛŒØ§Ø¯ Ú©Ø±Ø§';
  return 'Added';
}

String _clearAllTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ù…Ø³Ø­ Ø§Ù„ÙƒÙ„';
  if (code == 'ku') return 'Ù‡Û•Ù…ÙˆÙˆ Ù¾Ø§Ú© Ø¨Ú©Û•';
  return 'Clear all';
}

String _tapToSelectTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ø§Ø®ØªØ±';
  if (code == 'ku') return 'Ù‡Û•Ù„Ø¨Ú˜ÛŽØ±Û•';
  return 'Tap to select';
}

String _comparisonClearedTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'ØªÙ… Ù…Ø³Ø­ Ø§Ù„Ù…Ù‚Ø§Ø±Ù†Ø©';
  if (code == 'ku') return 'Ø¨Û•Ø±Û•ÙˆØ±Ø¯Ù† Ù¾Ø§Ú© Ú©Ø±Ø§';
  return 'Comparison cleared';
}

String _statusTitleGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ø§Ù„Ø­Ø§Ù„Ø©';
  if (code == 'ku') return 'Ø¯Û†Ø®';
  return 'Status';
}

String _quickSellTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ø¨ÙŠØ¹ Ø³Ø±ÙŠØ¹';
  if (code == 'ku') return 'ÙØ±Û†Ø´ØªÙ†ÛŒ Ø®ÛŽØ±Ø§';
  return 'Quick Sell';
}

String _ownersLabelGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ø¹Ø¯Ø¯ Ø§Ù„Ù…Ù„Ø§Ùƒ';
  if (code == 'ku') return 'Ú˜Ù…Ø§Ø±Û•ÛŒ Ø®Ø§ÙˆÛ•Ù†Ø¯Ø§Ø±';
  return 'Owners';
}

String _vinLabelGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ø±Ù‚Ù… Ø§Ù„Ø´Ø§ØµÙŠ (VIN)';
  if (code == 'ku') return 'Ú˜Ù…Ø§Ø±Û•ÛŒ Ø´Ø§Ø³ÛŒ (VIN)';
  return 'VIN';
}

String _accidentHistoryLabelGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ø³Ø¬Ù„ Ø§Ù„Ø­ÙˆØ§Ø¯Ø«';
  if (code == 'ku') return 'Ù…ÛŽÚ˜ÙˆÙˆÛŒ Ú©Ø§Ø±Û•Ø³Ø§Øª';
  return 'Accident History';
}

String _photosRequiredTitleGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ø§Ù„ØµÙˆØ± (Ø¥Ù„Ø²Ø§Ù…ÙŠØ©)';
  if (code == 'ku') return 'ÙˆÛŽÙ†Û•Ú©Ø§Ù† (Ù¾ÛŽÙˆÛŒØ³ØªÛ•)';
  return 'Photos (Required)';
}

String _videosOptionalTitleGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'Ø§Ù„ÙÙŠØ¯ÙŠÙˆÙ‡Ø§Øª (Ø§Ø®ØªÙŠØ§Ø±ÙŠ)';
  if (code == 'ku') return 'Ú¤ÛŒØ¯ÛŒÛ†Ú©Ø§Ù† (Ù‡Û•Ù„Ø¨Ú˜Ø§Ø±Ø¯Û•)';
  return 'Videos (Optional)';
}

String _pleaseSelectPhotoTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'ÙŠØ±Ø¬Ù‰ Ø§Ø®ØªÙŠØ§Ø± ØµÙˆØ±Ø© ÙˆØ§Ø­Ø¯Ø© Ø¹Ù„Ù‰ Ø§Ù„Ø£Ù‚Ù„';
  if (code == 'ku') return 'ØªÚ©Ø§ÛŒÛ• Ø¨Û•Ù„Ø§ÛŒÛ•Ù†ÛŒ Ú©Û•Ù…Û•ÙˆÛ• ÛŒÛ•Ú© ÙˆÛŽÙ†Û• Ù‡Û•Ù„Ø¨Ú˜ÛŽØ±Û•';
  return 'Please select at least one photo';
}

String _listingSubmittedSuccessTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'ØªÙ… Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„Ø¥Ø¹Ù„Ø§Ù† Ø¨Ù†Ø¬Ø§Ø­!';
  if (code == 'ku') return 'Ú•ÛŽÚ©Ù„Ø§Ù… Ø¨Û•Ø³Û•Ø±ÙƒÛ•ÙˆØªÙˆÙˆÛŒÛŒ Ù†ÛŽØ±Ø¯Ø±Ø§!';
  return 'Listing submitted successfully!';
}

String _couldNotLoadListingsTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'ØªØ¹Ø°Ù‘Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ø¥Ø¹Ù„Ø§Ù†Ø§Øª';
  if (code == 'ku') return 'Ù†Û•ØªÙˆØ§Ù†Ø±Ø§ Ú•ÛŽÚ©Ù„Ø§Ù…Û•Ú©Ø§Ù† Ø¨Ø§Ø±Ø¨Ú©Ø±ÛŽÙ†';
  return 'Could not load listings';
}

String _photosUploadedTextGlobal(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'ØªÙ… ØªØ­Ù…ÙŠÙ„ Ø§Ù„ØµÙˆØ±';
  if (code == 'ku') return 'ÙˆÛŽÙ†Û•Ú©Ø§Ù† Ø¨Ø§Ø±Ú©Ø±Ø§Ù†';
  return 'Photos uploaded';
}

// Convert localized sort options to backend API parameters
String? _convertSortToApiValue(BuildContext context, String? sortOption) {
  if (sortOption == null || sortOption.isEmpty) return null;
  
  final loc = AppLocalizations.of(context)!;
  
  // Map localized sort options to backend API values
  if (sortOption == loc.defaultSort) return null;
  if (sortOption == loc.sort_newest) return 'newest';
  if (sortOption == loc.sort_price_low_high) return 'price_asc';
  if (sortOption == loc.sort_price_high_low) return 'price_desc';
  if (sortOption == loc.sort_year_newest) return 'year_desc';
  if (sortOption == loc.sort_year_oldest) return 'year_asc';
  if (sortOption == loc.sort_mileage_low_high) return 'mileage_asc';
  if (sortOption == loc.sort_mileage_high_low) return 'mileage_desc';
  
  // Fallback for any unrecognized sort option
  return sortOption;
}

String? _translateValueGlobal(BuildContext context, String? raw) {
  if (raw == null) return null;
  final l = raw.trim().toLowerCase();
  final loc = AppLocalizations.of(context)!;
  switch (l) {
    case 'new': return loc.value_condition_new;
    case 'used': return loc.value_condition_used;
    case 'base':
    case 'standard':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø£Ø³Ø§Ø³ÙŠ' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ø¨Ù†Û•Ú•Û•ØªÛŒ' : 'Base';
    case 'sport':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø±ÙŠØ§Ø¶ÙŠ' : Localizations.localeOf(context).languageCode == 'ku' ? 'ÙˆÛ•Ø±Ø²Ø´ÛŒ' : 'Sport';
    case 'luxury':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'ÙØ§Ø®Ø±' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ù„ÙˆÚ©Ø³' : 'Luxury';
    case 'certified':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ù…Ø¹ØªÙ…Ø¯' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ø³Û•Ù„Ù…ÛŽÙ†Ø±Ø§Ùˆ' : 'certified';
    case 'automatic': return loc.value_transmission_automatic;
    case 'manual': return loc.value_transmission_manual;
    case 'semi-automatic':
    case 'semi automatic':
    case 'semi auto':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ù†ØµÙ Ø£ÙˆØªÙˆÙ…Ø§ØªÙŠÙƒ' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ù†ÛŒÙ…Û• Ø¦Û†ØªÛ†Ù…Ø§ØªÛŒÚ©' : 'semi-automatic';
    case 'gasoline': return loc.value_fuel_gasoline;
    case 'diesel': return loc.value_fuel_diesel;
    case 'electric': return loc.value_fuel_electric;
    case 'hybrid': return loc.value_fuel_hybrid;
    case 'lpg': return loc.value_fuel_lpg;
    case 'plug-in hybrid':
    case 'plugin hybrid':
    case 'plug in hybrid': return loc.value_fuel_plugin_hybrid;
    case 'clean': return loc.value_title_clean;
    case 'damaged': return loc.value_title_damaged;
    case 'fwd': return loc.value_drive_fwd;
    case 'rwd': return loc.value_drive_rwd;
    case 'awd': return loc.value_drive_awd;
    case '4wd': return loc.value_drive_4wd;
    case 'sedan': return loc.value_body_sedan;
    case 'suv': return loc.value_body_suv;
    case 'hatchback': return loc.value_body_hatchback;
    case 'coupe': return loc.value_body_coupe;
    case 'pickup': return loc.value_body_pickup;
    case 'van': return loc.value_body_van;
    case 'minivan': return loc.value_body_minivan;
    case 'motorcycle': return loc.value_body_motorcycle;
    case 'truck': return loc.value_body_truck;
    case 'cabriolet': return loc.value_body_cabriolet;
    case 'convertible': return loc.value_body_cabriolet;
    case 'roadster': return loc.value_body_roadster;
    case 'micro': return loc.value_body_micro;
    case 'cuv': return loc.value_body_cuv;
    case 'wagon': return loc.value_body_wagon;
    case 'minitruck': return loc.value_body_minitruck;
    case 'bigtruck': return loc.value_body_bigtruck;
    case 'supercar': return loc.value_body_supercar;
    case 'utv': return loc.value_body_utv;
    case 'atv': return loc.value_body_atv;
    case 'scooter': return loc.value_body_scooter;
    case 'super bike': return loc.value_body_super_bike;
    // Colors (AR + KU)
    case 'black':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø£Ø³ÙˆØ¯' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ú•Û•Ø´' : 'Black';
    case 'white':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø£Ø¨ÙŠØ¶' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ø³Ù¾ÛŒ' : 'White';
    case 'silver':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'ÙØ¶ÙŠ' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ù†Û•Ù‚Ø±Û•ÛŒ' : 'Silver';
    case 'gray':
    case 'grey':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø±Ù…Ø§Ø¯ÙŠ' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ø®Û†ÚµÛ•Ù¾ÛŽÙˆ' : 'Gray';
    case 'red':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø£Ø­Ù…Ø±' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ø³Û†Ø±' : 'Red';
    case 'blue':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø£Ø²Ø±Ù‚' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ø´ÛŒÙ†' : 'Blue';
    case 'green':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø£Ø®Ø¶Ø±' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ø³Û•ÙˆØ²' : 'Green';
    case 'yellow':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø£ØµÙØ±' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ø²Û•Ø±Ø¯' : 'Yellow';
    case 'orange':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø¨Ø±ØªÙ‚Ø§Ù„ÙŠ' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ù¾Ø±ØªÛ•Ù‚Û•ÚµÛŒ' : 'Orange';
    case 'purple':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø¨Ù†ÙØ³Ø¬ÙŠ' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ù…Û†Ø±' : 'Purple';
    case 'brown':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø¨Ù†ÙŠ' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ù‚Ø§ÙˆÛ•ÛŒÛŒ' : 'Brown';
    case 'beige':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø¨ÙŠØ¬' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ø¨ÛŽÚ˜ÛŒ' : 'Beige';
    case 'gold':
      return Localizations.localeOf(context).languageCode == 'ar' ? 'Ø°Ù‡Ø¨ÙŠ' : Localizations.localeOf(context).languageCode == 'ku' ? 'Ø²ÛŽÚ•ÛŒ' : 'Gold';
    // Cities
    case 'baghdad':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_baghdad : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_baghdad : 'Baghdad';
    case 'basra':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_basra : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_basra : 'Basra';
    case 'erbil':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_erbil : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_erbil : 'Erbil';
    case 'najaf':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_najaf : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_najaf : 'Najaf';
    case 'karbala':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_karbala : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_karbala : 'Karbala';
    case 'kirkuk':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_kirkuk : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_kirkuk : 'Kirkuk';
    case 'mosul':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_mosul : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_mosul : 'Mosul';
    case 'sulaymaniyah':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_sulaymaniyah : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_sulaymaniyah : 'Sulaymaniyah';
    case 'dohuk':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_dohuk : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_dohuk : 'Dohuk';
    case 'anbar':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_anbar : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_anbar : 'Anbar';
    case 'halabja':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_halabja : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_halabja : 'Halabja';
    case 'diyala':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_diyala : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_diyala : 'Diyala';
    case 'diyarbakir':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_diyarbakir : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_diyarbakir : 'Diyarbakir';
    case 'maysan':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_maysan : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_maysan : 'Maysan';
    case 'muthanna':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_muthanna : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_muthanna : 'Muthanna';
    case 'dhi qar':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_dhi_qar : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_dhi_qar : 'Dhi Qar';
    case 'salaheldeen':
      return Localizations.localeOf(context).languageCode == 'ar' ? loc.city_salaheldeen : Localizations.localeOf(context).languageCode == 'ku' ? loc.city_salaheldeen : 'Salaheldeen';
  }
  return raw;
}

// Global car card building function to ensure consistency across all pages
Widget buildGlobalCarCard(BuildContext context, Map car) {
  final brand = car['brand'] ?? '';
  final brandId = brandLogoFilenames[brand] ?? brand.toString().toLowerCase().replaceAll(' ', '-').replaceAll('Ã©', 'e').replaceAll('Ã¶', 'o');
  
  return Container(
    height: 205, // Standard height for all car cards
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.10),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Stack(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.pushNamed(
              context,
              '/car_detail',
              arguments: {'carId': car['id']},
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quick Sell Banner (conditional height)
              if (car['is_quick_sell'] == true || car['is_quick_sell'] == 'true')
                Container(
                  width: double.infinity,
                  height: 35, // Fixed height for banner
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange, Colors.deepOrange],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flash_on, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'QUICK SELL',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              // Image section
              Container(
                height: (car['is_quick_sell'] == true || car['is_quick_sell'] == 'true') ? 120 : 170,
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: (car['is_quick_sell'] == true || car['is_quick_sell'] == 'true') 
                      ? Radius.zero 
                      : Radius.circular(20),
                    bottom: Radius.zero,
                  ),
                  child: _buildGlobalCardImageCarousel(context, car),
                ),
              ),
              // Content section
              Container(
                height: 85, // Standard height for content
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (car['brand'] != null && car['brand'].toString().isNotEmpty)
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: Container(
                              width: 28,
                              height: 28,
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: CachedNetworkImage(
                                imageUrl: getApiBase() + '/static/images/brands/' + brandId + '.png',
                                placeholder: (context, url) => SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                errorWidget: (context, url, error) => Icon(Icons.directions_car, size: 20, color: Color(0xFFFF6B00)),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            car['title'] ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6B00),
                              fontSize: 15,
                              height: 1.1,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      _formatCurrencyGlobal(context, car['price']),
                      style: TextStyle(
                        color: Color(0xFFFF6B00),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Bottom info positioned relative to entire card
        Positioned(
          bottom: 35,
          left: 12,
          right: 12,
          child: Text(
            '${_localizeDigitsGlobal(context, (car['year'] ?? '').toString())} â€¢ ${_localizeDigitsGlobal(context, (car['mileage'] ?? '').toString())} ${AppLocalizations.of(context)!.unit_km}',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        // City name at bottom
        Positioned(
          bottom: 15,
          left: 12,
          child: Text(
            '${_translateValueGlobal(context, car['city']?.toString()) ?? (car['city'] ?? '')}',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

// Global image carousel for consistency
Widget _buildGlobalCardImageCarousel(BuildContext context, Map car) {
  final List<String> urls = () {
    final List<String> u = [];
    final String primary = (car['image_url'] ?? '').toString();
    final List<dynamic> imgs = (car['images'] is List) ? (car['images'] as List) : const [];
    if (primary.isNotEmpty) {
      u.add(getApiBase() + '/static/uploads/' + primary);
    }
    for (final dynamic it in imgs) {
      final s = it.toString();
      if (s.isNotEmpty) {
        final full = getApiBase() + '/static/uploads/' + s;
        if (!u.contains(full)) u.add(full);
      }
    }
    return u;
  }();

  if (urls.isEmpty) {
    return Container(
      color: Colors.grey[900],
      width: double.infinity,
      child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
    );
  }

  final PageController controller = PageController();
  int currentIndex = 0;

  return StatefulBuilder(
    builder: (context, setState) {
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(
                context,
                '/car_detail',
                arguments: {'carId': car['id']},
              );
            },
            child: PageView.builder(
              controller: controller,
              onPageChanged: (i) => setState(() => currentIndex = i),
              itemCount: urls.length,
              itemBuilder: (context, i) {
                final url = urls[i];
                return CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.white10,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[900],
                    child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
                  ),
                );
              },
            ),
          ),
          if (urls.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(urls.length, (i) {
                    final active = i == currentIndex;
                    return AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      margin: EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 8 : 6,
                      height: active ? 8 : 6,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white70,
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class AuthStore {
  static String? token;
  static Future<void> saveToken(String? t) async {
    try {
      const storage = FlutterSecureStorage();
      if (t == null || t.isEmpty) {
        await storage.delete(key: 'auth_token');
      } else {
        await storage.write(key: 'auth_token', value: t);
      }
      token = t;
    } catch (_) {
      // In sideload builds, keychain operations may fail; keep in-memory token
      token = t;
    }
  }
  static Future<void> loadToken() async {
    try {
      const storage = FlutterSecureStorage();
      token = await storage.read(key: 'auth_token');
    } catch (_) {
      token = null;
    }
  }
}

class LocaleController {
  static final ValueNotifier<Locale?> currentLocale = ValueNotifier<Locale?>(null);

  static Future<void> loadSavedLocale() async {
    final sp = await SharedPreferences.getInstance();
    final code = sp.getString('app_locale');
    if (code != null && code.isNotEmpty) {
      currentLocale.value = Locale(code);
    }
  }

  static Future<void> setLocale(Locale? locale) async {
    currentLocale.value = locale;
    final sp = await SharedPreferences.getInstance();
    if (locale == null) {
      await sp.remove('app_locale');
    } else {
      await sp.setString('app_locale', locale.languageCode);
    }
  }
}

Widget buildLanguageMenu() {
  return PopupMenuButton<String>(
    icon: const Icon(Icons.language),
    onSelected: (code) {
      LocaleController.setLocale(Locale(code));
    },
    itemBuilder: (context) => [
      PopupMenuItem(value: 'en', child: Text(AppLocalizations.of(context)!.english)),
      PopupMenuItem(value: 'ar', child: Text(AppLocalizations.of(context)!.arabic)),
      PopupMenuItem(value: 'ku', child: Text(AppLocalizations.of(context)!.kurdish)),
    ],
  );
}

class NoAnimationsPageTransitionsBuilder extends PageTransitionsBuilder {
  const NoAnimationsPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return child;
  }
}

class FullScreenGalleryPage extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  const FullScreenGalleryPage({required this.imageUrls, this.initialIndex = 0});
  @override
  State<FullScreenGalleryPage> createState() => _FullScreenGalleryPageState();
}

class _FullScreenGalleryPageState extends State<FullScreenGalleryPage> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: widget.imageUrls.length,
            itemBuilder: (context, i) {
              final url = widget.imageUrls[i];
              return InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => Container(color: Colors.black, alignment: Alignment.center, child: CircularProgressIndicator()),
                    errorWidget: (_, __, ___) => Container(color: Colors.black, alignment: Alignment.center, child: Icon(Icons.broken_image, color: Colors.white70, size: 48)),
                  ),
                ),
              );
            },
          ),
          if (widget.imageUrls.length > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: BouncingScrollPhysics(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.imageUrls.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    margin: EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 10 : 6,
                    height: active ? 10 : 6,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.white70,
                      shape: BoxShape.circle,
                    ),
                  );
                }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

//

// Dynamically discovered body types from assets
List<String> globalBodyTypes = ['Any'];
Map<String, String> globalBodyTypeAssetMap = {};

// Global vehicle specifications database - accessible to all pages
final Map<String, Map<String, Map<String, Map<String, dynamic>>>> globalVehicleSpecs = {
  'BMW': {
    'X3': {
      'Base': {
        'engineSizes': ['2.0', '3.0'],
        'bodyTypes': ['SUV'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline', 'Hybrid'],
        'driveTypes': ['AWD', 'RWD'],
        'cylinderCounts': ['4', '6'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'xDrive30i': {
        'engineSizes': ['2.0'],
        'bodyTypes': ['SUV'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['AWD'],
        'cylinderCounts': ['4'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'M40i': {
        'engineSizes': ['3.0'],
        'bodyTypes': ['SUV'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['AWD'],
        'cylinderCounts': ['6'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
    },
    'X5': {
      'Base': {
        'engineSizes': ['3.0', '4.4'],
        'bodyTypes': ['SUV'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline', 'Hybrid'],
        'driveTypes': ['AWD', 'RWD'],
        'cylinderCounts': ['6', '8'],
        'seatings': ['5', '7'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'xDrive40i': {
        'engineSizes': ['3.0'],
        'bodyTypes': ['SUV'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['AWD'],
        'cylinderCounts': ['6'],
        'seatings': ['5', '7'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'M50i': {
        'engineSizes': ['4.4'],
        'bodyTypes': ['SUV'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['AWD'],
        'cylinderCounts': ['8'],
        'seatings': ['5', '7'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
    },
  },
  'Toyota': {
    'Camry': {
      'L': {
        'engineSizes': ['2.5'],
        'bodyTypes': ['Sedan'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline', 'Hybrid'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'LE': {
        'engineSizes': ['2.5'],
        'bodyTypes': ['Sedan'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline', 'Hybrid'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'SE': {
        'engineSizes': ['2.5', '3.5'],
        'bodyTypes': ['Sedan'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4', '6'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'XSE': {
        'engineSizes': ['2.5', '3.5'],
        'bodyTypes': ['Sedan'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4', '6'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'XLE': {
        'engineSizes': ['2.5', '3.5'],
        'bodyTypes': ['Sedan'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline', 'Hybrid'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4', '6'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
    },
    'Corolla': {
      'L': {
        'engineSizes': ['1.8', '2.0'],
        'bodyTypes': ['Sedan', 'Hatchback'],
        'transmissions': ['Automatic', 'Manual'],
        'fuelTypes': ['Gasoline', 'Hybrid'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'LE': {
        'engineSizes': ['1.8', '2.0'],
        'bodyTypes': ['Sedan', 'Hatchback'],
        'transmissions': ['Automatic', 'Manual'],
        'fuelTypes': ['Gasoline', 'Hybrid'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'SE': {
        'engineSizes': ['2.0'],
        'bodyTypes': ['Sedan', 'Hatchback'],
        'transmissions': ['Automatic', 'Manual'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
    },
  },
  'Chevrolet': {
    'Tahoe': {
      'Base': {
        'engineSizes': ['5.3', '6.2'],
        'bodyTypes': ['SUV'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['RWD', '4WD'],
        'cylinderCounts': ['8'],
        'seatings': ['7', '8', '9'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'LT': {
        'engineSizes': ['5.3', '6.2'],
        'bodyTypes': ['SUV'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['RWD', '4WD'],
        'cylinderCounts': ['8'],
        'seatings': ['7', '8', '9'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'Premier': {
        'engineSizes': ['5.3', '6.2'],
        'bodyTypes': ['SUV'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['RWD', '4WD'],
        'cylinderCounts': ['8'],
        'seatings': ['7', '8', '9'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
    },
    'Silverado': {
      'Base': {
        'engineSizes': ['2.7', '5.3', '6.2'],
        'bodyTypes': ['Pickup'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['RWD', '4WD'],
        'cylinderCounts': ['4', '8'],
        'seatings': ['3', '6'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'LT': {
        'engineSizes': ['2.7', '5.3', '6.2'],
        'bodyTypes': ['Pickup'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['RWD', '4WD'],
        'cylinderCounts': ['4', '8'],
        'seatings': ['3', '6'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
    },
  },
  'Honda': {
    'Civic': {
      'LX': {
        'engineSizes': ['1.5', '2.0'],
        'bodyTypes': ['Sedan', 'Hatchback'],
        'transmissions': ['Automatic', 'Manual'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'Sport': {
        'engineSizes': ['1.5', '2.0'],
        'bodyTypes': ['Sedan', 'Hatchback'],
        'transmissions': ['Automatic', 'Manual'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
      'Touring': {
        'engineSizes': ['1.5'],
        'bodyTypes': ['Sedan', 'Hatchback'],
        'transmissions': ['Automatic'],
        'fuelTypes': ['Gasoline'],
        'driveTypes': ['FWD'],
        'cylinderCounts': ['4'],
        'seatings': ['5'],
        'colors': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
      },
    },
  },
};

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (FlutterErrorDetails details) async {
      // Persist the last error for diagnosis on sideload builds
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('last_startup_error', details.exceptionAsString());
      } catch (_) {}
    };

    // Skip Firebase/Push init for sideload builds on iOS to avoid entitlement crashes
    if (!(kSideloadBuild && Platform.isIOS)) {
      try { await Firebase.initializeApp(); } catch (_) {}
      try { await _initPushToken(); } catch (_) {}
    }

    // Keychain access can fail for sideloaded builds; don't crash.
    try { await ApiService.initializeTokens(); } catch (_) {}
    try { await LocaleController.loadSavedLocale(); } catch (_) {}
    runApp(MyApp());
  }, (error, stack) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('last_startup_error', error.toString());
    } catch (_) {}
  });
}

// Helper page to view last startup error if present (can be wired to a hidden gesture if needed)
class _StartupDiagnostics {
  static Future<String?> lastError() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString('last_startup_error');
    } catch (_) { return null; }
  }
}

Future<void> _initPushToken() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final enabled = sp.getBool('push_enabled') ?? true;
    if (!enabled) return;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true, provisional: false);
    if (settings.authorizationStatus == AuthorizationStatus.authorized || settings.authorizationStatus == AuthorizationStatus.provisional) {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('push_token', token);
      }
    }
  } catch (_) {}
}
// Car Comparison State Management
class CarComparisonStore extends ChangeNotifier {
  final List<Map<String, dynamic>> _comparisonCars = [];
  CarComparisonStore() {
    _loadFromPrefs();
  }
  
  List<Map<String, dynamic>> get comparisonCars => List.unmodifiable(_comparisonCars);
  
  bool get canAddMore => _comparisonCars.length < 5;
  
  bool isCarInComparison(int carId) {
    return _comparisonCars.any((car) => car['id'] == carId);
  }
  
  void addCarToComparison(Map<String, dynamic> car) {
    if (_comparisonCars.length >= 5) {
      return; // Already at maximum
    }
    
    if (!isCarInComparison(car['id'])) {
      _comparisonCars.add(car);
      // Analytics tracking for comparison add
      _saveToPrefs();
      notifyListeners();
    }
  }
  
  void removeCarFromComparison(int carId) {
    _comparisonCars.removeWhere((car) => car['id'] == carId);
    _saveToPrefs();
    notifyListeners();
  }
  
  void clearComparison() {
    _comparisonCars.clear();
    _saveToPrefs();
    notifyListeners();
  }
  
  int get comparisonCount => _comparisonCars.length;

  Future<void> _saveToPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final List<String> encoded = _comparisonCars.map((e) => json.encode(e)).toList();
      await sp.setStringList('comparison_cars', encoded);
    } catch (_) {}
  }

  Future<void> _loadFromPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final encoded = sp.getStringList('comparison_cars') ?? [];
      final List<Map<String, dynamic>> loaded = encoded
          .map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(json.decode(s)))
          .toList();

      bool changed = false;
      for (final Map<String, dynamic> car in loaded) {
        final dynamic rawId = car['id'] ?? car['car_id'] ?? car['carId'] ?? car['uuid'];
        final int loadedId = rawId is int
            ? rawId
            : (rawId is String
                ? (int.tryParse(rawId) ?? rawId.hashCode)
                : -1);

        if (!_comparisonCars.any((c) => c['id'] == loadedId)) {
          // Ensure consistent numeric id is present before adding
          final normalized = Map<String, dynamic>.from(car);
          normalized['id'] = loadedId;
          _comparisonCars.add(normalized);
          changed = true;
        }
      }

      if (changed) {
        notifyListeners();
      }
    } catch (_) {}
  }
}

// Comparison Button Widget
class ComparisonButton extends StatelessWidget {
  final Map<String, dynamic> car;
  final bool isCompact;
  
  const ComparisonButton({
    Key? key,
    required this.car,
    this.isCompact = false,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Consumer<CarComparisonStore>(
      builder: (context, comparisonStore, child) {
        final dynamic rawId = car['id'] ?? car['car_id'] ?? car['carId'] ?? car['uuid'];
        final int carId = rawId is int
            ? rawId
            : (rawId is String
                ? (int.tryParse(rawId) ?? rawId.hashCode)
                : -1);
        final isInComparison = comparisonStore.isCarInComparison(carId);
        final canAddMore = comparisonStore.canAddMore;
        
        return Container(
          decoration: BoxDecoration(
            color: isInComparison ? Colors.green : Colors.orange,
            borderRadius: BorderRadius.circular(isCompact ? 16 : 20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(isCompact ? 16 : 20),
              onTap: () {
                if (isInComparison) {
                  comparisonStore.removeCarFromComparison(carId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_removedFromComparisonTextGlobal(context)),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 1),
                    ),
                  );
                } else if (canAddMore && carId != -1) {
                  final normalized = Map<String, dynamic>.from(car);
                  normalized['id'] = carId; // ensure consistent numeric ID stored
                  comparisonStore.addCarToComparison(normalized);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_addedToComparisonTextGlobal(context, comparisonStore.comparisonCount)),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 1),
                    ),
                  );
                  Navigator.pushNamed(context, '/comparison');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_comparisonMaxLimitTextGlobal(context)),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 8 : 12,
                  vertical: isCompact ? 6 : 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isInComparison ? Icons.check : Icons.compare_arrows,
                      color: Colors.white,
                      size: isCompact ? 16 : 18,
                    ),
                    if (!isCompact) ...[
                      SizedBox(width: 4),
                      Text(
                        isInComparison ? _addedLabelGlobal(context) : _compareLabelGlobal(context),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => CarComparisonStore()),
      ],
      child: ValueListenableBuilder<Locale?>(
        valueListenable: LocaleController.currentLocale,
        builder: (context, locale, _) => Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) => MaterialApp(
      title: 'CARZO',
      locale: locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
        Locale('ku'),
      ],
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        const KuMaterialLocalizationsDelegate(),
        const KuWidgetsLocalizationsDelegate(),
        const KuCupertinoLocalizationsDelegate(),
      ],
      localeResolutionCallback: (deviceLocale, supported) {
        if (locale != null) return locale;
        if (deviceLocale == null) return const Locale('en');
        for (final l in supported) {
          if (l.languageCode == deviceLocale.languageCode) return l;
        }
        return const Locale('en');
      },
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => HomePage(),
        // Replace old AddListingPage with new multi-step SellCarPage route
        '/sell': (context) => SellCarPage(),
        '/settings': (context) => SettingsPage(),
        '/favorites': (context) => FavoritesPage(),
        '/chat': (context) => ChatListPage(),
        '/login': (context) => LoginPage(),
        '/signup': (context) => SignupPage(),
        '/profile': (context) => ProfilePage(),
        '/payment/history': (context) => PaymentHistoryPage(),
        '/payment/initiate': (context) => PaymentInitiatePage(),
        '/car_detail': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return CarDetailsPage(carId: args['carId']);
        },
        '/chat/conversation': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return ChatConversationPage(conversationId: args['conversationId']);
        },
        '/payment/status': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return PaymentStatusPage(paymentId: args['paymentId']);
        },
        '/edit': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return EditListingPage(car: args['car']);
        },
        '/my_listings': (context) => MyListingsPage(),
        '/comparison': (context) => CarComparisonPage(),
        '/analytics': (context) => AnalyticsPage(),
      },
    ),
          ),
        ),
    );
  }
}

// Theme Toggle Widget
// Moved to lib/widgets/theme_toggle_widget.dart

List<double> _tintColorMatrix(Color color) {
  const double lR = 0.2126;
  const double lG = 0.7152;
  const double lB = 0.0722;
  final double r = color.red / 255.0;
  final double g = color.green / 255.0;
  final double b = color.blue / 255.0;
  return [
    lR * r, lG * r, lB * r, 0, 0,
    lR * g, lG * g, lB * g, 0, 0,
    lR * b, lG * b, lB * b, 0, 0,
    0,      0,      0,      1, 0,
  ];
}

Widget _buildBodyTypeImage(String assetPath) {
  // Accept either PNG or SVG. Prefer PNG rendering via _WhiteKeyedImage; use SVG as fallback.
  String pngAssetPath;
  String svgFallbackPath;

  if (assetPath.toLowerCase().endsWith('.png')) {
    pngAssetPath = assetPath;
    svgFallbackPath = assetPath
        .replaceFirst('/body_types_png/', '/body_types_clean/')
        .replaceAll('.png', '.svg');
  } else {
    // Treat as SVG path and derive PNG companion
    svgFallbackPath = assetPath;
    pngAssetPath = assetPath
        .replaceFirst('/body_types_clean/', '/body_types_png/')
        .replaceAll('.svg', '.png');
  }

  return ColorFiltered(
    colorFilter: ColorFilter.matrix(_tintColorMatrix(const Color(0xFF707070))),
    child: _WhiteKeyedImage(assetPath: pngAssetPath, svgFallbackPath: svgFallbackPath),
  );
}

// Simple in-memory cache so we only process each icon once per run
final Map<String, Future<ui.Image>> _whiteKeyedCache = {};

class _WhiteKeyedImage extends StatefulWidget {
  final String assetPath;
  final String svgFallbackPath;
  const _WhiteKeyedImage({required this.assetPath, required this.svgFallbackPath});
  @override
  State<_WhiteKeyedImage> createState() => _WhiteKeyedImageState();
}

class _WhiteKeyedImageState extends State<_WhiteKeyedImage> {
  Future<ui.Image>? _futureImage;

  @override
  void initState() {
    super.initState();
    _futureImage = (_whiteKeyedCache[widget.assetPath] ??= _decodePngWithWhiteTransparent(widget.assetPath));
  }

  @override
  void didUpdateWidget(covariant _WhiteKeyedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      setState(() {
        _futureImage = (_whiteKeyedCache[widget.assetPath] ??= _decodePngWithWhiteTransparent(widget.assetPath));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _futureImage,
      builder: (context, snap) {
        if (snap.hasData) {
          return RawImage(image: snap.data, fit: BoxFit.contain, filterQuality: FilterQuality.high);
        }
        if (snap.hasError) {
          // Fallback to SVG if PNG missing or decode fails
          return SvgPicture.asset(widget.svgFallbackPath, fit: BoxFit.contain);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

Future<ui.Image> _decodePngWithWhiteTransparent(String assetPath) async {
  final services.ByteData data = await services.rootBundle.load(assetPath);
  final Uint8List bytes = data.buffer.asUint8List();
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final ByteData? raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) {
    throw Exception('Failed to read image bytes');
  }
  final Uint8List rgba = raw.buffer.asUint8List();
  // Only punch out near-white pixels to fully transparent; keep icon colors unchanged
  const int threshold = 250; // near pure white
  for (int i = 0; i < rgba.length; i += 4) {
    final int r = rgba[i];
    final int g = rgba[i + 1];
    final int b = rgba[i + 2];
    if (r >= threshold && g >= threshold && b >= threshold) {
      rgba[i + 3] = 0;
    }
  }
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    image.width,
    image.height,
    ui.PixelFormat.rgba8888,
    (ui.Image img) => completer.complete(img),
  );
  return completer.future;
}

// Global brand logo filenames map accessible to all classes
final Map<String, String> brandLogoFilenames = {
  'Toyota': 'toyota',
  'Volkswagen': 'volkswagen',
  'Ford': 'ford',
  'Honda': 'honda',
  'Hyundai': 'hyundai',
  'Nissan': 'nissan',
  'Chevrolet': 'chevrolet',
  'Kia': 'kia',
  'Mercedes-Benz': 'mercedes-benz',
  'BMW': 'bmw',
  'Audi': 'audi',
  'Lexus': 'lexus',
  'Mazda': 'mazda',
  'Subaru': 'subaru',
  'Volvo': 'volvo',
  'Jeep': 'jeep',
  'RAM': 'ram',
  'GMC': 'gmc',
  'Buick': 'buick',
  'Cadillac': 'cadillac',
  'Lincoln': 'lincoln',
  'Chrysler': 'chrysler',
  'Dodge': 'dodge',
  'Mitsubishi': 'mitsubishi',
  'Land Rover': 'land-rover',
  'Jaguar': 'jaguar',
  'Bentley': 'bentley',
  'Rolls-Royce': 'rolls-royce',
  'Aston Martin': 'aston-martin',
  'McLaren': 'mclaren',
  'Ferrari': 'ferrari',
  'Lamborghini': 'lamborghini',
  'Porsche': 'porsche',
  'Maserati': 'maserati',
  'Alfa Romeo': 'alfa-romeo',
  'Fiat': 'fiat',
  'Genesis': 'genesis',
  'Infiniti': 'infiniti',
  'Acura': 'acura',
  'Peugeot': 'peugeot',
  'CitroÃ«n': 'citroen',
  'Renault': 'renault',
  'Å koda': 'skoda',
  'SEAT': 'seat',
  'Opel': 'opel',
  'Saab': 'saab',
  'Lada': 'lada',
  'Dacia': 'dacia',
  'Suzuki': 'suzuki',
  'Isuzu': 'isuzu',
  'Daihatsu': 'daihatsu',
  'SsangYong': 'ssangyong',
  'Great Wall': 'great-wall',
  'Chery': 'chery',
  'Geely': 'geely',
  'BYD': 'byd',
  'Haval': 'haval',
  'Changan': 'changan',
  'Dongfeng': 'dongfeng',
  'FAW': 'faw',
  'JAC': 'jac',
  'BAIC': 'baic',
  'Brilliance': 'brilliance',
  'Zotye': 'zotye',
  'Lifan': 'lifan',
  'Foton': 'foton',
  'Leapmotor': 'leapmotor',
  'GAC': 'gac',
  'SAIC': 'saic',
  'MG': 'mg',
  'Vauxhall': 'vauxhall',
  'Smart': 'smart',
  'Buggati': 'bugatti',
  'Koenigzeg': 'koenigsegg',
  'Proto': 'proton',
};

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> cars = [];
  bool isLoading = true;
  bool hasLoadedOnce = false;
  String? loadErrorMessage;

  // Filter variables
  String? selectedBrand;
  String? selectedModel;
  String? selectedTrim;
  String? selectedMinPrice;
  String? selectedMaxPrice;
  String? selectedMinYear;
  String? selectedMaxYear;
  String? selectedMinMileage;
  String? selectedMaxMileage;
  String? selectedCondition;
  String? selectedTransmission;
  String? selectedFuelType;
  String? selectedBodyType;
  String? selectedColor;
  String? selectedDriveType;
  String? selectedCylinderCount;
  String? selectedSeating;
  String? selectedEngineSize;
  String? selectedCity;
  String? selectedTitleStatus;
  String? selectedDamagedParts;
  String? contactPhone;
  String? selectedSortBy;
  String? selectedOwners;
  String? selectedVIN;
  String? selectedAccidentHistory; // 'yes' | 'no'

  // Toggle states for unified filters
  bool isPriceDropdown = true;
  bool isYearDropdown = true;
  bool isMileageDropdown = true;
  static const String _filtersKey = 'home_filters_v1';
  static const String _sellFiltersKey = 'sell_filters_v1';
  static const String _savedSearchesKey = 'saved_searches_v1';
 
  // Listings layout
  int listingColumns = 2;

  // Bottom bar tab selection for inline pages (payments, chat, saved, etc.)
  int? _selectedBottomTabIndex;
  

  void _resetAllFiltersInMemory() {
    selectedBrand = null;
    selectedModel = null;
    selectedTrim = null;
    selectedMinPrice = null;
    selectedMaxPrice = null;
    selectedMinYear = null;
    selectedMaxYear = null;
    selectedMinMileage = null;
    selectedMaxMileage = null;
    selectedCondition = null;
    selectedTransmission = null;
    selectedFuelType = null;
    selectedBodyType = null;
    selectedColor = null;
    selectedDriveType = null;
    selectedCylinderCount = null;
    selectedSeating = null;
    selectedEngineSize = null;
    selectedCity = null;
    selectedTitleStatus = null;
    selectedDamagedParts = null;
    contactPhone = null;
    selectedSortBy = null;
    selectedOwners = null;
    selectedVIN = null;
    selectedAccidentHistory = null;
  }
  Future<void> _restoreFilters() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_filtersKey);
      if (raw == null || raw.isEmpty) return;
      final map = json.decode(raw) as Map<String, dynamic>;
      setState(() {
        selectedBrand = map['brand'];
        selectedModel = map['model'];
        selectedTrim = map['trim'];
        selectedMinPrice = map['price_min'];
        selectedMaxPrice = map['price_max'];
        selectedMinYear = map['year_min'];
        selectedMaxYear = map['year_max'];
        selectedMinMileage = map['min_mileage'];
        selectedMaxMileage = map['max_mileage'];
        selectedCondition = map['condition'];
        selectedTransmission = map['transmission'];
        selectedFuelType = map['fuel_type'];
        selectedBodyType = map['body_type'];
        selectedColor = map['color'];
        selectedDriveType = map['drive_type'];
        selectedCylinderCount = map['cylinders'];
        selectedSeating = map['seating'];
        selectedEngineSize = map['engine_size'];
        selectedCity = map['city'];
        selectedTitleStatus = map['title_status'];
        selectedDamagedParts = map['damaged_parts'];
        selectedSortBy = map['sort_by'];
        selectedOwners = map['owners'];
        selectedVIN = map['vin'];
        selectedAccidentHistory = map['accident_history'];
      });
    } catch (_) {}
  }

  Future<void> _persistFilters() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final Map<String, dynamic> map = {
        'brand': selectedBrand,
        'model': selectedModel,
        'trim': selectedTrim,
        'price_min': selectedMinPrice,
        'price_max': selectedMaxPrice,
        'year_min': selectedMinYear,
        'year_max': selectedMaxYear,
        'min_mileage': selectedMinMileage,
        'max_mileage': selectedMaxMileage,
        'condition': selectedCondition,
        'transmission': selectedTransmission,
        'fuel_type': selectedFuelType,
        'body_type': selectedBodyType,
        'color': selectedColor,
        'drive_type': selectedDriveType,
        'cylinders': selectedCylinderCount,
        'seating': selectedSeating,
        'engine_size': selectedEngineSize,
        'city': selectedCity,
        'title_status': selectedTitleStatus,
        'damaged_parts': selectedDamagedParts,
        'sort_by': selectedSortBy,
        'owners': selectedOwners,
        'vin': selectedVIN,
        'accident_history': selectedAccidentHistory,
      };
      await sp.setString(_filtersKey, json.encode(map));
    } catch (_) {}
  }

  Future<void> _clearPersistedFilters() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_filtersKey);
      await sp.remove(_sellFiltersKey);
      await sp.remove(_savedSearchesKey);
      // Clear known caches
      await sp.remove('cache_favorites');
      // Attempt to clear dynamic cache_home_* and cache_car_* keys by scanning
      final allKeys = sp.getKeys();
      for (final k in allKeys) {
        if (k.startsWith('cache_home_') || k.startsWith('cache_car_')) {
          await sp.remove(k);
        }
      }
    } catch (_) {}
  }

  Future<void> _clearFiltersOnly() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_filtersKey);
      await sp.remove(_sellFiltersKey);
      await sp.remove(_savedSearchesKey);
      // Don't clear cached car data to improve reliability
    } catch (_) {}
  }

  Future<void> _decodeVin() async {
    final vin = (selectedVIN ?? '').trim();
    if (vin.isEmpty) return;
    try {
      final uri = Uri.parse('https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValuesExtended/' + vin + '?format=json');
      final resp = await http.get(uri).timeout(Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is Map && data['Results'] is List && (data['Results'] as List).isNotEmpty) {
          final Map<String, dynamic> r = Map<String, dynamic>.from((data['Results'] as List).first as Map);
          final make = (r['Make'] ?? '').toString().trim();
          final model = (r['Model'] ?? '').toString().trim();
          final year = (r['ModelYear'] ?? '').toString().trim();
          setState(() {
            if (make.isNotEmpty) selectedBrand = make;
            if (model.isNotEmpty) { selectedModel = model; selectedTrim = null; }
            if (year.isNotEmpty) { selectedMinYear = year; selectedMaxYear = year; }
          });
          _persistFilters();
          onFilterChanged();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('VIN decoded')));
        }
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.error)));
    }
  }

  Future<void> _saveCurrentSearch() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final List<dynamic> current = json.decode(sp.getString(_savedSearchesKey) ?? '[]');
      final Map<String, dynamic> payload = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'name': _generateSearchName(),
        'filters': json.decode(await sp.getString(_filtersKey) ?? '{}'),
        'notify': true,
        'created_at': DateTime.now().toIso8601String(),
      };
      current.insert(0, payload);
      await sp.setString(_savedSearchesKey, json.encode(current));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.saved)));
      // Analytics tracking for saved search
      // Navigate to saved searches for quick edit
      Navigator.push(context, MaterialPageRoute(builder: (_) => SavedSearchesPage(parentState: this)));
    } catch (_) {}
  }

  // Auto-save search when filters are applied
  Future<void> _autoSaveSearch() async {
    try {
      // Only auto-save if there are meaningful filters applied
      if (!_hasMeaningfulFilters()) return;
      
      final sp = await SharedPreferences.getInstance();
      final List<dynamic> current = json.decode(sp.getString(_savedSearchesKey) ?? '[]');
      
      // Get current filter state
      final Map<String, dynamic> currentFilters = _getCurrentFilterState();
      
      // Check if this search already exists (avoid duplicates)
      final String searchName = _generateSearchName();
      final bool exists = current.any((item) => 
        item['name'] == searchName && 
        _areFiltersEqual(item['filters'], currentFilters)
      );
      
      if (exists) return; // Don't save duplicate searches
      
      final Map<String, dynamic> payload = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'name': searchName,
        'filters': currentFilters,
        'notify': true,
        'created_at': DateTime.now().toIso8601String(),
        'auto_saved': true, // Mark as auto-saved
      };
      
      current.insert(0, payload);
      
      // Keep only last 20 searches to prevent storage bloat
      if (current.length > 20) {
        current.removeRange(20, current.length);
      }
      
      await sp.setString(_savedSearchesKey, json.encode(current));
      // Analytics tracking for auto-saved search
    } catch (_) {}
  }

  // Check if current filters have meaningful values
  bool _hasMeaningfulFilters() {
    return (selectedBrand?.isNotEmpty == true) ||
           (selectedModel?.isNotEmpty == true) ||
           (selectedCity?.isNotEmpty == true) ||
           (selectedMinPrice?.isNotEmpty == true) ||
           (selectedMaxPrice?.isNotEmpty == true) ||
           (selectedMinYear?.isNotEmpty == true) ||
           (selectedMaxYear?.isNotEmpty == true) ||
           (selectedMinMileage?.isNotEmpty == true) ||
           (selectedMaxMileage?.isNotEmpty == true) ||
           (selectedCondition?.isNotEmpty == true && selectedCondition != 'Any') ||
           (selectedTransmission?.isNotEmpty == true && selectedTransmission != 'Any') ||
           (selectedFuelType?.isNotEmpty == true && selectedFuelType != 'Any') ||
           (selectedBodyType?.isNotEmpty == true && selectedBodyType != 'Any') ||
           (selectedColor?.isNotEmpty == true && selectedColor != 'Any') ||
           (selectedDriveType?.isNotEmpty == true && selectedDriveType != 'Any') ||
           (selectedCylinderCount?.isNotEmpty == true && selectedCylinderCount != 'Any') ||
           (selectedSeating?.isNotEmpty == true && selectedSeating != 'Any') ||
           (selectedOwners?.isNotEmpty == true) ||
           (selectedVIN?.isNotEmpty == true) ||
           (selectedAccidentHistory?.isNotEmpty == true) ||
           (selectedTitleStatus?.isNotEmpty == true);
  }

  // Get current filter state as a map
  Map<String, dynamic> _getCurrentFilterState() {
    final Map<String, dynamic> filters = {};
    
    // Brand and Model filters
    if (selectedBrand?.isNotEmpty == true) filters['brand'] = selectedBrand!;
    if (selectedModel?.isNotEmpty == true) filters['model'] = selectedModel!;
    if (selectedTrim?.isNotEmpty == true) filters['trim'] = selectedTrim!;
    
    // Price filters - apply individually, not requiring both
    if (selectedMinPrice?.isNotEmpty == true) filters['min_price'] = selectedMinPrice!;
    if (selectedMaxPrice?.isNotEmpty == true) filters['max_price'] = selectedMaxPrice!;
    
    // Year filters - apply individually, not requiring both
    if (selectedMinYear?.isNotEmpty == true) filters['min_year'] = selectedMinYear!;
    if (selectedMaxYear?.isNotEmpty == true) filters['max_year'] = selectedMaxYear!;
    
    // Mileage filters - apply individually, not requiring both
    if (selectedMinMileage?.isNotEmpty == true) filters['min_mileage'] = selectedMinMileage!;
    if (selectedMaxMileage?.isNotEmpty == true) filters['max_mileage'] = selectedMaxMileage!;
    
    // Vehicle condition and specifications
    if (selectedCondition?.isNotEmpty == true && selectedCondition != 'Any') filters['condition'] = selectedCondition!.toLowerCase();
    if (selectedTransmission?.isNotEmpty == true && selectedTransmission != 'Any') filters['transmission'] = selectedTransmission!.toLowerCase();
    if (selectedFuelType?.isNotEmpty == true && selectedFuelType != 'Any') filters['fuel_type'] = selectedFuelType!.toLowerCase();
    if (selectedBodyType?.isNotEmpty == true && selectedBodyType != 'Any') filters['body_type'] = selectedBodyType!.toLowerCase();
    if (selectedColor?.isNotEmpty == true && selectedColor != 'Any') filters['color'] = selectedColor!.toLowerCase();
    if (selectedDriveType?.isNotEmpty == true && selectedDriveType != 'Any') filters['drive_type'] = selectedDriveType!.toLowerCase();
    if (selectedCylinderCount?.isNotEmpty == true && selectedCylinderCount != 'Any') filters['cylinder_count'] = selectedCylinderCount!;
    if (selectedSeating?.isNotEmpty == true && selectedSeating != 'Any') filters['seating'] = selectedSeating!;
    
    // Location and other filters
    if (selectedCity?.isNotEmpty == true) filters['city'] = selectedCity!;
    // Convert localized sort option to backend API value
    final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
    if (apiSortValue?.isNotEmpty == true) filters['sort_by'] = apiSortValue!;
    if (selectedOwners?.isNotEmpty == true) filters['owners'] = selectedOwners!;
    if (selectedVIN?.isNotEmpty == true) filters['vin'] = selectedVIN!;
    if (selectedAccidentHistory?.isNotEmpty == true) filters['accident_history'] = selectedAccidentHistory!;
    
    // Title status and damaged parts
    if (selectedTitleStatus?.isNotEmpty == true) {
      filters['title_status'] = selectedTitleStatus!;
      if (selectedTitleStatus == 'damaged' && selectedDamagedParts?.isNotEmpty == true) {
        filters['damaged_parts'] = selectedDamagedParts!;
      }
    }
    
    return filters;
  }

  // Check if two filter maps are equal
  bool _areFiltersEqual(Map<String, dynamic> filters1, Map<String, dynamic> filters2) {
    if (filters1.length != filters2.length) return false;
    for (String key in filters1.keys) {
      if (filters1[key] != filters2[key]) return false;
    }
    return true;
  }

  String _generateSearchName() {
    final parts = <String>[];
    if (selectedBrand?.isNotEmpty == true) parts.add(selectedBrand!);
    if (selectedModel?.isNotEmpty == true) parts.add(selectedModel!);
    if (selectedCity?.isNotEmpty == true) parts.add(_translateValueGlobal(context, selectedCity) ?? selectedCity!);
    if (selectedMaxPrice?.isNotEmpty == true) parts.add('\$' + (selectedMaxPrice ?? ''));
    return parts.isEmpty ? AppLocalizations.of(context)!.defaultSort : parts.join(' â€¢ ');
  }

  // Static options
  final List<String> homeBrands = [
    'Toyota', 'Volkswagen', 'Ford', 'Honda', 'Hyundai', 'Nissan', 'Chevrolet', 'Kia', 'Mercedes-Benz', 'BMW', 'Audi', 'Lexus', 'Mazda', 'Subaru', 'Volvo', 'Jeep', 'RAM', 'GMC', 'Buick', 'Cadillac', 'Lincoln', 'Mitsubishi', 'Acura', 'Infiniti', 'Tesla', 'Mini', 'Porsche', 'Land Rover', 'Jaguar', 'Fiat', 'Renault', 'Peugeot', 'CitroÃ«n', 'Å koda', 'SEAT', 'Dacia', 'Chery', 'BYD', 'Great Wall', 'FAW', 'Roewe', 'Proton', 'Perodua', 'Tata', 'Mahindra', 'Lada', 'ZAZ', 'Daewoo', 'SsangYong', 'Changan', 'Haval', 'Wuling', 'Baojun', 'Nio', 'XPeng', 'Li Auto', 'VinFast', 'Ferrari', 'Lamborghini', 'Bentley', 'Rolls-Royce', 'Aston Martin', 'McLaren', 'Maserati', 'Bugatti', 'Pagani', 'Koenigsegg', 'Polestar', 'Rivian', 'Lucid', 'Alfa Romeo', 'Lancia', 'Abarth', 'Opel', 'DS', 'MAN', 'Iran Khodro', 'Genesis', 'Isuzu', 'Datsun', 'JAC Motors', 'JAC Trucks', 'KTM', 'Alpina', 'Brabus', 'Mansory', 'Bestune', 'Hongqi', 'Dongfeng', 'FAW Jiefang', 'Foton', 'Leapmotor', 'GAC', 'SAIC', 'MG', 'Vauxhall', 'Smart'
  ];
  final Map<String, List<String>> models = {
    'BMW': ['X3', 'X5', 'X7', '3 Series', '5 Series', '7 Series', 'M3', 'M5', 'X1', 'X6'],
    'Mercedes-Benz': ['C-Class', 'E-Class', 'S-Class', 'GLC', 'GLE', 'GLS', 'A-Class', 'CLA', 'GLA', 'AMG GT'],
    'Audi': ['A3', 'A4', 'A6', 'A8', 'Q3', 'Q5', 'Q7', 'Q8', 'RS6', 'TT'],
    'Toyota': ['Camry', 'Corolla', 'RAV4', 'Highlander', 'Tacoma', 'Tundra', 'Prius', 'Avalon', '4Runner', 'Sequoia'],
    'Honda': ['Civic', 'Accord', 'CR-V', 'Pilot', 'Ridgeline', 'Odyssey', 'HR-V', 'Passport', 'Insight', 'Clarity'],
    'Nissan': ['Altima', 'Maxima', 'Rogue', 'Murano', 'Pathfinder', 'Frontier', 'Titan', 'Leaf', 'Sentra', 'Versa'],
    'Ford': ['F-150', 'Mustang', 'Explorer', 'Escape', 'Edge', 'Ranger', 'Bronco', 'Mach-E', 'Focus', 'Fusion'],
    'Chevrolet': ['Silverado', 'Camaro', 'Equinox', 'Tahoe', 'Suburban', 'Colorado', 'Corvette', 'Malibu', 'Cruze', 'Traverse'],
    'Hyundai': ['Elantra', 'Sonata', 'Tucson', 'Santa Fe', 'Palisade', 'Kona', 'Venue', 'Accent', 'Veloster', 'Ioniq'],
    'Kia': ['Forte', 'K5', 'Sportage', 'Telluride', 'Sorento', 'Soul', 'Rio', 'Stinger', 'EV6', 'Niro']
  };
  
  

  

  // Trims by brand and model for Add Listing (scoped to this page)
  final Map<String, Map<String, List<String>>> trimsByBrandModel = {
    'BMW': {
      'X3': ['Base', 'xDrive30i', 'M40i'],
      'X5': ['Base', 'xDrive40i', 'M50i'],
      '3 Series': ['320i', '330i', 'M340i', 'M3'],
    },
    'Mercedes-Benz': {
      'C-Class': ['C 200', 'C 300', 'AMG C 43', 'AMG C 63'],
      'E-Class': ['E 200', 'E 300', 'E 450', 'AMG E 53'],
      'GLC': ['GLC 200', 'GLC 300', 'AMG GLC 43'],
    },
    'Audi': {
      'A4': ['30 TDI', '35 TDI', '40 TFSI', '45 TFSI', 'S4', 'RS4'],
      'Q5': ['40 TDI', '45 TFSI', 'SQ5'],
    },
    'Toyota': {
      'Camry': ['L', 'LE', 'SE', 'XSE', 'XLE'],
      'Corolla': ['L', 'LE', 'SE', 'XSE', 'XLE'],
      'RAV4': ['LE', 'XLE', 'XLE Premium', 'Adventure', 'Limited', 'TRD Off-Road'],
    },
    'Honda': {
      'Civic': ['LX', 'Sport', 'EX', 'EX-L', 'Touring', 'Si', 'Type R'],
      'Accord': ['LX', 'Sport', 'EX-L', 'Touring'],
    },
    'Nissan': {
      'Altima': ['S', 'SV', 'SR', 'SL', 'Platinum'],
      'Rogue': ['S', 'SV', 'SL', 'Platinum'],
    },
    'Ford': {
      'F-150': ['XL', 'XLT', 'Lariat', 'King Ranch', 'Platinum', 'Limited', 'Raptor'],
      'Explorer': ['XLT', 'Limited', 'ST', 'Platinum'],
    },
    'Chevrolet': {
      'Silverado': ['WT', 'Custom', 'LT', 'RST', 'LTZ', 'High Country'],
      'Camaro': ['1LS', '1LT', '2LT', '3LT', '1SS', '2SS', 'ZL1'],
    },
    'Hyundai': {
      'Elantra': ['SE', 'SEL', 'Limited', 'N Line'],
      'Tucson': ['SE', 'SEL', 'Limited', 'N Line'],
    },
    'Kia': {
      'Sportage': ['LX', 'EX', 'SX', 'X-Line'],
      'Sorento': ['LX', 'S', 'EX', 'SX', 'SX Prestige'],
    },
  };

  

  
  
  

  // DUPLICATE REMOVED: trimsByBrandModel

  
  
  final List<String> trims = ['Base', 'Sport', 'Luxury', 'Premium', 'Limited', 'Platinum', 'Signature', 'Touring', 'SE', 'LE', 'XLE', 'XSE'];
  final List<String> conditions = ['Any', 'New', 'Used'];
  final List<String> transmissions = ['Any', 'Automatic', 'Manual'];
  final List<String> fuelTypes = ['Any', 'Gasoline', 'Diesel', 'Electric', 'Hybrid', 'LPG', 'Plug-in Hybrid'];
  // Use global caches so static helpers can access
  List<String> bodyTypes = globalBodyTypes;
  final List<String> colors = ['Any', 'Black', 'White', 'Silver', 'Gray', 'Red', 'Blue', 'Green', 'Yellow', 'Orange', 'Purple', 'Brown', 'Beige', 'Gold'];
  final List<String> driveTypes = ['Any', 'FWD', 'RWD', 'AWD', '4WD'];
  final List<String> cylinderCounts = ['Any', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16'];
  final List<String> seatings = ['Any', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30', '31', '32', '33', '34', '35', '36', '37', '38', '39', '40', '41', '42', '43', '44', '45', '46', '47', '48', '49', '50'];
  final List<String> engineSizes = ['Any', '0.5', '0.6', '0.7', '0.8', '0.9', '1.0', '1.1', '1.2', '1.3', '1.4', '1.5', '1.6', '1.7', '1.8', '1.9', '2.0', '2.1', '2.2', '2.3', '2.4', '2.5', '2.6', '2.7', '2.8', '2.9', '3.0', '3.1', '3.2', '3.3', '3.4', '3.5', '3.6', '3.7', '3.8', '3.9', '4.0', '4.1', '4.2', '4.3', '4.4', '4.5', '4.6', '4.7', '4.8', '4.9', '5.0', '5.1', '5.2', '5.3', '5.4', '5.5', '5.6', '5.7', '5.8', '5.9', '6.0', '6.1', '6.2', '6.3', '6.4', '6.5', '6.6', '6.7', '6.8', '6.9', '7.0', '7.1', '7.2', '7.3', '7.4', '7.5', '7.6', '7.7', '7.8', '7.9', '8.0', '8.1', '8.2', '8.3', '8.4', '8.5', '8.6', '8.7', '8.8', '8.9', '9.0', '9.1', '9.2', '9.3', '9.4', '9.5', '9.6', '9.7', '9.8', '9.9', '10.0', '10.1', '10.2', '10.3', '10.4', '10.5', '10.6', '10.7', '10.8', '10.9', '11.0', '11.1', '11.2', '11.3', '11.4', '11.5', '11.6', '11.7', '11.8', '11.9', '12.0', '12.1', '12.2', '12.3', '12.4', '12.5', '12.6', '12.7', '12.8', '12.9', '13.0', '13.1', '13.2', '13.3', '13.4', '13.5', '13.6', '13.7', '13.8', '13.9', '14.0', '14.1', '14.2', '14.3', '14.4', '14.5', '14.6', '14.7', '14.8', '14.9', '15.0', '15.1', '15.2', '15.3', '15.4', '15.5', '15.6', '15.7', '15.8', '15.9', '16.0'];
  final List<String> cities = ['Any', 'Baghdad', 'Basra', 'Erbil', 'Najaf', 'Karbala', 'Kirkuk', 'Mosul', 'Sulaymaniyah', 'Dohuk', 'Anbar', 'Halabja', 'Diyala', 'Diyarbakir', 'Maysan', 'Muthanna', 'Dhi Qar', 'Salaheldeen'];
  List<String> getLocalizedSortOptions(BuildContext context) => [
    AppLocalizations.of(context)!.defaultSort,
    AppLocalizations.of(context)!.sort_newest,
    AppLocalizations.of(context)!.sort_price_low_high,
    AppLocalizations.of(context)!.sort_price_high_low,
    AppLocalizations.of(context)!.sort_year_newest,
    AppLocalizations.of(context)!.sort_year_oldest,
    AppLocalizations.of(context)!.sort_mileage_low_high,
    AppLocalizations.of(context)!.sort_mileage_high_low,
  ];



  

  bool useCustomMinPrice = false;
  bool useCustomMaxPrice = false;
  bool useCustomMinMileage = false;
  bool useCustomMaxMileage = false;

  @override
  void initState() {
    super.initState();
    // Only clear filters, but preserve cached car data for better reliability
    _clearFiltersOnly();
    _resetAllFiltersInMemory();
    _loadBodyTypesFromAssets();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchCars();
    });
  }

  Future<void> _loadBodyTypesFromAssets() async {
    try {
      final String manifestJson = await services.rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestJson);
      final Iterable<String> allAssets = manifestMap.keys.cast<String>();

      // Accept both SVG (clean) and PNG variants from both folders
      final List<String> btAssets = allAssets.where((p) =>
        (p.startsWith('assets/body_types_clean/') && (p.endsWith('.svg') || p.endsWith('.png')))
        || (p.startsWith('assets/body_types_png/') && p.endsWith('.png'))
      ).toList();

      // Build normalized label -> canonical svg path map
      final Map<String, String> labelToSvg = {};
      for (final String path in btAssets) {
        // Extract base filename without extension
        final String fileName = path.split('/').last; // e.g., sedan.svg
        final String base = fileName.replaceAll('.svg', '').replaceAll('.png', '');
        if (base.toLowerCase() == 'default') continue; // skip default placeholder

        // Build a user-friendly label (title case, even if file uses underscores)
        final String label = base
          .replaceAll('_', ' ')
          .split(' ') 
          .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))) 
          .join(' ');

        // Prefer clean SVG if available for same label, otherwise use PNG
        if (!labelToSvg.containsKey(label)) {
          labelToSvg[label] = path;
        } else {
          final String existing = labelToSvg[label]!;
          final bool existingIsSvg = existing.toLowerCase().endsWith('.svg');
          final bool incomingIsSvg = path.toLowerCase().endsWith('.svg');
          if (!existingIsSvg && incomingIsSvg) {
            labelToSvg[label] = path;
          }
        }
      }

      if (mounted) {
        setState(() {
          final List<String> labels = labelToSvg.keys.toList()..sort();
          globalBodyTypes = ['Any', ...labels];
          bodyTypes = globalBodyTypes;
          globalBodyTypeAssetMap = labelToSvg;
        });
      }
    } catch (_) {
      // If anything fails, keep the existing static fallback already present in code
    }
  }

  Future<void> fetchCars({bool bypassCache = false, bool isRetry = false}) async {
    print('ðŸš€ fetchCars called with bypassCache: $bypassCache, isRetry: $isRetry');
    // Analytics tracking for search fetch
    if (mounted) setState(() { isLoading = true; loadErrorMessage = null; });
    Map<String, String> filters = _buildFilters();
    
    String query = Uri(queryParameters: filters).query;
    final url = Uri.parse('${getApiBase()}/cars${query.isNotEmpty ? '?$query' : ''}');

    // Debug: Print the URL being called
    print('ðŸ” Fetching cars from: $url');
    print('ðŸ” Applied filters: $filters');
    print('ðŸ” Sort parameter: ${filters['sort_by']}');

    // Offline-first cache (skip cache if bypassCache is true)
    final sp = await SharedPreferences.getInstance();
    final cacheKey = 'cache_home_' + query.hashCode.toString();
    String? cached;
    if (!bypassCache) {
      // Use cached data to improve reliability and reduce API dependency
      cached = sp.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        print('ðŸ“¦ Using cached data for key: $cacheKey');
        try {
          final decoded = json.decode(cached);
          final List<Map<String, dynamic>> parsed = decoded is List
              ? decoded.whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList().cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[];
          if (mounted) setState(() { cars = parsed; isLoading = false; hasLoadedOnce = true; loadErrorMessage = null; });
        } catch (_) {}
      }
    } else {
      print('ðŸš« Bypassing cache for key: $cacheKey');
    }

    try {
      // Use longer timeout for sorting requests and add connection headers
      final timeout = filters.containsKey('sort_by') ? Duration(seconds: 30) : Duration(seconds: 15);
      final response = await http.get(
        url,
        headers: {
          'Connection': 'keep-alive',
          'Accept': 'application/json',
          'User-Agent': 'CARZO-Mobile/1.0',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ).timeout(timeout);
      
      print('ðŸ“¡ Response status: ${response.statusCode}');
      print('ðŸ“¡ Response body length: ${response.body.length}');
      
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<Map<String, dynamic>> parsed = decoded is List
            ? decoded
                .whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                .toList()
                .cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        
        print('ðŸ“Š Parsed ${parsed.length} cars from response');
        
        if (mounted) {
          setState(() {
            cars = parsed;
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage = null; // Clear any previous error message on success
          });
        }
        // Save fresh cache
        unawaited(sp.setString(cacheKey, response.body));
        print('âœ… Found ${parsed.length} cars with applied filters');
        // Reset retry count on success
        _fetchRetryCount = 0;
      } else {
        print('âŒ Server error: ${response.statusCode}');
        print('âŒ Response body: ${response.body}');
        await _handleFetchError(bypassCache, cached, 'Server ${response.statusCode}', isRetry: isRetry);
      }
    } catch (e) {
      print('âŒ Network error: $e');
      await _handleFetchError(bypassCache, cached, 'Network error', isRetry: isRetry);
    }
  }
  
  Future<void> _handleFetchError(bool bypassCache, String? cached, String errorMessage, {bool isRetry = false}) async {
    // Don't show error immediately - try fallback strategies first
    print('ðŸ”„ Handling fetch error: $errorMessage, isRetry: $isRetry');
    
    // If sorting failed and we have a sort parameter, try without sorting first
    if (selectedSortBy != null && selectedSortBy!.isNotEmpty && !isRetry) {
      print('ðŸ”„ Sorting failed, trying without sort parameter');
      try {
        await _fetchWithoutSort();
        return; // Success, don't show error
      } catch (e) {
        print('âŒ Fallback without sort also failed: $e');
      }
    }
    
    // Auto-retry logic for network errors
    if (_fetchRetryCount < _maxRetries && errorMessage == 'Network error' && !isRetry) {
      _fetchRetryCount++;
      print('ðŸ”„ Auto-retrying fetch (attempt $_fetchRetryCount/$_maxRetries)');
      await Future.delayed(Duration(seconds: 1)); // Shorter delay for better UX
      if (mounted) {
        try {
          await fetchCars(bypassCache: bypassCache, isRetry: true);
          return; // Success, don't show error
        } catch (e) {
          print('âŒ Auto-retry failed: $e');
        }
      }
    }
    
    // Only show error if all fallback strategies failed
    if (mounted) {
      setState(() { 
        isLoading = false; 
        hasLoadedOnce = true; 
        // Only show error if bypassing cache OR no cached data is available
        if (bypassCache || cached == null) {
          loadErrorMessage = errorMessage;
        } else {
          loadErrorMessage = null; // Clear error when using cached data
        }
      });
    }
  }
  
  Future<void> _fetchWithAlternativeHeaders(String sortValue) async {
    try {
      print('ðŸ”„ Attempting fetch with alternative headers for sort: $sortValue');
      Map<String, String> filters = _buildFilters();
      
      String query = Uri(queryParameters: filters).query;
      final url = Uri.parse('${getApiBase()}/cars${query.isNotEmpty ? '?$query' : ''}');
      
      print('ðŸ” Alternative fetch URL: $url');
      
      final response = await http.get(
        url,
        headers: {
          'Connection': 'close',
          'Accept': 'application/json',
          'User-Agent': 'CARZO-Mobile/1.0',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ).timeout(Duration(seconds: 25));
      
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<Map<String, dynamic>> parsed = decoded is List
            ? decoded
                .whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                .toList()
                .cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        
        if (mounted) {
          setState(() {
            cars = parsed;
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage = null;
          });
        }
        
        print('âœ… Alternative fetch successful: ${parsed.length} cars loaded');
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('âŒ Alternative fetch error: $e');
      rethrow;
    }
  }

  Future<void> _fetchWithoutSort() async {
    try {
      print('ðŸ”„ Attempting fetch without sort parameter');
      Map<String, String> filters = _buildFilters(includeSort: false);
      
      String query = Uri(queryParameters: filters).query;
      final url = Uri.parse('${getApiBase()}/cars${query.isNotEmpty ? '?$query' : ''}');
      
      print('ðŸ” Fallback URL: $url');
      
      final response = await http.get(url).timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<Map<String, dynamic>> parsed = decoded is List
            ? decoded
                .whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                .toList()
                .cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        
        if (mounted) {
          setState(() {
            cars = parsed;
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage = null;
          });
        }
        
        print('âœ… Fallback fetch successful: ${parsed.length} cars loaded');
        
        // Show a message that sorting was disabled
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sorting temporarily disabled due to server issue'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        print('âŒ Fallback fetch failed: ${response.statusCode}');
        if (mounted) {
          setState(() {
            loadErrorMessage = 'Server error: ${response.statusCode}';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('âŒ Fallback fetch error: $e');
      if (mounted) {
        setState(() {
          loadErrorMessage = 'Network error';
          isLoading = false;
        });
      }
    }
  }

  void onFilterChanged() {
    // Analytics tracking for filters applied
    fetchCars();
    // Auto-save search after applying filters
    unawaited(_autoSaveSearch());
  }

  Timer? _sortDebounceTimer;
  int _fetchRetryCount = 0;
  static const int _maxRetries = 3;
  
  Map<String, String> _buildFilters({bool includeSort = true}) {
    Map<String, String> filters = {};
    
    // Brand and Model filters
    if (selectedBrand != null && selectedBrand!.isNotEmpty) filters['brand'] = selectedBrand!;
    if (selectedModel != null && selectedModel!.isNotEmpty) filters['model'] = selectedModel!;
    if (selectedTrim != null && selectedTrim!.isNotEmpty) filters['trim'] = selectedTrim!;
    
    // Price filters - apply individually, not requiring both
    if (selectedMinPrice != null && selectedMinPrice!.isNotEmpty) filters['min_price'] = selectedMinPrice!;
    if (selectedMaxPrice != null && selectedMaxPrice!.isNotEmpty) filters['max_price'] = selectedMaxPrice!;
    
    // Year filters - apply individually, not requiring both
    if (selectedMinYear != null && selectedMinYear!.isNotEmpty) filters['min_year'] = selectedMinYear!;
    if (selectedMaxYear != null && selectedMaxYear!.isNotEmpty) filters['max_year'] = selectedMaxYear!;
    
    // Mileage filters - apply individually, not requiring both
    if (selectedMinMileage != null && selectedMinMileage!.isNotEmpty) filters['min_mileage'] = selectedMinMileage!;
    if (selectedMaxMileage != null && selectedMaxMileage!.isNotEmpty) filters['max_mileage'] = selectedMaxMileage!;
    
    // Vehicle condition and specifications
    if (selectedCondition != null && selectedCondition!.isNotEmpty && selectedCondition != 'Any') filters['condition'] = selectedCondition!.toLowerCase();
    if (selectedTransmission != null && selectedTransmission!.isNotEmpty && selectedTransmission != 'Any') filters['transmission'] = selectedTransmission!.toLowerCase();
    if (selectedFuelType != null && selectedFuelType!.isNotEmpty && selectedFuelType != 'Any') filters['fuel_type'] = selectedFuelType!.toLowerCase();
    if (selectedBodyType != null && selectedBodyType!.isNotEmpty && selectedBodyType != 'Any') filters['body_type'] = selectedBodyType!.toLowerCase();
    if (selectedColor != null && selectedColor!.isNotEmpty && selectedColor != 'Any') filters['color'] = selectedColor!.toLowerCase();
    if (selectedDriveType != null && selectedDriveType!.isNotEmpty && selectedDriveType != 'Any') filters['drive_type'] = selectedDriveType!.toLowerCase();
    if (selectedCylinderCount != null && selectedCylinderCount!.isNotEmpty && selectedCylinderCount != 'Any') filters['cylinder_count'] = selectedCylinderCount!;
    if (selectedSeating != null && selectedSeating!.isNotEmpty && selectedSeating != 'Any') filters['seating'] = selectedSeating!;
    if (selectedEngineSize != null && selectedEngineSize!.isNotEmpty && selectedEngineSize != 'Any') filters['engine_size'] = selectedEngineSize!;
    
    // Location and other filters
    if (selectedCity != null && selectedCity!.isNotEmpty) filters['city'] = selectedCity!;
    
    // Only include sort if requested and valid
    if (includeSort) {
      final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
      if (apiSortValue != null && apiSortValue.isNotEmpty) {
        filters['sort_by'] = apiSortValue;
      }
    }
    
    if (selectedOwners != null && selectedOwners!.isNotEmpty) filters['owners'] = selectedOwners!;
    if (selectedVIN != null && selectedVIN!.isNotEmpty) filters['vin'] = selectedVIN!;
    if (selectedAccidentHistory != null && selectedAccidentHistory!.isNotEmpty) filters['accident_history'] = selectedAccidentHistory!;
    
    // Title status and damaged parts
    if (selectedTitleStatus != null && selectedTitleStatus!.isNotEmpty) {
      filters['title_status'] = selectedTitleStatus!;
      if (selectedTitleStatus == 'damaged' && selectedDamagedParts != null && selectedDamagedParts!.isNotEmpty) {
        filters['damaged_parts'] = selectedDamagedParts!;
      }
    }
    
    return filters;
  }
  
  void onSortChanged() async {
    print('ðŸ”„ Sort changed to: $selectedSortBy');
    // Analytics tracking for sort changed
    
    // Cancel any pending sort operation
    _sortDebounceTimer?.cancel();
    
    // Immediate response - no debounce for better UX
    if (!mounted) return;
    
    // Reset retry count when sorting changes
    _fetchRetryCount = 0;
    
    // Clear any previous error messages
    if (mounted) {
      setState(() {
        loadErrorMessage = null;
        isLoading = true;
      });
    }
    
    // Clear cache for current filters
    try {
      final sp = await SharedPreferences.getInstance();
      final currentFilters = _buildFilters();
      final query = Uri(queryParameters: currentFilters).query;
      final cacheKey = 'cache_home_' + query.hashCode.toString();
      await sp.remove(cacheKey);
      print('ðŸ—‘ï¸ Cleared cache for current filters: $cacheKey');
    } catch (e) {
      print('âŒ Error clearing cache: $e');
    }
    
    // Try the sort operation immediately
    await _performSortWithFallback();
  }
  
  Future<void> _performSortWithFallback() async {
    // Validate sort parameter before attempting
    final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
    print('ðŸ”„ Sort parameter validation: ${selectedSortBy} -> ${apiSortValue}');
    
    if (apiSortValue == null || apiSortValue.isEmpty) {
      print('âš ï¸ Invalid sort parameter, skipping sort');
      await fetchCars(bypassCache: true);
      return;
    }
    
    // Try multiple strategies in sequence
    List<Future<void> Function()> strategies = [
      () => _tryDirectSort(apiSortValue),
      () => _tryAlternativeSort(apiSortValue),
      () => _trySimpleSort(apiSortValue),
      () => _tryConnectionReset(apiSortValue),
      () => _tryWithoutSort(),
    ];
    
    for (int i = 0; i < strategies.length; i++) {
      try {
        print('ðŸ”„ Trying strategy ${i + 1}/${strategies.length}');
        await strategies[i]();
        print('âœ… Strategy ${i + 1} successful');
        return;
      } catch (e) {
        print('âŒ Strategy ${i + 1} failed: $e');
        if (i < strategies.length - 1) {
          await Future.delayed(Duration(milliseconds: 200));
        }
      }
    }
    
    // If all strategies fail, show error
    if (mounted) {
      setState(() {
        loadErrorMessage = 'Failed to load listings';
        isLoading = false;
      });
    }
  }
  
  Future<void> _tryDirectSort(String apiSortValue) async {
    print('ðŸ”„ Direct sort attempt with: $apiSortValue');
    
    // Try up to 5 times with increasing delays and different approaches
    for (int attempt = 1; attempt <= 5; attempt++) {
      try {
        // Use different timeout and connection settings based on attempt
        final timeout = Duration(seconds: 10 + (attempt * 5));
        print('ðŸ”„ Attempt $attempt with ${timeout.inSeconds}s timeout');
        
        Map<String, String> filters = _buildFilters();
        String query = Uri(queryParameters: filters).query;
        final url = Uri.parse('${getApiBase()}/cars${query.isNotEmpty ? '?$query' : ''}');
        
        final response = await http.get(
          url,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'CARZO-Mobile/1.0',
            'Connection': attempt % 2 == 0 ? 'close' : 'keep-alive',
            'Cache-Control': 'no-cache',
          },
        ).timeout(timeout);
        
        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          final List<Map<String, dynamic>> parsed = decoded is List
              ? decoded.whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList().cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[];
          
          if (mounted) {
            setState(() {
              cars = parsed;
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
            });
          }
          
          // Save to cache
          final sp = await SharedPreferences.getInstance();
          final cacheKey = 'cache_home_' + query.hashCode.toString();
          unawaited(sp.setString(cacheKey, response.body));
          
          unawaited(_autoSaveSearch());
          print('âœ… Direct sort successful on attempt $attempt');
          return;
        } else {
          throw Exception('Server error: ${response.statusCode}');
        }
      } catch (e) {
        print('âŒ Direct sort attempt $attempt failed: $e');
        if (attempt < 5) {
          await Future.delayed(Duration(milliseconds: 200 * attempt));
        } else {
          rethrow;
        }
      }
    }
  }
  
  Future<void> _tryAlternativeSort(String apiSortValue) async {
    print('ðŸ”„ Alternative sort attempt with: $apiSortValue');
    
    // Try with different connection approaches
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        Map<String, String> filters = _buildFilters();
        String query = Uri(queryParameters: filters).query;
        final url = Uri.parse('${getApiBase()}/cars${query.isNotEmpty ? '?$query' : ''}');
        
        final response = await http.get(
          url,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'CARZO-Mobile/1.0',
            'Connection': 'close',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            'If-None-Match': '*',
          },
        ).timeout(Duration(seconds: 15));
        
        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          final List<Map<String, dynamic>> parsed = decoded is List
              ? decoded.whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList().cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[];
          
          if (mounted) {
            setState(() {
              cars = parsed;
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
            });
          }
          
          unawaited(_autoSaveSearch());
          print('âœ… Alternative sort successful on attempt $attempt');
          return;
        } else {
          throw Exception('Server error: ${response.statusCode}');
        }
      } catch (e) {
        print('âŒ Alternative sort attempt $attempt failed: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 300));
        } else {
          rethrow;
        }
      }
    }
  }
  
  Future<void> _trySimpleSort(String apiSortValue) async {
    print('ðŸ”„ Simple sort attempt with: $apiSortValue');
    // Try with minimal headers and shorter timeout
    Map<String, String> filters = _buildFilters();
    String query = Uri(queryParameters: filters).query;
    final url = Uri.parse('${getApiBase()}/cars${query.isNotEmpty ? '?$query' : ''}');
    
    final response = await http.get(
      url,
      headers: {'Accept': 'application/json'},
    ).timeout(Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final List<Map<String, dynamic>> parsed = decoded is List
          ? decoded.whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList().cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      
      if (mounted) {
        setState(() {
          cars = parsed;
          isLoading = false;
          hasLoadedOnce = true;
          loadErrorMessage = null;
        });
      }
      unawaited(_autoSaveSearch());
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }
  
  Future<void> _tryConnectionReset(String apiSortValue) async {
    print('ðŸ”„ Connection reset attempt with: $apiSortValue');
    
    // Wait a bit longer and try with a completely fresh approach
    await Future.delayed(Duration(milliseconds: 1000));
    
    try {
      Map<String, String> filters = _buildFilters();
      String query = Uri(queryParameters: filters).query;
      final url = Uri.parse('${getApiBase()}/cars${query.isNotEmpty ? '?$query' : ''}');
      
      // Try with a very simple request
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: 20));
      
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<Map<String, dynamic>> parsed = decoded is List
            ? decoded.whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList().cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        
        if (mounted) {
          setState(() {
            cars = parsed;
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage = null;
          });
        }
        
        unawaited(_autoSaveSearch());
        print('âœ… Connection reset successful');
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('âŒ Connection reset failed: $e');
      rethrow;
    }
  }

  Future<void> _tryWithoutSort() async {
    print('ðŸ”„ Fallback: trying without sort');
    try {
      await _fetchWithoutSort();
      // If we get here, try client-side sorting as a last resort
      await _tryClientSideSort();
    } catch (e) {
      print('âŒ Fallback also failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sorting temporarily unavailable'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
  
  Future<void> _tryClientSideSort() async {
    print('ðŸ”„ Attempting client-side sort');
    final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
    if (apiSortValue == null || selectedSortBy == null) return;
    
    List<Map<String, dynamic>> sortedCars = List.from(cars);
    
    try {
      switch (apiSortValue) {
        case 'price_asc':
          sortedCars.sort((a, b) {
            final priceA = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
            final priceB = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
            return priceA.compareTo(priceB);
          });
          break;
        case 'price_desc':
          sortedCars.sort((a, b) {
            final priceA = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
            final priceB = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
            return priceB.compareTo(priceA);
          });
          break;
        case 'year_desc':
          sortedCars.sort((a, b) {
            final yearA = int.tryParse(a['year']?.toString() ?? '0') ?? 0;
            final yearB = int.tryParse(b['year']?.toString() ?? '0') ?? 0;
            return yearB.compareTo(yearA);
          });
          break;
        case 'year_asc':
          sortedCars.sort((a, b) {
            final yearA = int.tryParse(a['year']?.toString() ?? '0') ?? 0;
            final yearB = int.tryParse(b['year']?.toString() ?? '0') ?? 0;
            return yearA.compareTo(yearB);
          });
          break;
        case 'mileage_asc':
          sortedCars.sort((a, b) {
            final mileageA = int.tryParse(a['mileage']?.toString() ?? '0') ?? 0;
            final mileageB = int.tryParse(b['mileage']?.toString() ?? '0') ?? 0;
            return mileageA.compareTo(mileageB);
          });
          break;
        case 'mileage_desc':
          sortedCars.sort((a, b) {
            final mileageA = int.tryParse(a['mileage']?.toString() ?? '0') ?? 0;
            final mileageB = int.tryParse(b['mileage']?.toString() ?? '0') ?? 0;
            return mileageB.compareTo(mileageA);
          });
          break;
        case 'newest':
          sortedCars.sort((a, b) {
            final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
            final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
            return dateB.compareTo(dateA);
          });
          break;
      }
      
      if (mounted) {
        setState(() {
          cars = sortedCars;
          isLoading = false;
          loadErrorMessage = null;
        });
      }
      
      print('âœ… Client-side sort successful');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sorted locally (server unavailable)'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      print('âŒ Client-side sort failed: $e');
      rethrow;
    }
  }

  void clearFiltersOnVehicleChange() {
    // Clear filters that are specific to vehicle specifications
    selectedBodyType = null;
    selectedTransmission = null;
    selectedFuelType = null;
    selectedDriveType = null;
    selectedCylinderCount = null;
    selectedSeating = null;
    selectedEngineSize = null;
    selectedColor = null;
  }

  // Helper methods to get available options based on selected vehicle
  List<String> getAvailableEngineSizes() {
    if (selectedBrand == null || selectedModel == null || selectedTrim == null) {
      return engineSizes;
    }
    
    final specs = globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['engineSizes'] != null) {
      return ['Any', ...specs['engineSizes']];
    }
    return engineSizes;
  }

  List<String> getAvailableConditions() {
    return conditions;
  }

  List<String> getAvailableBodyTypes() {
    if (selectedBrand == null || selectedModel == null || selectedTrim == null) {
      return bodyTypes;
    }
    
    final specs = globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['bodyTypes'] != null) {
      return ['Any', ...specs['bodyTypes']];
    }
    return bodyTypes;
  }

  List<String> getAvailableTransmissions() {
    if (selectedBrand == null || selectedModel == null || selectedTrim == null) {
      return transmissions;
    }
    
    final specs = globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['transmissions'] != null) {
      return ['Any', ...specs['transmissions']];
    }
    return transmissions;
  }

  List<String> getAvailableFuelTypes() {
    if (selectedBrand == null || selectedModel == null || selectedTrim == null) {
      return fuelTypes;
    }
    
    final specs = globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['fuelTypes'] != null) {
      return ['Any', ...specs['fuelTypes']];
    }
    return fuelTypes;
  }

  List<String> getAvailableDriveTypes() {
    if (selectedBrand == null || selectedModel == null || selectedTrim == null) {
      return driveTypes;
    }
    
    final specs = globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['driveTypes'] != null) {
      return ['Any', ...specs['driveTypes']];
    }
    return driveTypes;
  }

  List<String> getAvailableCylinderCounts() {
    if (selectedBrand == null || selectedModel == null || selectedTrim == null) {
      return cylinderCounts;
    }
    
    final specs = globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['cylinderCounts'] != null) {
      return ['Any', ...specs['cylinderCounts']];
    }
    return cylinderCounts;
  }

  List<String> getAvailableSeatings() {
    if (selectedBrand == null || selectedModel == null || selectedTrim == null) {
      return seatings;
    }
    
    final specs = globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['seatings'] != null) {
      return ['Any', ...specs['seatings']];
    }
    return seatings;
  }

  List<String> getAvailableColors() {
    if (selectedBrand == null || selectedModel == null || selectedTrim == null) {
      return colors;
    }
    
    final specs = globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['colors'] != null) {
      return ['Any', ...specs['colors']];
    }
    return colors;
  }

  // Helper method to get a valid drive type value for dropdown
  String? _getValidDriveTypeValue() {
    if (selectedDriveType == null) return '';
    
    final availableTypes = getAvailableDriveTypes();
    
    // First try exact match
    if (availableTypes.contains(selectedDriveType)) {
      return selectedDriveType;
    }
    
    // Try case-insensitive match
    final lowerSelected = selectedDriveType!.toLowerCase();
    for (final type in availableTypes) {
      if (type.toLowerCase() == lowerSelected) {
        return type;
      }
    }
    
    // If no match found, return empty string
    return '';
  }

  // Helper method to get a valid transmission value for dropdown
  String? _getValidTransmissionValue() {
    if (selectedTransmission == null) return '';
    
    final availableTypes = getAvailableTransmissions();
    
    // First try exact match
    if (availableTypes.contains(selectedTransmission)) {
      return selectedTransmission;
    }
    
    // Try case-insensitive match
    final lowerSelected = selectedTransmission!.toLowerCase();
    for (final type in availableTypes) {
      if (type.toLowerCase() == lowerSelected) {
        return type;
      }
    }
    
    // If no match found, return empty string
    return '';
  }

  // Helper method to get a valid fuel type value for dropdown
  String? _getValidFuelTypeValue() {
    if (selectedFuelType == null) return '';
    
    final availableTypes = getAvailableFuelTypes();
    
    // First try exact match
    if (availableTypes.contains(selectedFuelType)) {
      return selectedFuelType;
    }
    
    // Try case-insensitive match
    final lowerSelected = selectedFuelType!.toLowerCase();
    for (final type in availableTypes) {
      if (type.toLowerCase() == lowerSelected) {
        return type;
      }
    }
    
    // If no match found, return empty string
    return '';
  }

  // Helper method to check if there are any active filters
  bool _hasActiveFilters() {
    return selectedBrand != null ||
           selectedModel != null ||
           selectedTrim != null ||
           selectedMinPrice != null ||
           selectedMaxPrice != null ||
           selectedMinYear != null ||
           selectedMaxYear != null ||
           selectedMinMileage != null ||
           selectedMaxMileage != null ||
           selectedCondition != null ||
           selectedTransmission != null ||
           selectedFuelType != null ||
           selectedBodyType != null ||
           selectedColor != null ||
           selectedDriveType != null ||
           selectedCylinderCount != null ||
           selectedSeating != null ||
           selectedEngineSize != null ||
           selectedCity != null ||
           selectedSortBy != null ||
           selectedTitleStatus != null ||
           selectedDamagedParts != null;
  }

  // Helper method to clear all filters
  void _clearAllFilters() {
    setState(() {
      selectedBrand = null;
      selectedModel = null;
      selectedTrim = null;
      selectedMinPrice = null;
      selectedMaxPrice = null;
      selectedMinYear = null;
      selectedMaxYear = null;
      selectedMinMileage = null;
      selectedMaxMileage = null;
      selectedCondition = null;
      selectedTransmission = null;
      selectedFuelType = null;
      selectedBodyType = null;
      selectedColor = null;
      selectedDriveType = null;
      selectedCylinderCount = null;
      selectedSeating = null;
      selectedEngineSize = null;
      selectedCity = null;
      selectedSortBy = null;
      selectedTitleStatus = null;
      selectedDamagedParts = null;
      selectedOwners = null;
      selectedVIN = null;
      selectedAccidentHistory = null;
    });
    onFilterChanged();
  }

  // Helper method to clear a specific filter
  void _clearFilter(String filterType) {
    setState(() {
      switch (filterType) {
        case 'brand':
          selectedBrand = null;
          selectedModel = null;
          selectedTrim = null;
          break;
        case 'model':
          selectedModel = null;
          selectedTrim = null;
          break;
        case 'trim':
          selectedTrim = null;
          break;
        case 'price':
          selectedMinPrice = null;
          selectedMaxPrice = null;
          break;
        case 'year':
          selectedMinYear = null;
          selectedMaxYear = null;
          break;
        case 'mileage':
          selectedMinMileage = null;
          selectedMaxMileage = null;
          break;
        case 'condition':
          selectedCondition = null;
          break;
        case 'transmission':
          selectedTransmission = null;
          break;
        case 'fuelType':
          selectedFuelType = null;
          break;
        case 'titleStatus':
          selectedTitleStatus = null;
          selectedDamagedParts = null;
          break;
        case 'damagedParts':
          selectedDamagedParts = null;
          break;
        case 'bodyType':
          selectedBodyType = null;
          break;
        case 'color':
          selectedColor = null;
          break;
        case 'driveType':
          selectedDriveType = null;
          break;
        case 'cylinderCount':
          selectedCylinderCount = null;
          break;
        case 'seating':
          selectedSeating = null;
          break;
        case 'engineSize':
          selectedEngineSize = null;
          break;
        case 'city':
          selectedCity = null;
          break;
        case 'sortBy':
          selectedSortBy = null;
          break;
        case 'owners':
          selectedOwners = null;
          break;
        case 'vin':
          selectedVIN = null;
          break;
        case 'accident_history':
          selectedAccidentHistory = null;
          break;
      }
    });
    onFilterChanged();
  }
  // Helper method to build active filter chips
  List<Widget> _buildActiveFilterChips() {
    List<Widget> chips = [];

    // Brand filter
    if (selectedBrand != null && selectedBrand!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.brandLabel, _translateValueGlobal(context, selectedBrand) ?? selectedBrand!, 'brand', Icons.directions_car, Color(0xFFFF6B00)));
    }

    // Model filter
    if (selectedModel != null && selectedModel!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.modelLabel, _translateValueGlobal(context, selectedModel) ?? selectedModel!, 'model', Icons.directions_car, Color(0xFFFF6B00)));
    }

    // Trim filter
    if (selectedTrim != null && selectedTrim!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.trimLabel, _translateValueGlobal(context, selectedTrim) ?? selectedTrim!, 'trim', Icons.settings, Color(0xFFFF6B00)));
    }

    // Price range filter
    if (selectedMinPrice != null || selectedMaxPrice != null) {
      String priceText = '';
      if (selectedMinPrice != null && selectedMaxPrice != null) {
        priceText = _formatCurrencyGlobal(context, selectedMinPrice!) + ' - ' + _formatCurrencyGlobal(context, selectedMaxPrice!);
      } else if (selectedMinPrice != null) {
        priceText = '${AppLocalizations.of(context)!.minPrice}: ' + _formatCurrencyGlobal(context, selectedMinPrice!);
      } else if (selectedMaxPrice != null) {
        priceText = '${AppLocalizations.of(context)!.maxPrice}: ' + _formatCurrencyGlobal(context, selectedMaxPrice!);
      }
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.priceLabel, priceText, 'price', Icons.attach_money, Colors.green));
    }

    // Year range filter
    if (selectedMinYear != null || selectedMaxYear != null) {
      String yearText = '';
      if (selectedMinYear != null && selectedMaxYear != null) {
        yearText = '${_localizeDigitsGlobal(context, selectedMinYear!)} - ${_localizeDigitsGlobal(context, selectedMaxYear!)}';
      } else if (selectedMinYear != null) {
        yearText = '${AppLocalizations.of(context)!.minYear}: ${_localizeDigitsGlobal(context, selectedMinYear!)}';
      } else if (selectedMaxYear != null) {
        yearText = '${AppLocalizations.of(context)!.maxYear}: ${_localizeDigitsGlobal(context, selectedMaxYear!)}';
      }
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.yearLabel, yearText, 'year', Icons.calendar_today, Colors.blue));
    }

    // Mileage range filter
    if (selectedMinMileage != null || selectedMaxMileage != null) {
      String mileageText = '';
      if (selectedMinMileage != null && selectedMaxMileage != null) {
        mileageText = '${_localizeDigitsGlobal(context, selectedMinMileage!)} - ${_localizeDigitsGlobal(context, selectedMaxMileage!)} ${AppLocalizations.of(context)!.unit_km}';
      } else if (selectedMinMileage != null) {
        mileageText = '${AppLocalizations.of(context)!.minMileage}: ${_localizeDigitsGlobal(context, selectedMinMileage!)} ${AppLocalizations.of(context)!.unit_km}';
      } else if (selectedMaxMileage != null) {
        mileageText = '${AppLocalizations.of(context)!.maxMileage}: ${_localizeDigitsGlobal(context, selectedMaxMileage!)} ${AppLocalizations.of(context)!.unit_km}';
      }
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.mileageLabel, mileageText, 'mileage', Icons.speed, Colors.orange));
    }

    // Condition filter
    if (selectedCondition != null && selectedCondition!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.detail_condition, _translateValueGlobal(context, selectedCondition) ?? selectedCondition!, 'condition', Icons.check_circle, Colors.green));
    }

    // Transmission filter
    if (selectedTransmission != null && selectedTransmission!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.transmissionLabel, _translateValueGlobal(context, selectedTransmission) ?? selectedTransmission!, 'transmission', Icons.settings, Colors.purple));
    }

    // Fuel type filter
    if (selectedFuelType != null && selectedFuelType!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.detail_fuel, _translateValueGlobal(context, selectedFuelType) ?? selectedFuelType!, 'fuelType', Icons.local_gas_station, Colors.orange));
    }

    // Title/parts filter
    if (selectedTitleStatus != null && selectedTitleStatus!.isNotEmpty) {
      if (selectedTitleStatus == 'damaged' && selectedDamagedParts != null && selectedDamagedParts!.isNotEmpty) {
        chips.add(_buildFilterChip(AppLocalizations.of(context)!.titleStatus, '${AppLocalizations.of(context)!.value_title_damaged} (${_localizeDigitsGlobal(context, selectedDamagedParts!)} ${AppLocalizations.of(context)!.damagedParts})', 'titleStatus', Icons.report, Colors.redAccent));
      } else {
        chips.add(_buildFilterChip(AppLocalizations.of(context)!.titleStatus, _translateValueGlobal(context, selectedTitleStatus) ?? selectedTitleStatus!.substring(0,1).toUpperCase() + selectedTitleStatus!.substring(1), 'titleStatus', Icons.verified, Colors.green));
      }
    }

    // Body type filter
    if (selectedBodyType != null && selectedBodyType!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.bodyTypeLabel, _translateValueGlobal(context, selectedBodyType) ?? selectedBodyType!, 'bodyType', _getBodyTypeIcon(selectedBodyType!), Color(0xFFFF6B00)));
    }

    // Color filter
    if (selectedColor != null && selectedColor!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.colorLabel, _translateValueGlobal(context, selectedColor) ?? selectedColor!, 'color', Icons.palette, _getColorValue(selectedColor!)));
    }

    // Drive type filter
    if (selectedDriveType != null && selectedDriveType!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.driveType, _translateValueGlobal(context, selectedDriveType) ?? selectedDriveType!, 'driveType', Icons.directions_car, Colors.cyan));
    }

    // Cylinder count filter
    if (selectedCylinderCount != null && selectedCylinderCount!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.detail_cylinders, _localizeDigitsGlobal(context, selectedCylinderCount!), 'cylinderCount', Icons.engineering, Colors.red));
    }

    // Seating filter
    if (selectedSeating != null && selectedSeating!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.seating, _localizeDigitsGlobal(context, selectedSeating!), 'seating', Icons.airline_seat_recline_normal, Colors.indigo));
    }

    // Engine Size filter
    if (selectedEngineSize != null && selectedEngineSize!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.engineSizeL, '${_localizeDigitsGlobal(context, selectedEngineSize!)}${AppLocalizations.of(context)!.unit_liter_suffix}', 'engineSize', Icons.engineering, Colors.deepOrange));
    }

    // City filter
    if (selectedCity != null && selectedCity!.toLowerCase() != 'any') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.cityLabel, _translateValueGlobal(context, selectedCity) ?? selectedCity!, 'city', Icons.location_city, Colors.teal));
    }

    // Sort by filter
    if (selectedSortBy != null && selectedSortBy!.toLowerCase() != 'any' && selectedSortBy!.toLowerCase() != 'default') {
      chips.add(_buildFilterChip(AppLocalizations.of(context)!.sortBy, _translateValueGlobal(context, selectedSortBy) ?? selectedSortBy!, 'sortBy', Icons.sort, Colors.grey));
    }

    return chips;
  }

  // Helper method to build individual filter chips
  Widget _buildFilterChip(String label, String value, String filterType, IconData icon, Color color) {
    return GestureDetector(
      onTap: () => _clearFilter(filterType),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 10),
            SizedBox(width: 4),
            Text(
              '$label: $value',
              style: GoogleFonts.orbitron(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(width: 4),
            Icon(Icons.close, color: color, size: 9),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(
            AppLocalizations.of(context)!.appTitle,
            style: TextStyle(fontSize: 18),
          ),
          actions: [
          IconButton(
            tooltip: 'Saved Searches',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SavedSearchesPage(parentState: this))),
            icon: Icon(Icons.bookmarks_outlined),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SellCarPage()),
              );
            },
            icon: Icon(Icons.add, color: Colors.white),
            label: Text('Sell', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white70),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const ThemeToggleWidget(),
          buildLanguageMenu(),
        ],
        ),
        // Pull-to-refresh is already provided inside the main content via internal scrollables
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.black87,
          selectedItemColor: Color(0xFFFF6B00),
          unselectedItemColor: Colors.white70,
          currentIndex: 0,
          onTap: (idx) {
            switch (idx) {
              case 0:
                Navigator.pushReplacementNamed(context, '/');
                break;
              case 1:
                Navigator.pushReplacementNamed(context, '/favorites');
                break;
              case 2:
                Navigator.pushReplacementNamed(context, '/profile');
                break;
            }
          },
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context)!.navHome),
            BottomNavigationBarItem(icon: Icon(Icons.favorite), label: AppLocalizations.of(context)!.navSaved),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) ? AppLocalizations.of(context)!.navLogin : AppLocalizations.of(context)!.navProfile),
          ],
        ),
        body: SafeArea(
        top: false,
        bottom: true,
        child: Stack(
          children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F1115), Color(0xFF131722), Color(0xFF0F1115)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 0.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: Card(
                    elevation: 12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    color: Colors.white.withOpacity(0.06),
                     child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.search, color: Color(0xFFFF6B00)),
                              SizedBox(width: 8),
                              Text(
                                AppLocalizations.of(context)!.appTitle,
                                style: GoogleFonts.orbitron(
                                  color: Color(0xFFFF6B00),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                           Row(
                            children: [
                              // Brand selector styled like a form field for symmetry
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final brand = await showDialog<String>(
                                      context: context,
                                      builder: (context) {
                                        return Dialog(
                                          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          child: Container(
                                            width: 400,
                                            padding: EdgeInsets.all(20),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(AppLocalizations.of(context)!.selectBrand, style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                                                    IconButton(
                                                      icon: Icon(Icons.close, color: Colors.white),
                                                      onPressed: () => Navigator.pop(context),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(height: 10),
                                                SizedBox(
                                                  height: 380,
                                                  child: GridView.builder(
                                                    shrinkWrap: true,
                                                    physics: BouncingScrollPhysics(),
                                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                      crossAxisCount: 4,
                                                      childAspectRatio: 0.85,
                                                      crossAxisSpacing: 10,
                                                      mainAxisSpacing: 10,
                                                    ),
                                                    itemCount: homeBrands.length,
                                                    itemBuilder: (context, index) {
                                                      final brand = homeBrands[index];
                                                      final logoFile = brandLogoFilenames[brand] ?? brand.toLowerCase().replaceAll(' ', '-').replaceAll('Ã©', 'e').replaceAll('Ã¶', 'o');
                                                      final logoUrl = getApiBase() + '/static/images/brands/' + logoFile + '.png';
                                                      return InkWell(
                                                        borderRadius: BorderRadius.circular(12),
                                                        onTap: () => Navigator.pop(context, brand),
                                                        child: Container(
                                                          decoration: BoxDecoration(
                                                            color: Colors.black.withOpacity(0.15),
                                                            borderRadius: BorderRadius.circular(12),
                                                            border: Border.all(color: Colors.white24),
                                                          ),
                                                          padding: EdgeInsets.all(6),
                                                          child: Column(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Container(
                                                                width: 32,
                                                                height: 32,
                                                                padding: EdgeInsets.all(4),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.white,
                                                                  borderRadius: BorderRadius.circular(8),
                                                                ),
                                                                child: CachedNetworkImage(
                                                                  imageUrl: logoUrl,
                                                                  placeholder: (context, url) => SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                                                  errorWidget: (context, url, error) => Icon(Icons.directions_car, size: 22, color: Color(0xFFFF6B00)),
                                                                  fit: BoxFit.contain,
                                                                ),
                                                              ),
                                                              SizedBox(height: 4),
                                                              Text(
                                                                brand,
                                                                style: GoogleFonts.orbitron(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                                                textAlign: TextAlign.center,
                                                                overflow: TextOverflow.ellipsis,
                                                                maxLines: 1,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                    if (brand != null) {
                                                                                              setState(() {
                                                          selectedBrand = brand;
                                                          selectedModel = null;
                                                          selectedTrim = null;
                                                          clearFiltersOnVehicleChange();
                                                        });
                                      onFilterChanged();
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: AppLocalizations.of(context)!.brandLabel,
                                      labelStyle: GoogleFonts.orbitron(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                      filled: true,
                                      fillColor: Colors.black.withOpacity(0.15),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    ),
                                    child: Row(
                                      children: [
                                        if (selectedBrand != null && selectedBrand!.isNotEmpty)
                                          Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                                            padding: EdgeInsets.all(2),
                                            child: CachedNetworkImage(
                                              imageUrl: getApiBase() + '/static/images/brands/' + (brandLogoFilenames[selectedBrand] ?? selectedBrand!.toLowerCase().replaceAll(' ', '-')) + '.png',
                                              placeholder: (context, url) => SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                              errorWidget: (context, url, error) => Icon(Icons.directions_car, size: 16, color: Color(0xFFFF6B00)),
                                              fit: BoxFit.contain,
                                            ),
                                          )
                                        else
                                          Icon(Icons.directions_car, size: 20, color: Color(0xFFFF6B00)),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            selectedBrand == null || selectedBrand!.isEmpty ? AppLocalizations.of(context)!.any : selectedBrand!,
                                            style: GoogleFonts.orbitron(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              // Model Dropdown
                               Expanded(
                                child: DropdownButtonFormField<String>(
                                  isDense: true,
                                  style: GoogleFonts.orbitron(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                                  value: selectedModel != null && (selectedModel!.isEmpty || (selectedBrand != null && models[selectedBrand] != null && models[selectedBrand]!.contains(selectedModel))) ? selectedModel : null,
                                  decoration: InputDecoration(
                                    labelText: AppLocalizations.of(context)!.modelLabel,
                                    labelStyle: GoogleFonts.orbitron(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                     filled: true,
                                     fillColor: Colors.black.withOpacity(0.15),
                                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  ),
                                  items: [
                                    DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: GoogleFonts.orbitron(color: Colors.grey, fontSize: 14))),
                                    if (selectedBrand != null && models[selectedBrand!] != null)
                                      ...models[selectedBrand!]!.map((m) => DropdownMenuItem(value: m, child: Text(_translateValueGlobal(context, m) ?? m, style: GoogleFonts.orbitron(fontSize: 14)))).toList(),
                                  ],
                                  onChanged: (value) {
                                    setState(() { 
                                      selectedModel = value == '' ? null : value;
                                      selectedTrim = null;
                                      clearFiltersOnVehicleChange();
                                    });
                                    onFilterChanged();
                                  },
                                ),
                              ),
                              SizedBox(width: 8),
                              // Trim Dropdown
                               Expanded(
                                child: DropdownButtonFormField<String>(
                                  isDense: true,
                                  style: GoogleFonts.orbitron(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                                  value: selectedTrim != null && (selectedTrim!.isEmpty || (selectedBrand != null && selectedModel != null && trimsByBrandModel[selectedBrand] != null && trimsByBrandModel[selectedBrand]![selectedModel] != null && trimsByBrandModel[selectedBrand]![selectedModel]!.contains(selectedTrim))) ? selectedTrim : null,
                                  decoration: InputDecoration(
                                    labelText: AppLocalizations.of(context)!.trimLabel,
                                    labelStyle: GoogleFonts.orbitron(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                     filled: true,
                                     fillColor: Colors.black.withOpacity(0.15),
                                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  ),
                                  items: [
                                    DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: GoogleFonts.orbitron(color: Colors.grey, fontSize: 14))),
                                    if (selectedBrand != null && selectedModel != null && trimsByBrandModel[selectedBrand] != null && trimsByBrandModel[selectedBrand]![selectedModel] != null)
                                      ...trimsByBrandModel[selectedBrand]![selectedModel]!.map((t) => DropdownMenuItem(value: t, child: Text(t, style: GoogleFonts.orbitron(fontSize: 14)))).toList(),
                                  ],
                                  onChanged: (value) {
                                    setState(() { 
                                      selectedTrim = value == '' ? null : value; 
                                      clearFiltersOnVehicleChange();
                                    });
                                    onFilterChanged();
                                  },
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          // Active Filters Display
                          if (_hasActiveFilters())
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.filter_list, color: Color(0xFFFF6B00), size: 16),
                                          SizedBox(width: 8),
                                          Text(
                                            AppLocalizations.of(context)!.activeFilters,
                                            style: GoogleFonts.orbitron(
                                              fontSize: 12,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(children: [
                                      GestureDetector(
                                        onTap: _clearAllFilters,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.red, width: 1),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.clear, color: Colors.red, size: 12),
                                              SizedBox(width: 4),
                                              Text(
                                                  AppLocalizations.of(context)!.clearFilters,
                                                style: GoogleFonts.orbitron(
                                                  fontSize: 10,
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: _saveCurrentSearch,
                                          child: Container(
                                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Color(0xFFFF6B00).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Color(0xFFFF6B00), width: 1),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.bookmark_add_outlined, color: Color(0xFFFF6B00), size: 12),
                                                SizedBox(width: 4),
                                                Text(
                                                  AppLocalizations.of(context)!.save,
                                                  style: GoogleFonts.orbitron(
                                                    fontSize: 10,
                                                    color: Color(0xFFFF6B00),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ]),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ..._buildActiveFilterChips(),
                                      if ((selectedOwners ?? '').isNotEmpty)
                                        _buildFilterChip(_ownersLabelGlobal(context), _localizeDigitsGlobal(context, selectedOwners!), 'owners', Icons.person_outline, Colors.teal),
                                      if ((selectedVIN ?? '').isNotEmpty)
                                        _buildFilterChip(_vinLabelGlobal(context), selectedVIN!, 'vin', Icons.qr_code_2, Colors.teal),
                                      if ((selectedAccidentHistory ?? '').isNotEmpty)
                                        _buildFilterChip(_accidentHistoryLabelGlobal(context), (selectedAccidentHistory == 'yes') ? _yesTextGlobal(context) : _noTextGlobal(context), 'accident_history', Icons.report_gmailerrorred, Colors.teal),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 36,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFFFF6B00),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                minimumSize: Size(0, 32),
                              ),
                              icon: Icon(Icons.tune, size: 18),
                              label: Text(AppLocalizations.of(context)!.moreFilters, style: GoogleFonts.orbitron(fontSize: 15, fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                await showDialog(
                                  context: context,
                                  builder: (context) {
                                    return StatefulBuilder(
                                      builder: (context, setStateDialog) {
                                        return AlertDialog(
                                          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          title: Text(AppLocalizations.of(context)!.moreFilters, style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold)),
                                          content: SingleChildScrollView(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Price Filter
                                                Text(AppLocalizations.of(context)!.priceRange, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                                SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: isPriceDropdown
                                                          ? Column(
                                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: DropdownButtonFormField<String>(
                                                        value: selectedMinPrice ?? '',
                                                        decoration: InputDecoration(
                                                          hintText: AppLocalizations.of(context)!.any,
                                                          filled: true,
                                                          fillColor: Colors.black.withOpacity(0.2),
                                                          hintStyle: TextStyle(color: Colors.white70),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))),
                                                          ...[
                                                            for (int p = 500; p <= 300000; p += 500) p,
                                                            for (int p = 310000; p <= 2000000; p += 10000) p,
                                                          ]
                                                              .where((p) {
                                                                if (selectedMaxPrice == null || selectedMaxPrice!.isEmpty) return true;
                                                                final max = int.tryParse(selectedMaxPrice!);
                                                                return max == null ? true : p <= max;
                                                              })
                                                              .map((p) => DropdownMenuItem(
                                                                    value: p.toString(),
                                                                    child: Text(_formatCurrencyGlobal(context, p)),
                                                                  ))
                                                              .toList(),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(() {
                                                            selectedMinPrice = value?.isEmpty == true ? null : value;
                                                            final min = int.tryParse(selectedMinPrice ?? '');
                                                            final max = int.tryParse(selectedMaxPrice ?? '');
                                                            if (min != null && max != null && min > max) {
                                                              selectedMaxPrice = selectedMinPrice;
                                                            }
                                                          });
                                                          setStateDialog(() {});
                                                        },
                                                                      ),
                                                                    ),
                                                                    SizedBox(width: 8),
                                                    Expanded(
                                                      child: DropdownButtonFormField<String>(
                                                        value: selectedMaxPrice ?? '',
                                                        decoration: InputDecoration(
                                                          hintText: AppLocalizations.of(context)!.any,
                                                          filled: true,
                                                          fillColor: Colors.black.withOpacity(0.2),
                                                          hintStyle: TextStyle(color: Colors.white70),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))),
                                                          ...[
                                                            for (int p = 500; p <= 300000; p += 500) p,
                                                            for (int p = 310000; p <= 2000000; p += 10000) p,
                                                          ]
                                                              .where((p) {
                                                                if (selectedMinPrice == null || selectedMinPrice!.isEmpty) return true;
                                                                final min = int.tryParse(selectedMinPrice!);
                                                                return min == null ? true : p >= min;
                                                              })
                                                              .map((p) => DropdownMenuItem(
                                                                    value: p.toString(),
                                                                    child: Text(_formatCurrencyGlobal(context, p)),
                                                                  ))
                                                              .toList(),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(() {
                                                            selectedMaxPrice = value?.isEmpty == true ? null : value;
                                                            final min = int.tryParse(selectedMinPrice ?? '');
                                                            final max = int.tryParse(selectedMaxPrice ?? '');
                                                            if (min != null && max != null && max < min) {
                                                              selectedMinPrice = selectedMaxPrice;
                                                            }
                                                          });
                                                          setStateDialog(() {});
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                              ],
                                                            )
                                                          : Column(
                                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: TextEditingController(text: selectedMinPrice ?? ''),
                                                        decoration: InputDecoration(
                                                          hintText: AppLocalizations.of(context)!.any,
                                                          filled: true,
                                                          fillColor: Colors.black.withOpacity(0.2),
                                                          hintStyle: TextStyle(color: Colors.white70),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                        keyboardType: TextInputType.number,
                                                                        onChanged: (value) {
                                                                          setState(() {
                                                                            selectedMinPrice = value.isEmpty ? null : value;
                                                                            final min = int.tryParse(selectedMinPrice ?? '');
                                                                            final max = int.tryParse(selectedMaxPrice ?? '');
                                                                            if (min != null && max != null && min > max) {
                                                                              selectedMaxPrice = selectedMinPrice;
                                                                            }
                                                                          });
                                                                          setStateDialog(() {});
                                                                        },
                                                      ),
                                                    ),
                                                                    SizedBox(width: 8),
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: TextEditingController(text: selectedMaxPrice ?? ''),
                                                        decoration: InputDecoration(
                                                          hintText: AppLocalizations.of(context)!.any,
                                                          filled: true,
                                                          fillColor: Colors.black.withOpacity(0.2),
                                                          hintStyle: TextStyle(color: Colors.white70),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                        keyboardType: TextInputType.number,
                                                                        onChanged: (value) {
                                                                          setState(() {
                                                                            selectedMaxPrice = value.isEmpty ? null : value;
                                                                            final min = int.tryParse(selectedMinPrice ?? '');
                                                                            final max = int.tryParse(selectedMaxPrice ?? '');
                                                                            if (min != null && max != null && max < min) {
                                                                              selectedMinPrice = selectedMaxPrice;
                                                                            }
                                                                          });
                                                                          setStateDialog(() {});
                                                                        },
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                    ),
                                                    SizedBox(width: 8),
                                                    IconButton(
                                                      onPressed: () => setStateDialog(() => isPriceDropdown = !isPriceDropdown),
                                                      icon: Icon(isPriceDropdown ? Icons.edit : Icons.list, color: Color(0xFFFF6B00)),
                                                      style: IconButton.styleFrom(
                                                        backgroundColor: Colors.black.withOpacity(0.2),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(height: 16),
                                                // Year Filter
                                                Text(AppLocalizations.of(context)!.yearRange, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                                SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: isYearDropdown
                                                          ? Column(
                                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: DropdownButtonFormField<String>(
                                                        value: selectedMinYear ?? '',
                                                        decoration: InputDecoration(
                                                          hintText: AppLocalizations.of(context)!.any,
                                                          filled: true,
                                                          fillColor: Colors.black.withOpacity(0.2),
                                                          hintStyle: TextStyle(color: Colors.white70),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                        items: [
                                                                          DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))),
                                                                          ...List.generate(127, (i) => (1900 + i).toString()).reversed
                                                                            .where((y) {
                                                                              if (selectedMaxYear == null || selectedMaxYear!.isEmpty) return true;
                                                                              final max = int.tryParse(selectedMaxYear!);
                                                                              final val = int.tryParse(y);
                                                                              return max == null || val == null ? true : val <= max;
                                                                            })
                                                                            .map((y) => DropdownMenuItem(value: y, child: Text(_localizeDigitsGlobal(context, y), style: TextStyle(color: Colors.white))))
                                                                          .toList(),
                                                                        ],
                                                                        onChanged: (value) {
                                                                          setState(() {
                                                                            selectedMinYear = value?.isEmpty == true ? null : value;
                                                                            final min = int.tryParse(selectedMinYear ?? '');
                                                                            final max = int.tryParse(selectedMaxYear ?? '');
                                                                            if (min != null && max != null && min > max) {
                                                                              selectedMaxYear = selectedMinYear;
                                                                            }
                                                                          });
                                                                          setStateDialog(() {});
                                                                        },
                                                                      ),
                                                                    ),
                                                                    SizedBox(width: 8),
                                                    Expanded(
                                                      child: DropdownButtonFormField<String>(
                                                        value: selectedMaxYear ?? '',
                                                        decoration: InputDecoration(
                                                          hintText: AppLocalizations.of(context)!.any,
                                                          filled: true,
                                                          fillColor: Colors.black.withOpacity(0.2),
                                                          hintStyle: TextStyle(color: Colors.white70),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                        items: [
                                                                          DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))),
                                                                          ...List.generate(127, (i) => (1900 + i).toString()).reversed
                                                                            .where((y) {
                                                                              if (selectedMinYear == null || selectedMinYear!.isEmpty) return true;
                                                                              final min = int.tryParse(selectedMinYear!);
                                                                              final val = int.tryParse(y);
                                                                              return min == null || val == null ? true : val >= min;
                                                                            })
                                                                            .map((y) => DropdownMenuItem(value: y, child: Text(_localizeDigitsGlobal(context, y), style: TextStyle(color: Colors.white))))
                                                                          .toList(),
                                                                        ],
                                                                        onChanged: (value) {
                                                                          setState(() {
                                                                            selectedMaxYear = value?.isEmpty == true ? null : value;
                                                                            final min = int.tryParse(selectedMinYear ?? '');
                                                                            final max = int.tryParse(selectedMaxYear ?? '');
                                                                            if (min != null && max != null && max < min) {
                                                                              selectedMinYear = selectedMaxYear;
                                                                            }
                                                                          });
                                                                          setStateDialog(() {});
                                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                              ],
                                                            )
                                                          : Column(
                                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: TextEditingController(text: selectedMinYear ?? ''),
                                                        decoration: InputDecoration(
                                                          hintText: AppLocalizations.of(context)!.any,
                                                          filled: true,
                                                          fillColor: Colors.black.withOpacity(0.2),
                                                          hintStyle: TextStyle(color: Colors.white70),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                        keyboardType: TextInputType.number,
                                                                        onChanged: (value) {
                                                                          setState(() => selectedMinYear = value.isEmpty ? null : value);
                                                                          setStateDialog(() {});
                                                                        },
                                                      ),
                                                    ),
                                                                    SizedBox(width: 8),
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: TextEditingController(text: selectedMaxYear ?? ''),
                                                        decoration: InputDecoration(
                                                          hintText: AppLocalizations.of(context)!.any,
                                                          filled: true,
                                                          fillColor: Colors.black.withOpacity(0.2),
                                                          hintStyle: TextStyle(color: Colors.white70),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                        keyboardType: TextInputType.number,
                                                                        onChanged: (value) {
                                                                          setState(() => selectedMaxYear = value.isEmpty ? null : value);
                                                                          setStateDialog(() {});
                                                                        },
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                    ),
                                                    SizedBox(width: 8),
                                                    IconButton(
                                                      onPressed: () => setStateDialog(() => isYearDropdown = !isYearDropdown),
                                                      icon: Icon(isYearDropdown ? Icons.edit : Icons.list, color: Color(0xFFFF6B00)),
                                                      style: IconButton.styleFrom(
                                                        backgroundColor: Colors.black.withOpacity(0.2),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(height: 16),
                                                // Mileage Filter
                                                Text(AppLocalizations.of(context)!.mileageRangeLabel, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                                SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: isMileageDropdown
                                                          ? Column(
                                                              children: [
                                                                Row(
                                                                  children: [
                                                                    Expanded(
                                                                      child: DropdownButtonFormField<String>(
                                                                        value: (selectedMinMileage != null && selectedMinMileage!.isNotEmpty) ? selectedMinMileage : '',
                                                                        decoration: InputDecoration(
                                                                          hintText: AppLocalizations.of(context)!.minMileage,
                                                                          filled: true,
                                                                          fillColor: Colors.black.withOpacity(0.2),
                                                                          hintStyle: TextStyle(color: Colors.white70),
                                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                                        ),
                                                                        items: [
                                                                          DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))),
                                                                          ...[
                                                                            for (int m = 0; m <= 100000; m += 1000) m,
                                                                            for (int m = 105000; m <= 300000; m += 5000) m,
                                                                          ]
                                                                              .where((m) {
                                                                                if (selectedMaxMileage == null || selectedMaxMileage!.isEmpty) return true;
                                                                                final max = int.tryParse(selectedMaxMileage!);
                                                                                return max == null ? true : m <= max;
                                                                              })
                                                                              .map((m) => DropdownMenuItem(
                                                                                    value: m.toString(),
                                                                                    child: Text(_localizeDigitsGlobal(context, m.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (mm) => '${mm[1]},'))),
                                                                                  ))
                                                                              .toList(),
                                                                        ],
                                                                        onChanged: (value) {
                                                                          setState(() {
                                                                            selectedMinMileage = (value == null || value.isEmpty) ? null : value;
                                                                            final min = int.tryParse(selectedMinMileage ?? '');
                                                                            final max = int.tryParse(selectedMaxMileage ?? '');
                                                                            if (min != null && max != null && min > max) {
                                                                              selectedMaxMileage = selectedMinMileage;
                                                                            }
                                                                          });
                                                                          setStateDialog(() {});
                                                                        },
                                                                      ),
                                                                    ),
                                                                    SizedBox(width: 8),
                                                                    Expanded(
                                                                      child: DropdownButtonFormField<String>(
                                                                        value: (selectedMaxMileage != null && selectedMaxMileage!.isNotEmpty) ? selectedMaxMileage : '',
                                                                        decoration: InputDecoration(
                                                                          hintText: AppLocalizations.of(context)!.maxMileage,
                                                                          filled: true,
                                                                          fillColor: Colors.black.withOpacity(0.2),
                                                                          hintStyle: TextStyle(color: Colors.white70),
                                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                                        ),
                                                                        items: [
                                                                          DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))),
                                                                          ...[
                                                                            for (int m = 0; m <= 100000; m += 1000) m,
                                                                            for (int m = 105000; m <= 300000; m += 5000) m,
                                                                          ]
                                                                              .where((m) {
                                                                                if (selectedMinMileage == null || selectedMinMileage!.isNotEmpty == false) return true;
                                                                                final min = int.tryParse(selectedMinMileage!);
                                                                                return min == null ? true : m >= min;
                                                                              })
                                                                              .map((m) => DropdownMenuItem(
                                                                                    value: m.toString(),
                                                                                    child: Text(_localizeDigitsGlobal(context, m.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (mm) => '${mm[1]},'))),
                                                                                  ))
                                                                              .toList(),
                                                                        ],
                                                                        onChanged: (value) {
                                                                          setState(() {
                                                                            selectedMaxMileage = (value == null || value.isEmpty) ? null : value;
                                                                            final min = int.tryParse(selectedMinMileage ?? '');
                                                                            final max = int.tryParse(selectedMaxMileage ?? '');
                                                                            if (min != null && max != null && max < min) {
                                                                              selectedMinMileage = selectedMaxMileage;
                                                                            }
                                                                          });
                                                                          setStateDialog(() {});
                                                                        },
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            )
                                                          : Column(
                                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: TextEditingController(text: selectedMinMileage ?? ''),
                                                        decoration: InputDecoration(
                                                          hintText: AppLocalizations.of(context)!.any,
                                                          filled: true,
                                                          fillColor: Colors.black.withOpacity(0.2),
                                                          hintStyle: TextStyle(color: Colors.white70),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                        keyboardType: TextInputType.number,
                                                                        onChanged: (value) {
                                                                          setState(() => selectedMinMileage = value.isEmpty ? null : value);
                                                                          setStateDialog(() {});
                                                                        },
                                                      ),
                                                    ),
                                                                    SizedBox(width: 8),
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: TextEditingController(text: selectedMaxMileage ?? ''),
                                                        decoration: InputDecoration(
                                                          hintText: AppLocalizations.of(context)!.any,
                                                          filled: true,
                                                          fillColor: Colors.black.withOpacity(0.2),
                                                          hintStyle: TextStyle(color: Colors.white70),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                        keyboardType: TextInputType.number,
                                                                        onChanged: (value) {
                                                                          setState(() => selectedMaxMileage = value.isEmpty ? null : value);
                                                                          setStateDialog(() {});
                                                                        },
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                    ),
                                                    SizedBox(width: 8),
                                                    IconButton(
                                                      onPressed: () => setStateDialog(() => isMileageDropdown = !isMileageDropdown),
                                                      icon: Icon(isMileageDropdown ? Icons.edit : Icons.list, color: Color(0xFFFF6B00)),
                                                      style: IconButton.styleFrom(
                                                        backgroundColor: Colors.black.withOpacity(0.2),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(height: 10),
                                                DropdownButtonFormField<String>(
                                                  value: selectedTitleStatus ?? '',
                                                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.titleStatus, filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  items: [
                                                    DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))),
                                                    DropdownMenuItem(value: 'clean', child: Text(AppLocalizations.of(context)!.value_title_clean)),
                                                    DropdownMenuItem(value: 'damaged', child: Text(AppLocalizations.of(context)!.value_title_damaged)),
                                                  ],
                                                  onChanged: (value) {
                                                    setState(() {
                                                      selectedTitleStatus = value == '' ? null : value;
                                                      if (selectedTitleStatus != 'damaged') {
                                                        selectedDamagedParts = null;
                                                      }
                                                    });
                                                    setStateDialog(() {});
                                                  },
                                                ),
                                                SizedBox(height: 10),
                                                if (selectedTitleStatus == 'damaged')
                                                  DropdownButtonFormField<String>(
                                                    value: selectedDamagedParts ?? '',
                                                    decoration: InputDecoration(labelText: AppLocalizations.of(context)!.damagedParts, filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                    items: [
                                                      DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))),
                                                      ...List.generate(15, (i) => (i + 1).toString()).map((p) => DropdownMenuItem(
                                                        value: p,
                                                        child: Text('${_localizeDigitsGlobal(context, p)} ${AppLocalizations.of(context)!.damagedParts}'),
                                                      ))
                                                    ],
                                                    onChanged: (value) {
                                                      setState(() => selectedDamagedParts = value == '' ? null : value);
                                                      setStateDialog(() {});
                                                    },
                                                  ),
                                                SizedBox(height: 10),
                                                DropdownButtonFormField<String>(
                                                  value: selectedCondition ?? 'Any',
                                                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.conditionLabel, filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  items: conditions.map((c) => DropdownMenuItem(
                                                    value: c, 
                                                    child: Text(
                                                      _translateValueGlobal(context, c) ?? c,
                                                      style: TextStyle(
                                                        color: c == 'Any' ? Colors.grey : null,
                                                      ),
                                                    ),
                                                  )).toList(),
                                                  onChanged: (value) => setState(() => selectedCondition = value == 'Any' ? 'Any' : value),
                                                ),
                                                SizedBox(height: 10),
                                                DropdownButtonFormField<String>(
                                                  value: _getValidTransmissionValue(),
                                                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.transmissionLabel, filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  items: [DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))), ...getAvailableTransmissions().where((t) => t != 'Any').map((t) => DropdownMenuItem(value: t, child: Text(_translateValueGlobal(context, t) ?? t))).toList()],
                                                  onChanged: (value) => setState(() => selectedTransmission = value == '' ? 'Any' : value),
                                                ),
                                                SizedBox(height: 10),
                                                DropdownButtonFormField<String>(
                                                  value: _getValidFuelTypeValue(),
                                                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.fuelTypeLabel, filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  items: [DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))), ...getAvailableFuelTypes().where((f) => f != 'Any').map((f) => DropdownMenuItem(value: f, child: Text(_translateValueGlobal(context, f) ?? f))).toList()],
                                                  onChanged: (value) => setState(() => selectedFuelType = value == '' ? 'Any' : value),
                                                ),
                                                SizedBox(height: 10),
                                                TextFormField(
                                                  readOnly: true,
                                                  controller: TextEditingController(text: (selectedBodyType ?? AppLocalizations.of(context)!.any)),
                                                  decoration: InputDecoration(
                                                    labelText: AppLocalizations.of(context)!.bodyTypeLabel,
                                                    filled: true,
                                                    fillColor: Colors.black.withOpacity(0.2),
                                                    labelStyle: TextStyle(color: Colors.white),
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                    suffixIcon: Container(
                                                      margin: EdgeInsets.all(8),
                                                      width: 44,
                                                      height: 44,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: Colors.white,
                                                        border: Border.all(color: Color(0xFFFF6B00), width: 2),
                                                      ),
                                                      child: Padding(
                                                        padding: EdgeInsets.all(6),
                                                        child: ClipOval(
                                                          child: FittedBox(
                                                            fit: BoxFit.contain,
                                                            child: (selectedBodyType != null && selectedBodyType!.isNotEmpty)
                                                                ? _buildBodyTypeImage(_getBodyTypeAsset(selectedBodyType!))
                                                                : Icon(
                                                                    _getBodyTypeIcon('car'),
                                                                    color: Colors.black,
                                                                  ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  onTap: () async {
                                                    final bodyType = await showDialog<String>(
                                                      context: context,
                                                      builder: (context) {
                                                        return Dialog(
                                                          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                          child: Container(
                                                            width: 400,
                                                            padding: EdgeInsets.all(20),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                Row(
                                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                  children: [
                                                                    Text(AppLocalizations.of(context)!.selectBodyType, style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                                                                    IconButton(
                                                                      icon: Icon(Icons.close, color: Colors.white),
                                                                      onPressed: () => Navigator.pop(context),
                                                                    ),
                                                                  ],
                                                                ),
                                                                SizedBox(height: 10),
                                                                SizedBox(
                                                                  height: 300,
                                                                  child: GridView.builder(
                                                                    shrinkWrap: true,
                                                                    physics: BouncingScrollPhysics(),
                                                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                                      crossAxisCount: 3,
                                                                      childAspectRatio: 0.82,
                                                                      crossAxisSpacing: 12,
                                                                      mainAxisSpacing: 12,
                                                                    ),
                                                                    itemCount: getAvailableBodyTypes().length,
                                                                    itemBuilder: (context, index) {
                                                                      final bodyTypeName = getAvailableBodyTypes()[index];
                                                                      final asset = _getBodyTypeAsset(bodyTypeName);
                                                                      final bool isSelected = (selectedBodyType ?? AppLocalizations.of(context)!.any) == bodyTypeName;
                                                                      return InkWell(
                                                                        borderRadius: BorderRadius.circular(12),
                                                                        onTap: () => Navigator.pop(context, bodyTypeName),
                                                                        child: Container(
                                                                          decoration: BoxDecoration(
                                                                            color: Colors.transparent,
                                                                            borderRadius: BorderRadius.circular(12),
                                                                            border: Border.all(color: isSelected ? const Color(0xFFFF6B00) : Colors.white24, width: isSelected ? 2 : 1),
                                                                            boxShadow: isSelected
                                                                                ? [
                                                                                    BoxShadow(color: const Color(0xFFFF6B00).withOpacity(0.35), blurRadius: 14, spreadRadius: 1, offset: const Offset(0, 4)),
                                                                                  ]
                                                                                : [
                                                                                    const BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 0, offset: Offset(0, 3)),
                                                                                  ],
                                                                          ),
                                                                          padding: EdgeInsets.all(8),
                                                                          child: Column(
                                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                                            children: [
                                                                              Container(
                                                                                width: 56,
                                                                                height: 56,
                                                                                decoration: BoxDecoration(
                                                                                  shape: BoxShape.circle,
                                                                                  color: Colors.white,
                                                                                  border: Border.all(color: isSelected ? const Color(0xFFFF6B00) : Colors.white24, width: isSelected ? 2 : 1),
                                                                                ),
                                                                                child: Padding(
                                                                                  padding: const EdgeInsets.all(8),
                                                                                  child: FittedBox(
                                                                                    fit: BoxFit.contain,
                                                                                    child: _buildBodyTypeImage(asset),
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              const SizedBox(height: 8),
                                                                              Text(
                                                                                _translateValueGlobal(context, bodyTypeName) ?? bodyTypeName,
                                                                                style: GoogleFonts.orbitron(
                                                                                  fontSize: 12,
                                                                                  color: isSelected ? Colors.white : Colors.white70,
                                                                                  fontWeight: FontWeight.bold,
                                                                                ),
                                                                                textAlign: TextAlign.center,
                                                                                overflow: TextOverflow.ellipsis,
                                                                                maxLines: 1,
                                                                              ),
                                                                            ],
                                            ),
                                                                        ),
                                                                      );
                                                                    },
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    );
                                                    if (bodyType != null) {
                                                      setState(() {
                                                        selectedBodyType = bodyType == 'Any' ? null : bodyType;
                                                      });
                                                      setStateDialog(() {});
                                                    }
                                                  },
                                                ),
                                                SizedBox(height: 10),
                                                TextFormField(
                                                  readOnly: true,
                                                  controller: TextEditingController(text: (_translateValueGlobal(context, selectedColor) ?? selectedColor ?? AppLocalizations.of(context)!.any)),
                                                  decoration: InputDecoration(
                                                    labelText: AppLocalizations.of(context)!.colorLabel,
                                                    filled: true,
                                                    fillColor: Colors.black.withOpacity(0.2),
                                                    labelStyle: TextStyle(color: Colors.white),
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                                    suffixIcon: Container(
                                                      width: 24,
                                                      height: 24,
                                                      margin: EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: selectedColor != null ? _getColorValue(selectedColor!) : Colors.grey,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: Colors.white24, width: 2),
                                                      ),
                                                    ),
                                                  ),
                                                  onTap: () async {
                                                    final color = await showDialog<String>(
                                                      context: context,
                                                      builder: (context) {
                                                        return Dialog(
                                                          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                          child: Container(
                                                            width: 400,
                                                            padding: EdgeInsets.all(20),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                Row(
                                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                  children: [
                                                                    Text(AppLocalizations.of(context)!.selectColor, style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                                                                    IconButton(
                                                                      icon: Icon(Icons.close, color: Colors.white),
                                                                      onPressed: () => Navigator.pop(context),
                                                                    ),
                                                                  ],
                                                                ),
                                                                SizedBox(height: 10),
                                                                SizedBox(
                                                                  height: 300,
                                                                  child: GridView.builder(
                                                                    shrinkWrap: true,
                                                                    physics: BouncingScrollPhysics(),
                                                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                                      crossAxisCount: 3,
                                                                      childAspectRatio: 1.2,
                                                                      crossAxisSpacing: 10,
                                                                      mainAxisSpacing: 10,
                                                                    ),
                                                                    itemCount: getAvailableColors().length,
                                                                    itemBuilder: (context, index) {
                                                                      final colorName = getAvailableColors()[index];
                                                                      Color colorValue = Colors.grey;
                                                                      switch (colorName.toLowerCase()) {
                                                                        case 'black':
                                                                          colorValue = Colors.black;
                                                                          break;
                                                                        case 'white':
                                                                          colorValue = Colors.white;
                                                                          break;
                                                                        case 'silver':
                                                                          colorValue = Colors.grey[300]!;
                                                                          break;
                                                                        case 'gray':
                                                                          colorValue = Colors.grey[600]!;
                                                                          break;
                                                                        case 'red':
                                                                          colorValue = Colors.red;
                                                                          break;
                                                                        case 'blue':
                                                                          colorValue = Colors.blue;
                                                                          break;
                                                                        case 'green':
                                                                          colorValue = Colors.green;
                                                                          break;
                                                                        case 'yellow':
                                                                          colorValue = Colors.yellow;
                                                                          break;
                                                                        case 'orange':
                                                                          colorValue = Colors.orange;
                                                                          break;
                                                                        case 'purple':
                                                                          colorValue = Colors.purple;
                                                                          break;
                                                                        case 'brown':
                                                                          colorValue = Colors.brown;
                                                                          break;
                                                                        case 'beige':
                                                                          colorValue = Color(0xFFF5F5DC);
                                                                          break;
                                                                        case 'gold':
                                                                          colorValue = Color(0xFFFFD700);
                                                                          break;
                                                                        default:
                                                                          colorValue = Colors.grey;
                                                                      }
                                                                      return InkWell(
                                                                        borderRadius: BorderRadius.circular(12),
                                                                        onTap: () => Navigator.pop(context, colorName),
                                                                        child: Container(
                                                                          decoration: BoxDecoration(
                                                                            color: Colors.black.withOpacity(0.15),
                                                                            borderRadius: BorderRadius.circular(12),
                                                                            border: Border.all(color: Colors.white24),
                                                                          ),
                                                                          padding: EdgeInsets.all(8),
                                                                          child: Column(
                                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                                            children: [
                                                                              Container(
                                                                                width: 40,
                                                                                height: 40,
                                                                                decoration: BoxDecoration(
                                                                                  color: colorValue,
                                                                                  borderRadius: BorderRadius.circular(8),
                                                                                  border: Border.all(color: Colors.white24, width: 2),
                                                                                ),
                                                                              ),
                                                                              SizedBox(height: 8),
                                                                              Text(
                                                                                _translateValueGlobal(context, colorName) ?? colorName,
                                                                                style: GoogleFonts.orbitron(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                                                                textAlign: TextAlign.center,
                                                                                overflow: TextOverflow.ellipsis,
                                                                                maxLines: 1,
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      );
                                                                    },
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    );
                                                    if (color != null) {
                                                      setState(() {
                                                        selectedColor = color == 'Any' ? null : color;
                                                      });
                                                      setStateDialog(() {});
                                                    }
                                                  },
                                                ),
                                                SizedBox(height: 10),
                                                // Drive Type Dropdown
                                                DropdownButtonFormField<String>(
                                                  value: _getValidDriveTypeValue(),
                                                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.driveType, filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  items: [DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))), ...getAvailableDriveTypes().where((d) => d != 'Any').map((d) => DropdownMenuItem(value: d, child: Text(_translateValueGlobal(context, d) ?? d))).toList()],
                                                  onChanged: (value) { setState(() => selectedDriveType = value == '' ? null : value); _persistFilters(); },
                                                ),
                                                SizedBox(height: 10),
                                                // Cylinder Count Dropdown
                                                DropdownButtonFormField<String>(
                                                  value: selectedCylinderCount ?? '',
                                                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.cylinderCount, filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  items: [DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))), ...getAvailableCylinderCounts().where((c) => c != 'Any').map((c) => DropdownMenuItem(value: c, child: Text(_localizeDigitsGlobal(context, c)))).toList()],
                                                  onChanged: (value) { setState(() => selectedCylinderCount = value == '' ? null : value); _persistFilters(); },
                                                ),
                                                SizedBox(height: 10),
                                                // Seating Dropdown
                                                DropdownButtonFormField<String>(
                                                  value: selectedSeating ?? '',
                                                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.seating, filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  items: [DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))), ...getAvailableSeatings().where((s) => s != 'Any').map((s) => DropdownMenuItem(value: s, child: Text(_localizeDigitsGlobal(context, s)))).toList()],
                                                  onChanged: (value) { setState(() => selectedSeating = value == '' ? null : value); _persistFilters(); },
                                                ),
                                                SizedBox(height: 10),
                                                // Engine Size Dropdown
                                                DropdownButtonFormField<String>(
                                                  value: selectedEngineSize ?? '',
                                                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.engineSizeL, filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  items: [DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))), ...getAvailableEngineSizes().where((e) => e != 'Any').map((e) => DropdownMenuItem(value: e, child: Text('${_localizeDigitsGlobal(context, e)}${AppLocalizations.of(context)!.unit_liter_suffix}'))).toList()],
                                                  onChanged: (value) { setState(() => selectedEngineSize = value == '' ? null : value); _persistFilters(); },
                                                ),
                                                SizedBox(height: 10),
                                                DropdownButtonFormField<String>(
                                                  value: selectedCity ?? '',
                                                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.cityLabel, filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  items: [DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))), ...cities.map((c) => DropdownMenuItem(value: c, child: Text(_translateValueGlobal(context, c) ?? c))).toList()],
                                                  onChanged: (value) { setState(() => selectedCity = value == '' ? null : value); _persistFilters(); },
                                                ),
                                                SizedBox(height: 10),
                                                // Owners
                                                TextFormField(
                                                  controller: TextEditingController(text: selectedOwners ?? ''),
                                                  decoration: InputDecoration(labelText: _ownersLabelGlobal(context), filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  keyboardType: TextInputType.number,
                                                  onChanged: (v) { setState(() => selectedOwners = v.trim().isEmpty ? null : v.trim()); _persistFilters(); },
                                                ),
                                                SizedBox(height: 10),
                                                // VIN
                                                TextFormField(
                                                  controller: TextEditingController(text: selectedVIN ?? ''),
                                                  decoration: InputDecoration(labelText: _vinLabelGlobal(context), filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  keyboardType: TextInputType.text,
                                                  inputFormatters: [
                                                    services.FilteringTextInputFormatter.allow(RegExp(r'[A-HJ-NPR-Z0-9]')),
                                                    services.LengthLimitingTextInputFormatter(17),
                                                  ],
                                                  onChanged: (v) { setState(() => selectedVIN = v.trim().isEmpty ? null : v.trim()); _persistFilters(); },
                                                ),
                                                Align(
                                                  alignment: Alignment.centerRight,
                                                  child: TextButton.icon(
                                                    onPressed: _decodeVin,
                                                    icon: Icon(Icons.qr_code, color: Color(0xFFFF6B00)),
                                                    label: Text(_vinLabelGlobal(context), style: TextStyle(color: Color(0xFFFF6B00))),
                                                  ),
                                                ),
                                                Align(
                                                  alignment: Alignment.centerRight,
                                                  child: TextButton.icon(
                                                    onPressed: () async {
                                                      final vin = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => VinScanPage()));
                                                      if (vin != null && vin.trim().isNotEmpty) {
                                                        setState(() => selectedVIN = vin.trim());
                                                        await _persistFilters();
                                                        await _decodeVin();
                                                      }
                                                    },
                                                    icon: Icon(Icons.camera_alt_outlined, color: Color(0xFFFF6B00)),
                                                    label: Text(_vinLabelGlobal(context)),
                                                  ),
                                                ),
                                                SizedBox(height: 10),
                                                DropdownButtonFormField<String>(
                                                  value: selectedAccidentHistory ?? '',
                                                  decoration: InputDecoration(labelText: _accidentHistoryLabelGlobal(context), filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                  items: [
                                                    DropdownMenuItem(value: '', child: Text(AppLocalizations.of(context)!.any, style: TextStyle(color: Colors.grey))),
                                                    DropdownMenuItem(value: 'yes', child: Text(_yesTextGlobal(context))),
                                                    DropdownMenuItem(value: 'no', child: Text(_noTextGlobal(context))),
                                                  ],
                                                  onChanged: (v) { setState(() => selectedAccidentHistory = (v == null || v.isEmpty) ? null : v); _persistFilters(); },
                                                ),
                                              ],
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: Text(_cancelTextGlobal(context), style: TextStyle(color: Colors.white70)),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFF6B00)),
                                              onPressed: () {
                                                onFilterChanged();
                                                Navigator.pop(context);
                                              },
                                              child: Text(AppLocalizations.of(context)!.applyFilters),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: isLoading
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
                              ),
                              SizedBox(height: 16),
                              Text(
                                selectedSortBy != null 
                                  ? 'Sorting listings...' 
                                  : 'Loading listings...',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : (loadErrorMessage != null && cars.isEmpty)
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_couldNotLoadListingsTextGlobal(context), style: TextStyle(color: Colors.white70)),
                                  SizedBox(height: 8),
                                  Wrap(spacing: 8, children: [
                                    OutlinedButton(
                                      onPressed: () {
                                        _fetchRetryCount = 0; // Reset retry count
                                        fetchCars(bypassCache: true);
                                      }, 
                                      child: Text('Retry')
                                    ),
                                    OutlinedButton(onPressed: () => onFilterChanged(), child: Text(AppLocalizations.of(context)!.clearFilters)),
                                  ]),
                                ],
                              ),
                            )
                          : cars.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(AppLocalizations.of(context)!.noCarsFound, style: TextStyle(color: Colors.white70)),
                                      SizedBox(height: 8),
                                      OutlinedButton(onPressed: () => onFilterChanged(), child: Text(AppLocalizations.of(context)!.applyFilters)),
                                    ],
                                  ),
                                )
                              : Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      PopupMenuButton<String>(
                                        tooltip: AppLocalizations.of(context)!.sortBy,
                                        icon: Icon(Icons.sort, size: 20),
                                        onSelected: (value) {
                                          setState(() => selectedSortBy = value == '' ? null : value);
                                          _persistFilters();
                                          onSortChanged();
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(value: '', child: Text(AppLocalizations.of(context)!.defaultSort)),
                                          ...getLocalizedSortOptions(context).skip(1).map((s) => PopupMenuItem(value: s, child: Text(s))).toList(),
                                        ],
                                      ),
                                      ToggleButtons(
                                        isSelected: [listingColumns == 1, listingColumns == 2],
                                        onPressed: (index) {
                                          setState(() {
                                            listingColumns = index == 0 ? 1 : 2;
                                          });
                                        },
                                        children: const [
                                          Icon(Icons.view_agenda),
                                          Icon(Icons.grid_view),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      // Show a subtle indicator when there's cached data with an error
                                      if (loadErrorMessage != null && cars.isNotEmpty)
                                        Container(
                                          width: double.infinity,
                                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.offline_bolt, color: Colors.orange, size: 16),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Showing cached results',
                                                  style: TextStyle(color: Colors.orange, fontSize: 12),
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: fetchCars,
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  minimumSize: Size(0, 0),
                                                ),
                                                child: Text('Refresh', style: TextStyle(color: Colors.orange, fontSize: 12)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Expanded(
                                        child: GridView.builder(
                                          padding: EdgeInsets.all(8),
                                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: listingColumns,
                                            childAspectRatio: listingColumns == 2 ? 0.65 : 1.32, // Adjusted for taller cards (205px height)
                                            crossAxisSpacing: 8,
                                            mainAxisSpacing: 8,
                                          ),
                                          itemCount: cars.length,
                                          itemBuilder: (context, index) {
                                            final car = cars[index];
                                            return buildGlobalCarCard(context, car);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
      floatingActionButton: null,
    );
  }

  Widget _buildCardImageCarousel(BuildContext context, Map car) {
    final List<String> urls = () {
      final List<String> u = [];
      final String primary = (car['image_url'] ?? '').toString();
      final List<dynamic> imgs = (car['images'] is List) ? (car['images'] as List) : const [];
      if (primary.isNotEmpty) {
        u.add(getApiBase() + '/static/uploads/' + primary);
      }
      for (final dynamic it in imgs) {
        final s = it.toString();
        if (s.isNotEmpty) {
          final full = getApiBase() + '/static/uploads/' + s;
          if (!u.contains(full)) u.add(full);
        }
      }
      return u;
    }();

    if (urls.isEmpty) {
      return Container(
        color: Colors.grey[900],
        width: double.infinity,
        child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
      );
    }

    final PageController controller = PageController();
    int currentIndex = 0;

    return StatefulBuilder(
      builder: (context, setState) {
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/car_detail',
                  arguments: {'carId': car['id']},
                );
              },
              child: PageView.builder(
                controller: controller,
                onPageChanged: (i) => setState(() => currentIndex = i),
                itemCount: urls.length,
                itemBuilder: (context, i) {
                  final url = urls[i];
                  return CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (_, __) => Container(color: Colors.white10),
                    errorWidget: (_, __, ___) => Container(color: Colors.grey[900], child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400])),
                  );
                },
              ),
            ),
            if (urls.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(urls.length, (i) {
                      final active = i == currentIndex;
                      return AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        margin: EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 8 : 6,
                        height: active ? 8 : 6,
                        decoration: BoxDecoration(
                          color: active ? Colors.white : Colors.white70,
                          shape: BoxShape.circle,
                        ),
                      );
                    }),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Helper methods for unified filter functionality
  String? _getPriceRangeValue() {
    return selectedMinPrice ?? '';
  }

  String _formatPrice(String raw) {
    try {
      final num? value = num.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (value == null) return _localizeDigitsGlobal(context, raw);
      final locale = Localizations.localeOf(context).toLanguageTag();
      final formatter = _decimalFormatterGlobal(context);
      return _localizeDigitsGlobal(context, formatter.format(value));
    } catch (_) {
      return _localizeDigitsGlobal(context, raw);
    }
  }

  void _updatePriceFilter(String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        selectedMinPrice = null;
        selectedMaxPrice = null;
      } else {
        selectedMinPrice = value;
        selectedMaxPrice = null;
      }
    });
  }

  String? _getYearRangeValue() {
    return selectedMinYear ?? '';
  }

  void _updateYearFilter(String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        selectedMinYear = null;
        selectedMaxYear = null;
      } else {
        selectedMinYear = value;
        selectedMaxYear = null;
      }
    });
  }

  String? _getMileageRangeValue() {
    return selectedMinMileage ?? '';
  }

  void _updateMileageFilter(String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        selectedMinMileage = null;
        selectedMaxMileage = null;
      } else {
        selectedMinMileage = value;
        selectedMaxMileage = null;
      }
    });
  }

  // Helper function to get body type icon
  IconData _getBodyTypeIcon(String bodyType) {
    switch (bodyType.toLowerCase()) {
      case 'sedan':
        return Icons.directions_car;
      case 'suv':
        return Icons.directions_car_filled;
      case 'hatchback':
        return Icons.directions_car;
      case 'coupe':
        return Icons.directions_car;
      case 'wagon':
        return Icons.directions_car;
      case 'pickup':
        return Icons.local_shipping;
      case 'van':
        return Icons.airport_shuttle;
      case 'minivan':
        return Icons.airport_shuttle;
      case 'motorcycle':
        return Icons.motorcycle;
      case 'utv':
        return Icons.directions_car;
      case 'atv':
        return Icons.directions_car;
      default:
        return Icons.directions_car;
    }
  }

  // Helper function to get color value
  Color _getColorValue(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'silver':
        return Colors.grey[300]!;
      case 'gray':
        return Colors.grey[600]!;
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'brown':
        return Colors.brown;
      case 'beige':
        return Color(0xFFF5F5DC);
      case 'gold':
        return Color(0xFFFFD700);
      default:
        return Colors.grey;
    }
  }

  // Helper function to get an emoji for a given body type
  String _getBodyTypeEmoji(String bodyType) {
    switch (bodyType.toLowerCase()) {
      case 'sedan':
        return 'ðŸš—';
      case 'suv':
        return 'ðŸš™';
      case 'hatchback':
        return 'ðŸš—';
      case 'coupe':
        return 'ðŸŽï¸';
      case 'wagon':
        return 'ðŸš™';
      case 'pickup':
        return 'ðŸ›»';
      case 'van':
        return 'ðŸš';
      case 'minivan':
        return 'ðŸš';
      case 'motorcycle':
        return 'ðŸï¸';
      case 'utv':
        return 'ðŸšœ';
      case 'atv':
        return 'ðŸŽï¸';
      default:
        return 'ðŸš˜';
    }
  }
  
  @override
  void dispose() {
    _sortDebounceTimer?.cancel();
    super.dispose();
  }
}

class SavedSearchesPage extends StatefulWidget {
  final dynamic parentState;
  
  const SavedSearchesPage({Key? key, this.parentState}) : super(key: key);
  
  @override
  State<SavedSearchesPage> createState() => _SavedSearchesPageState();
}

class _SavedSearchesPageState extends State<SavedSearchesPage> {
  static const String _savedSearchesKey = 'saved_searches_v1';
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_savedSearchesKey);
    final list = (raw == null || raw.isEmpty) ? [] : (json.decode(raw) as List).cast<dynamic>();
    setState(() {
      _items = list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loading = false;
    });
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_savedSearchesKey, json.encode(_items));
  }

  void _rename(int index) async {
    final controller = TextEditingController(text: _items[index]['name']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context)!.ok)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(AppLocalizations.of(context)!.save)),
        ],
      ),
    );
    if (ok == true) {
      setState(() { _items[index]['name'] = controller.text.trim().isEmpty ? _items[index]['name'] : controller.text.trim(); });
      await _save();
    }
  }

  void _delete(int index) async {
    setState(() { _items.removeAt(index); });
    await _save();
  }

  void _toggleNotify(int index, bool value) async {
    setState(() { _items[index]['notify'] = value; });
    await _save();
    // Optionally sync to backend if available
    unawaited(_syncSavedSearchNotify(index));
  }

  Future<void> _syncSavedSearchNotify(int index) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final token = sp.getString('push_token');
      if (token == null || token.isEmpty) return;
      final body = {
        'push_token': token,
        'search_id': _items[index]['id'],
        'notify': _items[index]['notify'] == true,
        'filters': _items[index]['filters'] ?? {},
      };
      final url = Uri.parse(getApiBase() + '/api/saved_search/notify');
      await http.post(url, headers: {'Content-Type': 'application/json'}, body: json.encode(body));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Searches'),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No saved searches yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                      SizedBox(height: 8),
                      Text('Your searches will be automatically saved here', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final filters = item['filters'] as Map<String, dynamic>? ?? {};
                    final isAutoSaved = item['auto_saved'] == true;
                    
                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        onTap: () => _showFilterDetails(item['name']?.toString() ?? 'Unnamed Search', filters),
                        leading: Icon(
                          Icons.bookmark, 
                          color: Color(0xFFFF6B00)
                        ),
                        title: Text(
                          item['name']?.toString() ?? 'Unnamed Search',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 4),
                            _buildFilterChips(filters),
                            SizedBox(height: 4),
                            Text(
                              _formatDate(item['created_at']?.toString() ?? ''),
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.search, color: Colors.green),
                              onPressed: () => _applySearch(filters),
                              tooltip: 'Apply Search',
                            ),
                            IconButton(
                              icon: Icon(Icons.edit), 
                              onPressed: () => _rename(index),
                              tooltip: 'Rename',
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: Colors.red), 
                              onPressed: () => _delete(index),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildFilterChips(Map<String, dynamic> filters) {
    final chips = <Widget>[];
    
    // Add filter chips for all criteria
    if (filters['brand'] != null) {
      chips.add(_buildFilterChip('Brand', filters['brand'].toString()));
    }
    if (filters['model'] != null) {
      chips.add(_buildFilterChip('Model', filters['model'].toString()));
    }
    if (filters['trim'] != null) {
      chips.add(_buildFilterChip('Trim', filters['trim'].toString()));
    }
    if (filters['city'] != null) {
      chips.add(_buildFilterChip('City', filters['city'].toString()));
    }
    if (filters['min_price'] != null || filters['max_price'] != null) {
      final priceRange = '${filters['min_price'] ?? '0'} - ${filters['max_price'] ?? 'âˆž'}';
      chips.add(_buildFilterChip('Price', priceRange));
    }
    if (filters['min_year'] != null || filters['max_year'] != null) {
      final yearRange = '${filters['min_year'] ?? '0'} - ${filters['max_year'] ?? 'âˆž'}';
      chips.add(_buildFilterChip('Year', yearRange));
    }
    if (filters['min_mileage'] != null || filters['max_mileage'] != null) {
      final mileageRange = '${filters['min_mileage'] ?? '0'} - ${filters['max_mileage'] ?? 'âˆž'} km';
      chips.add(_buildFilterChip('Mileage', mileageRange));
    }
    if (filters['transmission'] != null) {
      chips.add(_buildFilterChip('Transmission', _capitalizeFirst(filters['transmission'].toString())));
    }
    if (filters['condition'] != null) {
      chips.add(_buildFilterChip('Condition', _capitalizeFirst(filters['condition'].toString())));
    }
    if (filters['body_type'] != null) {
      chips.add(_buildFilterChip('Body Type', _capitalizeFirst(filters['body_type'].toString())));
    }
    if (filters['fuel_type'] != null) {
      chips.add(_buildFilterChip('Fuel Type', _capitalizeFirst(filters['fuel_type'].toString())));
    }
    if (filters['color'] != null) {
      chips.add(_buildFilterChip('Color', _capitalizeFirst(filters['color'].toString())));
    }
    if (filters['drive_type'] != null) {
      chips.add(_buildFilterChip('Drive Type', filters['drive_type'].toString().toUpperCase()));
    }
    if (filters['cylinder_count'] != null) {
      chips.add(_buildFilterChip('Cylinders', filters['cylinder_count'].toString()));
    }
    if (filters['seating'] != null) {
      chips.add(_buildFilterChip('Seating', '${filters['seating'].toString()} seats'));
    }
    if (filters['engine_size'] != null) {
      chips.add(_buildFilterChip('Engine', '${filters['engine_size'].toString()}L'));
    }
    if (filters['title_status'] != null) {
      chips.add(_buildFilterChip('Title', _capitalizeFirst(filters['title_status'].toString())));
    }
    if (filters['damaged_parts'] != null) {
      chips.add(_buildFilterChip('Damaged Parts', filters['damaged_parts'].toString()));
    }
    if (filters['sort_by'] != null) {
      chips.add(_buildFilterChip('Sort By', _capitalizeFirst(filters['sort_by'].toString())));
    }
    if (filters['owners'] != null) {
      chips.add(_buildFilterChip('Owners', filters['owners'].toString()));
    }
    if (filters['vin'] != null) {
      chips.add(_buildFilterChip('VIN', filters['vin'].toString()));
    }
    if (filters['accident_history'] != null) {
      chips.add(_buildFilterChip('Accident History', _capitalizeFirst(filters['accident_history'].toString())));
    }
    
    if (chips.isEmpty) {
      return Text('No filters applied', style: TextStyle(color: Colors.grey[600], fontSize: 12));
    }
    
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: chips,
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, color: Color(0xFFFF6B00)),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays == 0) {
        return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateString;
    }
  }

  void _applySearch(Map<String, dynamic> filters) async {
    // Navigate back to home page
    Navigator.pop(context);
    
    // Apply the saved filters to the home page state
    if (widget.parentState != null) {
      widget.parentState!.setState(() {
        // Clear all current filters first
        widget.parentState!._resetAllFiltersInMemory();
        
        // Apply saved filters
        widget.parentState!.selectedBrand = filters['brand'];
        widget.parentState!.selectedModel = filters['model'];
        widget.parentState!.selectedTrim = filters['trim'];
        widget.parentState!.selectedMinPrice = filters['min_price'];
        widget.parentState!.selectedMaxPrice = filters['max_price'];
        widget.parentState!.selectedMinYear = filters['min_year'];
        widget.parentState!.selectedMaxYear = filters['max_year'];
        widget.parentState!.selectedMinMileage = filters['min_mileage'];
        widget.parentState!.selectedMaxMileage = filters['max_mileage'];
        widget.parentState!.selectedCondition = filters['condition'];
        widget.parentState!.selectedTransmission = filters['transmission'];
        widget.parentState!.selectedFuelType = filters['fuel_type'];
        widget.parentState!.selectedBodyType = filters['body_type'];
        widget.parentState!.selectedColor = filters['color'];
        widget.parentState!.selectedDriveType = filters['drive_type'];
        widget.parentState!.selectedCylinderCount = filters['cylinder_count'];
        widget.parentState!.selectedSeating = filters['seating'];
        widget.parentState!.selectedEngineSize = filters['engine_size'];
        widget.parentState!.selectedCity = filters['city'];
        widget.parentState!.selectedTitleStatus = filters['title_status'];
        widget.parentState!.selectedDamagedParts = filters['damaged_parts'];
        widget.parentState!.selectedSortBy = filters['sort_by'];
        widget.parentState!.selectedOwners = filters['owners'];
        widget.parentState!.selectedVIN = filters['vin'];
        widget.parentState!.selectedAccidentHistory = filters['accident_history'];
      });
      
      // Persist the applied filters
      await widget.parentState!._persistFilters();
      
      // Trigger filter change to fetch cars with applied filters
      widget.parentState!.onFilterChanged();
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Search applied successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showFilterDetails(String searchName, Map<String, dynamic> filters) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          searchName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.filter_list, color: Color(0xFFFF6B00), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Applied Filters:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              _buildDetailedFilterList(filters),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[400],
            ),
            child: Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _applySearch(filters);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF6B00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Apply Search'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedFilterList(Map<String, dynamic> filters) {
    final List<Widget> filterItems = [];
    
    // Vehicle Information
    if (filters['brand'] != null) {
      filterItems.add(_buildFilterDetailItem('Brand', filters['brand'].toString()));
    }
    if (filters['model'] != null) {
      filterItems.add(_buildFilterDetailItem('Model', filters['model'].toString()));
    }
    if (filters['trim'] != null) {
      filterItems.add(_buildFilterDetailItem('Trim', filters['trim'].toString()));
    }
    
    // Price Range
    if (filters['min_price'] != null || filters['max_price'] != null) {
      final minPrice = filters['min_price']?.toString() ?? 'Any';
      final maxPrice = filters['max_price']?.toString() ?? 'Any';
      filterItems.add(_buildFilterDetailItem('Price Range', '$minPrice - $maxPrice'));
    }
    
    // Year Range
    if (filters['min_year'] != null || filters['max_year'] != null) {
      final minYear = filters['min_year']?.toString() ?? 'Any';
      final maxYear = filters['max_year']?.toString() ?? 'Any';
      filterItems.add(_buildFilterDetailItem('Year Range', '$minYear - $maxYear'));
    }
    
    // Mileage Range
    if (filters['min_mileage'] != null || filters['max_mileage'] != null) {
      final minMileage = filters['min_mileage']?.toString() ?? 'Any';
      final maxMileage = filters['max_mileage']?.toString() ?? 'Any';
      filterItems.add(_buildFilterDetailItem('Mileage Range', '$minMileage - $maxMileage km'));
    }
    
    // Vehicle Specifications
    if (filters['condition'] != null) {
      filterItems.add(_buildFilterDetailItem('Condition', _capitalizeFirst(filters['condition'].toString())));
    }
    if (filters['transmission'] != null) {
      filterItems.add(_buildFilterDetailItem('Transmission', _capitalizeFirst(filters['transmission'].toString())));
    }
    if (filters['fuel_type'] != null) {
      filterItems.add(_buildFilterDetailItem('Fuel Type', _capitalizeFirst(filters['fuel_type'].toString())));
    }
    if (filters['body_type'] != null) {
      filterItems.add(_buildFilterDetailItem('Body Type', _capitalizeFirst(filters['body_type'].toString())));
    }
    if (filters['color'] != null) {
      filterItems.add(_buildFilterDetailItem('Color', _capitalizeFirst(filters['color'].toString())));
    }
    if (filters['drive_type'] != null) {
      filterItems.add(_buildFilterDetailItem('Drive Type', filters['drive_type'].toString().toUpperCase()));
    }
    if (filters['cylinder_count'] != null) {
      filterItems.add(_buildFilterDetailItem('Cylinder Count', filters['cylinder_count'].toString()));
    }
    if (filters['seating'] != null) {
      filterItems.add(_buildFilterDetailItem('Seating', '${filters['seating'].toString()} seats'));
    }
    if (filters['engine_size'] != null) {
      filterItems.add(_buildFilterDetailItem('Engine Size', '${filters['engine_size'].toString()}L'));
    }
    
    // Location and Other
    if (filters['city'] != null) {
      filterItems.add(_buildFilterDetailItem('City', _capitalizeFirst(filters['city'].toString())));
    }
    if (filters['title_status'] != null) {
      filterItems.add(_buildFilterDetailItem('Title Status', _capitalizeFirst(filters['title_status'].toString())));
    }
    if (filters['damaged_parts'] != null) {
      filterItems.add(_buildFilterDetailItem('Damaged Parts', filters['damaged_parts'].toString()));
    }
    if (filters['sort_by'] != null) {
      filterItems.add(_buildFilterDetailItem('Sort By', _capitalizeFirst(filters['sort_by'].toString())));
    }
    if (filters['owners'] != null) {
      filterItems.add(_buildFilterDetailItem('Number of Owners', filters['owners'].toString()));
    }
    if (filters['vin'] != null) {
      filterItems.add(_buildFilterDetailItem('VIN', filters['vin'].toString()));
    }
    if (filters['accident_history'] != null) {
      filterItems.add(_buildFilterDetailItem('Accident History', _capitalizeFirst(filters['accident_history'].toString())));
    }
    
    if (filterItems.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Color(0xFF404040), width: 1),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.grey[400],
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'No filters applied to this search.',
              style: TextStyle(
                color: Colors.grey[400],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }
    
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: filterItems,
    );
  }

  Widget _buildFilterDetailItem(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(0xFF404040), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFFFF6B00),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}

// Library-wide helper to map body types to emojis for all pages
String _getBodyTypeAsset(String bodyType) {
  // First try dynamic map built from assets
  if (bodyType.toLowerCase() == 'any') {
    return 'assets/body_types_clean/default.svg';
  }

  // Try direct label match from dynamic map
  // We store labels in title case keys (e.g., 'Mini Truck'), so we normalize here
  String normalizeTitle(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '')))
      .join(' ');

  final String titleKey = normalizeTitle(bodyType);
  if (globalBodyTypeAssetMap.containsKey(titleKey)) {
    return globalBodyTypeAssetMap[titleKey]!;
  }

  // Fallback to known static mappings for common names
  switch (bodyType.toLowerCase()) {
    case 'micro':
      return 'assets/body_types_clean/micro.svg';
    case 'cuv':
      return 'assets/body_types_clean/cuv.svg';
    case 'sedan':
      return 'assets/body_types_clean/sedan.svg';
    case 'suv':
      return 'assets/body_types_clean/suv.svg';
    case 'hatchback':
      return 'assets/body_types_clean/hatchback.svg';
    case 'coupe':
      return 'assets/body_types_clean/coupe.svg';
    case 'wagon':
      return 'assets/body_types_clean/wagon.svg';
    case 'pickup':
      return 'assets/body_types_clean/pickup.svg';
    case 'roadster':
      return 'assets/body_types_clean/roadster.svg';
    case 'truck':
      return 'assets/body_types_clean/truck.svg';
    case 'minitruck':
      return 'assets/body_types_clean/minitruck.svg';
    case 'bigtruck':
    case 'big truck':
      return 'assets/body_types_clean/bigtruck.svg';
    case 'van':
      return 'assets/body_types_clean/van.svg';
    case 'minivan':
      return 'assets/body_types_clean/minivan.svg';
    case 'supercar':
      return 'assets/body_types_clean/supercar.svg';
    case 'cabriolet':
      return 'assets/body_types_clean/cabriolet.svg';
    case 'motorcycle':
      return 'assets/body_types_clean/motorcycle.svg';
    case 'utv':
      return 'assets/body_types_clean/utv.svg';
    case 'atv':
      return 'assets/body_types_clean/atv.svg';
    default:
      return 'assets/body_types_clean/default.svg';
  }
}

// Placeholder classes for other pages
class CarDetailsPage extends StatefulWidget {
  final int carId;
  CarDetailsPage({required this.carId});
  @override
  _CarDetailsPageState createState() => _CarDetailsPageState();
}
class _CarDetailsPageState extends State<CarDetailsPage> {
  Map<String, dynamic>? car;
  bool loading = true;
  bool isFavorite = false;
  List<Map<String, dynamic>> similarCars = [];
  List<Map<String, dynamic>> relatedCars = [];
  bool loadingSimilar = false;
  bool loadingRelated = false;
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;

  Future<void> _toggleFavoriteOnServer() async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.loginRequired)));
        return;
      }
      final url = Uri.parse(getApiBase() + '/api/favorite/' + widget.carId.toString());
      final resp = await http.post(url, headers: { 'Authorization': 'Bearer ' + tok });
      if (resp.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(resp.body);
        final bool favorited = data['favorited'] == true;
        if (mounted) setState(() { isFavorite = favorited; });
        // Track favorite for analytics
        if (favorited) {
          unawaited(AnalyticsService.trackFavorite(widget.carId.toString()));
        }
      } else if (resp.statusCode == 401) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.loginRequired)));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.couldNotSubmitListing)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  List<String> get _imageUrls {
    final List<String> urls = [];
    if (car != null) {
      final String primary = (car!['image_url'] ?? '').toString();
      final List<dynamic> imgs = (car!['images'] is List) ? (car!['images'] as List) : const [];
      if (primary.isNotEmpty) {
        urls.add(getApiBase() + '/static/uploads/' + primary);
      }
      for (final dynamic it in imgs) {
        final s = it.toString();
        if (s.isNotEmpty) {
          final full = getApiBase() + '/static/uploads/' + s;
          if (!urls.contains(full)) urls.add(full);
        }
      }
    }
    return urls;
  }

  List<String> get _videoUrls {
    final List<String> urls = [];
    if (car != null) {
      final List<dynamic> videos = (car!['videos'] is List) ? (car!['videos'] as List) : const [];
      for (final dynamic it in videos) {
        final s = it.toString();
        if (s.isNotEmpty) {
          final full = getApiBase() + '/static/uploads/' + s;
          if (!urls.contains(full)) urls.add(full);
        }
      }
    }
    return urls;
  }

  @override
  void initState() {
    super.initState();
    _loadCar();
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  Future<void> _loadCar() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cacheKey = 'cache_car_${widget.carId}';
      final cached = sp.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          final data = json.decode(cached);
          if (data is Map) { setState(() { car = Map<String, dynamic>.from(data); loading = false; }); }
          else if (data is List && data.isNotEmpty) { setState(() { car = Map<String, dynamic>.from(data.first); loading = false; }); }
        } catch (_) {}
      }
      final url = Uri.parse(getApiBase() + '/cars?id=${widget.carId}');
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is List && data.isNotEmpty) {
          setState(() { car = Map<String, dynamic>.from(data.first); loading = false; });
          _loadSimilarAndRelated();
          unawaited(sp.setString(cacheKey, json.encode(car)));
          // Track view for analytics
          _trackView();
        } else if (data is Map) {
          setState(() { car = Map<String, dynamic>.from(data); loading = false; });
          _loadSimilarAndRelated();
          unawaited(sp.setString(cacheKey, json.encode(car)));
          // Track view for analytics
          _trackView();
        } else {
          setState(() { loading = false; });
        }
      } else {
        if (cached == null) setState(() { loading = false; });
      }
    } catch (_) {
      setState(() { loading = false; });
    }
  }

  Future<void> _trackView() async {
    try {
      await AnalyticsService.trackView(widget.carId.toString());
    } catch (e) {
      // Silently fail - don't interrupt user experience
      print('Failed to track view: $e');
    }
  }

  Future<void> _shareCar() async {
    try {
      if (car == null) return;
      
      final String title = car!['title']?.toString() ?? 'Car Listing';
      final String brand = car!['brand']?.toString() ?? '';
      final String model = car!['model']?.toString() ?? '';
      final String year = car!['year']?.toString() ?? '';
      final String price = car!['price']?.toString() ?? '';
      
      final String shareText = '$title - $brand $model ($year) - \$${price}';
      
      await Share.share(shareText);
      
      // Track share for analytics
      await AnalyticsService.trackShare(widget.carId.toString());
    } catch (e) {
      print('Failed to share car: $e');
    }
  }

  Future<void> _loadSimilarAndRelated() async {
    if (car == null) return;
    final String? brand = car!['brand']?.toString();
    final String? model = car!['model']?.toString();
    if (brand == null || brand.isEmpty) return;
    setState(() { loadingSimilar = true; loadingRelated = true; });
    try {
      final sp = await SharedPreferences.getInstance();
      final simKey = 'cache_similar_${widget.carId}';
      final relKey = 'cache_related_${widget.carId}';
      // Load cached similar/related first
      try {
        final simCached = sp.getString(simKey);
        if (simCached != null && simCached.isNotEmpty) {
          final simData = json.decode(simCached);
          if (simData is List) setState(() { similarCars = simData.cast<Map<String, dynamic>>(); });
        }
        final relCached = sp.getString(relKey);
        if (relCached != null && relCached.isNotEmpty) {
          final relData = json.decode(relCached);
          if (relData is List) setState(() { relatedCars = relData.cast<Map<String, dynamic>>(); });
        }
      } catch (_) {}
      // Similar: strictly same brand + model
      if (model != null && model.isNotEmpty) {
        final simUrl = Uri(
          scheme: 'http', host: '10.0.2.2', port: 5000, path: '/cars',
          queryParameters: {
            'brand': brand,
            'model': model,
            // ensure newest first handled by API default
          },
        );
        final simResp = await http.get(simUrl);
        if (simResp.statusCode == 200) {
          final simData = json.decode(simResp.body);
          if (simData is List) {
            final list = simData
                .cast<dynamic>()
                .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
                .where((e) => e['id'] != widget.carId)
                .toList();
            setState(() { similarCars = list.take(12).toList(); });
            unawaited(sp.setString(simKey, json.encode(similarCars)));
          }
        }
      } else {
        setState(() { similarCars = []; });
      }

      // Related: same brand and matching key attributes ("same filters")
      // Build a query around the viewed car's attributes: price/year ranges, transmission, fuel, condition, city
      final Map<String, String> qp = {'brand': brand};
      // Price band: +/- 15%
      final num? priceNum = (car!['price'] is num)
          ? (car!['price'] as num)
          : num.tryParse((car!['price'] ?? '').toString());
      if (priceNum != null && priceNum > 0) {
        final double minP = (priceNum * 0.85).floorToDouble();
        final double maxP = (priceNum * 1.15).ceilToDouble();
        qp['min_price'] = minP.toStringAsFixed(0);
        qp['max_price'] = maxP.toStringAsFixed(0);
      }
      // Year band: +/- 2 years
      final int? yearNum = (car!['year'] is int)
          ? (car!['year'] as int)
          : int.tryParse((car!['year'] ?? '').toString());
      if (yearNum != null && yearNum > 0) {
        qp['min_year'] = (yearNum - 2).toString();
        qp['max_year'] = (yearNum + 2).toString();
      }
      // Transmission, fuel, condition, city
      void addIfPresent(String key) {
        final val = car![key]?.toString();
        if (val != null && val.isNotEmpty) qp[key] = val;
      }
      addIfPresent('transmission');
      addIfPresent('fuel_type');
      addIfPresent('condition');
      addIfPresent('city');

      final relUrl = Uri(scheme: 'http', host: '10.0.2.2', port: 5000, path: '/cars', queryParameters: qp);
      final relResp = await http.get(relUrl);
      if (relResp.statusCode == 200) {
        final relData = json.decode(relResp.body);
        if (relData is List) {
          final list = relData
              .cast<dynamic>()
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .where((e) => e['id'] != widget.carId)
              .toList();
          setState(() { relatedCars = list.take(12).toList(); });
          unawaited(sp.setString(relKey, json.encode(relatedCars)));
        }
      }
    } catch (_) {
      // ignore network errors for these sections
    } finally {
      if (mounted) {
        setState(() { loadingSimilar = false; loadingRelated = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: loading
          ? Center(child: CircularProgressIndicator())
          : car == null
              ? Center(child: Text(AppLocalizations.of(context)!.carNotFound))
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      stretch: true,
                      expandedHeight: 300,
                      leading: IconButton(
                        icon: Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      actions: [
                        IconButton(
                          onPressed: _toggleFavoriteOnServer,
                          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                        ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(24),
                                bottomRight: Radius.circular(24),
                              ),
                              child: GestureDetector(
                                onTap: () {
                                  final urls = _imageUrls;
                                  if (urls.isEmpty) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => FullScreenGalleryPage(
                                        imageUrls: urls,
                                        initialIndex: _currentImageIndex,
                                      ),
                                    ),
                                  );
                                },
                                child: (_imageUrls.isNotEmpty)
                                    ? PageView.builder(
                                        controller: _imagePageController,
                                        onPageChanged: (idx) => setState(() => _currentImageIndex = idx),
                                        itemCount: _imageUrls.length,
                                        itemBuilder: (context, index) {
                                          final url = _imageUrls[index];
                                          return CachedNetworkImage(
                                            imageUrl: url,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            placeholder: (_, __) => Container(color: Colors.white10),
                                            errorWidget: (_, __, ___) => Container(color: Colors.grey[900], child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400])),
                                          );
                                        },
                                      )
                                    : Container(
                                        color: Colors.grey[900],
                                        width: double.infinity,
                                        child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
                                      ),
                              ),
                            ),
                            if (_imageUrls.length > 1)
                              Positioned(
                                bottom: 16,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  ignoring: true,
                                  child: Center(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      physics: BouncingScrollPhysics(),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: List.generate(_imageUrls.length, (i) {
                                          final bool active = i == _currentImageIndex;
                                          return AnimatedContainer(
                                            duration: Duration(milliseconds: 200),
                                            margin: EdgeInsets.symmetric(horizontal: 4),
                                            width: active ? 10 : 6,
                                            height: active ? 10 : 6,
                                            decoration: BoxDecoration(
                                              color: active ? Colors.white : Colors.white70,
                                              shape: BoxShape.circle,
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // Removed title/price overlay to avoid blocking the image
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Quick Sell Banner
                            if (car!['is_quick_sell'] == true || car!['is_quick_sell'] == 'true')
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                margin: EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.orange, Colors.deepOrange],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.flash_on, color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      AppLocalizations.of(context)!.quickSell,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Title and price moved below the image header
                            Text(
                              car!['title']?.toString() ?? '',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 8),
                            if (car!['price'] != null)
                              Text(
                                _formatCurrencyGlobal(context, car!['price']),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF6B00),
                                ),
                              ),
                            SizedBox(height: 16),
                            // Actions
                            SizedBox(height: 8),
                            if (car!['contact_phone'] != null && car!['contact_phone'].toString().isNotEmpty)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: Icon(Icons.chat),
                                  label: Text(AppLocalizations.of(context)!.chatOnWhatsApp),
                                  onPressed: () async {
final String raw = car!['contact_phone'].toString();
                                    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
                                    final String msg = Uri.encodeComponent('Hi, I am interested in your ${car!['title'] ?? 'car'}');

                                    final Uri waApp = Uri.parse('whatsapp://send?phone=$digits&text=$msg');
                                    final Uri waWeb = Uri.parse('https://wa.me/$digits?text=$msg');

                                    bool launched = await launchUrl(
                                      waApp,
                                      mode: LaunchMode.externalNonBrowserApplication,
                                    ).catchError((_) => false);
                                    if (!launched) {
                                      launched = await launchUrl(
                                        waWeb,
                                        mode: LaunchMode.externalApplication,
                                      ).catchError((_) => false);
                                    }
                                    if (!launched) {
                                      launched = await launchUrl(
                                        waWeb,
                                        mode: LaunchMode.platformDefault,
                                      ).catchError((_) => false);
                                    }
                                    if (!launched && mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.unableToOpenWhatsApp)));
                                    } else if (launched) {
                                      // Track message for analytics
                                      await AnalyticsService.trackMessage(widget.carId.toString());
                                    }
                                  },
                                ),
                              ),
                            if (car!['contact_phone'] != null && car!['contact_phone'].toString().isNotEmpty) ...[
                              SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFF007AFF),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: Icon(Icons.phone),
                                  label: Text('Call Seller'),
                                  onPressed: () async {
                                    final String raw = car!['contact_phone'].toString();
                                    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
                                    
                                    final Uri callUri = Uri.parse('tel:$digits');
                                    
                                    bool launched = await launchUrl(
                                      callUri,
                                      mode: LaunchMode.externalApplication,
                                    ).catchError((_) => false);
                                    
                                    if (launched) {
                                      // Track call for analytics
                                      await AnalyticsService.trackCall(widget.carId.toString());
                                    } else if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Unable to make call')),
                                      );
                                    }
                                  },
                                ),
                              ),
                              SizedBox(height: 12),
                            ],
                            
                            Text(
                              AppLocalizations.of(context)!.specificationsLabel,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF6B00),
                              ),
                            ),
                            SizedBox(height: 12),
                            _buildSpecsGrid(),
                            SizedBox(height: 24),
                            
                            // Videos Section
                            if (_videoUrls.isNotEmpty) ...[
                              Text(
                                AppLocalizations.of(context)!.vehicleVideos,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF6B00),
                                ),
                              ),
                              SizedBox(height: 12),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 1,
                                  childAspectRatio: 16 / 9,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                                itemCount: _videoUrls.length,
                                itemBuilder: (context, index) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: Colors.grey[900],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            height: double.infinity,
                                            color: Colors.grey[800],
                                            child: Icon(
                                              Icons.videocam,
                                              size: 48,
                                              color: Colors.grey[400],
                                            ),
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            padding: EdgeInsets.all(12),
                                            child: Icon(
                                              Icons.play_arrow,
                                              color: Colors.white,
                                              size: 32,
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 8,
                                            left: 8,
                                            child: Container(
                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                AppLocalizations.of(context)!.videoIndex((index + 1).toString()),
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              SizedBox(height: 24),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: _toggleFavoriteOnServer,
                                        icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                                        label: Text(isFavorite ? AppLocalizations.of(context)!.saved : AppLocalizations.of(context)!.save),
                                      ),
                                      SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ComparisonButton(car: car!),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _shareCar,
                                        icon: Icon(Icons.share),
                                        label: Text('Share'),
                                      ),
                                      SizedBox(height: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => Navigator.of(context).maybePop(),
                                        icon: Icon(Icons.list_alt),
                                        label: Text(AppLocalizations.of(context)!.backToList),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 28),
                            if (similarCars.isNotEmpty) ...[
                              Text(AppLocalizations.of(context)!.similarListings, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                              SizedBox(height: 12),
                              _buildHorizontalList(similarCars),
                              SizedBox(height: 28),
                            ] else if (loadingSimilar) ...[
                              Text(AppLocalizations.of(context)!.similarListings, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                              SizedBox(height: 12),
                              SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
                              SizedBox(height: 28),
                            ],
                            if (relatedCars.isNotEmpty) ...[
                              Text(AppLocalizations.of(context)!.relatedListings, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                              SizedBox(height: 12),
                              _buildHorizontalList(relatedCars),
                            ] else if (loadingRelated) ...[
                              Text(AppLocalizations.of(context)!.relatedListings, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                              SizedBox(height: 12),
                              SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _formatPrice(String raw) {
    try {
      final num? value = num.tryParse(raw.replaceAll(RegExp(r'[^0-9\.-]'), ''));
      if (value == null) return raw;
      final localeCode = Localizations.localeOf(context).toLanguageTag();
      final formatter = _decimalFormatterGlobal(context);
      return formatter.format(value);
    } catch (_) {
      return raw;
    }
  }

  // Safely get the first non-empty string value from several possible keys (handles snake_case and camelCase)
  String? _getFirstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      final String stringValue = value.toString().trim();
      if (stringValue.isNotEmpty) return stringValue;
    }
    return null;
  }

  // Styled detail row with icon, label and value pill
  Widget _detailRow({required IconData icon, required String label, required String? value}) {
    if (value == null || value.isEmpty) return SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.black),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
            ),
          ),
          // Inline overlay only belongs to HomePage, not here
        ],
      ),
    );
  }





  Widget _buildSpecsGrid() {
    // Primary fields
    final List<_SpecItem> primary = [
      _SpecItem(icon: Icons.calendar_month, label: AppLocalizations.of(context)!.yearLabel, value: car!['year'] != null ? _localizeDigitsGlobal(context, car!['year'].toString()) : null),
      _SpecItem(icon: Icons.speed, label: AppLocalizations.of(context)!.mileageLabel, value: car!['mileage'] != null ? '${_localizeDigitsGlobal(context, _formatPrice(car!['mileage'].toString()))} ${AppLocalizations.of(context)!.unit_km}' : null),
      _SpecItem(icon: Icons.settings, label: AppLocalizations.of(context)!.transmissionLabel, value: _translateValueGlobal(context, _getFirstNonEmpty(car!, ['transmission']))),
      _SpecItem(icon: Icons.location_city, label: AppLocalizations.of(context)!.cityLabel, value: car!['city'] != null ? _translateValueGlobal(context, car!['city'].toString()) ?? car!['city'].toString() : null),
      _SpecItem(icon: Icons.assignment_turned_in, label: AppLocalizations.of(context)!.titleStatus, value: car!['title_status'] != null
          ? (car!['title_status'].toString().toLowerCase() == 'damaged'
              ? (AppLocalizations.of(context)!.value_title_damaged + (car!['damaged_parts'] != null ? ' (${_localizeDigitsGlobal(context, car!['damaged_parts'].toString())} ${AppLocalizations.of(context)!.damagedParts})' : ''))
              : AppLocalizations.of(context)!.value_title_clean)
          : null),
      _SpecItem(icon: Icons.local_gas_station, label: AppLocalizations.of(context)!.detail_fuel, value: _translateValueGlobal(context, _getFirstNonEmpty(car!, ['fuel_type']))),
    ];

    // Vertical list for detailed specs below the big labels
    final String? engineSize = _getFirstNonEmpty(car!, ['engine_size', 'engineSize', 'engine']);
    final List<Widget> details = [
      _detailRow(icon: Icons.place, label: AppLocalizations.of(context)!.cityLabel, value: _translateValueGlobal(context, _getFirstNonEmpty(car!, ['city']))),
      _detailRow(icon: Icons.check_circle, label: AppLocalizations.of(context)!.detail_condition, value: _translateValueGlobal(context, _getFirstNonEmpty(car!, ['condition']))),
      _detailRow(icon: Icons.settings, label: AppLocalizations.of(context)!.transmissionLabel, value: _translateValueGlobal(context, _getFirstNonEmpty(car!, ['transmission']))),
      _detailRow(icon: Icons.local_gas_station, label: AppLocalizations.of(context)!.detail_fuel, value: _translateValueGlobal(context, _getFirstNonEmpty(car!, ['fuel_type', 'fuelType', 'fuel']))),
      _detailRow(icon: Icons.directions_car_filled, label: AppLocalizations.of(context)!.detail_body, value: _translateValueGlobal(context, _getFirstNonEmpty(car!, ['body_type', 'bodyType', 'body']))),
      _detailRow(icon: Icons.color_lens, label: AppLocalizations.of(context)!.detail_color, value: _translateValueGlobal(context, _getFirstNonEmpty(car!, ['color']))),
      _detailRow(icon: Icons.drive_eta, label: AppLocalizations.of(context)!.detail_drive, value: _translateValueGlobal(context, _getFirstNonEmpty(car!, ['drive_type', 'driveType', 'drivetrain', 'drive']))),
      _detailRow(icon: Icons.settings_input_component, label: AppLocalizations.of(context)!.detail_cylinders, value: _localizeDigitsGlobal(context, _getFirstNonEmpty(car!, ['cylinder_count', 'cylinders', 'cylinderCount']) ?? '')),
      _detailRow(icon: Icons.straighten, label: AppLocalizations.of(context)!.detail_engine, value: engineSize != null ? '${_localizeDigitsGlobal(context, engineSize.toString())}${AppLocalizations.of(context)!.unit_liter_suffix}' : null),
      _detailRow(icon: Icons.airline_seat_recline_normal, label: AppLocalizations.of(context)!.detail_seating, value: _localizeDigitsGlobal(context, _getFirstNonEmpty(car!, ['seating', 'seats', 'seatCount']) ?? '')),
      _detailRow(icon: Icons.assignment_turned_in, label: AppLocalizations.of(context)!.titleStatus, value: car!['title_status'] != null
          ? (car!['title_status'].toString().toLowerCase() == 'damaged'
              ? (AppLocalizations.of(context)!.value_title_damaged + (car!['damaged_parts'] != null ? ' (${_localizeDigitsGlobal(context, car!['damaged_parts'].toString())} ${AppLocalizations.of(context)!.damagedParts})' : ''))
              : AppLocalizations.of(context)!.value_title_clean)
          : null),
      _detailRow(icon: Icons.person_outline, label: _ownersLabelGlobal(context), value: _localizeDigitsGlobal(context, _getFirstNonEmpty(car!, ['owners', 'owner_count', 'ownerCount']) ?? '')),
      _detailRow(icon: Icons.qr_code_2, label: _vinLabelGlobal(context), value: _getFirstNonEmpty(car!, ['vin'])),
      _detailRow(icon: Icons.report_gmailerrorred, label: _accidentHistoryLabelGlobal(context), value: (() {
        final v = _getFirstNonEmpty(car!, ['accident_history', 'accidentHistory']);
        if (v == null) return null;
        final s = v.toString().toLowerCase();
        if (s == '1' || s == 'true' || s == 'yes') return _yesTextGlobal(context);
        if (s == '0' || s == 'false' || s == 'no') return _noTextGlobal(context);
        return v.toString();
      })()),
      _detailRow(icon: Icons.phone, label: AppLocalizations.of(context)!.phoneLabel, value: _getFirstNonEmpty(car!, ['contact_phone'])),
    ];

    final primItems = primary.where((i) => i.value != null && i.value!.isNotEmpty).toList();

    final primGrid = GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: primItems.length,
      itemBuilder: (context, index) => _buildSpecCard(primItems[index]),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        primGrid,
        SizedBox(height: 12),
        ...details,
      ],
    );
  }
  Widget _buildSpecCard(_SpecItem item) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      constraints: BoxConstraints(minHeight: 84),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(item.icon, size: 16, color: Colors.black87),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            item.value!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              height: 1.15,
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ),
          ),
          // Inline overlay only for HomePage (removed from here)
        ],
      ),
    );
  }

  

  Widget _buildSpecCardSmall(_SpecItem item) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00).withOpacity(0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(item.icon, size: 14, color: Colors.black87),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            item.value!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalList(List<Map<String, dynamic>> items) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildSmallCarCard(item);
        },
      ),
    );
  }

  Widget _buildSmallCarCard(Map<String, dynamic> data) {
    return InkWell(
      onTap: () {
        // Analytics tracking for view listing
        Navigator.pushNamed(context, '/car_detail', arguments: {'carId': data['id']});
      },
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              child: () {
                final String primary = (data['image_url'] ?? '').toString();
                final List<dynamic> imgs = (data['images'] is List) ? (data['images'] as List) : const [];
                final String rel = primary.isNotEmpty
                    ? primary
                    : (imgs.isNotEmpty ? imgs.first.toString() : '');
                if (rel.isNotEmpty) {
                  return CachedNetworkImage(
                    imageUrl: getApiBase() + '/static/uploads/' + rel,
                    height: 110,
                    width: 160,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(height: 110, width: 160, color: Colors.white10),
                    errorWidget: (_, __, ___) => Container(height: 110, width: 160, color: Colors.black26, child: Icon(Icons.directions_car, color: Colors.white38)),
                  );
                }
                return Container(height: 110, width: 160, color: Colors.black26, child: Icon(Icons.directions_car, color: Colors.white38));
              }(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 16.0, 8.0, 8.0), // Much more padding at top for space between image and text
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['title']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  if (data['price'] != null)
                    Text(
                      _formatCurrencyGlobal(context, data['price']),
                      style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spec(String label, String? value) {
    if (value == null || value.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: Colors.white70))),
          Expanded(child: Text(value, style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}

class _SpecItem {
  final IconData icon;
  final String label;
  final String? value;
  final bool isSecondary;
  _SpecItem({required this.icon, required this.label, required this.value, this.isSecondary = false});
}

// Removed old AddListingPage in favor of the new multi-step SellCarPage

// Multi-step sell page
class SellCarPage extends StatefulWidget {
  @override
  _SellCarPageState createState() => _SellCarPageState();
}

class _SellCarPageState extends State<SellCarPage> {
  int currentStep = 0;
  final PageController _pageController = PageController();
  
  // Car data that will be passed between steps
  Map<String, dynamic> carData = {};
  
  final List<Widget> steps = [
    SellStep1Page(),
    SellStep2Page(),
    SellStep3Page(),
    SellStep4Page(),
    SellStep5Page(),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.addListingTitle),
        backgroundColor: Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            if (currentStep > 0) {
              setState(() {
                currentStep--;
              });
              _pageController.previousPage(
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: List.generate(5, (index) {
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 4),
                    height: 4,
                    decoration: BoxDecoration(
                      color: index <= currentStep 
                        ? Color(0xFFFF6B00) 
                        : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          // Step indicator
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Step ${currentStep + 1} of 5',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _getStepTitle(currentStep),
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFFFF6B00),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Page content
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  currentStep = index;
                });
              },
              itemCount: steps.length,
              itemBuilder: (context, index) {
                return steps[index];
              },
            ),
          ),
        ],
      ),
    );
  }
  
  String _getStepTitle(int step) {
    switch (step) {
      case 0: return 'Basic Information';
      case 1: return 'Car Details';
      case 2: return 'Pricing & Contact';
      case 3: return 'Photos & Videos';
      case 4: return 'Review & Submit';
      default: return '';
    }
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

// Step 1: Basic Information (Brand, Model, Trim, Year)
class SellStep1Page extends StatefulWidget {
  @override
  _SellStep1PageState createState() => _SellStep1PageState();
}
class _SellStep1PageState extends State<SellStep1Page> {
  final _formKey = GlobalKey<FormState>();
  String? selectedBrand;
  String? selectedModel;
  String? selectedTrim;
  String? selectedYear;
  bool errBrand = false;
  bool errModel = false;
  bool errTrim = false;
  bool errYear = false;
  bool isYearManualInput = false;
  
  // Focus node for keyboard management
  FocusNode _yearFocusNode = FocusNode();
  
  String _brandSlug(String brand) {
    String s = brand.toLowerCase().trim();
    const replacements = {
      'Ã¡': 'a', 'Ã ': 'a', 'Ã¢': 'a', 'Ã¤': 'a', 'Ã£': 'a', 'Ã¥': 'a',
      'Ã©': 'e', 'Ã¨': 'e', 'Ãª': 'e', 'Ã«': 'e',
      'Ã­': 'i', 'Ã¬': 'i', 'Ã®': 'i', 'Ã¯': 'i',
      'Ã³': 'o', 'Ã²': 'o', 'Ã´': 'o', 'Ã¶': 'o', 'Ãµ': 'o', 'Ã¸': 'o',
      'Ãº': 'u', 'Ã¹': 'u', 'Ã»': 'u', 'Ã¼': 'u',
      'Ã½': 'y', 'Ã¿': 'y',
      'Ã±': 'n',
      'Ã§': 'c', 'Ä': 'c', 'Ä‡': 'c',
      'Å¡': 's', 'ÃŸ': 'ss',
      'Å¾': 'z',
      'Å“': 'oe', 'Ã¦': 'ae',
      'Ä‘': 'd',
      'Å‚': 'l'
    };
    replacements.forEach((k, v) { s = s.replaceAll(k, v); });
    s = s.replaceAll(RegExp(r"[^a-z0-9]+"), '-');
    s = s.replaceAll(RegExp(r"-+"), '-').replaceAll(RegExp(r"(^-|-$)"), '');
    return s;
  }
  
  @override
  void initState() {
    super.initState();
    _resetSellFilters();
  }
  
  @override
  void dispose() {
    _yearFocusNode.dispose();
    super.dispose();
  }
  
  Future<void> _resetSellFilters() async {
    selectedBrand = null;
    selectedModel = null;
    selectedTrim = null;
    selectedYear = null;
    setState(() {});
  }
  
  void _dismissKeyboard() {
    // Clear focus from year field
    _yearFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }
  
  Future<String?> _pickFromList(String title, List<String> options) async {
    services.HapticFeedback.selectionClick();
    return await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      pageBuilder: (context, a1, a2) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return Transform.translate(
          offset: Offset(0, (1 - curved.value) * 30),
          child: Opacity(
            opacity: curved.value,
            child: Dialog(
          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 420,
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                    IconButton(icon: Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                SizedBox(height: 10),
                SizedBox(
                  height: 400,
                  child: ListView.separated(
                    itemCount: options.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final value = options[index];
                          final lowerTitle = title.toLowerCase();
                          String displayText = value;
                          final bool isNumeric = RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(value);
                          if (lowerTitle.contains('price')) {
                            displayText = _formatCurrencyGlobal(context, value);
                          } else if (lowerTitle.contains('mileage') && isNumeric) {
                            final nf = _decimalFormatterGlobal(context);
                            displayText = _localizeDigitsGlobal(context, nf.format(num.tryParse(value) ?? 0)) + ' ' + AppLocalizations.of(context)!.unit_km;
                          } else if (lowerTitle.contains('year') && isNumeric) {
                            displayText = _localizeDigitsGlobal(context, value);
                          } else if (lowerTitle.contains('seating') && isNumeric) {
                            displayText = _localizeDigitsGlobal(context, value) + ' seats';
                          } else if (lowerTitle.contains('cylinder') && isNumeric) {
                            displayText = _localizeDigitsGlobal(context, value) + ' cylinders';
                          } else if (lowerTitle.contains('engine') && isNumeric) {
                            displayText = _localizeDigitsGlobal(context, value) + ' L';
                          } else {
                            final translated = _translateValueGlobal(context, value);
                            if (translated != null) displayText = translated;
                          }
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, value),
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  colors: [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.02)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(child: Text(displayText, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                                  Icon(Icons.chevron_right, color: Colors.white70),
                                ],
                              ),
                            ),
                      );
                    },
                  ),
                )
              ],
                ),
              ),
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
    );
  }
  
  Future<String?> _pickBrandModal() async {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 480,
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppLocalizations.of(context)!.selectBrand, style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                    IconButton(icon: Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                SizedBox(height: 10),
                SizedBox(
                  height: 420,
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: BouncingScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: brands.length,
                    itemBuilder: (context, index) {
                      final brand = brands[index];
                      final logoFile = _brandSlug(brand);
                      final logoUrl = getApiBase() + '/static/images/brands/' + logoFile + '.png';
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(context, brand),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          padding: EdgeInsets.all(6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                                child: CachedNetworkImage(
                                  imageUrl: logoUrl,
                                  placeholder: (context, url) => SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                  errorWidget: (context, url, error) => Image.network(
                                    getApiBase() + '/static/images/brands/default.png',
                                    fit: BoxFit.contain,
                                  ),
                                  fit: BoxFit.contain,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(brand, style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  final List<String> brands = [
    'Toyota', 'Volkswagen', 'Ford', 'Honda', 'Hyundai', 'Nissan', 'Chevrolet', 'Kia', 
    'Mercedes-Benz', 'BMW', 'Audi', 'Lexus', 'Mazda', 'Subaru', 'Volvo', 'Jeep', 'RAM', 
    'GMC', 'Buick', 'Cadillac', 'Lincoln', 'Mitsubishi', 'Acura', 'Infiniti', 'Tesla', 
    'Mini', 'Porsche', 'Land Rover', 'Jaguar', 'Fiat', 'Renault', 'Peugeot', 'CitroÃ«n', 
    'Å koda', 'SEAT', 'Dacia', 'Chery', 'BYD', 'Great Wall', 'FAW', 'Roewe', 'Proton', 
    'Perodua', 'Tata', 'Mahindra', 'Lada', 'ZAZ', 'Daewoo', 'SsangYong', 'Changan', 
    'Haval', 'Wuling', 'Baojun', 'Nio', 'XPeng', 'Li Auto', 'VinFast', 'Ferrari', 
    'Lamborghini', 'Bentley', 'Rolls-Royce', 'Aston Martin', 'McLaren', 'Maserati', 
    'Bugatti', 'Pagani', 'Koenigsegg', 'Polestar', 'Rivian', 'Lucid', 'Alfa Romeo', 
    'Lancia', 'Abarth', 'Opel', 'DS', 'MAN', 'Iran Khodro', 'Genesis', 'Isuzu', 
    'Datsun', 'JAC Motors', 'JAC Trucks', 'KTM', 'Alpina', 'Brabus', 'Mansory', 
    'Bestune', 'Hongqi', 'Dongfeng', 'FAW Jiefang', 'Foton', 'Leapmotor', 'GAC', 
    'SAIC', 'MG', 'Vauxhall', 'Smart'
  ];
  
  final Map<String, List<String>> models = {
    'BMW': ['X3', 'X5', 'X7', '3 Series', '5 Series', '7 Series', 'M3', 'M5', 'X1', 'X6'],
    'Mercedes-Benz': ['C-Class', 'E-Class', 'S-Class', 'GLC', 'GLE', 'GLS', 'A-Class', 'CLA', 'GLA', 'AMG GT'],
    'Audi': ['A3', 'A4', 'A6', 'A8', 'Q3', 'Q5', 'Q7', 'Q8', 'RS6', 'TT'],
    'Toyota': ['Camry', 'Corolla', 'RAV4', 'Highlander', 'Tacoma', 'Tundra', 'Prius', 'Avalon', '4Runner', 'Sequoia'],
    'Honda': ['Civic', 'Accord', 'CR-V', 'Pilot', 'Ridgeline', 'Odyssey', 'HR-V', 'Passport', 'Insight', 'Clarity'],
    'Nissan': ['Altima', 'Maxima', 'Rogue', 'Murano', 'Pathfinder', 'Frontier', 'Titan', 'Leaf', 'Sentra', 'Versa'],
    'Ford': ['F-150', 'Mustang', 'Explorer', 'Escape', 'Edge', 'Ranger', 'Bronco', 'Mach-E', 'Focus', 'Fusion'],
    'Chevrolet': ['Silverado', 'Camaro', 'Equinox', 'Tahoe', 'Suburban', 'Colorado', 'Corvette', 'Malibu', 'Cruze', 'Traverse'],
    'Hyundai': ['Elantra', 'Sonata', 'Tucson', 'Santa Fe', 'Palisade', 'Kona', 'Venue', 'Accent', 'Veloster', 'Ioniq'],
    'Kia': ['Forte', 'K5', 'Sportage', 'Telluride', 'Sorento', 'Soul', 'Rio', 'Stinger', 'EV6', 'Niro']
  };
  
  final Map<String, Map<String, List<String>>> trimsByBrandModel = {
    'BMW': {
      'X3': ['Base', 'xDrive30i', 'M40i'],
      'X5': ['Base', 'xDrive40i', 'M50i'],
      '3 Series': ['320i', '330i', 'M340i', 'M3'],
    },
    'Toyota': {
      'Camry': ['L', 'LE', 'SE', 'XSE', 'XLE'],
      'Corolla': ['L', 'LE', 'SE', 'XSE', 'XLE'],
      'RAV4': ['LE', 'XLE', 'XLE Premium', 'Adventure', 'Limited', 'TRD Off-Road'],
    },
    'Mercedes-Benz': {
      'C-Class': ['C 200', 'C 300', 'AMG C 43', 'AMG C 63'],
      'E-Class': ['E 200', 'E 300', 'E 450', 'AMG E 53'],
      'GLC': ['GLC 200', 'GLC 300', 'AMG GLC 43'],
    },
  };
  
  List<String> get availableYears {
    final currentYear = DateTime.now().year;
    return List.generate(30, (index) => (currentYear - index).toString());
  }
  
  List<String> get availableTrims {
    if (selectedBrand != null && selectedModel != null) {
      return trimsByBrandModel[selectedBrand!]?[selectedModel!] ?? ['Base'];
    }
    return ['Base'];
  }
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.directions_car, size: 48, color: Color(0xFFFF6B00)),
                  SizedBox(height: 12),
                  Text(
                    'Basic Information',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tell us about your car\'s basic details',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            
            // Brand Selection (Modal)
            FormField<String>(
              validator: (_) => selectedBrand == null ? 'Please select a brand' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickBrandModal();
                  if (choice != null) {
                    setState(() {
                      selectedBrand = choice;
                      selectedModel = null;
                      selectedTrim = null;
                    });
                  }
                },
                child: buildFancySelector(
                  context,
                  label: 'Brand *',
                  value: selectedBrand,
                  isError: errBrand && (selectedBrand == null || selectedBrand!.isEmpty),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: const Color(0xFFFF6B00).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: selectedBrand == null
                        ? Icon(Icons.business, color: const Color(0xFFFF6B00))
                        : Padding(
                            padding: const EdgeInsets.all(6),
                            child: CachedNetworkImage(
                              imageUrl: getApiBase() + '/static/images/brands/' + _brandSlug(selectedBrand!) + '.png',
                              fit: BoxFit.contain,
                              errorWidget: (context, url, error) => Image.network(
                                getApiBase() + '/static/images/brands/default.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            
            // Model (Modal)
            FormField<String>(
              validator: (_) => selectedModel == null ? 'Please select a model' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  if (selectedBrand == null) return;
                  final options = models[selectedBrand!] ?? [];
                  final choice = await _pickFromList('Model', options);
                  if (choice != null) {
                    setState(() { selectedModel = choice; selectedTrim = null; });
                  }
                },
                child: buildFancySelector(context, icon: Icons.directions_car, label: 'Model *', value: selectedModel ?? (selectedBrand == null ? 'Select brand first' : ''), isError: errModel && (selectedModel == null || selectedModel!.isEmpty)),
              ),
            ),
            SizedBox(height: 16),
            
            // Trim (Modal)
            FormField<String>(
              validator: (_) => selectedTrim == null ? 'Please select a trim' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickFromList('Trim', availableTrims);
                  if (choice != null) setState(() { selectedTrim = choice; });
                },
                child: buildFancySelector(context, icon: Icons.settings, label: 'Trim *', value: selectedTrim, isError: errTrim && (selectedTrim == null || selectedTrim!.isEmpty)),
              ),
            ),
            SizedBox(height: 16),
            
             // Year (Modal or Manual Input)
             Row(
               children: [
                 Expanded(
                   child: isYearManualInput
                      ? TextFormField(
                          focusNode: _yearFocusNode,
                          initialValue: selectedYear,
                          decoration: InputDecoration(
                            labelText: 'Year *',
                            hintText: 'Enter year (e.g. 2024)',
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.2),
                            labelStyle: TextStyle(color: Colors.white),
                            hintStyle: TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.red),
                            ),
                          ),
                          style: TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            setState(() {
                              selectedYear = value.isEmpty ? null : value;
                            });
                          },
                           validator: (value) {
                             if (value == null || value.isEmpty) return 'Please enter year';
                             final year = int.tryParse(value);
                             if (year == null) return 'Invalid year';
                             if (year < 1900 || year > DateTime.now().year + 1) return 'Year out of range';
                             return null;
                           },
                         )
                       : FormField<String>(
                           validator: (_) => selectedYear == null ? 'Please select a year' : null,
                           builder: (state) => GestureDetector(
                             onTap: () async {
                               final choice = await _pickFromList('Year', availableYears);
                               if (choice != null) setState(() { selectedYear = choice; });
                             },
                             child: buildFancySelector(context, icon: Icons.calendar_today, label: 'Year *', value: selectedYear != null ? _localizeDigitsGlobal(context, selectedYear!) : null, isError: errYear && (selectedYear == null || selectedYear!.isEmpty)),
                           ),
                         ),
                 ),
                 SizedBox(width: 8),
                 IconButton(
                   onPressed: () => setState(() => isYearManualInput = !isYearManualInput),
                   icon: Icon(isYearManualInput ? Icons.list : Icons.edit, color: Color(0xFFFF6B00)),
                   style: IconButton.styleFrom(
                     backgroundColor: Colors.grey.withOpacity(0.1),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                   ),
                   tooltip: isYearManualInput ? 'Select from list' : 'Type manually',
                 ),
               ],
             ),
            SizedBox(height: 32),
            
            // Next Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  // Manual validation for required selectors (since we use custom tiles)
                  final List<String> missing = [];
                  if (selectedBrand == null || (selectedBrand ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.brandLabel);
                  if (selectedModel == null || (selectedModel ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.modelLabel);
                  if (selectedTrim == null || (selectedTrim ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.trimLabel);
                  if (selectedYear == null || (selectedYear ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.yearLabel);

                  if (missing.isNotEmpty) {
                    setState(() {
                      errBrand = selectedBrand == null || (selectedBrand ?? '').isEmpty;
                      errModel = selectedModel == null || (selectedModel ?? '').isEmpty;
                      errTrim = selectedTrim == null || (selectedTrim ?? '').isEmpty;
                      errYear = selectedYear == null || (selectedYear ?? '').isEmpty;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_pleaseFillRequiredGlobal(context) + ': ' + missing.join(', ')), backgroundColor: Colors.red),
                    );
                    return;
                  }

                    // Save data and navigate to next step
                    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
                    if (parentState != null) {
                      parentState.carData['brand'] = selectedBrand;
                      parentState.carData['model'] = selectedModel;
                      parentState.carData['trim'] = selectedTrim;
                      parentState.carData['year'] = selectedYear;
                    setState(() { errBrand = errModel = errTrim = errYear = false; });
                    parentState._pageController.nextPage(duration: Duration(milliseconds: 300), curve: Curves.easeInOut);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFFF6B00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: Text(
                  'Next Step',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Step 2: Car Details (Mileage, Condition, Transmission, etc.)
class SellStep2Page extends StatefulWidget {
  @override
  _SellStep2PageState createState() => _SellStep2PageState();
}
class _SellStep2PageState extends State<SellStep2Page> {
  final _formKey = GlobalKey<FormState>();
  String? selectedMileage;
  String? selectedCondition;
  String? selectedTransmission;
  String? selectedFuelType;
  String? selectedBodyType;
  String? selectedColor;
  String? selectedDriveType;
  String? selectedSeating;
  String? selectedEngineSize;
  String? selectedCylinderCount;
  String? selectedTitleStatus;
  String? selectedDamagedParts;
  bool errMileage = false;
  bool errCondition = false;
  bool errTransmission = false;
  bool errFuelType = false;
  bool errBodyType = false;
  bool errColor = false;
  bool errDrive = false;
  bool errSeating = false;
  bool errTitle = false;
  bool errDamagedParts = false;
  bool isMileageManualInput = false;
  
  // Focus node for keyboard management
  FocusNode _mileageFocusNode = FocusNode();
  
  @override
  void initState() {
    super.initState();
    _resetStep2();
  }
  
  @override
  void dispose() {
    _mileageFocusNode.dispose();
    super.dispose();
  }
  
  void _resetStep2() {
    selectedMileage = null;
    selectedCondition = null;
    selectedTransmission = null;
    selectedFuelType = null;
    selectedBodyType = null;
    selectedColor = null;
    selectedDriveType = null;
    selectedSeating = null;
    selectedEngineSize = null;
    selectedCylinderCount = null;
    selectedTitleStatus = null;
    selectedDamagedParts = null;
  }
  
  void _dismissKeyboard() {
    // Clear focus from mileage field
    _mileageFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }
  
  final List<String> conditions = ['New', 'Used', 'Certified'];
  final List<String> transmissions = ['Automatic', 'Manual', 'CVT', 'Semi-Automatic'];
  final List<String> fuelTypes = ['Gasoline', 'Diesel', 'Electric', 'Hybrid', 'Plug-in Hybrid'];
  final List<String> bodyTypes = ['Sedan', 'SUV', 'Hatchback', 'Coupe', 'Convertible', 'Wagon', 'Pickup', 'Van', 'Minivan'];
  final List<String> colors = ['Black', 'White', 'Silver', 'Gray', 'Red', 'Blue', 'Green', 'Brown', 'Gold', 'Other'];
  final List<String> driveTypes = ['FWD', 'RWD', 'AWD', '4WD'];
  final List<String> seatings = ['2', '4', '5', '6', '7', '8'];
  final List<String> engineSizes = ['1.0', '1.2', '1.4', '1.6', '1.8', '2.0', '2.2', '2.4', '2.5', '3.0', '3.5', '4.0', '5.0', '6.0'];
  final List<String> cylinderCounts = ['3', '4', '5', '6', '8', '10', '12'];
  final List<String> titleStatuses = ['Clean', 'Damaged'];
  
  // Helpers to mirror search page availability with simple defaults
  List<String> getAvailableBodyTypes() {
    return bodyTypes;
  }
  
  List<String> getAvailableColors() {
    return colors;
  }
  
  // Availability helpers aligned with More Filters (simple pass-throughs here)
  List<String> getAvailableConditions() {
    return conditions;
  }
  List<String> getAvailableTransmissions() {
    return transmissions;
  }
  List<String> getAvailableFuelTypes() {
    return fuelTypes;
  }
  List<String> getAvailableDriveTypes() {
    return driveTypes;
  }
  List<String> getAvailableSeatings() {
    return seatings;
  }
  List<String> getAvailableEngineSizes() {
    return engineSizes;
  }
  List<String> getAvailableCylinderCounts() {
    return cylinderCounts;
  }

  Color _colorFromName(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'silver':
        return Colors.grey[300]!;
      case 'gray':
        return Colors.grey[600]!;
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'brown':
        return Colors.brown;
      case 'beige':
        return const Color(0xFFF5F5DC);
      case 'gold':
        return const Color(0xFFFFD700);
      default:
        return Colors.grey;
    }
  }
  
  Future<String?> _pickFromList(String title, List<String> options) async {
    return await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      pageBuilder: (context, a1, a2) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return Transform.translate(
          offset: Offset(0, (1 - curved.value) * 30),
          child: Opacity(
            opacity: curved.value,
            child: Dialog(
          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 420,
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                    IconButton(icon: Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                SizedBox(height: 10),
                SizedBox(
                  height: 420,
                  child: ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (_, __) => SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final value = options[index];
                      final lowerTitle = title.toLowerCase();
                      String displayText = value;
                      final bool isNumeric = RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(value);
                      if (lowerTitle.contains('price')) {
                        displayText = _formatCurrencyGlobal(context, value);
                      } else if (lowerTitle.contains('mileage') && isNumeric) {
                        final localeTag = Localizations.localeOf(context).toLanguageTag();
                        final nf = _decimalFormatterGlobal(context);
                        displayText = _localizeDigitsGlobal(context, nf.format(num.tryParse(value) ?? 0)) + ' ' + AppLocalizations.of(context)!.unit_km;
                      } else if (lowerTitle.contains('year') && isNumeric) {
                        displayText = _localizeDigitsGlobal(context, value);
                      } else if (lowerTitle.contains('seating') && isNumeric) {
                        displayText = _localizeDigitsGlobal(context, value) + ' seats';
                      } else if (lowerTitle.contains('cylinder') && isNumeric) {
                        displayText = _localizeDigitsGlobal(context, value) + ' cylinders';
                      } else if (lowerTitle.contains('engine') && isNumeric) {
                        displayText = _localizeDigitsGlobal(context, value) + ' L';
                      } else {
                        final translated = _translateValueGlobal(context, value);
                        if (translated != null) displayText = translated;
                      }
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, value),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.02)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(displayText, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                              Icon(Icons.chevron_right, color: Colors.white70),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              ],
                ),
              ),
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.settings, size: 48, color: Color(0xFFFF6B00)),
                  SizedBox(height: 12),
                  Text(
                    'Car Details',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Provide detailed information about your car',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            
             // Mileage (Modal or Manual Input)
             Row(
               children: [
                 Expanded(
                   child: isMileageManualInput
                      ? TextFormField(
                          focusNode: _mileageFocusNode,
                          initialValue: selectedMileage,
                          decoration: InputDecoration(
                            labelText: 'Mileage (km) *',
                            hintText: 'Enter mileage',
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.2),
                            labelStyle: TextStyle(color: Colors.white),
                            hintStyle: TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.red),
                            ),
                          ),
                          style: TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            setState(() {
                              selectedMileage = value.isEmpty ? null : value;
                            });
                          },
                           validator: (value) {
                             if (value == null || value.isEmpty) return 'Please enter mileage';
                             final mileage = int.tryParse(value);
                             if (mileage == null) return 'Invalid mileage';
                             if (mileage < 0) return 'Mileage cannot be negative';
                             return null;
                           },
                         )
                       : FormField<String>(
                           validator: (_) => (selectedMileage == null || selectedMileage!.isEmpty) ? 'Please select mileage' : null,
                           builder: (state) => GestureDetector(
                             onTap: () async {
                               final miles = [
                                 ...[for (int m = 0; m <= 100000; m += 1000) m.toString()],
                                 ...[for (int m = 105000; m <= 300000; m += 5000) m.toString()],
                               ];
                               final choice = await _pickFromList('Mileage (km)', miles);
                               if (choice != null) setState(() => selectedMileage = choice);
                             },
                             child: buildFancySelector(
                               context,
                               icon: Icons.speed,
                               label: 'Mileage (km) *',
                               value: selectedMileage != null
                                   ? (_localizeDigitsGlobal(context, _decimalFormatterGlobal(context).format(int.tryParse(selectedMileage!) ?? 0)) + ' ' + AppLocalizations.of(context)!.unit_km)
                                   : null,
                               isError: errMileage && (selectedMileage == null || selectedMileage!.isEmpty),
                             ),
                           ),
                         ),
                 ),
                 SizedBox(width: 8),
                 IconButton(
                   onPressed: () => setState(() => isMileageManualInput = !isMileageManualInput),
                   icon: Icon(isMileageManualInput ? Icons.list : Icons.edit, color: Color(0xFFFF6B00)),
                   style: IconButton.styleFrom(
                     backgroundColor: Colors.grey.withOpacity(0.1),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                   ),
                   tooltip: isMileageManualInput ? 'Select from list' : 'Type manually',
                 ),
               ],
             ),
            SizedBox(height: 16),
            
            // Condition (Modal)
            FormField<String>(
              validator: (_) => selectedCondition == null ? 'Please select condition' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickFromList('Condition', getAvailableConditions());
                  if (choice != null) setState(() => selectedCondition = choice);
                },
                child: buildFancySelector(context, icon: Icons.check_circle, label: 'Condition *', value: selectedCondition, isError: errCondition && (selectedCondition == null || selectedCondition!.isEmpty)),
              ),
            ),
            SizedBox(height: 16),
            
            // Transmission (Modal)
            FormField<String>(
              validator: (_) => selectedTransmission == null ? 'Please select transmission' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList('Transmission', getAvailableTransmissions());
                  if (choice != null) setState(() => selectedTransmission = choice);
                },
                child: buildFancySelector(context, icon: Icons.settings, label: 'Transmission *', value: selectedTransmission, isError: errTransmission && (selectedTransmission == null || selectedTransmission!.isEmpty)),
              ),
            ),
            SizedBox(height: 16),
            
            // Fuel Type (Modal)
            FormField<String>(
              validator: (_) => selectedFuelType == null ? 'Please select fuel type' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList('Fuel Type', getAvailableFuelTypes());
                  if (choice != null) setState(() => selectedFuelType = choice);
                },
                child: buildFancySelector(context, icon: Icons.local_gas_station, label: 'Fuel Type *', value: selectedFuelType, isError: errFuelType && (selectedFuelType == null || selectedFuelType!.isEmpty)),
              ),
            ),
            SizedBox(height: 16),
            
            // Body Type (Modal - grid like search)
            FormField<String>(
              validator: (_) => selectedBodyType == null ? 'Please select body type' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        child: Container(
                          width: 400,
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(AppLocalizations.of(context)!.selectBodyType, style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                                  IconButton(icon: Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                                ],
                              ),
                              SizedBox(height: 10),
                              SizedBox(
                                height: 300,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: BouncingScrollPhysics(),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 0.82,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                                  itemCount: getAvailableBodyTypes().length,
                                  itemBuilder: (context, index) {
                                    final bodyTypeName = getAvailableBodyTypes()[index];
                                    final asset = _getBodyTypeAsset(bodyTypeName);
                                    final bool isSelected = (selectedBodyType ?? '') == bodyTypeName;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => Navigator.pop(context, bodyTypeName),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: isSelected ? const Color(0xFFFF6B00) : Colors.white24, width: isSelected ? 2 : 1),
                                          boxShadow: isSelected
                                              ? [BoxShadow(color: const Color(0xFFFF6B00).withOpacity(0.35), blurRadius: 14, spreadRadius: 1, offset: const Offset(0, 4))]
                                              : [const BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 0, offset: Offset(0, 3))],
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 56,
                                              height: 56,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white,
                                                border: Border.all(color: isSelected ? const Color(0xFFFF6B00) : Colors.white24, width: isSelected ? 2 : 1),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(8),
                                                child: FittedBox(
                                                  fit: BoxFit.contain,
                                                  child: _buildBodyTypeImage(asset),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _translateValueGlobal(context, bodyTypeName) ?? bodyTypeName,
                                              style: GoogleFonts.orbitron(fontSize: 12, color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold),
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                  if (choice != null) setState(() => selectedBodyType = choice);
                },
                child: buildFancySelector(context, icon: Icons.directions_car, label: 'Body Type *', value: selectedBodyType ?? _tapToSelectTextGlobal(context), isError: errBodyType && (selectedBodyType == null || selectedBodyType!.isEmpty)),
              ),
            ),
            SizedBox(height: 16),
            
            // Color (Modal - swatches like search)
            FormField<String>(
              validator: (_) => selectedColor == null ? AppLocalizations.of(context)!.selectColor : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        child: Container(
                          width: 400,
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(AppLocalizations.of(context)!.selectColor, style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                                  IconButton(icon: Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                                ],
                              ),
                              SizedBox(height: 10),
                              SizedBox(
                                height: 300,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: BouncingScrollPhysics(),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 1.2,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                                  itemCount: getAvailableColors().length,
                                  itemBuilder: (context, index) {
                                    final colorName = getAvailableColors()[index];
                                    final colorValue = _colorFromName(colorName);
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => Navigator.pop(context, colorName),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.white24),
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: colorValue,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.white24, width: 2),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Text(_translateValueGlobal(context, colorName) ?? colorName, style: GoogleFonts.orbitron(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 1),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                  if (choice != null) setState(() => selectedColor = choice);
                },
                child: buildFancySelector(context, icon: Icons.palette, label: 'Color *', value: selectedColor ?? _tapToSelectTextGlobal(context), isError: errColor && (selectedColor == null || selectedColor!.isEmpty)),
              ),
            ),
            SizedBox(height: 16),
            
            // Drive Type (Modal)
            FormField<String>(
              validator: (_) => selectedDriveType == null ? 'Please select drive type' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList('Drive Type', getAvailableDriveTypes());
                  if (choice != null) setState(() => selectedDriveType = choice);
                },
                child: buildFancySelector(context, icon: Icons.directions, label: 'Drive Type *', value: selectedDriveType, isError: errDrive && (selectedDriveType == null || selectedDriveType!.isEmpty)),
              ),
            ),
            SizedBox(height: 16),
            
            // Seating (Modal)
            FormField<String>(
              validator: (_) => selectedSeating == null ? 'Please select seating' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList('Seating', getAvailableSeatings().where((s) => s != 'Any').toList());
                  if (choice != null) setState(() => selectedSeating = choice);
                },
                child: buildFancySelector(context, icon: Icons.people, label: 'Seating *', value: selectedSeating == null ? null : (_localizeDigitsGlobal(context, selectedSeating!) + ' seats'), isError: errSeating && (selectedSeating == null || selectedSeating!.isEmpty)),
              ),
            ),
            SizedBox(height: 16),
            
            // Engine Size (Modal)
            FormField<String>(
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList('Engine Size (L)', getAvailableEngineSizes().where((e) => e != 'Any').toList());
                  if (choice != null) setState(() => selectedEngineSize = choice.replaceAll(' L', ''));
                },
                child: buildFancySelector(context, icon: Icons.engineering, label: 'Engine Size (L)', value: selectedEngineSize == null ? null : (_localizeDigitsGlobal(context, selectedEngineSize!) + ' L')),
              ),
            ),
            SizedBox(height: 16),
            
            // Cylinder Count (Modal)
            FormField<String>(
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList('Cylinder Count', getAvailableCylinderCounts().where((c) => c != 'Any').toList());
                  if (choice != null) setState(() => selectedCylinderCount = choice.replaceAll(' cylinders', ''));
                },
                child: buildFancySelector(context, icon: Icons.settings_input_component, label: 'Cylinder Count', value: selectedCylinderCount == null ? null : (_localizeDigitsGlobal(context, selectedCylinderCount!) + ' cylinders')),
              ),
            ),
            SizedBox(height: 16),
            
            // Title Status (Modal)
            FormField<String>(
              validator: (_) => selectedTitleStatus == null ? AppLocalizations.of(context)!.titleStatus : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(AppLocalizations.of(context)!.titleStatus, titleStatuses);
                  if (choice != null) {
                    setState(() {
                      selectedTitleStatus = choice;
                      if (choice != 'Damaged') selectedDamagedParts = null;
                    });
                  }
                },
                child: buildFancySelector(context, icon: Icons.description, label: AppLocalizations.of(context)!.titleStatus + ' *', value: _translateValueGlobal(context, selectedTitleStatus), isError: errTitle && (selectedTitleStatus == null || (selectedTitleStatus ?? '').isEmpty)),
              ),
            ),
            SizedBox(height: 16),
            
            // Damaged Parts modal
            if ((selectedTitleStatus ?? '').toLowerCase() == 'damaged')
              FormField<String>(
                builder: (state) => GestureDetector(
                  onTap: () async {
                    final nums = List.generate(20, (i) => (i + 1).toString());
                    final choice = await _pickFromList(AppLocalizations.of(context)!.damagedParts, nums);
                    if (choice != null) setState(() => selectedDamagedParts = choice);
                  },
                  child: buildFancySelector(context, icon: Icons.warning, label: AppLocalizations.of(context)!.damagedParts, value: selectedDamagedParts == null ? null : _localizeDigitsGlobal(context, selectedDamagedParts!), isError: errDamagedParts && (selectedDamagedParts == null || selectedDamagedParts!.isEmpty)),
                ),
              ),
            SizedBox(height: 32),
            // Navigation Buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        final parentState = context.findAncestorStateOfType<_SellCarPageState>();
                        if (parentState != null) {
                          parentState._pageController.previousPage(
                            duration: Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Color(0xFFFF6B00)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Previous',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6B00),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        final List<String> missing = [];
                        if (selectedMileage == null || (selectedMileage ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.mileageLabel);
                        if (selectedCondition == null || (selectedCondition ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.conditionLabel);
                        if (selectedTransmission == null || (selectedTransmission ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.transmissionLabel);
                        if (selectedFuelType == null || (selectedFuelType ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.fuelTypeLabel);
                        if (selectedBodyType == null || (selectedBodyType ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.selectBodyType);
                        if (selectedColor == null || (selectedColor ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.selectColor);
                        if (selectedDriveType == null || (selectedDriveType ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.driveType);
                        if (selectedSeating == null || (selectedSeating ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.seating);
                        if (selectedTitleStatus == null || (selectedTitleStatus ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.titleStatus);
                        if ((selectedTitleStatus?.toLowerCase() == 'damaged') && (selectedDamagedParts == null || (selectedDamagedParts ?? '').isEmpty)) missing.add(AppLocalizations.of(context)!.damagedParts);
                        if (missing.isNotEmpty) {
                          setState(() {
                            errMileage = selectedMileage == null || (selectedMileage ?? '').isEmpty;
                            errCondition = selectedCondition == null || (selectedCondition ?? '').isEmpty;
                            errTransmission = selectedTransmission == null || (selectedTransmission ?? '').isEmpty;
                            errFuelType = selectedFuelType == null || (selectedFuelType ?? '').isEmpty;
                            errBodyType = selectedBodyType == null || (selectedBodyType ?? '').isEmpty;
                            errColor = selectedColor == null || (selectedColor ?? '').isEmpty;
                            errDrive = selectedDriveType == null || (selectedDriveType ?? '').isEmpty;
                            errSeating = selectedSeating == null || (selectedSeating ?? '').isEmpty;
                            errTitle = selectedTitleStatus == null || (selectedTitleStatus ?? '').isEmpty;
                            errDamagedParts = (selectedTitleStatus?.toLowerCase() == 'damaged') && (selectedDamagedParts == null || (selectedDamagedParts ?? '').isEmpty);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(_pleaseFillRequiredGlobal(context) + ': ' + missing.join(', ')), backgroundColor: Colors.red),
                          );
                          return;
                        }
                          final parentState = context.findAncestorStateOfType<_SellCarPageState>();
                          if (parentState != null) {
                            parentState.carData['mileage'] = selectedMileage;
                            parentState.carData['condition'] = selectedCondition;
                            parentState.carData['transmission'] = selectedTransmission;
                            parentState.carData['fuel_type'] = selectedFuelType;
                            parentState.carData['body_type'] = selectedBodyType;
                            parentState.carData['color'] = selectedColor;
                            parentState.carData['drive_type'] = selectedDriveType;
                            parentState.carData['seating'] = selectedSeating;
                            parentState.carData['engine_size'] = selectedEngineSize;
                            parentState.carData['cylinder_count'] = selectedCylinderCount;
                            parentState.carData['title_status'] = selectedTitleStatus;
                            parentState.carData['damaged_parts'] = selectedDamagedParts;
                          setState(() { errMileage = errCondition = errTransmission = errFuelType = errBodyType = errColor = errDrive = errSeating = errTitle = errDamagedParts = false; });
                          parentState._pageController.nextPage(duration: Duration(milliseconds: 300), curve: Curves.easeInOut);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFFF6B00),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        'Next Step',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Step 3: Pricing & Contact Information
class SellStep3Page extends StatefulWidget {
  @override
  _SellStep3PageState createState() => _SellStep3PageState();
}

class _SellStep3PageState extends State<SellStep3Page> {
  final _formKey = GlobalKey<FormState>();
  String? selectedPrice;
  String? selectedCity;
  String? contactPhone;
  bool isQuickSell = false;
  bool isPriceManualInput = false;
  String selectedCurrency = 'USD';
  
  // Focus node for keyboard management
  FocusNode _priceFocusNode = FocusNode();
  
  // Currency conversion method
  String _convertCurrency(String price, String fromCurrency, String toCurrency) {
    if (price.isEmpty) return price;
    
    // Extract numeric value from price string
    String numericValue = price.replaceAll(RegExp(r'[^\d.]'), '');
    double value = double.tryParse(numericValue) ?? 0;
    
    if (value == 0) return price;
    
    double convertedValue;
    
    if (fromCurrency == 'USD' && toCurrency == 'IQD') {
      // Convert USD to IQD: 1 USD = 1420 IQD
      convertedValue = value * 1420;
    } else if (fromCurrency == 'IQD' && toCurrency == 'USD') {
      // Convert IQD to USD: 1 IQD = 1/1420 USD
      convertedValue = value / 1420;
    } else {
      // Same currency, no conversion needed
      return price;
    }
    
    // Format the converted value
    if (toCurrency == 'IQD') {
      return 'IQD ${convertedValue.toStringAsFixed(0)}';
    } else {
      return '\$${convertedValue.toStringAsFixed(0)}';
    }
  }
  
  @override
  void initState() {
    super.initState();
    _resetStep3();
  }
  
  @override
  void dispose() {
    _priceFocusNode.dispose();
    super.dispose();
  }
  
  void _resetStep3() {
    selectedPrice = null;
    selectedCity = null;
    contactPhone = null;
    isQuickSell = false;
    selectedCurrency = 'USD';
  }
  
  void _dismissKeyboard() {
    // Clear focus from all number input fields
    _priceFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }
  
  Widget _buildCurrencyButton(String currency, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedCurrency = currency;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFFF6B00) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          currency,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
  
  final List<String> cities = [
    'Baghdad', 'Basra', 'Mosul', 'Erbil', 'Najaf', 'Karbala', 'Sulaymaniyah', 
    'Kirkuk', 'Nasiriyah', 'Amara', 'Ramadi', 'Fallujah', 'Tikrit', 'Samarra'
  ];
  
  Future<String?> _pickFromList(String title, List<String> options) async {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 420,
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                    IconButton(icon: Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                SizedBox(height: 10),
                SizedBox(
                  height: 420,
                  child: ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (_, __) => SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final value = options[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, value),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.02)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                              Icon(Icons.chevron_right, color: Colors.white70),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.attach_money, size: 48, color: Color(0xFFFF6B00)),
                  SizedBox(height: 12),
                  Text(
                    'Pricing & Contact',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Set your price and contact information',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            
            // Price (Modal or Manual Input)
            Column(
              children: [
                Row(
                  children: [
                Expanded(
                  child: isPriceManualInput
                      ? TextFormField(
                          focusNode: _priceFocusNode,
                          initialValue: selectedPrice,
                          decoration: InputDecoration(
                            labelText: 'Price ($selectedCurrency) *',
                            hintText: 'Enter price',
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.2),
                            labelStyle: TextStyle(color: Colors.white),
                            hintStyle: TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.red),
                            ),
                          ),
                          style: TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            setState(() {
                              selectedPrice = value.isEmpty ? null : value;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Please enter price';
                            final price = int.tryParse(value);
                            if (price == null) return 'Invalid price';
                            if (price < 0) return 'Price cannot be negative';
                            return null;
                          },
                        )
                      : FormField<String>(
              validator: (_) => (selectedPrice == null || selectedPrice!.isEmpty) ? 'Please select price' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final priceOptions = selectedCurrency == 'IQD' 
                    ? [
                        ...List.generate(200, (i) => (500000 + i * 500000).toString()),
                        ...List.generate(100, (i) => (100000000 + (i + 1) * 1000000).toString()),
                      ].map((p) => 'IQD ' + p).toList()
                    : [
                        ...List.generate(600, (i) => (500 + i * 500).toString()),
                        ...List.generate(171, (i) => (300000 + (i + 1) * 10000).toString()),
                      ].map((p) => '\$' + p).toList();
                  final choice = await _pickFromList('Price ($selectedCurrency)', priceOptions);
                  if (choice != null) setState(() => selectedPrice = choice);
                },
                child: buildFancySelector(
                  context,
                  icon: selectedCurrency == 'IQD' ? Icons.currency_exchange : Icons.attach_money,
                  label: 'Price ($selectedCurrency) *',
                  value: selectedPrice != null ? _formatCurrencyGlobal(context, selectedPrice) : null,
                ),
              ),
                        ),
                ),
                SizedBox(width: 8),
                // Currency Selector button (styled like pencil button)
                IconButton(
                  onPressed: () {
                    setState(() {
                      // Convert price when switching currency
                      if (selectedPrice != null && selectedPrice!.isNotEmpty) {
                        String convertedPrice = _convertCurrency(selectedPrice!, selectedCurrency, selectedCurrency == 'USD' ? 'IQD' : 'USD');
                        selectedPrice = convertedPrice;
                      }
                      selectedCurrency = selectedCurrency == 'USD' ? 'IQD' : 'USD';
                    });
                  },
                  icon: Text(
                    selectedCurrency,
                    style: TextStyle(
                      color: Color(0xFFFF6B00),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  tooltip: 'Switch to ${selectedCurrency == 'USD' ? 'IQD' : 'USD'}',
                ),
                SizedBox(width: 8),
                // Pencil button
                IconButton(
                  onPressed: () => setState(() => isPriceManualInput = !isPriceManualInput),
                  icon: Icon(isPriceManualInput ? Icons.list : Icons.edit, color: Color(0xFFFF6B00)),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  tooltip: isPriceManualInput ? 'Select from list' : 'Type manually',
                ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),
            
            // City (Modal)
            FormField<String>(
              validator: (_) => selectedCity == null ? 'Please select city' : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickFromList('City', cities);
                  if (choice != null) setState(() => selectedCity = choice);
                },
                child: buildFancySelector(context, icon: Icons.location_city, label: 'City *', value: selectedCity),
              ),
            ),
            SizedBox(height: 16),
            
            // Contact Phone
            TextFormField(
              onTap: () => _dismissKeyboard(),
              decoration: InputDecoration(
                labelText: 'WhatsApp/Phone Number *',
                hintText: '+964 7XX XXX XXXX',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.phone, color: Color(0xFFFF6B00)),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                services.FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                services.LengthLimitingTextInputFormatter(20),
              ],
              onChanged: (value) => contactPhone = value,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Please enter phone number';
                final s = value.trim();
                final bool looksOk = s.startsWith('+') ? RegExp(r'^\+\d{7,}$').hasMatch(s) : RegExp(r'^\d{7,}$').hasMatch(s);
                if (!looksOk) return 'Please use international format';
                return null;
              },
            ),
            SizedBox(height: 24),
            
            // Quick Sell Option
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.flash_on, color: Colors.orange, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Sell',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        Text(
                          'Make your listing stand out with a special banner',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isQuickSell,
                    onChanged: (value) {
                      setState(() {
                        isQuickSell = value;
                      });
                    },
                    activeColor: Colors.orange,
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),
            
            // Navigation Buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        final parentState = context.findAncestorStateOfType<_SellCarPageState>();
                        if (parentState != null) {
                          parentState._pageController.previousPage(
                            duration: Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Color(0xFFFF6B00)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Previous',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6B00),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        final List<String> missing = [];
                        if (selectedPrice == null || (selectedPrice ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.priceLabel);
                        if (selectedCity == null || (selectedCity ?? '').isEmpty) missing.add(AppLocalizations.of(context)!.cityLabel);
                        if (contactPhone == null || (contactPhone ?? '').trim().isEmpty) missing.add('Phone');
                        if (missing.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(_pleaseFillRequiredGlobal(context) + ': ' + missing.join(', ')), backgroundColor: Colors.red),
                          );
                          return;
                        }
                          final parentState = context.findAncestorStateOfType<_SellCarPageState>();
                          if (parentState != null) {
                            parentState.carData['price'] = selectedPrice;
                            parentState.carData['city'] = selectedCity;
                            parentState.carData['contact_phone'] = contactPhone;
                            parentState.carData['is_quick_sell'] = isQuickSell;
                          parentState._pageController.nextPage(duration: Duration(milliseconds: 300), curve: Curves.easeInOut);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFFF6B00),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        'Next Step',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Step 4: Photos & Videos
class SellStep4Page extends StatefulWidget {
  @override
  _SellStep4PageState createState() => _SellStep4PageState();
}
class _SellStep4PageState extends State<SellStep4Page> {
  final ImagePicker _imagePicker = ImagePicker();
  List<XFile> _selectedImages = [];
  List<XFile> _selectedVideos = [];
  
  Future<void> _pickImages() async {
    try {
      final files = await _imagePicker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
      if (files.isNotEmpty) {
        setState(() {
          _selectedImages = files;
        });
      }
    } catch (_) {}
  }
  
  Future<void> _pickVideos() async {
    try {
      final file = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: Duration(minutes: 5),
      );
      if (file != null) {
        setState(() {
          _selectedVideos.add(file);
        });
      }
    } catch (_) {}
  }
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Icon(Icons.photo_library, size: 48, color: Color(0xFFFF6B00)),
                SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context)!.addPhotos,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.addMorePhotos,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          
          // Photos Section
          Text(_photosRequiredTitleGlobal(context), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          SizedBox(height: 12),
          if (_selectedImages.isNotEmpty)
            Container(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                itemBuilder: (context, index) {
                  final image = _selectedImages[index];
                  return Container(
                    margin: EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.file(File(image.path), fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedImages.removeAt(index);
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pickImages,
              icon: Icon(Icons.photo_library),
              label: Text(_selectedImages.isEmpty ? 'Add Photos' : 'Add More Photos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.withOpacity(0.2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          SizedBox(height: 24),
          
          // Videos Section
          Text(_videosOptionalTitleGlobal(context), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          SizedBox(height: 12),
          if (_selectedVideos.isNotEmpty)
            Container(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedVideos.length,
                itemBuilder: (context, index) {
                  final video = _selectedVideos[index];
                  return Container(
                    margin: EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Container(
                                color: Colors.grey[800],
                                child: Center(
                                  child: Icon(Icons.videocam, color: Colors.white, size: 32),
                                ),
                              ),
                              Center(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.play_arrow, color: Colors.white, size: 24),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedVideos.removeAt(index);
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pickVideos,
              icon: Icon(Icons.videocam),
              label: Text(_selectedVideos.isEmpty ? 'Add Videos' : 'Add More Videos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.withOpacity(0.2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          SizedBox(height: 32),
          
          // Navigation Buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () {
                      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
                      if (parentState != null) {
                        parentState._pageController.previousPage(
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Color(0xFFFF6B00)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Previous',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFF6B00),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_selectedImages.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_pleaseSelectPhotoTextGlobal(context)),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      
                      // Save data and navigate to next step
                      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
                      if (parentState != null) {
                        parentState.carData['images'] = _selectedImages;
                        parentState.carData['videos'] = _selectedVideos;
                        
                        parentState._pageController.nextPage(
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF6B00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      'Next Step',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Step 5: Review & Submit
class SellStep5Page extends StatefulWidget {
  @override
  _SellStep5PageState createState() => _SellStep5PageState();
}

class _SellStep5PageState extends State<SellStep5Page> {
  bool isSubmitting = false;
  
  @override
  Widget build(BuildContext context) {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final carData = parentState?.carData ?? {};
    
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Icon(Icons.check_circle, size: 48, color: Color(0xFFFF6B00)),
                SizedBox(height: 12),
                Text(
                  'Review & Submit',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Review your listing before submitting',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          
          // Car Summary
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Car Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 12),
                _buildSummaryRow('Brand', carData['brand']),
                _buildSummaryRow('Model', carData['model']),
                _buildSummaryRow('Trim', carData['trim']),
                _buildSummaryRow('Year', carData['year']),
                _buildSummaryRow('Mileage', '${carData['mileage']} km'),
                _buildSummaryRow('Condition', carData['condition']),
                _buildSummaryRow('Transmission', carData['transmission']),
                _buildSummaryRow('Fuel Type', carData['fuel_type']),
                _buildSummaryRow('Body Type', carData['body_type']),
                _buildSummaryRow('Color', carData['color']),
                _buildSummaryRow('Price', '\$${carData['price']}'),
                _buildSummaryRow('City', carData['city']),
                _buildSummaryRow('Contact', carData['contact_phone']),
                if (carData['is_quick_sell'] == true)
                  _buildSummaryRow('Quick Sell', 'Enabled', isHighlight: true),
              ],
            ),
          ),
          SizedBox(height: 24),
          
          // Photos Summary
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Media',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 12),
                _buildSummaryRow('Photos', '${carData['images']?.length ?? 0} selected'),
                _buildSummaryRow('Videos', '${carData['videos']?.length ?? 0} selected'),
              ],
            ),
          ),
          SizedBox(height: 32),
          
          // Navigation Buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: isSubmitting ? null : () {
                      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
                      if (parentState != null) {
                        parentState._pageController.previousPage(
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Color(0xFFFF6B00)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Previous',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFF6B00),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isSubmitting ? null : () async {
                      setState(() {
                        isSubmitting = true;
                      });
                      
                      try {
                        // Client-side validation before submit
                        final parentState = context.findAncestorStateOfType<_SellCarPageState>();
                        final Map<String, dynamic> carData = Map<String, dynamic>.from(parentState?.carData ?? {});
                        final List<String> required = [
                          'brand','model','trim','year','mileage','condition','transmission','fuel_type','color','body_type','seating','drive_type','title_status'
                        ];
                        final List<String> missing = [];
                        for (final k in required) {
                          final v = carData[k];
                          final isEmpty = v == null || (v is String && v.trim().isEmpty);
                          if (isEmpty) missing.add(k);
                        }
                        if (missing.isNotEmpty) {
                          final stepFor = (String k) {
                            const step1 = {'brand','model','trim','year'};
                            const step2 = {'mileage','condition','transmission','fuel_type','color','body_type','seating','drive_type','title_status'};
                            if (step1.contains(k)) return 1;
                            if (step2.contains(k)) return 2;
                            return 3;
                          };
                          final first = missing.first;
                          final targetStep = stepFor(first);
                          // Navigate user to the step containing the first missing field
                          if (parentState != null) {
                            parentState._pageController.jumpToPage(targetStep - 1);
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Please complete: ' + missing.join(', ')),
                              backgroundColor: Colors.red,
                            ),
                          );
                          setState(() { isSubmitting = false; });
                          return;
                        }
                        // Submit the listing
                        await _submitListing(carData);
                        
                        // Show success message
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_listingSubmittedSuccessTextGlobal(context)),
                            backgroundColor: Colors.green,
                          ),
                        );
                        
                        // Navigate back to home
                        Navigator.pushReplacementNamed(context, '/');
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              (e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString()).isEmpty
                                  ? AppLocalizations.of(context)!.couldNotSubmitListing
                                  : (e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString()),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        setState(() {
                          isSubmitting = false;
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF6B00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: isSubmitting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Submit Listing',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryRow(String label, String? value, {bool isHighlight = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'Not specified',
              style: TextStyle(
                color: isHighlight ? Colors.orange : Colors.grey[800],
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _submitListing(Map<String, dynamic> carData) async {
    // Require authentication before allowing submission
    final existingToken = ApiService.accessToken;
    if (existingToken == null || existingToken.isEmpty) {
      throw Exception('Authentication required');
    }

    final brand = carData['brand']?.toString() ?? '';
    final model = carData['model']?.toString() ?? '';
    final trim = carData['trim']?.toString() ?? 'Base';
    final year = int.tryParse(carData['year']?.toString() ?? '') ?? DateTime.now().year;
    final mileage = int.tryParse(carData['mileage']?.toString() ?? '0') ?? 0;
    final condition = (carData['condition']?.toString() ?? 'Used').toLowerCase();
    final transmission = (carData['transmission']?.toString() ?? 'Automatic').toLowerCase();
    final fuelType = (carData['fuel_type']?.toString() ?? 'Gasoline').toLowerCase();
    final color = (carData['color']?.toString() ?? 'Black').toLowerCase();
    final bodyType = (carData['body_type']?.toString() ?? 'Sedan').toLowerCase();
    final seating = int.tryParse(carData['seating']?.toString() ?? '5') ?? 5;
    final driveType = (carData['drive_type']?.toString() ?? 'fwd').toLowerCase();
    final titleStatus = (carData['title_status']?.toString() ?? 'clean').toLowerCase();
    final damagedParts = titleStatus == 'damaged' ? int.tryParse(carData['damaged_parts']?.toString() ?? '') : null;
    final cylinderCount = int.tryParse(carData['cylinder_count']?.toString() ?? '');
    final engineSize = double.tryParse(carData['engine_size']?.toString() ?? '');
    final price = int.tryParse(carData['price']?.toString() ?? '');
    final city = (carData['city']?.toString() ?? 'Baghdad').toLowerCase();
    final title = '$brand $model $trim'.trim();

    final payload = {
      'title': title,
      'brand': brand.toLowerCase().replaceAll(' ', '-'),
      'model': model,
      'trim': trim,
      'year': year,
      'price': price,
      'mileage': mileage,
      'condition': condition,
      'transmission': transmission,
      'fuel_type': fuelType,
      'color': color,
      'body_type': bodyType,
      'seating': seating,
      'drive_type': driveType,
      'title_status': titleStatus,
      'damaged_parts': damagedParts,
      'cylinder_count': cylinderCount,
      'engine_size': engineSize,
      'city': city,
      'contact_phone': (carData['contact_phone']?.toString() ?? '').trim(),
      'is_quick_sell': carData['is_quick_sell'] ?? false,
    };

    try {
      final url = Uri.parse(getApiBase() + '/cars');
      final headers = {
        'Content-Type': 'application/json',
        if (existingToken != null) 'Authorization': 'Bearer $existingToken',
      };

      final response = await http.post(
        url,
        headers: headers,
        body: json.encode(payload),
      );

      if (response.statusCode == 201) {
        // Success - listing created
        final Map<String, dynamic> created = json.decode(response.body);
        final int carId = created['id'];
        // Upload images if any were selected in the form flow
        try {
          final dynamic maybeImgs = carData['images'];
          final List<dynamic> imgs = (maybeImgs is List) ? maybeImgs : const [];
          if (imgs.isNotEmpty) {
            final uploadUrl = Uri.parse(getApiBase() + '/api/cars/' + carId.toString() + '/images');
            final request = http.MultipartRequest('POST', uploadUrl);
            final tok = ApiService.accessToken;
            if (tok != null) request.headers['Authorization'] = 'Bearer ' + tok;
            for (final dynamic img in imgs) {
              try {
                String? path;
                if (img is XFile) {
                  path = img.path;
                } else if (img is String) {
                  path = img;
                }
                if (path != null && path.isNotEmpty) {
                  request.files.add(await http.MultipartFile.fromPath('image', path));
                }
              } catch (_) {}
            }
            final uploadResp = await request.send();
            if (uploadResp.statusCode != 201) {
              final uploadHttpResp = await http.Response.fromStream(uploadResp);
              throw Exception('Image upload failed: ' + uploadResp.statusCode.toString() + ' ' + uploadHttpResp.body);
            }
          }
        } catch (_) {}
        print('Listing created successfully');
        return;
      } else if (response.statusCode == 401) {
        print('Submission failed: Authentication failed');
        throw Exception('Authentication failed. Please log in again.');
      } else {
        print('Submission failed: ${response.statusCode} - ${response.body}');
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to create listing');
      }
    } catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('HandshakeException')) {
        throw Exception('Network error. Please check your connection.');
      }
      rethrow;
    }
  }
}
// Car Comparison Page
class CarComparisonPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.specificationsLabel),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: () async {
              try {
                final store = Provider.of<CarComparisonStore>(context, listen: false);
                final cars = store.comparisonCars;
                final text = cars.map((c) => '${c['title'] ?? ''} â€¢ ${c['year'] ?? ''} â€¢ ${c['price'] ?? ''}').join('\n');
                if (text.trim().isNotEmpty) Share.share(text);
              } catch (_) {}
            },
            icon: Icon(Icons.share_outlined),
          ),
          Consumer<CarComparisonStore>(
            builder: (context, comparisonStore, child) {
              if (comparisonStore.comparisonCount > 0) {
                return TextButton(
                  onPressed: () {
                    comparisonStore.clearComparison();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!.clearFilters),
                        backgroundColor: Color(0xFFFF6B00),
                      ),
                    );
                  },
                  child: Text(
                    AppLocalizations.of(context)!.clearFilters,
                    style: TextStyle(color: Colors.white),
                  ),
                );
              }
              return SizedBox.shrink();
            },
          ),
          const ThemeToggleWidget(),
          buildLanguageMenu(),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F1115), Color(0xFF131722), Color(0xFF0F1115)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Consumer<CarComparisonStore>(
        builder: (context, comparisonStore, child) {
          final cars = comparisonStore.comparisonCars;
          final double columnWidth = 260.0;
          
          if (cars.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.compare_arrows,
                    size: 84,
                    color: Colors.white24,
                  ),
                  SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.noCarsFound,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.tapToSelectBrand,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/'),
                    icon: Icon(Icons.search),
                    label: Text(AppLocalizations.of(context)!.navHome),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF6B00),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            );
          }
          
          return ListView(
            padding: EdgeInsets.all(16),
            children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.compare_arrows, color: Color(0xFFFF6B00), size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.specificationsLabel,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${AppLocalizations.of(context)!.sortBy}: ${cars.length}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                            SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Color(0xFFFF6B00)),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  onPressed: () {
                                    Navigator.pushReplacementNamed(context, '/');
                                  },
                                  icon: Icon(Icons.add, color: Color(0xFFFF6B00), size: 18),
                                  label: Text(AppLocalizations.of(context)!.addMorePhotos),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.white24),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  onPressed: () {
                                    Provider.of<CarComparisonStore>(context, listen: false).clearComparison();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(_comparisonClearedTextGlobal(context)),
                                        backgroundColor: Color(0xFFFF6B00),
                                      ),
                                    );
                                  },
                                  icon: Icon(Icons.delete_outline, color: Colors.white70, size: 18),
                                  label: Text(_clearAllTextGlobal(context)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                
                // Comparison Table
                LayoutBuilder(
                  builder: (context, constraints) {
                    final double labelWidth = 120.0;
                    final double horizontalPadding = 32.0; // padding inside row containers
                    final bool isTwoCars = cars.length == 2;
                    final double availableWidth = constraints.maxWidth;
                    final double effectiveRowWidth = availableWidth - horizontalPadding;
                    final int numColumns = cars.isEmpty ? 1 : cars.length;
                    final double baseColumnWidth = (effectiveRowWidth - labelWidth) / numColumns;
                    final double columnWidth = isTwoCars
                        ? (baseColumnWidth < 96.0 ? 96.0 : baseColumnWidth)
                        : baseColumnWidth.clamp(120.0, 260.0).toDouble();
                    final double requiredWidth = labelWidth + (numColumns * columnWidth) + horizontalPadding;
                    final double tableWidth = requiredWidth > availableWidth ? requiredWidth : availableWidth;
                    final double imageSize = isTwoCars ? ((columnWidth - 16).clamp(88.0, 120.0)).toDouble() : 120.0;
                    final double headerTitleHeight = 36.0;
                    final double headerPriceHeight = 22.0;

                    final table = Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 16,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Car Headers
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: Color(0xFFFF6B00).withOpacity(0.12),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            child: Row(
                              mainAxisAlignment: isTwoCars ? MainAxisAlignment.center : MainAxisAlignment.start,
                              children: isTwoCars
                                  ? [
                                      // Left car
                                      SizedBox(
                                        width: columnWidth,
                                        child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8),
                                        child: Column(
                                          children: [
                                            Container(
                                              height: imageSize,
                                              width: imageSize,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.white10),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: _buildCarImage(cars[0]),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            SizedBox(
                                              height: headerTitleHeight,
                                              child: Center(
                                                child: Text(
                                                  cars[0]['title'] ?? '',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            SizedBox(
                                              height: headerPriceHeight,
                                              child: Center(
                                                child: Text(
                                                  _formatCurrencyGlobal(context, cars[0]['price']?.toString() ?? '0'),
                                                  style: TextStyle(
                                                    color: Color(0xFFFF6B00),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            IconButton(
                                              onPressed: () {
                                                comparisonStore.removeCarFromComparison(cars[0]['id']);
                                              },
                                              icon: Icon(Icons.close, color: Colors.red, size: 24),
                                              constraints: BoxConstraints(),
                                              padding: EdgeInsets.zero,
                                            ),
                                          ],
                                        ),
                                        ),
                                      ),
                                      // Middle spacer for labels
                                      SizedBox(width: labelWidth),
                                      // Right car
                                      SizedBox(
                                        width: columnWidth,
                                        child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8),
                                        child: Column(
                                          children: [
                                            Container(
                                              height: imageSize,
                                              width: imageSize,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.white10),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: _buildCarImage(cars[1]),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            SizedBox(
                                              height: headerTitleHeight,
                                              child: Center(
                                                child: Text(
                                                  cars[1]['title'] ?? '',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            SizedBox(
                                              height: headerPriceHeight,
                                              child: Center(
                                                child: Text(
                                                  _formatCurrencyGlobal(context, cars[1]['price']?.toString() ?? '0'),
                                                  style: TextStyle(
                                                    color: Color(0xFFFF6B00),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            IconButton(
                                              onPressed: () {
                                                comparisonStore.removeCarFromComparison(cars[1]['id']);
                                              },
                                              icon: Icon(Icons.close, color: Colors.red, size: 24),
                                              constraints: BoxConstraints(),
                                              padding: EdgeInsets.zero,
                                            ),
                                          ],
                                        ),
                                        ),
                                      ),
                                    ]
                                  : [
                                      SizedBox(width: labelWidth), // Space for property names
                                      ...cars.map((car) => SizedBox(
                                        width: columnWidth,
                                        child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8),
                                        child: Column(
                                          children: [
                                            Container(
                                              height: 110,
                                              width: 110,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.white10),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: _buildCarImage(car),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            SizedBox(
                                              height: headerTitleHeight,
                                              child: Center(
                                                child: Text(
                                                  car['title'] ?? '',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            SizedBox(
                                              height: headerPriceHeight,
                                              child: Center(
                                                child: Text(
                                                  _formatCurrencyGlobal(context, car['price']?.toString() ?? '0'),
                                                  style: TextStyle(
                                                    color: Color(0xFFFF6B00),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            IconButton(
                                              onPressed: () {
                                                comparisonStore.removeCarFromComparison(car['id']);
                                              },
                                              icon: Icon(Icons.close, color: Colors.red, size: 24),
                                              constraints: BoxConstraints(),
                                              padding: EdgeInsets.zero,
                                            ),
                                          ],
                                        ),
                                        ),
                                      )).toList(),
                                    ],
                            ),
                          ),
                          SizedBox(height: 12),

                          // Comparison Rows
                          ..._buildComparisonRows(context, cars, columnWidth, labelWidth),
                        ],
                      ),
                    );

                    if (isTwoCars) {
                      return SizedBox(
                        width: availableWidth,
                        child: table,
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: BouncingScrollPhysics(),
                      child: SizedBox(
                        width: tableWidth,
                        child: table,
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
        ],
      ),
    );
  }
  
  Widget _buildCarImage(Map<String, dynamic> car) {
    final imageUrl = car['image_url']?.toString();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: '${getApiBase()}/static/uploads/$imageUrl',
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.white10),
        errorWidget: (context, url, error) => Container(
          color: Colors.white10,
          child: Icon(Icons.directions_car, color: Colors.white24),
        ),
      );
    }
    return Container(
      color: Colors.white10,
      child: Icon(Icons.directions_car, color: Colors.white24),
    );
  }
  
  List<Widget> _buildComparisonRows(BuildContext context, List<Map<String, dynamic>> cars, double columnWidth, double labelWidth) {
    final sections = [
      {
        'title': AppLocalizations.of(context)!.brandLabel,
        'icon': Icons.info_outline,
        'rows': [
          {'label': AppLocalizations.of(context)!.brandLabel, 'key': 'brand', 'icon': Icons.directions_car},
          {'label': AppLocalizations.of(context)!.modelLabel, 'key': 'model', 'icon': Icons.badge_outlined},
          {'label': AppLocalizations.of(context)!.trimLabel, 'key': 'trim', 'icon': Icons.layers},
          {'label': AppLocalizations.of(context)!.yearLabel, 'key': 'year', 'icon': Icons.calendar_today},
          {'label': AppLocalizations.of(context)!.cityLabel, 'key': 'city', 'icon': Icons.location_city},
          {'label': AppLocalizations.of(context)!.priceLabel, 'key': 'price', 'icon': Icons.attach_money},
        ],
      },
      {
        'title': AppLocalizations.of(context)!.specificationsLabel,
        'icon': Icons.speed,
        'rows': [
          {'label': AppLocalizations.of(context)!.mileageLabel, 'key': 'mileage', 'suffix': ' ${AppLocalizations.of(context)!.unit_km}', 'icon': Icons.speed},
          {'label': AppLocalizations.of(context)!.engineSizeL, 'key': 'engine_size', 'suffix': AppLocalizations.of(context)!.unit_liter_suffix, 'icon': Icons.settings},
          {'label': AppLocalizations.of(context)!.detail_cylinders, 'key': 'cylinder_count', 'suffix': '', 'icon': Icons.precision_manufacturing},
          {'label': AppLocalizations.of(context)!.seating, 'key': 'seating', 'suffix': '', 'icon': Icons.event_seat},
        ],
      },
      {
        'title': AppLocalizations.of(context)!.moreFilters,
        'icon': Icons.tune,
        'rows': [
          {'label': AppLocalizations.of(context)!.detail_condition, 'key': 'condition', 'icon': Icons.verified},
          {'label': AppLocalizations.of(context)!.transmissionLabel, 'key': 'transmission', 'icon': Icons.settings_suggest},
          {'label': AppLocalizations.of(context)!.detail_fuel, 'key': 'fuel_type', 'icon': Icons.local_gas_station},
          {'label': AppLocalizations.of(context)!.detail_body, 'key': 'body_type', 'icon': Icons.directions_car_filled},
          {'label': AppLocalizations.of(context)!.driveType, 'key': 'drive_type', 'icon': Icons.all_inclusive},
          {'label': AppLocalizations.of(context)!.detail_color, 'key': 'color', 'icon': Icons.color_lens},
        ],
      },
      {
        'title': _statusTitleGlobal(context),
        'icon': Icons.assignment_turned_in,
        'rows': [
          {'label': AppLocalizations.of(context)!.titleStatus, 'key': 'title_status', 'icon': Icons.assignment},
          {'label': AppLocalizations.of(context)!.damagedParts, 'key': 'damaged_parts', 'suffix': '', 'icon': Icons.build},
          {'label': _quickSellTextGlobal(context), 'key': 'is_quick_sell', 'isBoolean': true, 'icon': Icons.flash_on},
          {'label': _ownersLabelGlobal(context), 'key': 'owners', 'icon': Icons.person_outline},
          {'label': _vinLabelGlobal(context), 'key': 'vin', 'icon': Icons.qr_code_2},
          {'label': _accidentHistoryLabelGlobal(context), 'key': 'accident_history', 'icon': Icons.report_gmailerrorred},
        ],
      },
    ];

    final List<Widget> out = [];
    for (int s = 0; s < sections.length; s++) {
      final section = sections[s] as Map<String, dynamic>;
      out.add(Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        margin: EdgeInsets.only(top: s == 0 ? 0 : 16),
        decoration: BoxDecoration(
          color: Color(0xFFFF6B00).withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (section['icon'] is IconData)
              Icon(section['icon'] as IconData, color: Color(0xFFFF6B00), size: 18)
            else
              Icon(Icons.toc, color: Color(0xFFFF6B00), size: 18),
            SizedBox(width: 8),
            Text(
              section['title'].toString(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ));

      final List rows = section['rows'] as List;
      for (int i = 0; i < rows.length; i++) {
        final property = Map<String, dynamic>.from(rows[i] as Map);
        final bool isOdd = i % 2 == 1;
        out.add(Container(
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: isOdd ? Colors.white.withOpacity(0.02) : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: Colors.white12),
            ),
          ),
          child: Row(
            mainAxisAlignment: cars.length == 2 ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (cars.length == 2) ...[
                SizedBox(
                  width: columnWidth,
                  child: _buildCellValue(context, cars[0], property),
                ),
                SizedBox(
                  width: labelWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (rows[i]['icon'] is IconData)
                        Icon(rows[i]['icon'] as IconData, color: Colors.white54, size: 16)
                      else
                        Icon(Icons.label_outline, color: Colors.white54, size: 16),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          property['label']!.toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: columnWidth,
                  child: _buildCellValue(context, cars[1], property),
                ),
              ] else ...[
                SizedBox(
                  width: labelWidth,
                  child: Row(
                    children: [
                      if (rows[i]['icon'] is IconData)
                        Icon(rows[i]['icon'] as IconData, color: Colors.white54, size: 16)
                      else
                        Icon(Icons.label_outline, color: Colors.white54, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          property['label']!.toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: cars.map((car) => SizedBox(
                      width: columnWidth,
                      child: _buildCellValue(context, car, property),
                    )).toList(),
                  ),
                ),
              ],
            ],
          ),
        ));
      }
    }
    return out;
  }

  Widget _buildCellValue(BuildContext context, Map<String, dynamic> car, Map<String, dynamic> property) {
    final text = _formatPropertyValue(context, car, property);
    final isBool = property['isBoolean'] == true || property['isBoolean'] == 'true';
    if (isBool) {
      final boolVal = text.toLowerCase() == 'yes';
      return Align(
        alignment: Alignment.center,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: boolVal ? Colors.green.withOpacity(0.18) : Colors.red.withOpacity(0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: boolVal ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3)),
          ),
          child: Text(
            boolVal ? _yesTextGlobal(context) : _noTextGlobal(context),
            style: TextStyle(
              color: boolVal ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      textAlign: TextAlign.center,
    );
  }
  
  String _formatPropertyValue(BuildContext context, Map<String, dynamic> car, Map<String, dynamic> property) {
    final key = property['key']!;
    final value = car[key];
    
    if (value == null) return '-';
    if (key == 'price') {
      return _formatCurrencyGlobal(context, value);
    }
    
    if (property['isBoolean'] == true || property['isBoolean'] == 'true') {
      return value == true || value == 'true' ? _yesTextGlobal(context) : _noTextGlobal(context);
    }
    
    final suffix = property['suffix'] ?? '';
    final String raw = value.toString();
    // Translate known categorical fields
    const translatableKeys = {
      'condition',
      'transmission',
      'fuel_type',
      'body_type',
      'drive_type',
      'color',
      'city',
      'title_status',
    };
    if (translatableKeys.contains(key)) {
      final translated = _translateValueGlobal(context, raw) ?? raw;
      return translated + (suffix?.toString() ?? '');
    }
    // Localize digits for numeric-like strings
    return _localizeDigitsGlobal(context, raw + (suffix?.toString() ?? ''));
  }
  
  String _formatPrice(BuildContext context, String price) {
    try {
      final num? value = num.tryParse(price.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (value == null) return _localizeDigitsGlobal(context, price);
      final locale = Localizations.localeOf(context).toLanguageTag();
      final formatter = _decimalFormatterGlobal(context);
      return _localizeDigitsGlobal(context, formatter.format(value));
    } catch (_) {
      return _localizeDigitsGlobal(context, price);
    }
  }
}
/* Legacy AddListingPage implementation removed - begin (commented out)
  final _formKey = GlobalKey<FormState>();
  String? selectedBrand;
  String? selectedModel;
  String? selectedYear;
  String? selectedMinYear;
  String? selectedMaxYear;
  String? selectedPrice;
  String? selectedMinPrice;
  String? selectedMaxPrice;
  String? selectedMileage;
  String? selectedMinMileage;
  String? selectedMaxMileage;
  String? selectedCondition;
  String? selectedTransmission;
  String? selectedFuelType;
  String? selectedBodyType;
  String? selectedColor;
  String? selectedTrim;
  String? selectedDriveType;
  String? selectedCylinderCount;
  String? selectedSeating;
  String? selectedEngineSize;
  String? selectedCity;
  String? selectedTitleStatus;
  String? selectedDamagedParts;
  String? contactPhone;
  bool isQuickSell = false;

  // For image picker
  final ImagePicker _imagePicker = ImagePicker();
  List<XFile> _selectedImages = [];
  Future<void> _pickImages() async {
    try {
      final files = await _imagePicker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
      if (files.isNotEmpty) {
        setState(() {
          _selectedImages = files;
        });
      }
    } catch (_) {}
  }

  // For video picker
  List<XFile> _selectedVideos = [];
  Future<void> _pickVideos() async {
    try {
      final file = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: Duration(minutes: 5),
      );
      if (file != null) {
        setState(() {
          _selectedVideos.add(file);
        });
      }
    } catch (_) {}
  }
  
  // Toggle states for unified filters
  bool isPriceDropdown = true;
  bool isYearDropdown = true;
  bool isMileageDropdown = true;

  // Use the same options as HomePage
  final List<String> addBrands = [
    'Toyota', 'Volkswagen', 'Ford', 'Honda', 'Hyundai', 'Nissan', 'Chevrolet', 'Kia', 'Mercedes-Benz', 'BMW', 'Audi', 'Lexus', 'Mazda', 'Subaru', 'Volvo', 'Jeep', 'RAM', 'GMC', 'Buick', 'Cadillac', 'Lincoln', 'Mitsubishi', 'Acura', 'Infiniti', 'Tesla', 'Mini', 'Porsche', 'Land Rover', 'Jaguar', 'Fiat', 'Renault', 'Peugeot', 'CitroÃ«n', 'Å koda', 'SEAT', 'Dacia', 'Chery', 'BYD', 'Great Wall', 'FAW', 'Roewe', 'Proton', 'Perodua', 'Tata', 'Mahindra', 'Lada', 'ZAZ', 'Daewoo', 'SsangYong', 'Changan', 'Haval', 'Wuling', 'Baojun', 'Nio', 'XPeng', 'Li Auto', 'VinFast', 'Ferrari', 'Lamborghini', 'Bentley', 'Rolls-Royce', 'Aston Martin', 'McLaren', 'Maserati', 'Bugatti', 'Pagani', 'Koenigsegg', 'Polestar', 'Rivian', 'Lucid', 'Alfa Romeo', 'Lancia', 'Abarth', 'Opel', 'DS', 'MAN', 'Iran Khodro', 'Genesis', 'Isuzu', 'Datsun', 'JAC Motors', 'JAC Trucks', 'KTM', 'Alpina', 'Brabus', 'Mansory', 'Bestune', 'Hongqi', 'Dongfeng', 'FAW Jiefang', 'Foton', 'Leapmotor', 'GAC', 'SAIC', 'MG', 'Vauxhall', 'Smart'
  ];
  final Map<String, List<String>> models = {
    'BMW': ['X3', 'X5', 'X7', '3 Series', '5 Series', '7 Series', 'M3', 'M5', 'X1', 'X6'],
    'Mercedes-Benz': ['C-Class', 'E-Class', 'S-Class', 'GLC', 'GLE', 'GLS', 'A-Class', 'CLA', 'GLA', 'AMG GT'],
    'Audi': ['A3', 'A4', 'A6', 'A8', 'Q3', 'Q5', 'Q7', 'Q8', 'RS6', 'TT'],
    'Toyota': ['Camry', 'Corolla', 'RAV4', 'Highlander', 'Tacoma', 'Tundra', 'Prius', 'Avalon', '4Runner', 'Sequoia'],
    'Honda': ['Civic', 'Accord', 'CR-V', 'Pilot', 'Ridgeline', 'Odyssey', 'HR-V', 'Passport', 'Insight', 'Clarity'],
    'Nissan': ['Altima', 'Maxima', 'Rogue', 'Murano', 'Pathfinder', 'Frontier', 'Titan', 'Leaf', 'Sentra', 'Versa'],
    'Ford': ['F-150', 'Mustang', 'Explorer', 'Escape', 'Edge', 'Ranger', 'Bronco', 'Mach-E', 'Focus', 'Fusion'],
    'Chevrolet': ['Silverado', 'Camaro', 'Equinox', 'Tahoe', 'Suburban', 'Colorado', 'Corvette', 'Malibu', 'Cruze', 'Traverse'],
    'Hyundai': ['Elantra', 'Sonata', 'Tucson', 'Santa Fe', 'Palisade', 'Kona', 'Venue', 'Accent', 'Veloster', 'Ioniq'],
    'Kia': ['Forte', 'K5', 'Sportage', 'Telluride', 'Sorento', 'Soul', 'Rio', 'Stinger', 'EV6', 'Niro']
  };
// Legacy AddListingPage implementation removed - end
*/
  // @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.addListingTitle),
        automaticallyImplyLeading: false,
        actions: [
          const ThemeToggleWidget(),
          buildLanguageMenu(),
        ],
      ),
      /* Legacy AddListingPage UI removed
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              GestureDetector(
                onTap: _pickBrand,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.brandLabel,
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      if (selectedBrand != null)
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: CachedNetworkImage(
                                imageUrl: getApiBase() + '/static/images/brands/' + (brandLogoFilenames[selectedBrand] ?? selectedBrand!.toLowerCase().replaceAll(' ', '-')) + '.png',
                                placeholder: (context, url) => SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                errorWidget: (context, url, error) => Icon(Icons.directions_car, size: 22, color: Color(0xFFFF6B00)),
                                fit: BoxFit.contain,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(selectedBrand!, style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        )
                      else
                        Text(AppLocalizations.of(context)!.tapToSelectBrand, style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12),
              FormField<String>(
                validator: (_) => (selectedModel == null || selectedModel!.isEmpty) ? AppLocalizations.of(context)!.modelLabel : null,
                builder: (state) => GestureDetector(
                  onTap: _pickModel,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.modelLabel,
                      border: OutlineInputBorder(),
                      errorText: state.errorText,
                    ),
                    child: Text(
                      selectedModel ?? AppLocalizations.of(context)!.tapToSelectBrand,
                      style: TextStyle(color: selectedModel == null ? Colors.grey : Colors.white),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Trim Dropdown (dependent on brand + model) placed under Model
              FormField<String>(
                validator: (_) => (selectedTrim == null || selectedTrim!.isEmpty) ? AppLocalizations.of(context)!.trimLabel : null,
                builder: (state) => GestureDetector(
                  onTap: _pickTrimOption,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.trimLabel,
                      border: OutlineInputBorder(),
                      errorText: state.errorText,
                    ),
                    child: Text(
                      selectedTrim ?? AppLocalizations.of(context)!.anyOption,
                      style: TextStyle(color: selectedTrim == null ? Colors.grey : Colors.white),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Row(
                  children: [
                    Expanded(
                      child: isYearDropdown
                          ? DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              value: (selectedMinYear != null && selectedMinYear!.isNotEmpty && years.contains(selectedMinYear)) ? selectedMinYear : null,
                              items: years.map((y) => DropdownMenuItem(value: y, child: Text(_localizeDigitsGlobal(context, y)))).toList(),
                              onChanged: (v) { setState(() { selectedMinYear = v; selectedMaxYear = v; }); _persistFilters(); },
                            )
                          : TextFormField(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) { setState(() { selectedMinYear = v; selectedMaxYear = v; }); _persistFilters(); },
                            ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(() => isYearDropdown = !isYearDropdown),
                      icon: Icon(isYearDropdown ? Icons.edit : Icons.list, color: Color(0xFFFF6B00)),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.withOpacity(0.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
              ),
              SizedBox(height: 12),
              SizedBox(height: 12),
              Row(
                  children: [
                    Expanded(
                      child: isPriceDropdown
                          ? DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              value: (selectedMinPrice != null && selectedMinPrice!.isNotEmpty) ? selectedMinPrice : null,
                              items: [
                                ...List.generate(600, (i) => (500 + i * 500).toString()).map((p) => DropdownMenuItem(value: p, child: Text(_formatCurrencyGlobal(context, p)))).toList(),
                                ...List.generate(171, (i) => (300000 + (i + 1) * 10000).toString()).map((p) => DropdownMenuItem(value: p, child: Text(_formatCurrencyGlobal(context, p)))).toList(),
                              ],
                              onChanged: (v) => setState(() { selectedMinPrice = v; selectedMaxPrice = v; }),
                            )
                          : TextFormField(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => setState(() { selectedMinPrice = v; selectedMaxPrice = v; }),
                            ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(() => isPriceDropdown = !isPriceDropdown),
                      icon: Icon(isPriceDropdown ? Icons.edit : Icons.list, color: Color(0xFFFF6B00)),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.withOpacity(0.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
              ),
              SizedBox(height: 12),
              SizedBox(height: 12),
              Row(
                  children: [
                    Expanded(
                      child: isMileageDropdown
                          ? DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              value: (selectedMaxMileage != null && selectedMaxMileage!.isNotEmpty) ? selectedMaxMileage : null,
                              items: [
                                ...[
                                  for (int m = 0; m <= 100000; m += 1000) m,
                                  for (int m = 105000; m <= 300000; m += 5000) m,
                                ]
                                    .map((m) => DropdownMenuItem(
                                          value: m.toString(),
                                          child: Text(_localizeDigitsGlobal(context, m.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (mm) => '${mm[1]},'))),
                                        ))
                                    .toList(),
                              ],
                              onChanged: (v) => setState(() { selectedMaxMileage = v; }),
                              validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context)!.mileageLabel : null,
                            )
                          : TextFormField(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => setState(() { selectedMaxMileage = v; }),
                            ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(() => isMileageDropdown = !isMileageDropdown),
                      icon: Icon(isMileageDropdown ? Icons.edit : Icons.list, color: Color(0xFFFF6B00)),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.withOpacity(0.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.conditionLabel),
                value: selectedCondition != null && conditions.contains(selectedCondition) ? selectedCondition : null,
                items: conditions.map((c) => DropdownMenuItem(value: c, child: Text(_translateValueGlobal(context, c) ?? c))).toList(),
                onChanged: (v) => setState(() => selectedCondition = v),
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.conditionLabel : null,
              ),
              SizedBox(height: 12),
              // Title Status
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.titleStatus),
                value: selectedTitleStatus,
                items: [
                  DropdownMenuItem(value: 'clean', child: Text(AppLocalizations.of(context)!.value_title_clean)),
                  DropdownMenuItem(value: 'damaged', child: Text(AppLocalizations.of(context)!.value_title_damaged)),
                ],
                onChanged: (v) {
                  setState(() {
                    selectedTitleStatus = v;
                    if (selectedTitleStatus != 'damaged') {
                      selectedDamagedParts = null;
                    }
                  });
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.titleStatus : null,
              ),
              if (selectedTitleStatus == 'damaged') ...[
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.damagedParts),
                  value: selectedDamagedParts,
                  items: [
                    ...List.generate(15, (i) => (i + 1).toString()).map((p) => DropdownMenuItem(value: p, child: Text(_localizeDigitsGlobal(context, p))))
                  ],
                  onChanged: (v) => setState(() => selectedDamagedParts = v),
                  validator: (v) => (selectedTitleStatus == 'damaged' && (v == null || v.isEmpty)) ? AppLocalizations.of(context)!.damagedParts : null,
                ),
              ],
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.transmissionLabel),
                value: selectedTransmission != null && transmissions.contains(selectedTransmission) ? selectedTransmission : null,
                items: transmissions.map((t) => DropdownMenuItem(value: t, child: Text(_translateValueGlobal(context, t) ?? t))).toList(),
                onChanged: (v) => setState(() => selectedTransmission = v),
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.transmissionLabel : null,
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.fuelTypeLabel),
                value: selectedFuelType != null && fuelTypes.contains(selectedFuelType) ? selectedFuelType : null,
                items: fuelTypes.map((f) => DropdownMenuItem(value: f, child: Text(_translateValueGlobal(context, f) ?? f))).toList(),
                onChanged: (v) => setState(() => selectedFuelType = v),
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.fuelTypeLabel : null,
              ),
              SizedBox(height: 12),
              // Body Type Selection Button
              Container(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final bodyType = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        return Dialog(
                          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: Container(
                            width: 400,
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(AppLocalizations.of(context)!.selectBodyType, style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                                    IconButton(
                                      icon: Icon(Icons.close, color: Colors.white),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 10),
                                SizedBox(
                                  height: 300,
                                  child: GridView.builder(
                                    shrinkWrap: true,
                                    physics: BouncingScrollPhysics(),
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      childAspectRatio: 1.2,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    itemCount: bodyTypes.length,
                                    itemBuilder: (context, index) {
                                      final bodyTypeName = bodyTypes[index];
                                      final asset = _getBodyTypeAsset(bodyTypeName);
                                      
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => Navigator.pop(context, bodyTypeName),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.white24),
                                          ),
                                          padding: EdgeInsets.all(8),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                width: 56,
                                                height: 56,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.white24, width: 1),
                                                ),
                                                child: Padding(
                                                  padding: EdgeInsets.all(8),
                                                  child: FittedBox(
                                                    fit: BoxFit.contain,
                                                    child: _buildBodyTypeImage(asset),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                _translateValueGlobal(context, bodyTypeName) ?? bodyTypeName,
                                                style: GoogleFonts.orbitron(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                    if (bodyType != null) {
                      setState(() {
                        selectedBodyType = bodyType == 'Any' ? null : bodyType;
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (selectedBodyType != null) ...[
                              Container(
                                width: 24,
                                height: 24,
                                margin: EdgeInsets.only(right: 8),
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: _buildBodyTypeImage(_getBodyTypeAsset(selectedBodyType!)),
                                ),
                              ),
                          ],
                          Text(
                            selectedBodyType != null ? _translateValueGlobal(context, selectedBodyType!) ?? selectedBodyType! : AppLocalizations.of(context)!.anyOption,
                            style: TextStyle(
                              color: selectedBodyType != null ? Color(0xFFFF6B00) : Colors.white,
                              fontSize: 16,
                              fontWeight: selectedBodyType != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Color Selection Button
              Container(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final color = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        return Dialog(
                          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: Container(
                            width: 400,
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(AppLocalizations.of(context)!.selectColor, style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                                    IconButton(
                                      icon: Icon(Icons.close, color: Colors.white),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 10),
                                SizedBox(
                                  height: 300,
                                  child: GridView.builder(
                                    shrinkWrap: true,
                                    physics: BouncingScrollPhysics(),
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      childAspectRatio: 1.2,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    itemCount: getAddCarAvailableColors().length,
                                    itemBuilder: (context, index) {
                                      final colorName = getAddCarAvailableColors()[index];
                                      Color colorValue = Colors.grey;
                                      
                                      // Map color names to actual colors
                                      switch (colorName.toLowerCase()) {
                                        case 'black':
                                          colorValue = Colors.black;
                                          break;
                                        case 'white':
                                          colorValue = Colors.white;
                                          break;
                                        case 'silver':
                                          colorValue = Colors.grey[300]!;
                                          break;
                                        case 'gray':
                                          colorValue = Colors.grey[600]!;
                                          break;
                                        case 'red':
                                          colorValue = Colors.red;
                                          break;
                                        case 'blue':
                                          colorValue = Colors.blue;
                                          break;
                                        case 'green':
                                          colorValue = Colors.green;
                                          break;
                                        case 'yellow':
                                          colorValue = Colors.yellow;
                                          break;
                                        case 'orange':
                                          colorValue = Colors.orange;
                                          break;
                                        case 'purple':
                                          colorValue = Colors.purple;
                                          break;
                                        case 'brown':
                                          colorValue = Colors.brown;
                                          break;
                                        case 'beige':
                                          colorValue = Color(0xFFF5F5DC);
                                          break;
                                        case 'gold':
                                          colorValue = Color(0xFFFFD700);
                                          break;
                                        default:
                                          colorValue = Colors.grey;
                                      }
                                      
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => Navigator.pop(context, colorName),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.white24),
                                          ),
                                          padding: EdgeInsets.all(8),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: colorValue,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.white24, width: 2),
                                                ),
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                _translateValueGlobal(context, colorName) ?? colorName,
                                                style: GoogleFonts.orbitron(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                    if (color != null) {
                      setState(() {
                        selectedColor = color == 'Any' ? null : color;
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (selectedColor != null) ...[
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: _getColorValue(selectedColor!),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white24, width: 1),
                              ),
                            ),
                            SizedBox(width: 8),
                          ],
                          Text(
                            selectedColor != null ? _translateValueGlobal(context, selectedColor!) ?? selectedColor! : AppLocalizations.of(context)!.anyOption,
                            style: TextStyle(
                              color: selectedColor != null ? Color(0xFFFF6B00) : Colors.white,
                              fontSize: 16,
                              fontWeight: selectedColor != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Drive Type Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.driveType),
                value: selectedDriveType != null && getAddCarAvailableDriveTypes().contains(selectedDriveType) ? selectedDriveType : null,
                items: getAddCarAvailableDriveTypes().map((d) => DropdownMenuItem(value: d, child: Text(_translateValueGlobal(context, d) ?? d))).toList(),
                onChanged: (v) => setState(() => selectedDriveType = v),
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectDriveType : null,
              ),
              SizedBox(height: 12),
              // Cylinder Count Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.cylinderCount),
                value: selectedCylinderCount != null && getAddCarAvailableCylinderCounts().contains(selectedCylinderCount) ? selectedCylinderCount : null,
                items: getAddCarAvailableCylinderCounts().map((c) => DropdownMenuItem(value: c, child: Text(_localizeDigitsGlobal(context, c)))).toList(),
                onChanged: (v) => setState(() => selectedCylinderCount = v),
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectCylinderCount : null,
              ),
              SizedBox(height: 12),
              // Seating Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.seating),
                value: selectedSeating != null && getAddCarAvailableSeatings().contains(selectedSeating) ? selectedSeating : null,
                items: getAddCarAvailableSeatings().map((s) => DropdownMenuItem(value: s, child: Text(_localizeDigitsGlobal(context, s)))).toList(),
                onChanged: (v) => setState(() => selectedSeating = v),
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectSeating : null,
              ),
              SizedBox(height: 12),
              // Engine Size Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.engineSizeL),
                value: selectedEngineSize != null && getAddCarAvailableEngineSizes().contains(selectedEngineSize) ? selectedEngineSize : null,
                items: getAddCarAvailableEngineSizes().map((e) => DropdownMenuItem(value: e, child: Text('${_localizeDigitsGlobal(context, e)}${AppLocalizations.of(context)!.unit_liter_suffix}'))).toList(),
                onChanged: (v) => setState(() => selectedEngineSize = v),
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectEngineSize : null,
              ),
              SizedBox(height: 12),
              // City Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.cityLabel),
                value: selectedCity != null && cities.contains(selectedCity) ? selectedCity : null,
                items: cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => selectedCity = v),
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectCity : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.whatsappLabel, hintText: AppLocalizations.of(context)!.whatsappHint),
                keyboardType: TextInputType.phone,
                onChanged: (v) => setState(() => contactPhone = v.trim()),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return AppLocalizations.of(context)!.enterWhatsAppNumber;
                  final s = v.trim();
                  final bool looksOk = s.startsWith('+') ? RegExp(r'^\+\d{7,}$').hasMatch(s) : RegExp(r'^\d{7,}$').hasMatch(s);
                  if (!looksOk) return AppLocalizations.of(context)!.useInternationalFormat;
                  return null;
                },
                onSaved: (_) {},
              ),
              SizedBox(height: 16),
              Text(_photosRequiredTitleGlobal(context), style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              if (_selectedImages.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._selectedImages.map((x) => Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.file(File(x.path), fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedImages.remove(x);
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ))
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: Icon(Icons.photo_library),
                  label: Text(_selectedImages.isEmpty ? AppLocalizations.of(context)!.addPhotos : AppLocalizations.of(context)!.addMorePhotos),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.2),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(_videosOptionalTitleGlobal(context), style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              if (_selectedVideos.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._selectedVideos.map((x) => Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              // Video thumbnail placeholder
                              Container(
                                color: Colors.grey[800],
                                child: Center(
                                  child: Icon(Icons.videocam, color: Colors.white, size: 32),
                                ),
                              ),
                              // Play button overlay
                              Center(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.play_arrow, color: Colors.white, size: 24),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedVideos.remove(x);
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ))
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: _pickVideos,
                  icon: Icon(Icons.videocam),
                  label: Text(_selectedVideos.isEmpty ? 'Add Videos' : 'Add More Videos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.2),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 24),
              // Quick Sell Option
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flash_on, color: Colors.orange, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick Sell',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          Text(
                            'Enable this to make your listing stand out with a special banner',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isQuickSell,
                      onChanged: (value) {
                        setState(() {
                          isQuickSell = value;
                        });
                      },
                      activeColor: Colors.orange,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),
              ElevatedButton.icon(
                icon: Icon(Icons.add),
                label: Text(AppLocalizations.of(context)!.submitListing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  // Require authentication before allowing submission
                  final existingToken = ApiService.accessToken;
                  if (existingToken == null || existingToken.isEmpty) {
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(AppLocalizations.of(context)!.loginRequired),
                        content: Text(AppLocalizations.of(context)!.authenticationRequired),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/login');
                            },
                            child: Text(AppLocalizations.of(context)!.navLogin),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(_cancelTextGlobal(context)),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  if (!_formKey.currentState!.validate()) return;
                  
                  // Validate that at least one photo is selected
                  if (_selectedImages.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_pleaseSelectPhotoTextGlobal(context)),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  final brand = selectedBrand?.toString() ?? '';
                  final model = selectedModel?.toString() ?? '';
                  final trim = selectedTrim?.toString() ?? 'Base';
                  final year = int.tryParse(selectedMinYear ?? selectedYear ?? '') ?? DateTime.now().year;
                  final mileage = int.tryParse(selectedMaxMileage ?? '0') ?? 0;
                  final condition = (selectedCondition ?? 'Used').toLowerCase();
                  final transmission = (selectedTransmission ?? 'Automatic').toLowerCase();
                  final fuelType = (selectedFuelType ?? 'Gasoline').toLowerCase();
                  final color = (selectedColor ?? 'Black').toLowerCase();
                  final bodyType = (selectedBodyType ?? 'Sedan').toLowerCase();
                  final seating = int.tryParse(selectedSeating ?? '5') ?? 5;
                  final driveType = (selectedDriveType ?? 'fwd').toLowerCase();
                  final titleStatus = (selectedTitleStatus ?? 'clean').toLowerCase();
                  final damagedParts = titleStatus == 'damaged' ? int.tryParse(selectedDamagedParts ?? '') : null;
                  final cylinderCount = int.tryParse(selectedCylinderCount ?? '');
                  final engineSize = double.tryParse(selectedEngineSize ?? '');
                  final price = int.tryParse(selectedMinPrice ?? '');
                  final city = (selectedCity ?? 'Baghdad').toLowerCase();
                  final title = '$brand $model $trim'.trim();

                  final payload = {
                    'title': title,
                    'brand': brand.toLowerCase().replaceAll(' ', '-'),
                    'model': model,
                    'trim': trim,
                    'year': year,
                    'price': price,
                    'mileage': mileage,
                    'condition': condition,
                    'transmission': transmission,
                    'fuel_type': fuelType,
                    'color': color,
                    'body_type': bodyType,
                    'seating': seating,
                    'drive_type': driveType,
                    'title_status': titleStatus,
                    'damaged_parts': damagedParts,
                    'cylinder_count': cylinderCount,
                    'engine_size': engineSize,
                    'city': city,
                    'contact_phone': (contactPhone ?? '').trim(),
                    'is_quick_sell': isQuickSell,
                  };

                  try {
                    final url = Uri.parse(getApiBase() + '/cars');
                    final headers = {
                      'Content-Type': 'application/json',
                      if (ApiService.accessToken != null) 'Authorization': 'Bearer ' + ApiService.accessToken!,
                    };
                    final resp = await http.post(
                      url,
                      headers: headers,
                      body: json.encode(payload),
                    );
                    if (resp.statusCode == 201) {
                      final Map<String, dynamic> created = json.decode(resp.body);
                      final int carId = created['id'];
                      if (_selectedImages.isNotEmpty) {
                        final uploadUrl = Uri.parse(getApiBase() + '/api/cars/' + carId.toString() + '/images');
                        final request = http.MultipartRequest('POST', uploadUrl);
                        final tok = ApiService.accessToken;
                        if (tok != null) request.headers['Authorization'] = 'Bearer ' + tok;
                        for (final img in _selectedImages) {
                          request.files.add(await http.MultipartFile.fromPath('image', img.path));
                        }
                        final uploadResp = await request.send();
                        final uploadHttpResp = await http.Response.fromStream(uploadResp);
                        if (uploadResp.statusCode == 201) {
                          try {
                            final respJson = json.decode(uploadHttpResp.body);
                            final newPrimary = (respJson is Map) ? (respJson['image_url']?.toString() ?? '') : '';
                            if (newPrimary.isNotEmpty) {
                              // Navigate back to home so the new image shows up immediately
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(_photosUploadedTextGlobal(context))),
                              );
                            }
                          } catch (_) {}
                        } else {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(AppLocalizations.of(context)!.error),
                              content: Text(
                                AppLocalizations.of(context)!.listingUploadPartialFail(uploadResp.statusCode) +
                                (uploadHttpResp.body.isNotEmpty ? '\n' + uploadHttpResp.body : ''),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.ok)),
                              ],
                            ),
                          );
                        }
                      }
                      
                      // Upload videos if any
                      if (_selectedVideos.isNotEmpty) {
                        final videoUploadUrl = Uri.parse(getApiBase() + '/api/cars/' + carId.toString() + '/videos');
                        final videoRequest = http.MultipartRequest('POST', videoUploadUrl);
                        final tok = ApiService.accessToken;
                        if (tok != null) videoRequest.headers['Authorization'] = 'Bearer ' + tok;
                        for (final video in _selectedVideos) {
                          videoRequest.files.add(await http.MultipartFile.fromPath('video', video.path));
                        }
                        final videoUploadResp = await videoRequest.send();
                        if (videoUploadResp.statusCode != 201) {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(AppLocalizations.of(context)!.error),
                              content: Text('${AppLocalizations.of(context)!.error}: ${_localizeDigitsGlobal(context, videoUploadResp.statusCode.toString())}'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.ok)),
                              ],
                            ),
                          );
                        }
                      }
                      
                      // After successful create and uploads, go home to refresh
                      Navigator.pushReplacementNamed(context, '/');
                    } else if (resp.statusCode == 401 || resp.statusCode == 403) {
                      // Token missing/expired or not authorized -> prompt login
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(AppLocalizations.of(context)!.authenticationRequired),
                          content: Text(AppLocalizations.of(context)!.loginRequired),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pushNamed(context, '/login');
                              },
                              child: Text(AppLocalizations.of(context)!.navLogin),
                            ),
                            TextButton(onPressed: () => Navigator.pop(context), child: Text(_cancelTextGlobal(context))),
                          ],
                        ),
                      );
                    } else {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(AppLocalizations.of(context)!.error),
                          content: Text(AppLocalizations.of(context)!.failedToSubmitListing(resp.body)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.ok)),
                          ],
                        ),
                      );
                    }
                  } catch (e) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(AppLocalizations.of(context)!.error),
                        content: Text(AppLocalizations.of(context)!.couldNotSubmitListing),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.ok)),
                        ],
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
      */
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black87,
        selectedItemColor: Color(0xFFFF6B00),
        unselectedItemColor: Colors.white70,
        currentIndex: 0,
        onTap: (idx) {
          switch (idx) {
            case 0:
              Navigator.pushReplacementNamed(context, '/');
              break;
            case 1:
              Navigator.pushReplacementNamed(context, '/favorites');
              break;
            case 2:
              if (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                Navigator.pushReplacementNamed(context, '/profile');
              }
              break;
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context)!.navHome),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: AppLocalizations.of(context)!.navSaved),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) ? AppLocalizations.of(context)!.navLogin : AppLocalizations.of(context)!.navProfile),
        ],
      ),
    );
  }

  // Helper function to get body type icon
  IconData _getBodyTypeIcon(String bodyType) {
    switch (bodyType.toLowerCase()) {
      case 'sedan':
        return Icons.directions_car;
      case 'suv':
        return Icons.directions_car_filled;
      case 'hatchback':
        return Icons.directions_car;
      case 'coupe':
        return Icons.directions_car;
      case 'wagon':
        return Icons.directions_car;
      case 'pickup':
        return Icons.local_shipping;
      case 'van':
        return Icons.airport_shuttle;
      case 'minivan':
        return Icons.airport_shuttle;
      case 'motorcycle':
        return Icons.motorcycle;
      case 'utv':
        return Icons.directions_car;
      case 'atv':
        return Icons.directions_car;
      default:
        return Icons.directions_car;
    }
  }

  // Helper function to get color value
  Color _getColorValue(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'silver':
        return Colors.grey[300]!;
      case 'gray':
        return Colors.grey[600]!;
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'brown':
        return Colors.brown;
      case 'beige':
        return Color(0xFFF5F5DC);
      case 'gold':
        return Color(0xFFFFD700);
      default:
        return Colors.grey;
    }
  }
// Removed stray closing brace that caused a syntax error

class FavoritesPage extends StatefulWidget {
  @override
  _FavoritesPageState createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() { _loading = true; _error = null; });
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        setState(() { _error = AppLocalizations.of(context)!.loginRequired; _loading = false; });
        return;
      }
      final sp = await SharedPreferences.getInstance();
      final cacheKey = 'cache_favorites';
      final cached = sp.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          final data = json.decode(cached);
          if (data is List) {
            setState(() { _favorites = data.cast<Map<String, dynamic>>(); _loading = false; });
          }
        } catch (_) {}
      }
      final url = Uri.parse(getApiBase() + '/api/favorites');
      final resp = await http.get(url, headers: { 'Authorization': 'Bearer ' + tok });
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is List) {
          setState(() { _favorites = data.cast<Map<String, dynamic>>(); });
          unawaited(sp.setString(cacheKey, json.encode(_favorites)));
        }
      } else if (resp.statusCode == 401) {
        setState(() { _error = AppLocalizations.of(context)!.loginRequired; });
      } else {
        setState(() { _error = AppLocalizations.of(context)!.couldNotSubmitListing; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _toggleFavorite(int carId) async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) return;
      final url = Uri.parse(getApiBase() + '/api/favorite/' + carId.toString());
      final resp = await http.post(url, headers: { 'Authorization': 'Bearer ' + tok });
      if (resp.statusCode == 200) {
        // Remove if unfavorited; keep if favorited
        final Map<String, dynamic> res = json.decode(resp.body);
        final bool favorited = res['favorited'] == true;
        if (!favorited) {
          setState(() { _favorites.removeWhere((c) => c['id'] == carId); });
        } else {
          // If favorited, ensure it exists (no-op if already in list)
          // Could fetch full car if needed; skip for now
        }
        // Track favorite for analytics
        if (favorited) {
          unawaited(AnalyticsService.trackFavorite(carId.toString()));
        }
      }
    } catch (_) {}
  }

  String _formatPrice(String raw) {
    try {
      final num? value = num.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (value == null) return raw;
      final locale = Localizations.localeOf(context).toLanguageTag();
      final formatter = _decimalFormatterGlobal(context);
      return _localizeDigitsGlobal(context, formatter.format(value));
    } catch (_) {
      return raw;
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.favoritesTitle)),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Text(_error!))
              : (_favorites.isEmpty)
                  ? Center(child: Text('No favorites yet'))
                  : RefreshIndicator(
                      onRefresh: _loadFavorites,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemBuilder: (context, index) {
                          final car = _favorites[index];
                          final String title = (car['title']?.toString() ?? '').trim();
                          final String imageUrl = (car['image_url']?.toString() ?? '').trim();
                          final String? rel = imageUrl.isEmpty ? null : imageUrl;
                          final String fullImg = rel == null
                              ? ''
                              : (rel.startsWith('http')
                                  ? rel
                                  : (getApiBase() + '/static/uploads/' + rel));
                          return InkWell(
                            onTap: () {
                              final int? id = car['id'] is int ? car['id'] as int : int.tryParse(car['id']?.toString() ?? '');
                              if (id != null) {
                                // Analytics tracking for view listing
                                Navigator.pushNamed(context, '/car_detail', arguments: {'carId': id});
                              }
                            },
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: (fullImg.isNotEmpty)
                                      ? CachedNetworkImage(
                                          imageUrl: fullImg,
                                          width: 110,
                                          height: 78,
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => Container(width: 110, height: 78, color: Colors.white10),
                                          errorWidget: (_, __, ___) => Container(width: 110, height: 78, color: Colors.grey[900], child: Icon(Icons.directions_car, color: Colors.grey[500])),
                                        )
                                      : Container(
                                          width: 110,
                                          height: 78,
                                          color: Colors.grey[900],
                                          child: Icon(Icons.directions_car, color: Colors.grey[500]),
                                        ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title.isEmpty ? 'â€”' : title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                      ),
                                      SizedBox(height: 6),
                                      if (car['price'] != null)
                                        Text(
                                          _formatCurrencyGlobal(context, car['price']),
                                          style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.w700),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.favorite, color: Color(0xFFFF6B00)),
                                  onPressed: () {
                                    final int? id = car['id'] is int ? car['id'] as int : int.tryParse(car['id']?.toString() ?? '');
                                    if (id != null) {
                                      _toggleFavorite(id);
                                    }
                                  },
                                )
                              ],
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => SizedBox(height: 12),
                        itemCount: _favorites.length,
                      ),
                    ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black87,
        selectedItemColor: Color(0xFFFF6B00),
        unselectedItemColor: Colors.white70,
        currentIndex: 1,
        onTap: (idx) {
          switch (idx) {
            case 0:
              Navigator.pushReplacementNamed(context, '/');
              break;
            case 1:
              // Already on favorites
              break;
            case 2:
              Navigator.pushReplacementNamed(context, '/profile');
              break;
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context)!.navHome),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: AppLocalizations.of(context)!.navSaved),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) ? AppLocalizations.of(context)!.navLogin : AppLocalizations.of(context)!.navProfile),
        ],
      ),
    );
  }
}

class ChatListPage extends StatefulWidget {
  @override
  _ChatListPageState createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.chatTitle)),
      body: Center(child: Text(AppLocalizations.of(context)!.chatTitle)),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black87,
        selectedItemColor: Color(0xFFFF6B00),
        unselectedItemColor: Colors.white70,
        currentIndex: 0,
        onTap: (idx) {
          switch (idx) {
            case 0:
              Navigator.pushReplacementNamed(context, '/');
              break;
            case 1:
              Navigator.pushReplacementNamed(context, '/favorites');
              break;
            case 2:
              if (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                Navigator.pushReplacementNamed(context, '/profile');
              }
              break;
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context)!.navHome),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: AppLocalizations.of(context)!.navSaved),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) ? AppLocalizations.of(context)!.navLogin : AppLocalizations.of(context)!.navProfile),
        ],
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; });
    try {
      final url = Uri.parse(getApiBase() + '/api/auth/login');
      final resp = await http.post(url, headers: {'Content-Type': 'application/json'}, body: json.encode({
        'username': _usernameController.text.trim(),
        'password': _passwordController.text,
      }));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final token = data['token'] as String;
        // Store token in memory (simple for now); can add SharedPreferences later
        await AuthStore.saveToken(token);
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/');
      } else {
        final msg = resp.body.length > 0 ? resp.body : AppLocalizations.of(context)!.couldNotSubmitListing;
        if (!mounted) return;
        showDialog(context: context, builder: (_) => AlertDialog(title: Text(AppLocalizations.of(context)!.errorTitle), content: Text(msg), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text(AppLocalizations.of(context)!.okAction))]));
      }
    } catch (e) {
      if (!mounted) return;
      showDialog(context: context, builder: (_) => AlertDialog(title: Text(AppLocalizations.of(context)!.errorTitle), content: Text(e.toString()), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text(AppLocalizations.of(context)!.okAction))]));
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.loginTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.usernameLabel),
                validator: (v) => (v==null || v.trim().isEmpty) ? AppLocalizations.of(context)!.requiredField : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.passwordLabel),
                validator: (v) => (v==null || v.isEmpty) ? AppLocalizations.of(context)!.requiredField : null,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(AppLocalizations.of(context)!.navLogin),
              ),
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
                child: Text(AppLocalizations.of(context)!.createAccount),
              )
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black87,
        selectedItemColor: Color(0xFFFF6B00),
        unselectedItemColor: Colors.white70,
        currentIndex: 2,
        onTap: (idx) {
          switch (idx) {
            case 0:
              Navigator.pushReplacementNamed(context, '/');
              break;
            case 1:
              Navigator.pushReplacementNamed(context, '/favorites');
              break;
            case 2:
              // Already on login
              break;
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context)!.navHome),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: AppLocalizations.of(context)!.navSaved),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) ? AppLocalizations.of(context)!.navLogin : AppLocalizations.of(context)!.navProfile),
        ],
      ),
    );
  }
}

class SignupPage extends StatefulWidget {
  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  bool _loading = false;
  bool _otpSent = false;

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      showDialog(context: context, builder: (_) => AlertDialog(title: Text(AppLocalizations.of(context)!.errorTitle), content: Text(AppLocalizations.of(context)!.enterPhoneNumber), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text(AppLocalizations.of(context)!.okAction))]));
      return;
    }
    setState(() { _loading = true; });
    try {
      final url = Uri.parse(getApiBase() + '/api/auth/send_otp');
      final resp = await http.post(url, headers: {'Content-Type': 'application/json'}, body: json.encode({'phone': phone}));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final bool sent = data['sent'] == true;
        setState(() { _otpSent = true; });
        if (sent) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.verificationCodeSent)));
        } else if (data['dev_code'] != null) {
          final String code = data['dev_code'].toString();
          showDialog(context: context, builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.devCodeTitle),
            content: Text(AppLocalizations.of(context)!.useCodeToVerify(code)),
            actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text(AppLocalizations.of(context)!.okAction))],
          ));
        } else {
          final String err = data['error']?.toString() ?? AppLocalizations.of(context)!.couldNotSubmitListing;
          showDialog(context: context, builder: (_) => AlertDialog(title: Text(AppLocalizations.of(context)!.errorTitle), content: Text(err), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text(AppLocalizations.of(context)!.okAction))]));
        }
      } else {
        final msg = resp.body.isNotEmpty ? resp.body : AppLocalizations.of(context)!.couldNotSubmitListing;
        showDialog(context: context, builder: (_) => AlertDialog(title: Text(AppLocalizations.of(context)!.errorTitle), content: Text(msg), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text(AppLocalizations.of(context)!.okAction))]));
      }
    } catch (e) {
      showDialog(context: context, builder: (_) => AlertDialog(title: Text(AppLocalizations.of(context)!.errorTitle), content: Text(e.toString()), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text(AppLocalizations.of(context)!.okAction))]));
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; });
    try {
      final url = Uri.parse(getApiBase() + '/api/auth/signup');
      final resp = await http.post(url, headers: {'Content-Type': 'application/json'}, body: json.encode({
        'username': _usernameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'otp_code': _otpController.text.trim(),
        'password': _passwordController.text,
      }));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final token = data['token'] as String;
        await AuthStore.saveToken(token);
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/');
      } else {
        final msg = resp.body.length > 0 ? resp.body : AppLocalizations.of(context)!.couldNotSubmitListing;
        if (!mounted) return;
        showDialog(context: context, builder: (_) => AlertDialog(title: Text(AppLocalizations.of(context)!.errorTitle), content: Text(msg), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text(AppLocalizations.of(context)!.okAction))]));
      }
    } catch (e) {
      if (!mounted) return;
      showDialog(context: context, builder: (_) => AlertDialog(title: Text(AppLocalizations.of(context)!.errorTitle), content: Text(e.toString()), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text(AppLocalizations.of(context)!.okAction))]));
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.signupTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.usernameLabel),
                validator: (v) => (v==null || v.trim().isEmpty) ? AppLocalizations.of(context)!.requiredField : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.enterPhoneNumber),
                validator: (v) => (v==null || v.trim().isEmpty) ? AppLocalizations.of(context)!.requiredField : null,
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _otpController,
                      decoration: InputDecoration(labelText: AppLocalizations.of(context)!.sendCode),
                      validator: (v) => (!_otpSent) ? AppLocalizations.of(context)!.sendCodeFirst : ((v==null || v.trim().isEmpty) ? AppLocalizations.of(context)!.requiredField : null),
                    ),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _sendOtp,
                    child: Text(_otpSent ? 'Resend' : 'Send code'),
                  ),
                ],
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.passwordLabel),
                validator: (v) => (v==null || v.isEmpty) ? AppLocalizations.of(context)!.requiredField : null,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _signup,
                child: _loading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(AppLocalizations.of(context)!.createAccount),
              ),
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                child: Text(AppLocalizations.of(context)!.haveAccountLogin),
              )
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black87,
        selectedItemColor: Color(0xFFFF6B00),
        unselectedItemColor: Colors.white70,
        currentIndex: 2,
        onTap: (idx) {
          switch (idx) {
            case 0:
              Navigator.pushReplacementNamed(context, '/');
              break;
            case 1:
              Navigator.pushReplacementNamed(context, '/favorites');
              break;
            case 2:
              if (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                Navigator.pushReplacementNamed(context, '/profile');
              }
              break;
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context)!.navHome),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: AppLocalizations.of(context)!.navSaved),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) ? AppLocalizations.of(context)!.navLogin : AppLocalizations.of(context)!.navProfile),
        ],
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? me;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        setState(() { _loading = false; });
        return;
      }
      final url = Uri.parse(getApiBase() + '/api/auth/me');
      final resp = await http.get(url, headers: { 'Authorization': 'Bearer ' + tok });
      if (resp.statusCode == 200) {
        me = json.decode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; });
  }

  Future<void> _logout() async {
    await AuthStore.saveToken(null);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Widget _buildNotLoggedInState(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.white],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Color(0xFFFF6B00).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_outline,
                        size: 64,
                        color: Color(0xFFFF6B00),
                      ),
                    ),
                    SizedBox(height: 24),
                    Text(
                      AppLocalizations.of(context)!.notLoggedIn,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Sign in to access your profile and manage your account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.loginAction,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
                      child: Text(
                        AppLocalizations.of(context)!.createAccount,
                        style: TextStyle(
                          color: Color(0xFFFF6B00),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedInState(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.grey[50]!],
        ),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            // Profile Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Color(0xFFFF6B00).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person,
                      size: 48,
                      color: Color(0xFFFF6B00),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    me?['username']?.toString() ?? 'User',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    me?['email']?.toString() ?? '',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            
            // User Information Card
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 20),
                  _buildInfoRow(Icons.person_outline, AppLocalizations.of(context)!.usernameLabel, me?['username']?.toString() ?? ''),
                  SizedBox(height: 16),
                  _buildInfoRow(Icons.email_outlined, AppLocalizations.of(context)!.emailLabel, me?['email']?.toString() ?? ''),
                  if ((me?['phone']?.toString().isNotEmpty ?? false)) ...[
                    SizedBox(height: 16),
                    _buildInfoRow(Icons.phone_outlined, AppLocalizations.of(context)!.phoneLabel, me!['phone'].toString()),
                  ],
                  SizedBox(height: 16),
                  _buildInfoRow(Icons.lock_outline, AppLocalizations.of(context)!.passwordLabel, 'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢'),
                ],
              ),
            ),
            SizedBox(height: 24),
            
            // Action Buttons
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account Actions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 20),
                  _buildActionButton(
                    Icons.directions_car_outlined,
                    'My Listings',
                    () {
                      Navigator.pushNamed(context, '/my_listings');
                    },
                  ),
                  SizedBox(height: 12),
                  _buildActionButton(
                    Icons.analytics_outlined,
                    'Analytics',
                    () {
                      Navigator.pushNamed(context, '/analytics');
                    },
                  ),
                  SizedBox(height: 12),
                  _buildActionButton(
                    Icons.chat_outlined,
                    'Chat',
                    () {
                      Navigator.pushNamed(context, '/chat');
                    },
                  ),
                  SizedBox(height: 12),
                  Consumer<CarComparisonStore>(
                    builder: (context, comparisonStore, child) {
                      return _buildActionButton(
                        Icons.compare_arrows,
                        'Car Comparison (${comparisonStore.comparisonCount})',
                        () {
                          Navigator.pushNamed(context, '/comparison');
                        },
                      );
                    },
                  ),
                  SizedBox(height: 12),
                  _buildActionButton(
                    Icons.edit_outlined,
                    'Edit Profile',
                    () {
                      // TODO: Implement edit profile functionality
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Edit profile feature coming soon!')),
                      );
                    },
                  ),
                  SizedBox(height: 12),
                  _buildActionButton(
                    Icons.settings_outlined,
                    'Settings',
                    () {
                      // TODO: Implement settings functionality
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Settings feature coming soon!')),
                      );
                    },
                  ),
                  SizedBox(height: 12),
                  _buildActionButton(
                    Icons.help_outline,
                    'Help & Support',
                    () {
                      // TODO: Implement help functionality
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Help & Support feature coming soon!')),
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            
            // Logout Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => _showLogoutDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.logout,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color(0xFFFF6B00).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Color(0xFFFF6B00)),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Color(0xFFFF6B00).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: Color(0xFFFF6B00)),
            ),
            SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
            Spacer(),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Logout',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.profileTitle),
        backgroundColor: Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : (ApiService.accessToken == null || ApiService.accessToken!.isEmpty)
              ? _buildNotLoggedInState(context)
              : _buildLoggedInState(context),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black87,
        selectedItemColor: Color(0xFFFF6B00),
        unselectedItemColor: Colors.white70,
        currentIndex: 2,
        onTap: (idx) {
          switch (idx) {
            case 0:
              Navigator.pushReplacementNamed(context, '/');
              break;
            case 1:
              Navigator.pushReplacementNamed(context, '/favorites');
              break;
            case 2:
              if (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                Navigator.pushReplacementNamed(context, '/profile');
              }
              break;
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context)!.navHome),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: AppLocalizations.of(context)!.navSaved),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) ? AppLocalizations.of(context)!.navLogin : AppLocalizations.of(context)!.navProfile),
        ],
      ),
    );
  }
}

class PaymentHistoryPage extends StatefulWidget {
  @override
  _PaymentHistoryPageState createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.paymentHistoryTitle)),
      body: Center(child: Text(AppLocalizations.of(context)!.paymentHistoryTitle)),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black87,
        selectedItemColor: Color(0xFFFF6B00),
        unselectedItemColor: Colors.white70,
        currentIndex: 0,
        onTap: (idx) {
          switch (idx) {
            case 0:
              Navigator.pushReplacementNamed(context, '/');
              break;
            case 1:
              Navigator.pushReplacementNamed(context, '/favorites');
              break;
            case 2:
              Navigator.pushReplacementNamed(context, '/login');
              break;
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context)!.navHome),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: AppLocalizations.of(context)!.navSaved),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) ? AppLocalizations.of(context)!.navLogin : AppLocalizations.of(context)!.navProfile),
        ],
      ),
    );
  }
}

class PaymentInitiatePage extends StatefulWidget {
  @override
  _PaymentInitiatePageState createState() => _PaymentInitiatePageState();
}

class _PaymentInitiatePageState extends State<PaymentInitiatePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.paymentInitiateTitle)),
      body: Center(child: Text(AppLocalizations.of(context)!.paymentInitiateTitle)),
    );
  }
}

class ChatConversationPage extends StatefulWidget {
  final String conversationId;
  ChatConversationPage({required this.conversationId});
  @override
  _ChatConversationPageState createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.chatConversationTitle)),
      body: Center(child: Text(AppLocalizations.of(context)!.chatConversationTitle)),
    );
  }
}

class PaymentStatusPage extends StatefulWidget {
  final String paymentId;
  PaymentStatusPage({required this.paymentId});
  @override
  _PaymentStatusPageState createState() => _PaymentStatusPageState();
}

class _PaymentStatusPageState extends State<PaymentStatusPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.paymentStatusTitle)),
      body: Center(child: Text(AppLocalizations.of(context)!.paymentStatusTitle)),
    );
  }
}

class EditListingPage extends StatefulWidget {
  final Map car;
  EditListingPage({required this.car});
  @override
  _EditListingPageState createState() => _EditListingPageState();
}

class _EditListingPageState extends State<EditListingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.editListingTitle)),
      body: Center(child: Text(AppLocalizations.of(context)!.editListingTitle)),
    );
  }
}

class MyListingsPage extends StatefulWidget {
  @override
  _MyListingsPageState createState() => _MyListingsPageState();
}

class SettingsPage extends StatefulWidget {
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class VinScanPage extends StatefulWidget {
  @override
  State<VinScanPage> createState() => _VinScanPageState();
}

class _VinScanPageState extends State<VinScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_vinLabelGlobal(context))),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_done) return;
              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;
              final raw = barcodes.first.rawValue ?? '';
              final vin = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
              if (vin.length >= 11) {
                _done = true;
                Navigator.pop(context, vin);
              }
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: Text(_vinLabelGlobal(context), style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPageState extends State<SettingsPage> {
  bool _pushEnabled = true;
  int _cacheEntries = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _pushEnabled = sp.getBool('push_enabled') ?? true;
    });
  }

  Future<void> _togglePush(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('push_enabled', v);
    setState(() { _pushEnabled = v; });
    final token = sp.getString('push_token');
    if (token != null && token.isNotEmpty) {
      try {
        await http.post(Uri.parse(getApiBase() + '/api/push/preferences'), headers: {'Content-Type': 'application/json'}, body: json.encode({'push_token': token, 'enabled': v}));
      } catch (_) {}
    }
  }

  Future<void> _clearCaches() async {
    final sp = await SharedPreferences.getInstance();
    // Clear known cache keys
    for (final k in sp.getKeys().toList()) {
      if (k.startsWith('cache_home_') || k.startsWith('cache_car_') || k.startsWith('cache_similar_') || k.startsWith('cache_related_') || k == 'cache_favorites') {
        await sp.remove(k);
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.settingsCleared)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.settingsTitle)),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(AppLocalizations.of(context)!.settingsEnablePush),
            value: _pushEnabled,
            onChanged: _togglePush,
          ),
          ListTile(
            title: Text(AppLocalizations.of(context)!.settingsClearCaches),
            subtitle: Text(AppLocalizations.of(context)!.settingsCachesSubtitle),
            trailing: Icon(Icons.delete_outline),
            onTap: _clearCaches,
          ),
        ],
      ),
    );
  }
}

class _MyListingsPageState extends State<MyListingsPage> {
  List<Map<String, dynamic>> myListings = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadMyListings();
  }

  Future<void> _loadMyListings() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) {
        setState(() {
          error = 'Please log in to view your listings';
          isLoading = false;
        });
        return;
      }

      final url = Uri.parse(getApiBase() + '/api/my_listings');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          myListings = data.cast<Map<String, dynamic>>();
          isLoading = false;
        });
        print('MyListings loaded: ${myListings.length} listings');
      } else if (response.statusCode == 401) {
        setState(() {
          error = 'Please log in to view your listings';
          isLoading = false;
        });
        print('MyListings API returned 401 - Authentication failed');
      } else {
        setState(() {
          error = 'Failed to load listings. Please try again.';
          isLoading = false;
        });
        print('MyListings API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      setState(() {
        error = 'Network error. Please check your connection.';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Listings'),
        backgroundColor: Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadMyListings,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F1115), Color(0xFF131722), Color(0xFF0F1115)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: isLoading
            ? Center(child: CircularProgressIndicator())
            : error != null
                ? _buildErrorState()
                : myListings.isEmpty
                    ? _buildEmptyState()
                    : _buildListingsGrid(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black87,
        selectedItemColor: Color(0xFFFF6B00),
        unselectedItemColor: Colors.white70,
        currentIndex: 2,
        onTap: (idx) {
          switch (idx) {
            case 0:
              Navigator.pushReplacementNamed(context, '/');
              break;
            case 1:
              Navigator.pushReplacementNamed(context, '/favorites');
              break;
            case 2:
              if (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                Navigator.pushReplacementNamed(context, '/profile');
              }
              break;
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context)!.navHome),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: AppLocalizations.of(context)!.navSaved),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) ? AppLocalizations.of(context)!.navLogin : AppLocalizations.of(context)!.navProfile),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            SizedBox(height: 16),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadMyListings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFFF6B00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xFFFF6B00).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_car_outlined,
                size: 64,
                color: Color(0xFFFF6B00),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'No Listings Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 8),
            Text(
              'You haven\'t created any car listings yet.\nStart by adding your first car!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/sell'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFFF6B00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add),
                  SizedBox(width: 8),
                  Text('Add Your First Car'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListingsGrid() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.directions_car, color: Color(0xFFFF6B00)),
                SizedBox(width: 12),
                Text(
                  'Your Listings (${myListings.length})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Spacer(),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/sell'),
                  icon: Icon(Icons.add, size: 18),
                  label: Text('Add New'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFF6B00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 0),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.65,
            ),
            itemCount: myListings.length,
            itemBuilder: (context, index) {
              final listing = myListings[index];
              return _buildListingCard(listing);
            },
          ),
        ),
      ],
    );
  }
  Widget _buildListingCard(Map<String, dynamic> listing) {
    // Convert listing data to match home page car format
    final String brand = (listing['brand'] ?? '').toString().trim();
    final String model = (listing['model'] ?? '').toString().trim();
    final String yearStr = (listing['year']?.toString() ?? '').trim();
    final String apiTitle = (listing['title'] ?? '').toString().trim();
    String displayTitle;
    if (apiTitle.isNotEmpty) {
      // Use server-provided title when available to match Home exactly
      displayTitle = apiTitle;
    } else {
      final String base = [
        if (brand.isNotEmpty) brand.toLowerCase(),
        if (model.isNotEmpty) model,
      ].join(' ');
      displayTitle = yearStr.isNotEmpty ? (base + ' (' + yearStr + ')') : base;
    }

    final num? _mileageNum = () {
      final v = listing['mileage'];
      if (v == null) return null;
      if (v is num) return v;
      final s = v.toString().replaceAll(RegExp(r'[^0-9.-]'), '');
      return num.tryParse(s);
    }();
    final String _mileageFormatted = _mileageNum == null
        ? (listing['mileage']?.toString() ?? '')
        : _decimalFormatterGlobal(context).format(_mileageNum);

    final car = {
      'id': listing['id'],
      'brand': brand,
      'title': displayTitle,
      'price': listing['price'],
      'year': listing['year'],
      'mileage': _mileageFormatted,
      'city': listing['city'],
      'image_url': listing['image_url'],
      'images': listing['images'],
      'is_quick_sell': listing['is_quick_sell'] ?? false,
    };
    
    // DUPLICATE the exact Home page card design (not shared component)
    return _buildMyListingsCarCard(context, car);
  }

  // DUPLICATED from Home page buildGlobalCarCard function
  Widget _buildMyListingsCarCard(BuildContext context, Map car) {
    final brand = car['brand'] ?? '';
    final brandId = brandLogoFilenames[brand] ?? brand.toString().toLowerCase().replaceAll(' ', '-').replaceAll('Ã©', 'e').replaceAll('Ã¶', 'o');
    
    return Container(
      height: 205, // Standard height for all car cards
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.pushNamed(
                context,
                '/car_detail',
                arguments: {'carId': car['id']},
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Sell Banner (conditional height)
                if (car['is_quick_sell'] == true || car['is_quick_sell'] == 'true')
                  Container(
                    width: double.infinity,
                    height: 35, // Fixed height for banner
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange, Colors.deepOrange],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.flash_on, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'QUICK SELL',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Image section
                Container(
                  height: (car['is_quick_sell'] == true || car['is_quick_sell'] == 'true') ? 120 : 170,
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: (car['is_quick_sell'] == true || car['is_quick_sell'] == 'true') 
                        ? Radius.zero 
                        : Radius.circular(20),
                      bottom: Radius.zero,
                    ),
                    child: _buildMyListingsCardImageCarousel(context, car),
                  ),
                ),
                // Content section
                Container(
                  height: 85, // Standard height for content
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (car['brand'] != null && car['brand'].toString().isNotEmpty)
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: Container(
                                width: 28,
                                height: 28,
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: CachedNetworkImage(
                                  imageUrl: getApiBase() + '/static/images/brands/' + brandId + '.png',
                                  placeholder: (context, url) => SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                  errorWidget: (context, url, error) => Icon(Icons.directions_car, size: 20, color: Color(0xFFFF6B00)),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              car['title'] ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF6B00),
                                fontSize: 15,
                                height: 1.1,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text(
                        _formatCurrencyGlobal(context, car['price']),
                        style: TextStyle(
                          color: Color(0xFFFF6B00),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Bottom info positioned relative to entire card
          Positioned(
            bottom: 35,
            left: 12,
            right: 12,
            child: Text(
              '${_localizeDigitsGlobal(context, (car['year'] ?? '').toString())} â€¢ ${_localizeDigitsGlobal(context, (car['mileage'] ?? '').toString())} ${AppLocalizations.of(context)!.unit_km}',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          // City name at bottom
          Positioned(
            bottom: 15,
            left: 12,
            child: Text(
              '${_translateValueGlobal(context, car['city']?.toString()) ?? (car['city'] ?? '')}',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // DUPLICATED from Home page _buildGlobalCardImageCarousel function
  Widget _buildMyListingsCardImageCarousel(BuildContext context, Map car) {
    final List<String> urls = () {
      final List<String> u = [];
      final String primary = (car['image_url'] ?? '').toString();
      final List<dynamic> imgs = (car['images'] is List) ? (car['images'] as List) : const [];
      if (primary.isNotEmpty) {
        u.add(getApiBase() + '/static/uploads/' + primary);
      }
      for (final dynamic it in imgs) {
        final s = it.toString();
        if (s.isNotEmpty) {
          final full = getApiBase() + '/static/uploads/' + s;
          if (!u.contains(full)) u.add(full);
        }
      }
      return u;
    }();

    if (urls.isEmpty) {
      return Container(
        color: Colors.grey[900],
        width: double.infinity,
        child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
      );
    }

    final PageController controller = PageController();
    int currentIndex = 0;

    return StatefulBuilder(
      builder: (context, setState) {
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/car_detail',
                  arguments: {'carId': car['id']},
                );
              },
              child: PageView.builder(
                controller: controller,
                onPageChanged: (i) => setState(() => currentIndex = i),
                itemCount: urls.length,
                itemBuilder: (context, i) {
                  final url = urls[i];
                  return CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.white10,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[900],
                      child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
                    ),
                  );
                },
              ),
            ),
            if (urls.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(urls.length, (i) {
                    final active = i == currentIndex;
                    return AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      margin: EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 8 : 6,
                      height: active ? 8 : 6,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white70,
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

}
