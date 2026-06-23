import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart' as services;
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/auth/token_store.dart';
import '../shared/text/pretty_title_case.dart';
import '../shared/vin/open_vin_search.dart';
import '../shared/media/media_url.dart';
import '../shared/i18n/locale_formatting.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/i18n/digits.dart';
import '../shared/prefs/sell_draft_step.dart';
import '../shared/ui/keyboard.dart';
import '../shared/debug/app_log.dart';
import '../shared/navigation/route_args.dart';
import '../shared/i18n/listing_field_labels.dart';
import '../shared/i18n/listing_value_labels.dart';
import '../shared/i18n/sort_api_mapping.dart';
import '../shared/listings/transmission_filter.dart';
import '../shared/listings/listing_uploaded_ago.dart';
import '../shared/auth/phone_verification_gate.dart';
import '../shared/errors/user_error_text.dart';
import '../features/home/home_feed_errors.dart';
import '../shared/listings/listing_events.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/listings/listing_status.dart';
import '../shared/listings/listing_sold_badge.dart';
import '../shared/listings/listing_share.dart';
import '../shared/listings/listing_card_data.dart' as listing_card_data;
import '../shared/prefs/listing_layout_prefs.dart';
import '../shared/prefs/sell_draft_media_persistence.dart';
import '../shared/prefs/legacy_sell_draft_prefs.dart';
import '../state/locale_controller.dart' as app_state;
import '../globals.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../widgets/theme_toggle_widget.dart';
import '../services/ai_service.dart';
import '../services/car_service.dart';
import '../services/push_notification_service.dart';
import '../services/websocket_service.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import '../features/chat/chat_pages.dart' as carzo_chat;
import '../pages/dealers_directory_page.dart';
import '../shared/listings/listing_management.dart'
    show
        confirmAndDeleteListing,
        confirmMarkListingSold,
        openEditListingPage,
        setListingSoldStatus;
import '../shared/listings/listing_owner.dart';
import '../features/comparison/state/car_comparison_store.dart';
import '../features/listing/listing_mappers.dart';
import '../data/car_catalog.dart';
import '../data/car_name_translations.dart';
import '../services/car_spec_index.dart';
import '../services/saved_search_service.dart';
import '../pages/legal_document_page.dart';
import '../shared/account/delete_account_dialog.dart';
import '../shared/trust/report_dialog.dart';
import '../models/online_spec_variant.dart';
import '../pages/listing_image_gallery_page.dart';
import '../widgets/network_video_thumbnail.dart';
import 'app_api_base.dart';
import '../data/brand_logo_filenames.dart';
import 'widgets/global_listing_card.dart';
import 'widgets/home_search_dialog.dart';
import 'widgets/listing_galleries.dart';
import 'widgets/listing_network_image.dart';

export 'widgets/global_listing_card.dart'
    show
        buildGlobalCarCard,
        localizedCarTitleForCard,
        localizedTrimForCard,
        mapListingToGlobalCarCardData;
export 'widgets/listing_galleries.dart'
    show FullScreenGalleryPage, ListingPreviewGalleryPage;
export 'widgets/home_search_dialog.dart' show HomeSearchDialog;
part '../features/home/widgets/home_feed_states.dart';
part '../features/home/home_page.dart';
part '../features/sell/sell_entry.dart';
part '../features/sell/sell_car_page.dart';
part '../features/sell/sell_step1.dart';
part '../features/sell/sell_step2.dart';
part '../features/sell/sell_step3.dart';
part '../features/sell/sell_step4.dart';
part '../features/sell/sell_step5.dart';
part '../pages/car_details_page.dart';
part '../pages/saved_searches_page.dart';
part '../pages/comparison_page.dart';
part '../pages/production_auth_pages.dart';
part '../pages/production_account_pages.dart';
part 'legacy_fallback_routes.dart';

const List<String> _kOnlineSpecOptionKeys = [
  '_online_opts_transmission',
  '_online_opts_drive',
  '_online_opts_body',
  '_online_opts_fuel',
  '_online_opts_engine_size',
  '_online_opts_cylinder',
  '_online_opts_seating',
];

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
      return _trLegacyText(context, 'GCC', ar: 'خليجي', ku: 'کەنداو');
    case 'us':
      return _trLegacyText(context, 'US', ar: 'أمريكي', ku: 'ئەمەریکی');
    case 'iraq':
      return _trLegacyText(context, 'Iraq', ar: 'عراقي', ku: 'عێراقی');
    case 'canada':
      return _trLegacyText(context, 'Canada', ar: 'كندي', ku: 'کەنەدی');
    case 'eu':
      return _trLegacyText(context, 'EU', ar: 'أوروبي', ku: 'ئەوروپی');
    case 'cn':
      return _trLegacyText(context, 'CN', ar: 'صيني', ku: 'چینی');
    case 'korea':
      return _trLegacyText(context, 'Korea', ar: 'كوري', ku: 'کۆری');
    case 'ru':
      return _trLegacyText(context, 'RU', ar: 'روسي', ku: 'ڕووسی');
    case 'iran':
      return _trLegacyText(context, 'Iran', ar: 'إيراني', ku: 'ئێرانی');
    default:
      return carRegionSpecDisplayLabel(code);
  }
}

bool isValidCarRegionSpecCode(String? s) {
  if (s == null || s.isEmpty) return false;
  return kCarRegionSpecCodes.contains(s.trim().toLowerCase());
}

String _trLegacyText(
  BuildContext context,
  String en, {
  String? ar,
  String? ku,
}) =>
    trLegacyText(context, en, ar: ar, ku: ku);

String _translatePlateTypeLegacy(BuildContext context, String raw) =>
    translatePlateTypeLabel(context, raw);

/// JSON list of [OnlineSpecVariant] maps for correlated step-2 fields (bundled catalog).
const String _kOnlineSpecVariantsKey = '_online_spec_variants';

void _clearOnlineSpecOptionsInCarData(Map<String, dynamic> d) {
  for (final k in _kOnlineSpecOptionKeys) {
    d.remove(k);
  }
  d.remove(_kOnlineSpecVariantsKey);
}

/// After catalog apply, pin step-2 pick lists to this row only (same keys as legacy `_online_opts_*`).
void _applyCatalogSpecConstrainedOptionsToCarData(
  Map<String, dynamic> d,
  CatalogSpecFields f,
) {
  d['_online_opts_transmission'] = [sellFlowTransmissionLabel(f.transmission)];
  d['_online_opts_drive'] = [sellFlowDriveLabel(f.driveType)];
  d['_online_opts_body'] = [sellFlowBodyLabel(f.bodyType)];
  d['_online_opts_fuel'] = [sellFlowFuelLabel(f.fuelType)];
  if (f.engineSizeLiters != null && f.engineSizeLiters! > 0.001) {
    d['_online_opts_engine_size'] = [
      '${f.engineSizeLiters!.toStringAsFixed(1)}${f.displacementSuffix}',
    ];
  }
  if (f.cylinderCount != null && f.cylinderCount! > 0) {
    d['_online_opts_cylinder'] = ['${f.cylinderCount}'];
  }
  final seatLabel = sellFlowNearestSeatingLabel(f.seating);
  if (seatLabel != null) {
    d['_online_opts_seating'] = [seatLabel];
  }
}

void _applyCatalogSellFieldUnionToCarData(
  Map<String, dynamic> d,
  CatalogSellFieldOptions o,
) {
  d['_online_opts_transmission'] = o.transmissions.toList()..sort();
  d['_online_opts_drive'] = o.driveTypes.toList()..sort();
  d['_online_opts_body'] = o.bodyTypes.toList()..sort();
  d['_online_opts_fuel'] = o.fuelTypes.toList()..sort();
  if (o.engineSizes.isNotEmpty) {
    final eng = o.engineSizes.toList()
      ..sort((a, b) {
        final la = OnlineSpecVariant.parseLeadingEngineLiters(a) ?? 0;
        final lb = OnlineSpecVariant.parseLeadingEngineLiters(b) ?? 0;
        final c = la.compareTo(lb);
        if (c != 0) return c;
        return a.compareTo(b);
      });
    d['_online_opts_engine_size'] = eng;
  }
  if (o.cylinderCounts.isNotEmpty) {
    d['_online_opts_cylinder'] = o.cylinderCounts.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
  }
  if (o.seatings.isNotEmpty) {
    d['_online_opts_seating'] = o.seatings.toList()..sort();
  }
}

OnlineSpecVariant _onlineSpecVariantFromCatalogFields(CatalogSpecFields f) {
  return OnlineSpecVariant(
    engineSizeLiters: f.engineSizeLiters,
    displacementSuffix: f.displacementSuffix,
    cylinderCount: f.cylinderCount,
    seating: f.seating,
    fuelEconomy: f.fuelEconomy,
    transmission: f.transmission,
    drivetrain: f.driveType,
    bodyType: f.bodyType,
    engineType: f.engineType,
    fuelType: f.fuelType,
  );
}

// Sideload build flag to disable services that require entitlements on iOS
const bool kSideloadBuild = bool.fromEnvironment(
  'SIDELOAD_BUILD',
  defaultValue: false,
);

/// Navigator key for deep link handling (e.g. reset-password from email link).
final GlobalKey<NavigatorState> productionNavigatorKey = GlobalKey<NavigatorState>();
// Build commit SHA for on-device verification
const String kBuildSha = String.fromEnvironment(
  'BUILD_COMMIT_SHA',
  defaultValue: 'dev',
);

// Flutter sets this at compile time when running `flutter test`.
const bool _kFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

void _debugLog(String message) => appLog(message);

Future<http.MultipartFile> _buildVideoMultipartFile(XFile video) async {
  final path = video.path.trim();
  final file = File(path);
  List<int> headerBytes = const [];
  try {
    final raf = await file.open(mode: FileMode.read);
    headerBytes = await raf.read(64);
    await raf.close();
  } catch (e, st) { logNonFatal(e, st); }

  String? sniffFromHeader() {
    if (headerBytes.length >= 12) {
      // MP4/MOV/3GP family: [size][ftyp][brand...]
      final box = String.fromCharCodes(headerBytes.sublist(4, 8));
      if (box == 'ftyp') {
        final brand = String.fromCharCodes(
          headerBytes.sublist(8, 12),
        ).toLowerCase();
        if (brand.startsWith('qt')) return 'video/quicktime';
        if (brand.startsWith('3g')) return 'video/3gpp';
        return 'video/mp4';
      }
    }
    if (headerBytes.length >= 4) {
      // EBML (webm/mkv)
      if (headerBytes[0] == 0x1A &&
          headerBytes[1] == 0x45 &&
          headerBytes[2] == 0xDF &&
          headerBytes[3] == 0xA3) {
        final lower = String.fromCharCodes(headerBytes).toLowerCase();
        if (lower.contains('webm')) return 'video/webm';
        return 'video/x-matroska';
      }
      // AVI
      if (headerBytes.length >= 12 &&
          String.fromCharCodes(headerBytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(headerBytes.sublist(8, 12)) == 'AVI ') {
        return 'video/x-msvideo';
      }
    }
    return null;
  }

  String mime =
      sniffFromHeader() ??
      lookupMimeType(path, headerBytes: headerBytes) ??
      'video/mp4';
  if (!mime.startsWith('video/')) {
    mime = 'video/mp4';
  }

  final srcName = video.name.trim().isNotEmpty
      ? video.name.trim()
      : p.basename(path);
  final base = p.basenameWithoutExtension(srcName).trim();
  final fallbackBase = base.isNotEmpty
      ? base
      : 'video_${DateTime.now().millisecondsSinceEpoch}';
  String ext = extensionFromMime(mime) ?? '';
  // Normalize edge cases to extensions backend validators commonly accept.
  if (mime == 'video/quicktime') ext = 'mov';
  if (mime == 'video/x-matroska') ext = 'mkv';
  if (ext.isEmpty) {
    ext = p.extension(srcName).replaceFirst('.', '');
  }
  final normalizedExt = ext.isNotEmpty ? ext : 'mp4';
  final filename = '$fallbackBase.$normalizedExt';

  MediaType contentType;
  try {
    contentType = MediaType.parse(mime);
  } catch (e, st) { logNonFatal(e, st); 
    contentType = MediaType('video', 'mp4');
  }

  return http.MultipartFile.fromPath(
    'files',
    path,
    filename: filename,
    contentType: contentType,
  );
}

// Fallback delegates to provide Material/Cupertino/Widgets localizations for 'ku'
class KuMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const KuMaterialLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<MaterialLocalizations> load(Locale locale) {
    // Reuse Arabic material localizations for Kurdish
    return GlobalMaterialLocalizations.delegate.load(const Locale('ar'));
  }

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<MaterialLocalizations> old,
  ) => false;
}

class KuCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const KuCupertinoLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    // Reuse Arabic cupertino localizations for Kurdish
    return GlobalCupertinoLocalizations.delegate.load(const Locale('ar'));
  }

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<CupertinoLocalizations> old,
  ) => false;
}

class KuWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const KuWidgetsLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    // Reuse Arabic widgets localizations for Kurdish
    return GlobalWidgetsLocalizations.delegate.load(const Locale('ar'));
  }

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<WidgetsLocalizations> old,
  ) => false;
}




String _buildFullImageUrl(String rel) => buildLegacyFullImageUrl(rel);

Widget _listingNetworkImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) =>
    listingNetworkImage(url, fit: fit, width: width, height: height);

String? _translateValueGlobal(BuildContext context, String? raw) =>
    translateListingValue(context, raw);

String _localizedCarTitleForCard(BuildContext context, Map car) =>
    localizedCarTitleForCard(context, car);

String _localizedTrimForCard(BuildContext context, Map car) =>
    localizedTrimForCard(context, car);

String _listingUploadedAgo(BuildContext context, Map car) =>
    listingUploadedAgo(context, car);

/// Normalizes API listing / favorite payloads into the shape expected by [buildGlobalCarCard].
Map<String, dynamic> mapListingToGlobalCarCardData(
  BuildContext context,
  Map<String, dynamic> listing,
) =>
    listing_card_data.mapListingToGlobalCarCardData(context, listing);

String _localizeDigitsGlobal(BuildContext context, String input) =>
    localizeDigits(context, input);

String _engineSizeChipLabel(BuildContext context, String raw) =>
    engineSizeChipLabel(context, raw);

String _engineSizeSellRowLabel(BuildContext context, String raw) =>
    engineSizeSellRowLabel(context, raw);

// Locale-aware currency formatting with digit localization
String _formatCurrencyGlobal(BuildContext context, dynamic raw) =>
    formatCurrency(context, raw);

// Custom currency icon widget that shows 'IQD' when IQD is selected
Widget buildCurrencyIcon(String currency) {
  if (currency == 'IQD') {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          'IQD',
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  } else {
    return Icon(Icons.attach_money, size: 24, color: Color(0xFFFF6B00));
  }
}

/// Sell flow: light shell field fill (matches former fancy-selector gradient end).
const Color kSellLightShellFieldFill = Color(0xFFFFF1E6);

Color _sellFlowManualFieldFill(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.black.withValues(alpha: 0.2)
    : kSellLightShellFieldFill;

TextStyle _sellFlowManualFieldLabelStyle(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)
    : TextStyle(color: Colors.grey[800]!, fontSize: 15, fontWeight: FontWeight.w700);

TextStyle _sellFlowManualFieldHintStyle(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const TextStyle(color: Colors.white54)
    : TextStyle(color: Colors.grey[600]!);

TextStyle _sellFlowManualFieldTextStyle(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const TextStyle(color: Colors.white)
    : TextStyle(color: Colors.grey[900]!);

/// Persists home feed scroll when main tabs use [Navigator.pushReplacement],
/// which disposes and rebuilds [HomePage].
class _HomeFeedScrollPersistence {
  _HomeFeedScrollPersistence._();

  static double? _pixels;

  static double get initialOffset => _pixels ?? 0;

  /// Home tab tapped while already on Home (scroll-to-top); keep bucket in sync.
  static void markTop() {
    _pixels = 0;
  }

  /// When the route is disposed before a deferred scroll restore runs, keep the target offset.
  static void savePixels(double pixels) {
    _pixels = pixels;
  }
}

void _switchMainTabNoAnimation(BuildContext context, String routeName) {
  final currentRoute = ModalRoute.of(context)?.settings.name;
  if (currentRoute == routeName) return;

  Widget? page;
  switch (routeName) {
    case '/':
      page = HomePage();
      break;
    case '/favorites':
      page = AuthGuard(child: FavoritesPage());
      break;
    case '/sell':
      page = AuthGuard(child: const SellEntryRouterPage());
      break;
    case '/dealers':
      page = const DealersDirectoryPage();
      break;
    case '/profile':
      page = AuthGuard(child: ProfilePage());
      break;
  }

  if (page == null) {
    Navigator.pushReplacementNamed(context, routeName);
    return;
  }

  Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      settings: RouteSettings(name: routeName),
      pageBuilder: (context, _, _) => page!,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
  );
}

/// Same as [_switchMainTabNoAnimation] but callable from other libraries (e.g. shell pages).
void navigateMainShellTab(BuildContext context, String routeName) {
  _switchMainTabNoAnimation(context, routeName);
}

Widget buildFloatingBottomNav(
  BuildContext context, {
  required int currentIndex,
  required ValueChanged<int> onTap,
  bool solidBackground = false,
}) {
  final brightness = Theme.of(context).brightness;
  final isLight = brightness == Brightness.light;
  final unselectedItemColor = isLight
      ? const Color(0xFF666666)
      : const Color(0xD9FFFFFF);
  final solidFill = isLight ? Colors.white : const Color(0xFF1C1C1E);

  final bar = Theme(
    data: Theme.of(context).copyWith(
      canvasColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: solidBackground ? solidFill : Colors.transparent,
        elevation: 0,
      ),
    ),
    child: BottomNavigationBar(
      key: ValueKey<int>(currentIndex),
      type: BottomNavigationBarType.fixed,
      backgroundColor: solidBackground ? solidFill : Colors.transparent,
      elevation: 0,
      selectedItemColor: const Color(0xFFFF6B00),
      unselectedItemColor: unselectedItemColor,
      selectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      showSelectedLabels: true,
      showUnselectedLabels: true,
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: AppLocalizations.of(context)!.navHome,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.favorite),
          label: AppLocalizations.of(context)!.navSaved,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.storefront_outlined),
          label: AppLocalizations.of(context)!.navDealers,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: AppLocalizations.of(context)!.navProfile,
        ),
      ],
    ),
  );

  final Widget navBody = solidBackground
      ? bar
      : BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: bar,
        );

  return Semantics(
    label: AppLocalizations.of(context)!.navHome,
    child: Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    child: SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: solidBackground ? solidFill : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isLight
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.14),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: navBody,
        ),
      ),
    ),
    ),
  );
}

// Fancy selector tile used in Sell page pickers
Widget buildFancySelector(
  BuildContext context, {
  IconData? icon,
  required String label,
  required String? value,
  Widget? leading,
  bool isError = false,
  String? currency,
}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color accent = const Color(0xFFFF6B00);
  final List<Color> bg = isDark
      ? [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.03)]
      : [kSellLightShellFieldFill, kSellLightShellFieldFill];
  final Color borderColor = isError
      ? Colors.redAccent
      : (isDark ? Colors.white12 : accent.withValues(alpha: 0.25));
  final Color labelColor = isError
      ? Colors.redAccent
      : (isDark ? Colors.white70 : Colors.grey[600]!);
  final loc = AppLocalizations.of(context)!;
  final bool valueShowsAny = value != null &&
      value.isNotEmpty &&
      (value == 'Any' ||
          value.trim().toLowerCase() == 'any' ||
          value == loc.any ||
          value == loc.anyOption);
  final bool isPlaceholder = value == null ||
      value.isEmpty ||
      value == loc.tapToSelect;
  final Color valueColor = isPlaceholder
      ? (isError ? Colors.redAccent : (isDark ? Colors.white38 : Colors.grey))
      : (isError
            ? Colors.redAccent
            : (valueShowsAny
                  ? accent
                  : (isDark ? Colors.white : Colors.grey[900]!)));
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: bg,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 10,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 44,
          decoration: BoxDecoration(
            color: (isError ? Colors.redAccent : accent).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        leading ??
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isError ? Colors.redAccent : accent).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: currency != null
                  ? Center(child: buildCurrencyIcon(currency))
                  : (icon != null
                        ? Icon(icon, color: isError ? Colors.redAccent : accent)
                        : const SizedBox.shrink()),
            ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: labelColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value == null || value.isEmpty
                    ? AppLocalizations.of(context)!.tapToSelect
                    : (value == 'Any'
                          ? AppLocalizations.of(context)!.anyOption
                          : value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String _cancelTextGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.cancelAction;
}

String _pleaseFillRequiredGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.pleaseFillRequired;
}

NumberFormat _decimalFormatterGlobal(BuildContext context) =>
    decimalFormatterForLocale(context);

// Lightweight helpers for translating UI snippets not covered by AppLocalizations
String _yesTextGlobal(BuildContext context) => yesText(context);

String _noTextGlobal(BuildContext context) => noText(context);

String _removedFromComparisonTextGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.removedFromComparison;
}

String _addedToComparisonTextGlobal(BuildContext context, int count) {
  return AppLocalizations.of(context)!.addedToComparison(count, 5);
}

String _comparisonMaxLimitTextGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.comparisonMaxLimit(5);
}

String _compareLabelGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.compareLabel;
}

String _addedLabelGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.addedLabel;
}

String _clearAllTextGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.clearAll;
}

String _tapToSelectTextGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.tapToSelect;
}

String _comparisonClearedTextGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.comparisonCleared;
}

String _statusTitleGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.status;
}

String _quickSellTextGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.quickSell;
}

String _photosRequiredTitleGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.photosRequired;
}

String _videosOptionalTitleGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.videosOptional;
}

String _pleaseSelectPhotoTextGlobal(BuildContext context) =>
    pleaseSelectPhotoText(context);

String _listingSubmittedSuccessTextGlobal(BuildContext context) =>
    listingSubmittedSuccessText(context);

String? _convertSortToApiValue(BuildContext context, String? sortOption) =>
    convertSortToApiValue(context, sortOption);

bool _isExcludedTransmissionFilter(String value) =>
    isExcludedTransmissionFilter(value);


class AuthStore {
  static String? get token => TokenStore.token;
  static Future<void> saveToken(String? t) async {
    await TokenStore.save(t);
    // Keep ApiService in sync for call sites that still use it.
    await ApiService.setAccessToken(TokenStore.token);
  }

  static Future<void> loadToken() async {
    await TokenStore.load();
    await ApiService.setAccessToken(TokenStore.token);
  }
}

class LocaleController {
  static ValueNotifier<Locale?> get currentLocale =>
      app_state.LocaleController.currentLocale;

  static Future<void> loadSavedLocale() =>
      app_state.LocaleController.loadSavedLocale();

  static Future<void> setLocale(Locale? locale) =>
      app_state.LocaleController.setLocale(locale);
}

Widget buildLanguageMenu() {
  return PopupMenuButton<String>(
    icon: const Icon(Icons.language),
    onSelected: (code) {
      LocaleController.setLocale(Locale(code));
    },
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'en', child: Text('English')),
      PopupMenuItem(value: 'ar', child: Text('العربية')),
      PopupMenuItem(value: 'ku', child: Text('کوردی')),
    ],
  );
}

class NoAnimationsPageTransitionsBuilder extends PageTransitionsBuilder {
  const NoAnimationsPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}


//

// Dynamically discovered body types from assets
List<String> globalBodyTypes = ['Any'];
Map<String, String> globalBodyTypeAssetMap = {};

// Global vehicle specifications database - accessible to all pages
final Map<String, Map<String, Map<String, Map<String, dynamic>>>>
globalVehicleSpecs = {
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


// Car Comparison State Management
// NOTE: `CarComparisonStore` now lives in `lib/features/comparison/state/`.

// Comparison Button Widget
class ComparisonButton extends StatelessWidget {
  final Map<String, dynamic> car;
  final bool isCompact;

  const ComparisonButton({
    super.key,
    required this.car,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<CarComparisonStore>(
      builder: (context, comparisonStore, child) {
        // Comparison store uses string IDs (public_id preferred).
        final String carId =
            (car['public_id'] ??
                    car['id'] ??
                    car['car_id'] ??
                    car['carId'] ??
                    car['uuid'])
                .toString()
                .trim();
        final isInComparison = carId.isNotEmpty
            ? comparisonStore.isCarInComparison(carId)
            : false;
        final canAddMore = comparisonStore.canAddMore;

        return Container(
          decoration: BoxDecoration(
            color: isInComparison ? Colors.green : Colors.orange,
            borderRadius: BorderRadius.circular(isCompact ? 14 : 17),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(isCompact ? 14 : 17),
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
                } else if (canAddMore && carId.isNotEmpty) {
                  final normalized = Map<String, dynamic>.from(car);
                  normalized['id'] =
                      carId; // ensure consistent string ID stored
                  comparisonStore.addCarToComparison(normalized);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _addedToComparisonTextGlobal(
                          context,
                          comparisonStore.comparisonCount,
                        ),
                      ),
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
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 7 : 10,
                    vertical: isCompact ? 6 : 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isInComparison ? Icons.check : Icons.compare_arrows,
                        color: Colors.white,
                        size: isCompact ? 16 : 19,
                      ),
                      if (!isCompact) ...[
                        SizedBox(width: 4),
                        Text(
                          isInComparison
                              ? _addedLabelGlobal(context)
                              : _compareLabelGlobal(context),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shown when a logged-out user opens Sell; offers login / signup or cancel.
class _SellAuthPrompt extends StatefulWidget {
  const _SellAuthPrompt();

  @override
  State<_SellAuthPrompt> createState() => _SellAuthPromptState();
}

class _SellAuthPromptState extends State<_SellAuthPrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showAuthDialog());
  }

  Future<void> _showAuthDialog() async {
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    var handled = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(loc.sellRequiresAuthTitle),
        content: Text(loc.sellRequiresAuthBody),
        actions: [
          TextButton(
            onPressed: () {
              handled = true;
              Navigator.pop(ctx);
              _switchMainTabNoAnimation(context, '/');
            },
            child: Text(loc.cancelAction),
          ),
          TextButton(
            onPressed: () {
              handled = true;
              Navigator.pop(ctx);
              Navigator.pushReplacementNamed(context, '/signup');
            },
            child: Text(loc.signupTitle),
          ),
          FilledButton(
            onPressed: () {
              handled = true;
              Navigator.pop(ctx);
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: Text(loc.loginAction),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (!handled) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// Redirects to /login if the user is not authenticated; otherwise shows [child].
/// Special-case: the Favorites page is allowed to show even when logged out
/// so it can display its own "login/signup required" message.
/// Sell shows a login/signup dialog instead of an immediate redirect.
class AuthGuard extends StatelessWidget {
  const AuthGuard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    // Allow FavoritesPage and ProfilePage for logged-out users so they can
    // show their own friendly login/signup prompts and UI.
    if (auth.isAuthenticated ||
        child is FavoritesPage ||
        child is ProfilePage) {
      return child;
    }
    if (auth.isLoading || ApiService.isAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (child is SellCarPage) {
      return const _SellAuthPrompt();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// Theme Toggle Widget
// Moved to lib/widgets/theme_toggle_widget.dart

List<double> _tintColorMatrix(Color color) {
  const double lR = 0.2126;
  const double lG = 0.7152;
  const double lB = 0.0722;
  final double r = color.r;
  final double g = color.g;
  final double b = color.b;
  return [
    lR * r,
    lG * r,
    lB * r,
    0,
    0,
    lR * g,
    lG * g,
    lB * g,
    0,
    0,
    lR * b,
    lG * b,
    lB * b,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
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
    child: _WhiteKeyedImage(
      assetPath: pngAssetPath,
      svgFallbackPath: svgFallbackPath,
    ),
  );
}

// Simple in-memory cache so we only process each icon once per run
final Map<String, Future<ui.Image>> _whiteKeyedCache = {};

class _WhiteKeyedImage extends StatefulWidget {
  final String assetPath;
  final String svgFallbackPath;
  const _WhiteKeyedImage({
    required this.assetPath,
    required this.svgFallbackPath,
  });
  @override
  State<_WhiteKeyedImage> createState() => _WhiteKeyedImageState();
}

class _WhiteKeyedImageState extends State<_WhiteKeyedImage> {
  Future<ui.Image>? _futureImage;

  @override
  void initState() {
    super.initState();
    _futureImage = (_whiteKeyedCache[widget.assetPath] ??=
        _decodePngWithWhiteTransparent(widget.assetPath));
  }

  @override
  void didUpdateWidget(covariant _WhiteKeyedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      setState(() {
        _futureImage = (_whiteKeyedCache[widget.assetPath] ??=
            _decodePngWithWhiteTransparent(widget.assetPath));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _futureImage,
      builder: (context, snap) {
        if (snap.hasData) {
          return RawImage(
            image: snap.data,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          );
        }
        if (snap.hasError) {
          // If the white-key decode fails (or the asset is missing), fall back to
          // the original asset, and finally to a Material icon.
          return Image.asset(
            widget.assetPath,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Icon(
              Icons.directions_car,
              color: Color(0xFF707070),
            ),
          );
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
  final ByteData? raw = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
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

// Helper function to generate video thumbnail
Future<String?> generateVideoThumbnail(String videoPath) async {
  try {
    final thumbnailPath = await VideoThumbnail.thumbnailFile(
      video: videoPath,
      thumbnailPath: (await Directory.systemTemp.createTemp()).path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 200,
      quality: 75,
    );
    return thumbnailPath;
  } catch (e) {
    _debugLog('Error generating video thumbnail: $e');
    return null;
  }
}



