import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
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
import '../models/analytics_model.dart';
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
import '../shared/listings/listing_events.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/listings/listing_status.dart';
import '../shared/listings/listing_sold_badge.dart';
import '../shared/listings/listing_share.dart';
import '../shared/listings/listing_card_media.dart';
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
import '../services/config.dart';
import '../services/ai_service.dart';
import '../services/car_service.dart';
import '../services/push_notification_service.dart';
import '../services/websocket_service.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import '../pages/chat_pages.dart' as carzo_chat;
import '../pages/dealers_directory_page.dart';
import '../shared/listings/listing_management.dart'
    show
        confirmAndDeleteListing,
        confirmMarkListingSold,
        openEditListingPage,
        setListingSoldStatus;
import '../shared/listings/listing_owner.dart';
import '../features/comparison/state/car_comparison_store.dart';
import '../data/car_catalog.dart';
import '../data/car_name_translations.dart';
import '../services/car_spec_index.dart';
import '../services/saved_search_service.dart';
import '../services/recently_viewed_service.dart';
import '../pages/legal_document_page.dart';
import '../shared/account/delete_account_dialog.dart';
import '../shared/trust/report_dialog.dart';
import '../models/online_spec_variant.dart';
import '../widgets/in_app_video_screen.dart';
import '../pages/listing_image_gallery_page.dart';
import '../widgets/network_video_thumbnail.dart';
part '../pages/home_page.dart';
part '../pages/sell_flow_page.dart';
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

String getApiBase() {
  // Must match [effectiveApiBase] so listing fetches and [ApiService] hit the same host.
  return effectiveApiBase();
}

String _buildFullImageUrl(String rel) => buildLegacyFullImageUrl(rel);

/// Listing image widget using Image.network (avoids CachedNetworkImage HTTP issues on Android).
/// Includes a small auto-retry to reduce transient "connection closed" failures.
Widget _listingNetworkImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) {
  if (url.isEmpty) {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
      ),
    );
  }
  return _RetryingListingNetworkImage(
    url: url,
    fit: fit,
    width: width,
    height: height,
  );
}

class _RetryingListingNetworkImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  const _RetryingListingNetworkImage({
    required this.url,
    required this.fit,
    this.width,
    this.height,
  });

  @override
  State<_RetryingListingNetworkImage> createState() =>
      _RetryingListingNetworkImageState();
}

class _RetryingListingNetworkImageState
    extends State<_RetryingListingNetworkImage> {
  int _attempt = 0;
  bool _retryScheduled = false;
  // Connection drops can happen when serving many large images; retry a bit more with backoff.
  static const int _maxRetries = 5;

  String _fallbackUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      // If we got a bare filename under /static/uploads/, it often actually lives in /static/uploads/car_photos/.
      // Example wrong:  /static/uploads/processed_x.jpg
      // Example right:   /static/uploads/car_photos/processed_x.jpg
      if (path.contains('/static/uploads/') &&
          !path.contains('/static/uploads/car_photos/')) {
        final idx = path.indexOf('/static/uploads/');
        final after = path.substring(idx + '/static/uploads/'.length);
        if (after.isNotEmpty && !after.contains('/')) {
          final newPath =
              '${path.substring(0, idx)}/static/uploads/car_photos/$after';
          return uri.replace(path: newPath).toString();
        }
      }
    } catch (e, st) { logNonFatal(e, st); }
    return url;
  }

  String get _effectiveUrl {
    // Attempt 0: original
    // Attempt 1: fallback path variant (fixes some backend path variants)
    if (_attempt == 1) return _fallbackUrl(widget.url);
    return widget.url;
  }

  void _scheduleRetry() {
    if (_attempt >= _maxRetries) return;
    if (_retryScheduled) return;
    _retryScheduled = true;
    final delayMs =
        700 * (1 << _attempt).clamp(1, 8); // 700ms, 1.4s, 2.8s... capped
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      setState(() {
        _attempt += 1;
        _retryScheduled = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _effectiveUrl;
    return Image.network(
      url,
      key: ValueKey('$url#$_attempt'),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.white10,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          (loadingProgress.expectedTotalBytes ?? 1)
                    : null,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        try {
          debugPrint(
            'Listing image failed (attempt=$_attempt): $url :: $error',
          );
        } catch (e, st) { logNonFatal(e, st); }
        _scheduleRetry();
        return Container(
          color: Colors.grey[900],
          child: Center(
            child: Icon(
              Icons.directions_car,
              size: 60,
              color: Colors.grey[400],
            ),
          ),
        );
      },
    );
  }
}

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

  return Padding(
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

String _couldNotLoadListingsTextGlobal(BuildContext context) =>
    couldNotLoadListingsText(context);

String? _convertSortToApiValue(BuildContext context, String? sortOption) =>
    convertSortToApiValue(context, sortOption);

bool _isExcludedTransmissionFilter(String value) =>
    isExcludedTransmissionFilter(value);

String? _translateValueGlobal(BuildContext context, String? raw) =>
    translateListingValue(context, raw);

/// Localized car title for cards: brand + model (translated), no trim, no year.
String _localizedCarTitleForCard(BuildContext context, Map car) {
  final title = CarNameTranslations.getLocalizedCarTitleNoYear(
    context,
    Map<String, dynamic>.from(car),
  );
  final raw = title.isEmpty ? (car['title']?.toString() ?? '') : title;
  return prettyTitleCase(raw);
}

/// Trim line for listing cards (under brand+model, above price). Empty if none / base.
String _localizedTrimForCard(BuildContext context, Map car) {
  final trim = car['trim']?.toString().trim();
  if (trim == null || trim.isEmpty) return '';
  if (trim.toLowerCase() == 'base') return '';
  return _translateValueGlobal(context, trim) ?? trim;
}

/// Normalizes API listing / favorite payloads into the shape expected by [buildGlobalCarCard].
Map<String, dynamic> mapListingToGlobalCarCardData(
  BuildContext context,
  Map<String, dynamic> listing,
) =>
    listing_card_data.mapListingToGlobalCarCardData(context, listing);

String _listingUploadedAgo(BuildContext context, Map car) =>
    listingUploadedAgo(context, car);

/// Video count pill used on global listing cards (grid + list layout).
Widget _globalListingCardVideoCountBadge(Map car) {
  return Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.videocam, color: Colors.white, size: 16),
        const SizedBox(width: 4),
        Text(
          '${(car['videos'] as List).length}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

/// Title / price / mileage block shared by grid and horizontal list listing cards.
Widget _buildGlobalCarCardInnerText(
  BuildContext context,
  Map car, {
  required String brandId,
  required String trimLine,
  required String yearDisplay,
  required String mileageDisplay,
  required String cityLine,
  required Color dividerLineColor,
  required Color metaTextColor,
  bool pinBottomMeta = false,
}) {
  // Keep the title box height stable (prevents card overflows), but render the
  // brand+model text larger so it has stronger hierarchy than trim.
  const double titleBoxFontSize = 15;
  const double titleFontSize = 17;
  const double titleLineHeight = 1.1;
  const int titleMaxLines = 2;
  final double reservedTitleHeight =
      titleBoxFontSize * titleLineHeight * titleMaxLines;
  final bool hasTrim = trimLine.isNotEmpty;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: pinBottomMeta ? MainAxisSize.max : MainAxisSize.min,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final double maxW = constraints.maxWidth;
          final double logoSize = maxW < 150 ? 22 : (maxW < 175 ? 24 : 28);
          final double logoInner = logoSize - 4;
          final double gap = maxW < 150 ? 6 : 8;
          final double effectiveTitleFontSize =
              maxW < 150 ? 15 : (maxW < 175 ? 16 : titleFontSize);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (car['brand'] != null && car['brand'].toString().isNotEmpty)
                SizedBox(
                  width: logoSize,
                  height: logoSize,
                  child: Container(
                    width: logoSize,
                    height: logoSize,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: null,
                    ),
                    child: CachedNetworkImage(
                      imageUrl:
                          '${getApiBase()}/static/images/brands/$brandId.png',
                      placeholder: (context, url) => SizedBox(
                        width: logoInner,
                        height: logoInner,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.directions_car,
                        size: 20,
                        color: Color(0xFFFF6B00),
                      ),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              SizedBox(width: gap),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    height: reservedTitleHeight,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AutoSizeText(
                        _localizedCarTitleForCard(context, car),
                        textScaleFactor: 1.0,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6B00),
                          fontSize: effectiveTitleFontSize,
                          height: titleLineHeight,
                        ),
                        maxLines: titleMaxLines,
                        minFontSize: 12,
                        stepGranularity: 0.5,
                        overflow: TextOverflow.clip,
                        softWrap: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 10),
      Visibility(
        visible: hasTrim,
        maintainAnimation: true,
        maintainSize: true,
        maintainState: true,
        child: Text(
          trimLine,
          textScaler: const TextScaler.linear(1.0),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFFF6B00),
            fontSize: 15,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
      const SizedBox(height: 6),
      Visibility(
        visible: hasTrim,
        maintainAnimation: true,
        maintainSize: true,
        maintainState: true,
        child: Divider(height: 1, thickness: 1, color: dividerLineColor),
      ),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              yearDisplay.isNotEmpty
                  ? yearDisplay
                  : _formatCurrencyGlobal(context, car['price']),
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                color: Color(0xFFFF6B00),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (yearDisplay.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  _formatCurrencyGlobal(context, car['price']),
                  textScaler: const TextScaler.linear(1.0),
                  style: TextStyle(
                    color: Color(0xFFFF6B00),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          ],
        ],
      ),
      if (pinBottomMeta) const Spacer(),
      if (mileageDisplay.isNotEmpty || cityLine.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 1,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: mileageDisplay.isNotEmpty
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          mileageDisplay,
                          textScaler: const TextScaler.linear(1.0),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: TextStyle(
                            color: metaTextColor,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (mileageDisplay.isNotEmpty && cityLine.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Container(
                    width: 1,
                    height: 12,
                    color: metaTextColor.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
            if (cityLine.isNotEmpty)
              Expanded(
                flex: 1,
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_city,
                            size: 12,
                            color: metaTextColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cityLine,
                            textScaler: const TextScaler.linear(1.0),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: metaTextColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ],
  );
}

// Global car card building function to ensure consistency across all pages
Widget buildGlobalCarCard(
  BuildContext context,
  Map car, {
  bool listLayout = false,
  int carouselResetSeed = 0,
  VoidCallback? onCardTap,
}) {
  final brand = car['brand'] ?? '';
  final brandId =
      brandLogoFilenames[brand] ??
      brand
          .toString()
          .toLowerCase()
          .replaceAll(' ', '-')
          .replaceAll('Ã©', 'e')
          .replaceAll('Ã¶', 'o');
  final trimLine = _localizedTrimForCard(context, car);
  final bool quickSell =
      car['is_quick_sell'] == true || car['is_quick_sell'] == 'true';
  final bool sold = isListingSold(Map<String, dynamic>.from(car));
  final String yearRaw = (car['year'] ?? '').toString().trim();
  final String mileageRaw = (car['mileage'] ?? '').toString().trim();
  String? cityRaw;
  for (final key in const ['city', 'location', 'city_name']) {
    final v = car[key];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) {
      cityRaw = s;
      break;
    }
  }
  final String cityLine = cityRaw == null || cityRaw.isEmpty
      ? ''
      : (_translateValueGlobal(context, cityRaw) ?? cityRaw).trim();
  final locCard = AppLocalizations.of(context)!;
  final String yearDisplay = yearRaw.isEmpty
      ? ''
      : _localizeDigitsGlobal(context, yearRaw);
  final num? mileageNum = mileageRaw.isEmpty
      ? null
      : num.tryParse(mileageRaw.replaceAll(RegExp(r'[^0-9.]'), ''));
  final String mileageDisplay = mileageRaw.isEmpty
      ? ''
      : '${_localizeDigitsGlobal(context, mileageNum == null ? mileageRaw : _decimalFormatterGlobal(context).format(mileageNum))} ${locCard.unit_km}';

  final isLight = Theme.of(context).brightness == Brightness.light;
  // On dark shell: true frosted overlay. On light shell: solid blend so color matches dark mode.
  final cardFill = isLight
      ? AppThemes.listingCardFillGridOnLightShell()
      : Colors.white.withValues(alpha: 0.10);
  final metaTextColor = Colors.white70;
  final dividerLineColor = Colors.white24;
  final bool showVideoCountBadge =
      car['videos'] != null && (car['videos'] as List).isNotEmpty;
  final EdgeInsets listingCardTextPadding = listLayout
      // Horizontal cards: keep top tighter so title sits higher; keep a bit of bottom room.
      ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
      : const EdgeInsets.fromLTRB(12, 8, 12, 10);

  Widget wrapCardTextTap(Widget child) {
    if (onCardTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCardTap,
        child: child,
      ),
    );
  }

  void onPublishedCardTap() {
    final carId = (car['id'] ?? '').toString().trim();
    if (carId.isEmpty) return;
    unawaited(
      RecentlyViewedService.recordView(
        carId,
        snapshot: Map<String, dynamic>.from(car),
      ),
    );
    Navigator.pushNamed(
      context,
      '/car_detail',
      arguments: {'carId': carId},
    );
  }

  final Widget cardInner = listLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    if (car['is_quick_sell'] == true ||
                        car['is_quick_sell'] == 'true')
                      Container(
                        width: double.infinity,
                        height: 35,
                        padding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.orange, Colors.deepOrange],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
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
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 4,
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(
                                  (car['is_quick_sell'] == true ||
                                          car['is_quick_sell'] == 'true')
                                      ? 0
                                      : 20,
                                ),
                                bottomLeft: const Radius.circular(20),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildGlobalCardImageCarousel(
                                    context,
                                    car,
                                    carouselResetSeed: carouselResetSeed,
                                    enableDetailTap: onCardTap == null,
                                  ),
                                  if (showVideoCountBadge)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: _globalListingCardVideoCountBadge(
                                        car,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 6,
                            child: wrapCardTextTap(
                              Padding(
                                padding: listingCardTextPadding,
                                child: SizedBox(
                                  width: double.infinity,
                                  height: double.infinity,
                                  child: _buildGlobalCarCardInnerText(
                                    context,
                                    car,
                                    brandId: brandId,
                                    trimLine: trimLine,
                                    yearDisplay: yearDisplay,
                                    mileageDisplay: mileageDisplay,
                                    cityLine: cityLine,
                                    dividerLineColor: dividerLineColor,
                                    metaTextColor: metaTextColor,
                                    pinBottomMeta: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Quick Sell Banner (conditional height)
                    if (car['is_quick_sell'] == true ||
                        car['is_quick_sell'] == 'true')
                      Container(
                        width: double.infinity,
                        height: 35, // Fixed height for banner
                        padding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.orange, Colors.deepOrange],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
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
                    SizedBox(
                      height: quickSell ? 120 : 170,
                      child: ClipRRect(
                        borderRadius: BorderRadius.vertical(
                          top:
                              (car['is_quick_sell'] == true ||
                                      car['is_quick_sell'] == 'true')
                                  ? Radius.zero
                                  : Radius.circular(20),
                          bottom: Radius.zero,
                        ),
                        child: _buildGlobalCardImageCarousel(
                          context,
                          car,
                          carouselResetSeed: carouselResetSeed,
                          enableDetailTap: onCardTap == null,
                        ),
                      ),
                    ),
                    // Content section (year/mileage + city below price — in flow, no overlap)
                    Expanded(
                      child: wrapCardTextTap(
                        Padding(
                          padding: listingCardTextPadding,
                          child: _buildGlobalCarCardInnerText(
                            context,
                            car,
                            brandId: brandId,
                            trimLine: trimLine,
                            yearDisplay: yearDisplay,
                            mileageDisplay: mileageDisplay,
                            cityLine: cityLine,
                            dividerLineColor: dividerLineColor,
                            metaTextColor: metaTextColor,
                            pinBottomMeta: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                );

  return Container(
    decoration: BoxDecoration(
      color: cardFill,
      borderRadius: BorderRadius.circular(20),
      border: null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (onCardTap == null)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onPublishedCardTap,
            child: cardInner,
          )
        else
          cardInner,
        if (!listLayout && showVideoCountBadge)
          Positioned(
            top: 12,
            right: 12,
            child: _globalListingCardVideoCountBadge(car),
          ),
        if (sold)
          Positioned(
            top: listLayout ? 8 : 12,
            left: listLayout ? 8 : 12,
            child: buildListingSoldBadge(context),
          ),
      ],
    ),
  );
}

// Global image carousel for consistency
Widget _buildGlobalCardImageCarousel(
  BuildContext context,
  Map car, {
  int carouselResetSeed = 0,
  bool enableDetailTap = true,
}) {
  final slots = ListingCardMedia.collectFromCar(
    car,
    resolveNetworkUrl: _buildFullImageUrl,
  );

  if (slots.isEmpty) {
    return Container(
      color: Colors.grey[900],
      width: double.infinity,
      child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
    );
  }

  int currentIndex = 0;
  const int kMaxVisibleDots = 6;
  int dotWindowStart = 0;
  bool dotWindowForward = true;

  return StatefulBuilder(
    key: ValueKey(
      'global_card_carousel_${car['id'] ?? car['draftId'] ?? ''}_$carouselResetSeed',
    ),
    builder: (context, setState) {
      int computeDotStart(int index) {
        final int visible =
            slots.length < kMaxVisibleDots ? slots.length : kMaxVisibleDots;
        if (visible <= 0 || slots.length <= visible) return 0;
        final int maxStart = (slots.length - visible).clamp(0, slots.length);
        return (index - (visible - 1)).clamp(0, maxStart);
      }

      final pageView = PageView.builder(
        onPageChanged: (i) {
          setState(() {
            currentIndex = i;
            final nextStart = computeDotStart(i);
            if (nextStart != dotWindowStart) {
              dotWindowForward = nextStart > dotWindowStart;
              dotWindowStart = nextStart;
            }
          });
        },
        itemCount: slots.length,
        itemBuilder: (context, i) {
          return ListingCardMedia.buildCarouselImage(
            slots[i],
            networkBuilder: _listingNetworkImage,
            fit: BoxFit.cover,
          );
        },
      );

      final carId = (car['id'] ?? '').toString().trim();
      final Widget pager = enableDetailTap && carId.isNotEmpty
          ? GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/car_detail',
                  arguments: {'carId': carId},
                );
              },
              child: pageView,
            )
          : pageView;

      return Stack(
        fit: StackFit.expand,
        children: [
          pager,
          if (slots.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: () {
                  final int visible = slots.length < kMaxVisibleDots
                      ? slots.length
                      : kMaxVisibleDots;
                  if (visible <= 1) return const SizedBox.shrink();

                  Widget buildDotRow(int startIndex) {
                    return Row(
                      key: ValueKey<int>(startIndex),
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(visible, (j) {
                        final i = startIndex + j;
                        final active = i == currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 8 : 6,
                          height: active ? 8 : 6,
                          decoration: BoxDecoration(
                            color: active ? Colors.white : Colors.white70,
                            shape: BoxShape.circle,
                          ),
                        );
                      }),
                    );
                  }

                  final start = dotWindowStart.clamp(
                    0,
                    (slots.length - visible).clamp(0, slots.length),
                  );

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      final beginX = dotWindowForward ? 1.0 : -1.0;
                      final slide = Tween<Offset>(
                        begin: Offset(beginX, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      final fade = Tween<double>(begin: 0, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      );
                      return ClipRect(
                        child: SlideTransition(
                          position: slide,
                          child: FadeTransition(opacity: fade, child: child),
                        ),
                      );
                    },
                    child: buildDotRow(start),
                  );
                }(),
              ),
            ),
        ],
      );
    },
  );
}

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

/// [InteractiveViewer] that only enables **pan** after pinch-zoom so horizontal
/// swipes are handled by the parent [PageView] (e.g. to reach video slides).
class _FullscreenZoomableSlide extends StatefulWidget {
  const _FullscreenZoomableSlide({required this.child});

  final Widget child;

  @override
  State<_FullscreenZoomableSlide> createState() =>
      _FullscreenZoomableSlideState();
}

class _FullscreenZoomableSlideState extends State<_FullscreenZoomableSlide> {
  final TransformationController _tc = TransformationController();

  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_syncZoom);
  }

  void _syncZoom() {
    if (!mounted) return;
    final s = _tc.value.storage;
    final scale = math.sqrt(s[0] * s[0] + s[4] * s[4] + s[8] * s[8]);
    final z = scale > 1.02;
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  @override
  void dispose() {
    _tc.removeListener(_syncZoom);
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _tc,
      minScale: 0.8,
      maxScale: 4.0,
      panEnabled: _zoomed,
      scaleEnabled: true,
      child: Center(child: widget.child),
    );
  }
}

class FullScreenGalleryPage extends StatefulWidget {
  final List<String> imageUrls;
  final List<String> videoUrls;
  final int initialIndex;
  const FullScreenGalleryPage({
    super.key,
    required this.imageUrls,
    this.videoUrls = const [],
    this.initialIndex = 0,
  });
  @override
  State<FullScreenGalleryPage> createState() => _FullScreenGalleryPageState();
}

class _FullScreenGalleryPageState extends State<FullScreenGalleryPage> {
  late final PageController _controller;
  late int _index;
  late final int _mediaCount;

  bool _isVideoSlide(int index) => index >= widget.imageUrls.length;

  @override
  void initState() {
    super.initState();
    _mediaCount = widget.imageUrls.length + widget.videoUrls.length;
    _index = widget.initialIndex.clamp(
      0,
      _mediaCount > 0 ? _mediaCount - 1 : 0,
    );
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
        title: _mediaCount > 0
            ? Text(
                '${_index + 1}/$_mediaCount',
                style: TextStyle(color: Colors.white),
              )
            : null,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: _mediaCount,
            itemBuilder: (context, i) {
              if (_isVideoSlide(i)) {
                final videoIndex = i - widget.imageUrls.length;
                final videoUrl = widget.videoUrls[videoIndex];
                return GalleryEmbeddedVideoPlayer(
                  videoUrl: videoUrl,
                  isActive: i == _index,
                );
              }

              final url = widget.imageUrls[i];
              return _FullscreenZoomableSlide(
                child: url.isEmpty
                    ? Icon(
                        Icons.directions_car,
                        size: 48,
                        color: Colors.white38,
                      )
                    : _listingNetworkImage(url, fit: BoxFit.contain),
              );
            },
          ),
          if (_mediaCount > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: BouncingScrollPhysics(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_mediaCount, (i) {
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

/// Full-screen gallery for listing preview: supports both local XFile and URL strings.
class ListingPreviewGalleryPage extends StatefulWidget {
  final List<dynamic> imageFilesOrUrls;
  final List<dynamic> videoFilesOrUrls;
  final int initialIndex;

  const ListingPreviewGalleryPage({
    super.key,
    required this.imageFilesOrUrls,
    this.videoFilesOrUrls = const [],
    this.initialIndex = 0,
  });

  @override
  State<ListingPreviewGalleryPage> createState() =>
      _ListingPreviewGalleryPageState();
}

class _ListingPreviewGalleryPageState extends State<ListingPreviewGalleryPage> {
  late final PageController _controller;
  late int _index;
  late final int _mediaCount;

  bool _isVideoSlide(int index) => index >= widget.imageFilesOrUrls.length;

  @override
  void initState() {
    super.initState();
    _mediaCount =
        widget.imageFilesOrUrls.length + widget.videoFilesOrUrls.length;
    _index = widget.initialIndex.clamp(
      0,
      _mediaCount > 0 ? _mediaCount - 1 : 0,
    );
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildImage(BuildContext context, dynamic item) {
    if (item is XFile) {
      return Image.file(File(item.path), fit: BoxFit.contain);
    }
    final url = item.toString().trim();
    final fullUrl = url.startsWith('http') ? url : _buildFullImageUrl(url);
    return _listingNetworkImage(fullUrl, fit: BoxFit.contain);
  }

  Widget _buildVideo(BuildContext context, dynamic item, bool isActive) {
    final String raw = item is XFile ? item.path : item.toString().trim();
    if (raw.isEmpty) {
      return const Center(
        child: Icon(Icons.videocam_off, color: Colors.white38, size: 48),
      );
    }
    final String source =
        (raw.startsWith('http://') || raw.startsWith('https://'))
        ? (raw.startsWith('http') ? raw : _buildFullImageUrl(raw))
        : raw;
    return GalleryEmbeddedVideoPlayer(videoUrl: source, isActive: isActive);
  }

  @override
  Widget build(BuildContext context) {
    if (_mediaCount == 0) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Icon(Icons.directions_car, size: 64, color: Colors.white38),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        title: Text('${_index + 1}/$_mediaCount'),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: _mediaCount,
            itemBuilder: (context, i) {
              if (_isVideoSlide(i)) {
                final videoIndex = i - widget.imageFilesOrUrls.length;
                final videoItem = widget.videoFilesOrUrls[videoIndex];
                return _buildVideo(context, videoItem, i == _index);
              }
              return _FullscreenZoomableSlide(
                child: _buildImage(context, widget.imageFilesOrUrls[i]),
              );
            },
          ),
          if (_mediaCount > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_mediaCount, (i) {
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

// Search Dialog Widget
class _SearchDialog extends StatefulWidget {
  final Function(String) onBrandSelected;
  final Function(String, String) onModelSelected;
  final List<String> brands;
  final Map<String, List<String>> models;

  const _SearchDialog({
    required this.onBrandSelected,
    required this.onModelSelected,
    required this.brands,
    required this.models,
  });

  @override
  _SearchDialogState createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredBrands = [];
  List<Map<String, String>> _filteredModels = [];
  bool _isSearchingBrands = true;

  ButtonStyle _searchModeButtonStyle({required bool selected}) {
    final backgroundColor = selected
        ? const Color(0xFFFF6B00)
        : Colors.white.withValues(alpha: 0.12);
    final foregroundColor = selected ? Colors.white : Colors.white70;
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      disabledBackgroundColor: backgroundColor,
      disabledForegroundColor: foregroundColor,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _filteredBrands = List.from(widget.brands);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Rebuilds result lists from the current field text. In model mode, an empty
  /// query shows no rows (typing filters by model name, or by brand to narrow).
  void _rebuildFilteredLists() {
    final raw = _searchController.text.toLowerCase().trim();
    if (_isSearchingBrands) {
      _filteredBrands = widget.brands
          .where((brand) => brand.toLowerCase().contains(raw))
          .toList();
      return;
    }
    if (raw.isEmpty) {
      _filteredModels = [];
      return;
    }
    final seen = <String>{};
    _filteredModels = [];
    for (final brand in widget.brands) {
      final brandModels = widget.models[brand] ?? [];
      if (brand.toLowerCase().contains(raw)) {
        for (final model in brandModels) {
          final key = '$brand|$model';
          if (seen.add(key)) {
            _filteredModels.add({'brand': brand, 'model': model});
          }
        }
      }
      for (final model in brandModels) {
        if (model.toLowerCase().contains(raw)) {
          final key = '$brand|$model';
          if (seen.add(key)) {
            _filteredModels.add({'brand': brand, 'model': model});
          }
        }
      }
    }
    _filteredModels.sort((a, b) {
      final ma = a['model']!.toLowerCase();
      final mb = b['model']!.toLowerCase();
      final c = ma.compareTo(mb);
      if (c != 0) return c;
      return a['brand']!.toLowerCase().compareTo(b['brand']!.toLowerCase());
    });
  }

  void _onSearchChanged() {
    setState(_rebuildFilteredLists);
  }

  void _toggleSearchMode() {
    _searchController.removeListener(_onSearchChanged);
    setState(() {
      _isSearchingBrands = !_isSearchingBrands;
      _searchController.clear();
      _rebuildFilteredLists();
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 500,
        height: 600,
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _trLegacyText(
                    context,
                    'Search Cars',
                    ar: 'البحث عن السيارات',
                    ku: 'گەڕان بە دوای ئۆتۆمبێل',
                  ),
                  style: GoogleFonts.orbitron(
                    color: Color(0xFFFF6B00),
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(height: 20),

            // Search Toggle
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSearchingBrands ? null : _toggleSearchMode,
                    style: _searchModeButtonStyle(selected: _isSearchingBrands),
                    child: Text(
                      _trLegacyText(
                        context,
                        'Search by Brand',
                        ar: 'بحث حسب العلامة',
                        ku: 'گەڕان بە براند',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSearchingBrands ? _toggleSearchMode : null,
                    style: _searchModeButtonStyle(selected: !_isSearchingBrands),
                    child: Text(
                      _trLegacyText(
                        context,
                        'Search by Model',
                        ar: 'بحث حسب الموديل',
                        ku: 'گەڕان بە مۆدێل',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),

            // Search Field
            TextField(
              controller: _searchController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _isSearchingBrands
                    ? _trLegacyText(
                        context,
                        'Search brands...',
                        ar: 'ابحث عن العلامات...',
                        ku: 'گەڕان بە براندەکان...',
                      )
                    : _trLegacyText(
                        context,
                        'Search models...',
                        ar: 'ابحث عن الموديلات...',
                        ku: 'گەڕان بە مۆدێلەکان...',
                      ),
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Color(0xFFFF6B00)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Color(0xFFFF6B00), width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[800],
              ),
            ),
            SizedBox(height: 20),

            // Results
            Expanded(
              child: _isSearchingBrands
                  ? _buildBrandsList()
                  : _buildModelsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandsList() {
    return ListView.builder(
      itemCount: _filteredBrands.length,
      itemBuilder: (context, index) {
        final brand = _filteredBrands[index];
        final logoFile =
            brandLogoFilenames[brand] ??
            brand
                .toLowerCase()
                .replaceAll(' ', '-')
                .replaceAll('Ã©', 'e')
                .replaceAll('Ã¶', 'o');
        final logoUrl = '${getApiBase()}/static/images/brands/$logoFile.png';

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.all(4),
            child: CachedNetworkImage(
              imageUrl: logoUrl,
              placeholder: (context, url) => SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              errorWidget: (context, url, error) => Icon(
                Icons.directions_car,
                size: 24,
                color: Color(0xFFFF6B00),
              ),
              fit: BoxFit.contain,
            ),
          ),
          title: Text(
            CarNameTranslations.getLocalizedBrand(context, brand).isNotEmpty
                ? CarNameTranslations.getLocalizedBrand(context, brand)
                : brand,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          onTap: () => widget.onBrandSelected(brand),
        );
      },
    );
  }

  Widget _buildModelsList() {
    if (_filteredModels.isEmpty) {
      final emptyHint = _searchController.text.trim().isEmpty
          ? 'Type a model name to search. You can also type a brand to see all its models.'
          : 'No models match your search.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400], fontSize: 15),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _filteredModels.length,
      itemBuilder: (context, index) {
        final item = _filteredModels[index];
        final brand = item['brand']!;
        final model = item['model']!;
        final logoFile =
            brandLogoFilenames[brand] ??
            brand
                .toLowerCase()
                .replaceAll(' ', '-')
                .replaceAll('Ã©', 'e')
                .replaceAll('Ã¶', 'o');
        final logoUrl = '${getApiBase()}/static/images/brands/$logoFile.png';

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.all(4),
            child: CachedNetworkImage(
              imageUrl: logoUrl,
              placeholder: (context, url) => SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              errorWidget: (context, url, error) => Icon(
                Icons.directions_car,
                size: 24,
                color: Color(0xFFFF6B00),
              ),
              fit: BoxFit.contain,
            ),
          ),
          title: Text(
            CarNameTranslations.getLocalizedModel(
                  context,
                  brand,
                  model,
                ).isNotEmpty
                ? CarNameTranslations.getLocalizedModel(context, brand, model)
                : model,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            CarNameTranslations.getLocalizedBrand(context, brand).isNotEmpty
                ? CarNameTranslations.getLocalizedBrand(context, brand)
                : brand,
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          onTap: () => widget.onModelSelected(brand, model),
        );
      },
    );
  }
}

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


