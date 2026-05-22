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
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart' as services;
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
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
import '../shared/listings/listing_events.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/listings/listing_status.dart';
import '../shared/listings/listing_sold_badge.dart';
import '../shared/listings/listing_share.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../state/locale_controller.dart' as app_state;
import '../globals.dart';
import '../pages/analytics_page.dart';
import '../pages/edit_profile_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../chat_ui_theme_controller.dart';
import '../widgets/theme_toggle_widget.dart';
import '../services/config.dart';
import '../services/ai_service.dart';
import '../services/car_service.dart';
import '../services/deep_link_service.dart';
import '../services/websocket_service.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import '../pages/auth_pages.dart' as auth_pages;
import '../pages/chat_pages.dart' as carzo_chat;
import '../pages/reset_password_page.dart';
import '../pages/verify_email_page.dart';
import '../pages/admin_dealers_page.dart';
import '../pages/dealer_profile_page.dart';
import '../pages/dealers_directory_page.dart';
import '../pages/edit_dealer_page.dart';
import '../pages/my_listings_page.dart' as modern_listings;
import '../pages/edit_listing_page.dart' as modern_edit;
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
import '../pages/recently_viewed_page.dart';
import '../pages/help_center_page.dart';
import '../pages/legal_document_page.dart';
import '../pages/admin_reports_page.dart';
import '../shared/trust/report_dialog.dart';
import '../models/online_spec_variant.dart';
import '../widgets/in_app_video_screen.dart';
import '../pages/listing_image_gallery_page.dart';
import '../widgets/network_video_thumbnail.dart';
import '../widgets/edge_swipe_back.dart';
part 'home_page_legacy.dart';
part 'sell_flow_legacy.dart';
part 'car_detail_legacy.dart';

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
}) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return ar ?? en;
  if (code == 'ku' || code == 'ckb') return ku ?? en;
  return en;
}

String _translatePlateTypeLegacy(BuildContext context, String raw) {
  final v = raw.trim().toLowerCase().replaceAll('-', ' ').replaceAll('_', ' ');
  switch (v) {
    case 'private':
      return _trLegacyText(context, 'Private', ar: 'خصوصي', ku: 'تایبەت');
    case 'commercial':
    case 'comercial':
      return _trLegacyText(context, 'Commercial', ar: 'تجاري', ku: 'بازرگانی');
    case 'taxi':
      return _trLegacyText(context, 'Taxi', ar: 'تاكسي', ku: 'تەکسی');
    case 'government':
      return _trLegacyText(context, 'Government', ar: 'حكومي', ku: 'حکومی');
    case 'temporary':
      return _trLegacyText(context, 'Temporary', ar: 'مؤقت', ku: 'کاتی');
    case 'diplomatic':
      return _trLegacyText(context, 'Diplomatic', ar: 'دبلوماسي', ku: 'دیبلۆماسی');
    case 'police':
      return _trLegacyText(context, 'Police', ar: 'شرطة', ku: 'پۆلیس');
    default:
      return prettyTitleCase(raw);
  }
}

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

bool _legacyScalarStep2KeyMissing(Map<String, dynamic> d, String key) {
  final v = d[key]?.toString().trim();
  return v == null || v.isEmpty;
}

/// Step 2 [carData] keys the UI hydrates from (not `_online_opts_*`).
bool _legacyCarDataHasAnyScalarStep2(Map<String, dynamic> d) {
  for (final k in const [
    'transmission',
    'fuel_type',
    'engine_type',
    'body_type',
    'drive_type',
    'engine_size',
    'cylinder_count',
    'seating',
    'fuel_economy',
  ]) {
    if (!_legacyScalarStep2KeyMissing(d, k)) return true;
  }
  return false;
}

bool _legacyHasValidOnlineEngineSizeOpts(Map<String, dynamic> d) {
  final raw = d['_online_opts_engine_size'];
  if (raw is! List || raw.isEmpty) return false;
  for (final e in raw) {
    final x = OnlineSpecVariant.parseLeadingEngineLiters(e.toString());
    if (x != null && x > 0.001) return true;
  }
  return false;
}

bool _legacyCarDataHasOnlineStep2Signals(Map<String, dynamic> d) {
  if (_legacyCarDataHasAnyScalarStep2(d)) return true;
  for (final k in const [
    '_online_opts_transmission',
    '_online_opts_drive',
    '_online_opts_body',
    '_online_opts_fuel',
    '_online_opts_engine_size',
    '_online_opts_cylinder',
    '_online_opts_seating',
  ]) {
    final v = d[k];
    if (v is! List || v.isEmpty) continue;
    if (k == '_online_opts_engine_size' &&
        !_legacyHasValidOnlineEngineSizeOpts(d)) {
      continue;
    }
    return true;
  }
  final v = d[_kOnlineSpecVariantsKey];
  return v is List && v.isNotEmpty;
}

/// Fill any still-missing scalars from the first bundled-catalog spec variant.
void _applyFirstOnlineSpecVariantForMissingScalars(Map<String, dynamic> d) {
  final raw = d[_kOnlineSpecVariantsKey];
  if (raw is! List || raw.isEmpty) return;
  final first = raw.first;
  if (first is! Map) return;
  final v = OnlineSpecVariant.fromJson(Map<String, dynamic>.from(first as Map));
  if (_legacyScalarStep2KeyMissing(d, 'transmission') &&
      v.transmission != null) {
    d['transmission'] = sellFlowTransmissionLabel(v.transmission!);
  }
  if (_legacyScalarStep2KeyMissing(d, 'fuel_type') && v.fuelType != null) {
    d['fuel_type'] = sellFlowFuelLabel(v.fuelType!);
  }
  if (_legacyScalarStep2KeyMissing(d, 'engine_type') && v.engineType != null) {
    d['engine_type'] = v.engineType!;
  }
  if (_legacyScalarStep2KeyMissing(d, 'body_type') && v.bodyType != null) {
    d['body_type'] = sellFlowBodyLabel(v.bodyType!);
  }
  if (_legacyScalarStep2KeyMissing(d, 'drive_type') && v.drivetrain != null) {
    d['drive_type'] = sellFlowDriveLabel(v.drivetrain!);
  }
  if (_legacyScalarStep2KeyMissing(d, 'engine_size') &&
      v.engineSizeLiters != null &&
      v.engineSizeLiters! > 0) {
    d['engine_size'] =
        '${v.engineSizeLiters!.toStringAsFixed(1)}${v.displacementSuffix}';
  }
  if (_legacyScalarStep2KeyMissing(d, 'cylinder_count') &&
      v.cylinderCount != null &&
      v.cylinderCount! > 0) {
    d['cylinder_count'] = '${v.cylinderCount}';
  }
  if (_legacyScalarStep2KeyMissing(d, 'seating') &&
      v.seating != null &&
      v.seating! > 0) {
    d['seating'] = sellFlowNearestSeatingLabel(v.seating) ?? '${v.seating}';
  }
  if (_legacyScalarStep2KeyMissing(d, 'fuel_economy') &&
      v.fuelEconomy != null &&
      v.fuelEconomy!.trim().isNotEmpty) {
    d['fuel_economy'] = v.fuelEconomy!.trim();
  }
}

// Sideload build flag to disable services that require entitlements on iOS
const bool kSideloadBuild = bool.fromEnvironment(
  'SIDELOAD_BUILD',
  defaultValue: false,
);

/// Navigator key for deep link handling (e.g. reset-password from email link).
final GlobalKey<NavigatorState> _appNavigatorKey = GlobalKey<NavigatorState>();
// Build commit SHA for on-device verification
const String kBuildSha = String.fromEnvironment(
  'BUILD_COMMIT_SHA',
  defaultValue: 'dev',
);

// Flutter sets this at compile time when running `flutter test`.
const bool _kFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

void _debugLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

Future<http.MultipartFile> _buildVideoMultipartFile(XFile video) async {
  final path = video.path.trim();
  final file = File(path);
  List<int> headerBytes = const [];
  try {
    final raf = await file.open(mode: FileMode.read);
    headerBytes = await raf.read(64);
    await raf.close();
  } catch (_) {}

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
  } catch (_) {
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

// Normalize relative image path into a full URL that works across
// different backend responses (uploads/, car_photos/, static/, http).
// Absolute URLs that point to our backend are rewritten to use getApiBase()
// so they work on emulator (10.0.2.2) and real device (LAN IP).
String _buildFullImageUrl(String rel) {
  String s = (rel ?? '').toString().trim().replaceAll(r'\', '/');
  // Guard against backend sending null-like values in lists/maps.
  if (s.toLowerCase() == 'null' || s.toLowerCase() == 'none') return '';
  if (s.isEmpty) return s;
  if (s.startsWith('http://') || s.startsWith('https://')) {
    try {
      final uri = Uri.parse(s);
      // If this is our static path, use getApiBase() so device/emulator can reach it
      if (uri.path.startsWith('/static/')) {
        final path = uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : '');
        return getApiBase() + path;
      }
    } catch (_) {}
    return s;
  }
  // drop leading '/'
  if (s.startsWith('/')) s = s.substring(1);
  if (s.startsWith('static/')) {
    return '${getApiBase()}/$s';
  }
  if (s.startsWith('uploads/')) {
    return '${getApiBase()}/static/$s';
  }
  if (s.startsWith('car_photos/')) {
    return '${getApiBase()}/static/uploads/$s';
  }
  // default: assume already a path under uploads (e.g. make, dir/file.jpg)
  return '${getApiBase()}/static/uploads/$s';
}

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
    } catch (_) {}
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
        } catch (_) {}
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

String _localizeDigitsGlobal(BuildContext context, String input) {
  final locale = Localizations.localeOf(context);
  if (locale.languageCode == 'ar' || locale.languageCode == 'ku') {
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ','];
    const eastern = [
      'Ù ',
      'Ù¡',
      'Ù¢',
      'Ù£',
      'Ù¤',
      'Ù¥',
      'Ù¦',
      'Ù§',
      'Ù¨',
      'Ù©',
      'Ù¬',
    ];
    // Skip digit conversion to avoid garbled display (mojibake).
    return input;
  }
  return input;
}

/// Bare number `3.0` → localized + liter unit; values with badges (`3.0 D`) unchanged.
String _engineSizeChipLabel(BuildContext context, String raw) {
  final t = raw.trim();
  if (double.tryParse(t) != null) {
    return '${_localizeDigitsGlobal(context, t)}${AppLocalizations.of(context)!.unit_liter_suffix}';
  }
  return _localizeDigitsGlobal(context, t);
}

String _engineSizeSellRowLabel(BuildContext context, String raw) {
  final t = raw.trim();
  if (double.tryParse(t) != null) {
    return '${_localizeDigitsGlobal(context, t)} ${AppLocalizations.of(context)!.unit_liter_suffix}';
  }
  return _localizeDigitsGlobal(context, t);
}

// Locale-aware currency formatting with digit localization
String _formatCurrencyGlobal(BuildContext context, dynamic raw) {
  final symbol = globalSymbol; // Use global currency symbol
  num? value;
  if (raw is num) {
    value = raw;
  } else {
    value = num.tryParse(
      raw?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '',
    );
  }
  if (value == null) {
    return symbol + _localizeDigitsGlobal(context, '0');
  }
  final formatter = _decimalFormatterGlobal(context);
  return symbol + _localizeDigitsGlobal(context, formatter.format(value));
}

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
    ? Colors.black.withOpacity(0.2)
    : kSellLightShellFieldFill;

TextStyle _sellFlowManualFieldLabelStyle(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const TextStyle(color: Colors.white)
    : TextStyle(color: Colors.grey[800]!);

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

  static void capture(ScrollController c) {
    try {
      if (c.hasClients) {
        final pos = c.position;
        _pixels = pos.pixels.clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
      }
    } catch (_) {}
  }

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
      pageBuilder: (_, __, ___) => page!,
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
}) {
  final brightness = Theme.of(context).brightness;
  final isLight = brightness == Brightness.light;
  final unselectedItemColor = isLight
      ? const Color(0xFF666666)
      : const Color(0xD9FFFFFF);

  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    child: SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isLight
                ? Colors.white.withOpacity(0.14)
                : Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isLight ? 0.08 : 0.14),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Theme(
              data: Theme.of(context).copyWith(
                canvasColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                ),
              ),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
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
            ),
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
      ? [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.03)]
      : [kSellLightShellFieldFill, kSellLightShellFieldFill];
  final Color borderColor = isError
      ? Colors.redAccent
      : (isDark ? Colors.white12 : accent.withOpacity(0.25));
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
  final Color valueColor = (value == null || value.isEmpty)
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
          color: Colors.black.withOpacity(0.06),
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
            color: (isError ? Colors.redAccent : accent).withOpacity(0.9),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        leading ??
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isError ? Colors.redAccent : accent).withOpacity(0.12),
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
                  fontSize: 12,
                  color: labelColor,
                  fontWeight: FontWeight.w600,
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

String _contactForPriceGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.contactForPrice;
}

String _pleaseFillRequiredGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.pleaseFillRequired;
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

String _pleaseSelectPhotoTextGlobal(BuildContext context) {
  return _trLegacyText(
    context,
    'Please select at least one photo',
    ar: 'يرجى اختيار صورة واحدة على الأقل',
    ku: 'تکایە لانیکەم یەک وێنە هەڵبژێرە',
  );
}

String _listingSubmittedSuccessTextGlobal(BuildContext context) {
  return _trLegacyText(
    context,
    'Listing submitted successfully!',
    ar: 'تم إرسال الإعلان بنجاح!',
    ku: 'ڕیکلام بە سەرکەوتوویی نێردرا!',
  );
}

String _couldNotLoadListingsTextGlobal(BuildContext context) {
  return _trLegacyText(
    context,
    'Could not load listings',
    ar: 'تعذر تحميل الإعلانات',
    ku: 'نەتوانرا ڕیکلامەکان باربکرێن',
  );
}

String _photosUploadedTextGlobal(BuildContext context) {
  return _trLegacyText(
    context,
    'Photos uploaded',
    ar: 'تم تحميل الصور',
    ku: 'وێنەکان بارکران',
  );
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

/// Options removed from filter UI; still used to drop spec-driven list entries.
bool _isExcludedTransmissionFilter(String value) {
  final compact = value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  return compact == 'semiautomatic' || compact == 'semiauto';
}

String? _translateValueGlobal(BuildContext context, String? raw) {
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
) {
  final String brand = (listing['brand'] ?? '').toString().trim();
  final String model = (listing['model'] ?? '').toString().trim();
  final String yearStr = (listing['year']?.toString() ?? '').trim();
  final String apiTitle = (listing['title'] ?? '').toString().trim();
  String displayTitle;
  if (apiTitle.isNotEmpty) {
    displayTitle = apiTitle;
  } else {
    final String base = [
      if (brand.isNotEmpty) prettyTitleCase(brand),
      if (model.isNotEmpty) prettyTitleCase(model),
    ].join(' ');
    displayTitle = yearStr.isNotEmpty ? ('$base ($yearStr)') : base;
  }
  displayTitle = prettyTitleCase(displayTitle);

  final num? mileageNum = () {
    final v = listing['mileage'];
    if (v == null) return null;
    if (v is num) return v;
    final s = v.toString().replaceAll(RegExp(r'[^0-9.-]'), '');
    return num.tryParse(s);
  }();
  final String mileageFormatted = mileageNum == null
      ? (listing['mileage']?.toString() ?? '')
      : _decimalFormatterGlobal(context).format(mileageNum);

  final String carId =
      (listing['public_id'] ?? listing['id'] ?? listing['car_id'] ?? '')
          .toString();

  return {
    'id': carId,
    'brand': brand,
    'model': model,
    'trim': listing['trim'],
    'title': displayTitle,
    'price': listing['price'],
    'year': listing['year'],
    'mileage': mileageFormatted,
    'city': listing['city'] ?? listing['location'] ?? listing['city_name'],
    'image_url': listing['image_url'],
    'images': listing['images'],
    'videos': listing['videos'],
    'is_quick_sell': listing['is_quick_sell'] ?? false,
    'status': listing['status'],
    'created_at': listing['created_at'],
  };
}

/// Human-readable "time since listing was created" for card and detail UI.
String _listingUploadedAgo(BuildContext context, Map car) {
  final loc = AppLocalizations.of(context);
  if (loc == null) return '';
  dynamic raw = car['created_at'];
  if (raw == null || raw.toString().trim().isEmpty) {
    raw = car['posted_at'] ?? car['listed_at'];
  }
  if (raw == null) return '';
  final dt = DateTime.tryParse(raw.toString().trim());
  if (dt == null) return '';
  final now = DateTime.now();
  var diff = now.difference(dt);
  if (diff.isNegative) diff = Duration.zero;
  if (diff.inMinutes < 1) return loc.justNow;
  if (diff.inHours < 24) {
    if (diff.inHours < 1) {
      return loc.timeMinutesAgo(diff.inMinutes < 1 ? 1 : diff.inMinutes);
    }
    return loc.timeHoursAgo(diff.inHours);
  }
  final days = diff.inDays;
  return loc.timeDaysAgo(days < 1 ? 1 : days);
}

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
  const double _titleBoxFontSize = 15;
  const double titleFontSize = 17;
  const double titleLineHeight = 1.1;
  const int titleMaxLines = 2;
  final double reservedTitleHeight =
      _titleBoxFontSize * titleLineHeight * titleMaxLines;
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
                    color: metaTextColor.withOpacity(0.35),
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
      : Colors.white.withOpacity(0.10);
  final metaTextColor = Colors.white70;
  final dividerLineColor = Colors.white24;
  final bool showVideoCountBadge =
      car['videos'] != null && (car['videos'] as List).isNotEmpty;
  final EdgeInsets listingCardTextPadding = listLayout
      // Horizontal cards: keep top tighter so title sits higher; keep a bit of bottom room.
      ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
      : const EdgeInsets.fromLTRB(12, 8, 12, 10);

  return Container(
    decoration: BoxDecoration(
      color: cardFill,
      borderRadius: BorderRadius.circular(20),
      border: null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
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
          },
          child: listLayout
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
                            child: Padding(
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
                        ),
                      ),
                    ),
                    // Content section (year/mileage + city below price — in flow, no overlap)
                    Expanded(
                      child: Padding(
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
                  ],
                ),
        ),
        // Video indicator (grid cards only; list layout shows it on the image tile)
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
}) {
  final List<String> urls = () {
    final List<String> u = [];
    final String primary = (car['image_url'] ?? '').toString();
    final List<dynamic> imgs = (car['images'] is List)
        ? (car['images'] as List)
        : const [];
    if (primary.isNotEmpty) {
      u.add(_buildFullImageUrl(primary));
    }
    for (final dynamic it in imgs) {
      if (it is Map &&
          (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
        continue;
      }
      String s;
      if (it is Map) {
        s = (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
            .toString();
      } else {
        s = it.toString();
      }
      if (s.isNotEmpty) {
        final full = _buildFullImageUrl(s);
        if (!u.contains(full)) u.add(full);
      }
    }
    if (u.isEmpty && imgs.isNotEmpty) {
      dynamic first;
      for (final dynamic e in imgs) {
        if (e is Map &&
            (e['kind'] ?? '').toString().toLowerCase() == 'damage') {
          continue;
        }
        first = e;
        break;
      }
      if (first != null) {
        final String s = first is Map
            ? (first['image_url'] ??
                      first['url'] ??
                      first['path'] ??
                      first['src'] ??
                      '')
                  .toString()
            : first.toString();
        if (s.isNotEmpty) u.add(_buildFullImageUrl(s));
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

  int currentIndex = 0;
  const int _kMaxVisibleDots = 6;
  int dotWindowStart = 0;
  bool dotWindowForward = true;

  return StatefulBuilder(
    key: ValueKey('global_card_carousel_${car['id']}_$carouselResetSeed'),
    builder: (context, setState) {
      int computeDotStart(int index) {
        final int visible =
            urls.length < _kMaxVisibleDots ? urls.length : _kMaxVisibleDots;
        if (visible <= 0 || urls.length <= visible) return 0;
        final int maxStart = (urls.length - visible).clamp(0, urls.length);
        return (index - (visible - 1)).clamp(0, maxStart);
      }

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
              itemCount: urls.length,
              itemBuilder: (context, i) {
                final url = urls[i];
                return _listingNetworkImage(url, fit: BoxFit.cover);
              },
            ),
          ),
          if (urls.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: () {
                  final int visible = urls.length < _kMaxVisibleDots
                      ? urls.length
                      : _kMaxVisibleDots;
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
                    (urls.length - visible).clamp(0, urls.length),
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
        : Colors.white.withOpacity(0.12);
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
      backgroundColor: Colors.grey[900]?.withOpacity(0.98),
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

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (FlutterErrorDetails details) async {
        // Persist the last error for diagnosis on sideload builds
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.setString('last_startup_error', details.exceptionAsString());
        } catch (_) {}
      };

      // Minimal pre-run init only (fast): load tokens if available.
      // Heavier work is deferred until after first frame to avoid splash hangs.
      try {
        await ApiService.initializeTokens();
      } catch (_) {}

      // Initialize global currency symbol
      globalSymbol = r'$';

      runApp(MyApp());

      // Defer heavy initializations to post-frame to avoid blocking first paint
      // Firebase, locale, and auth init can take time on emulators
      Future.microtask(() async {
        // Skip Firebase/Push init for sideload builds on iOS to avoid entitlement crashes
        if (!(kSideloadBuild && Platform.isIOS)) {
          try {
            await Firebase.initializeApp();
          } catch (_) {}
          try {
            await _initPushToken();
          } catch (_) {}
        }
        try {
          await LocaleController.loadSavedLocale();
        } catch (_) {}
        try {
          await AuthService().initialize();
        } catch (_) {}
      });
    },
    (error, stack) async {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('last_startup_error', error.toString());
      } catch (_) {}
    },
  );
}

// Helper page to view last startup error if present (can be wired to a hidden gesture if needed)
class _StartupDiagnostics {
  static Future<String?> lastError() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString('last_startup_error');
    } catch (_) {
      return null;
    }
  }
}

Future<void> _initPushToken() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final enabled = sp.getBool('push_enabled') ?? true;
    if (!enabled) return;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('push_token', token);
      }
    }
  } catch (_) {}
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
                color: Colors.black.withOpacity(0.2),
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

/// Wraps [MaterialApp] and inits deep link handling after first frame.
class _AppWithDeepLinks extends StatefulWidget {
  const _AppWithDeepLinks({required this.child});
  final Widget child;

  @override
  State<_AppWithDeepLinks> createState() => _AppWithDeepLinksState();
}

class _AppWithDeepLinksState extends State<_AppWithDeepLinks> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.init(_appNavigatorKey);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? routeArgs(BuildContext context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) return args;
      if (args is Map) {
        return args.map((key, value) => MapEntry(key.toString(), value));
      }
      return null;
    }

    Widget navigationError(String message) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation error')),
        body: Center(child: Text(message)),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => ChatUiThemeController()),
        ChangeNotifierProvider(create: (context) => CarComparisonStore()),
        ChangeNotifierProvider(create: (context) => AuthService()),
      ],
      child: ValueListenableBuilder<Locale?>(
        valueListenable: LocaleController.currentLocale,
        builder: (context, locale, _) => Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) => _AppWithDeepLinks(
            child: MaterialApp(
              navigatorKey: _appNavigatorKey,
              title: 'CARZO',
              builder: (context, child) => EdgeSwipeBack(
                navigatorKey: _appNavigatorKey,
                child: child ?? const SizedBox.shrink(),
              ),
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
                '/sell': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  final initialDraftSnapshot = args is Map
                      ? (args['draftSnapshot'] is Map
                          ? Map<String, dynamic>.from(
                              (args['draftSnapshot'] as Map).cast<String, dynamic>(),
                            )
                          : null)
                      : null;
                  final startFresh = args is Map && args['startFresh'] == true;
                  final showDraftGate = args is Map && args['showDraftGate'] == true;
                  if (initialDraftSnapshot != null) {
                    return AuthGuard(
                      child: SellCarPage(
                        initialDraftSnapshot: initialDraftSnapshot,
                      ),
                    );
                  }
                  if (startFresh) {
                    return AuthGuard(
                      child: const SellCarPage(startFreshListing: true),
                    );
                  }
                  if (showDraftGate) {
                    return AuthGuard(
                      child: const SellDraftGatePage(),
                    );
                  }
                  return AuthGuard(
                    child: const SellEntryRouterPage(),
                  );
                },
                '/settings': (context) => SettingsPage(),
                '/favorites': (context) => AuthGuard(child: FavoritesPage()),
                '/dealers': (context) => const DealersDirectoryPage(),
                '/chat': (context) => AuthGuard(child: ChatListPage()),
                '/login': (context) => LoginPage(),
                '/signup': (context) => SignupPage(),
                '/profile': (context) => AuthGuard(child: ProfilePage()),
                '/edit-profile': (context) =>
                    AuthGuard(child: EditProfilePage()),
                '/car_detail': (context) {
                  final args = routeArgs(context);
                  final carId = (args?['carId'] ?? '').toString().trim();
                  if (carId.isEmpty) {
                    return navigationError('Missing listing id');
                  }
                  return CarDetailsPage(carId: carId);
                },
                '/chat/conversation': (context) {
                  final args = routeArgs(context);
                  final rawId = (args?['carId'] ?? args?['conversationId'] ?? '')
                      .toString()
                      .trim();
                  if (rawId.isEmpty) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Navigation error')),
                      body: Center(
                        child: Text('Missing chat conversation id'),
                      ),
                    );
                  }
                  return AuthGuard(
                    child: carzo_chat.ChatConversationPage(
                      carId: rawId,
                      receiverId: args?['receiverId']?.toString(),
                      initialDraft: args?['initialDraft']?.toString(),
                      initialListingPreview: args?['listingPreview'] is Map
                          ? Map<String, dynamic>.from(
                              (args?['listingPreview'] as Map)
                                  .cast<String, dynamic>(),
                            )
                          : null,
                    ),
                  );
                },
                '/edit': (context) {
                  final args = routeArgs(context);
                  final car = args?['car'];
                  if (car is! Map) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Navigation error')),
                      body: const Center(child: Text('Missing listing data')),
                    );
                  }
                  return AuthGuard(
                    child: modern_edit.EditListingPage(
                      car: Map<String, dynamic>.from(
                        car.cast<String, dynamic>(),
                      ),
                    ),
                  );
                },
                '/edit_listing': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  final car = args is Map ? args['car'] : null;
                  if (car is! Map) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Navigation error')),
                      body: const Center(child: Text('Missing listing data')),
                    );
                  }
                  return AuthGuard(
                    child: modern_edit.EditListingPage(
                      car: Map<String, dynamic>.from(
                        car.cast<String, dynamic>(),
                      ),
                    ),
                  );
                },
                '/my_listings': (context) =>
                    AuthGuard(child: modern_listings.MyListingsPage()),
                '/comparison': (context) => CarComparisonPage(),
                '/recently-viewed': (context) =>
                    AuthGuard(child: const RecentlyViewedPage()),
                '/analytics': (context) => AnalyticsPage(),
                '/reset-password': (context) => ResetPasswordPage(),
                '/verify-email': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  final token = args is Map
                      ? (args['token'] ?? '').toString().trim()
                      : '';
                  return VerifyEmailPage(
                    initialToken: token.isNotEmpty ? token : null,
                  );
                },
                '/forgot-password': (context) =>
                    auth_pages.ForgotPasswordPage(),
                '/admin/dealers': (context) =>
                    AuthGuard(child: AdminDealersPage()),
                '/admin/reports': (context) =>
                    AuthGuard(child: const AdminReportsPage()),
                '/help': (context) => const HelpCenterPage(),
                '/dealer/edit': (context) =>
                    AuthGuard(child: EditDealerPage()),
                '/dealer/profile': (context) {
                  final args =
                      ModalRoute.of(context)?.settings.arguments
                          as Map<String, dynamic>?;
                  final dealerPublicId =
                      (args?['dealerPublicId'] ?? '').toString().trim();
                  if (dealerPublicId.isEmpty) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Navigation error')),
                      body: Center(
                        child: Text(
                          _trLegacyText(
                            context,
                            'Missing dealer id',
                            ar: 'معرّف الوكيل مفقود',
                            ku: 'ناسنامەی وەکیل ونە',
                          ),
                        ),
                      ),
                    );
                  }
                  return DealerProfilePage(dealerPublicId: dealerPublicId);
                },
              },
            ),
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


class SavedSearchesPage extends StatefulWidget {
  final dynamic parentState;

  const SavedSearchesPage({super.key, this.parentState});

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
    final merged = await SavedSearchService.loadMerged();
    if (!mounted) return;
    setState(() {
      _items = merged;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await SavedSearchService.persistLocal(_items);
  }

  void _rename(int index) async {
    final controller = TextEditingController(
      text: _items[index]['name']?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _items[index]['name'] = controller.text.trim().isEmpty
            ? _items[index]['name']
            : controller.text.trim();
      });
      await _save();
      unawaited(SavedSearchService.pushItemToServer(_items[index]));
    }
  }

  void _delete(int index) async {
    final id = (_items[index]['id'] ?? '').toString();
    setState(() {
      _items.removeAt(index);
    });
    await _save();
    unawaited(SavedSearchService.deleteOnServer(id));
  }

  void _toggleNotify(int index, bool value) async {
    setState(() {
      _items[index]['notify'] = value;
    });
    await _save();
    unawaited(SavedSearchService.pushItemToServer(_items[index]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.savedSearchesTitle),
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
                  Text(
                    AppLocalizations.of(context)!.noSavedSearchesYet,
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.savedSearchesHint,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
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
                    onTap: () => _showFilterDetails(
                      item['name']?.toString() ??
                          AppLocalizations.of(context)!.unnamedSearch,
                      filters,
                    ),
                    leading: Icon(Icons.bookmark, color: Color(0xFFFF6B00)),
                    title: Text(
                      item['name']?.toString() ??
                          AppLocalizations.of(context)!.unnamedSearch,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 4),
                        _buildFilterChips(context, filters),
                        SizedBox(height: 4),
                        Text(
                          _formatDate(
                            context,
                            item['created_at']?.toString() ?? '',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            (item['notify'] == true)
                                ? Icons.notifications_active
                                : Icons.notifications_none,
                            color: const Color(0xFFFF6B00),
                          ),
                          onPressed: () => _toggleNotify(
                            index,
                            item['notify'] != true,
                          ),
                          tooltip: _trLegacyText(
                            context,
                            'Alerts',
                            ar: 'التنبيهات',
                            ku: 'ئاگادارکردنەوە',
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.search, color: Colors.green),
                          onPressed: () => _applySearch(filters),
                          tooltip: AppLocalizations.of(context)!.applySearch,
                        ),
                        IconButton(
                          icon: Icon(Icons.edit),
                          onPressed: () => _rename(index),
                          tooltip: AppLocalizations.of(context)!.renameTooltip,
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _delete(index),
                          tooltip: AppLocalizations.of(context)!.deleteTooltip,
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

  Widget _buildFilterChips(BuildContext context, Map<String, dynamic> filters) {
    final chips = <Widget>[];
    final l = AppLocalizations.of(context)!;
    String tr(String? v) =>
        _translateValueGlobal(context, v?.toString()) ?? v ?? '';

    if (filters['brand'] != null) {
      chips.add(
        _buildFilterChip(context, l.brandLabel, filters['brand'].toString()),
      );
    }
    if (filters['model'] != null) {
      chips.add(
        _buildFilterChip(context, l.modelLabel, filters['model'].toString()),
      );
    }
    if (filters['trim'] != null) {
      chips.add(
        _buildFilterChip(context, l.trimLabel, filters['trim'].toString()),
      );
    }
    if (filters['city'] != null) {
      chips.add(
        _buildFilterChip(context, l.cityLabel, tr(filters['city'].toString())),
      );
    }
    if (filters['plate_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          _trLegacyText(context, 'Plate type', ar: 'نوع اللوحة', ku: 'جۆری پڵەیت'),
          _translatePlateTypeLegacy(context, filters['plate_type'].toString()),
        ),
      );
    }
    if (filters['plate_city'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          _trLegacyText(context, 'Plate city', ar: 'مدينة اللوحة', ku: 'شاری پڵەیت'),
          tr(filters['plate_city'].toString()),
        ),
      );
    }
    if (filters['min_price'] != null || filters['max_price'] != null) {
      final priceRange =
          '${filters['min_price'] ?? '0'} - ${filters['max_price'] ?? '∞'}';
      chips.add(_buildFilterChip(context, l.priceLabel, priceRange));
    }
    if (filters['min_year'] != null || filters['max_year'] != null) {
      final yearRange =
          '${filters['min_year'] ?? '0'} - ${filters['max_year'] ?? '∞'}';
      chips.add(_buildFilterChip(context, l.yearLabel, yearRange));
    }
    if (filters['min_mileage'] != null || filters['max_mileage'] != null) {
      final mileageRange =
          '${filters['min_mileage'] ?? '0'} - ${filters['max_mileage'] ?? '∞'} ${l.unit_km}';
      chips.add(_buildFilterChip(context, l.mileageLabel, mileageRange));
    }
    if (filters['transmission'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.transmissionLabel,
          tr(filters['transmission'].toString()),
        ),
      );
    }
    if (filters['condition'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.conditionLabel,
          tr(filters['condition'].toString()),
        ),
      );
    }
    if (filters['body_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.bodyTypeLabel,
          tr(filters['body_type'].toString()),
        ),
      );
    }
    if (filters['fuel_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.fuelTypeLabel,
          tr(filters['fuel_type'].toString()),
        ),
      );
    }
    if (filters['color'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.colorLabel,
          tr(filters['color'].toString()),
        ),
      );
    }
    if (filters['drive_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.driveType,
          tr(filters['drive_type'].toString()),
        ),
      );
    }
    if (filters['region_specs'] != null) {
      final code = filters['region_specs'].toString().trim().toLowerCase();
      chips.add(
        _buildFilterChip(
          context,
          l.regionSpecsLabel,
          carRegionSpecDisplayLabel(code),
        ),
      );
    }
    if (filters['cylinder_count'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.cylinderCount,
          filters['cylinder_count'].toString(),
        ),
      );
    }
    if (filters['seating'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.seating,
          '${filters['seating'].toString()}',
        ),
      );
    }
    if (filters['engine_size'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.engineSizeL,
          _engineSizeChipLabel(context, filters['engine_size'].toString()),
        ),
      );
    }
    if (filters['title_status'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.status,
          tr(filters['title_status'].toString()),
        ),
      );
    }
    if (filters['damaged_parts'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          'Damaged Parts',
          filters['damaged_parts'].toString(),
        ),
      );
    }
    if (filters['sort_by'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.sortBy,
          _capitalizeFirst(filters['sort_by'].toString()),
        ),
      );
    }
    if (filters['owners'] != null) {
      chips.add(
        _buildFilterChip(context, 'Owners', filters['owners'].toString()),
      );
    }
    if (filters['vin'] != null) {
      chips.add(_buildFilterChip(context, 'VIN', filters['vin'].toString()));
    }
    if (filters['accident_history'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          'Accident History',
          _capitalizeFirst(filters['accident_history'].toString()),
        ),
      );
    }

    if (chips.isEmpty) {
      return Text(
        l.noFiltersApplied,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      );
    }
    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }

  Widget _buildFilterChip(BuildContext context, String label, String value) {
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

  String _formatDate(BuildContext context, String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);
      final l = AppLocalizations.of(context)!;
      final timeStr =
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

      if (difference.inDays == 0) {
        return '${l.today} $timeStr';
      } else if (difference.inDays == 1) {
        return '${l.yesterday} $timeStr';
      } else if (difference.inDays < 7) {
        return l.daysAgo(difference.inDays);
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateString;
    }
  }

  void _applySearch(Map<String, dynamic> filters) async {
    final normalized = SavedSearchService.normalizeFilters(filters);
    await persistSavedSearchFiltersForHome(normalized);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final successText = _trLegacyText(
      context,
      'Search applied successfully!',
      ar: 'تم تطبيق البحث بنجاح!',
      ku: 'گەڕان بە سەرکەوتوویی جێبەجێ کرا!',
    );

    final parent = widget.parentState;
    if (parent != null && parent.mounted) {
      Navigator.pop(context);
      parent.setState(() {
        parent.applyFiltersFromSavedSearch(normalized);
      });
      parent.fetchCars(bypassCache: true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(successText),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    Navigator.pop(context);
    if (!context.mounted) return;
    await _markPendingSavedSearchFetch();
    navigateMainShellTab(context, '/');
    messenger.showSnackBar(
      SnackBar(
        content: Text(successText),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
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
                    _trLegacyText(
                      context,
                      'Applied Filters:',
                      ar: 'الفلاتر المطبقة:',
                      ku: 'فلتەرە جێبەجێکراوەکان:',
                    ),
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
            style: TextButton.styleFrom(foregroundColor: Colors.grey[400]),
            child: Text(
              _trLegacyText(
                context,
                'Close',
                ar: 'إغلاق',
                ku: 'داخستن',
              ),
            ),
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
            child: Text(
              _trLegacyText(
                context,
                'Apply Search',
                ar: 'تطبيق البحث',
                ku: 'جێبەجێکردنی گەڕان',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedFilterList(Map<String, dynamic> filters) {
    final List<Widget> filterItems = [];

    // Vehicle Information
    if (filters['brand'] != null) {
      filterItems.add(
        _buildFilterDetailItem('Brand', filters['brand'].toString()),
      );
    }
    if (filters['model'] != null) {
      filterItems.add(
        _buildFilterDetailItem('Model', filters['model'].toString()),
      );
    }
    if (filters['trim'] != null) {
      filterItems.add(
        _buildFilterDetailItem('Trim', filters['trim'].toString()),
      );
    }

    // Price Range
    if (filters['min_price'] != null || filters['max_price'] != null) {
      final minPrice = filters['min_price']?.toString() ?? 'Any';
      final maxPrice = filters['max_price']?.toString() ?? 'Any';
      filterItems.add(
        _buildFilterDetailItem('Price Range', '$minPrice - $maxPrice'),
      );
    }

    // Year Range
    if (filters['min_year'] != null || filters['max_year'] != null) {
      final minYear = filters['min_year']?.toString() ?? 'Any';
      final maxYear = filters['max_year']?.toString() ?? 'Any';
      filterItems.add(
        _buildFilterDetailItem('Year Range', '$minYear - $maxYear'),
      );
    }

    // Mileage Range
    if (filters['min_mileage'] != null || filters['max_mileage'] != null) {
      final minMileage = filters['min_mileage']?.toString() ?? 'Any';
      final maxMileage = filters['max_mileage']?.toString() ?? 'Any';
      filterItems.add(
        _buildFilterDetailItem('Mileage Range', '$minMileage - $maxMileage km'),
      );
    }

    // Vehicle Specifications
    if (filters['condition'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Condition',
          _capitalizeFirst(filters['condition'].toString()),
        ),
      );
    }
    if (filters['transmission'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Transmission',
          _capitalizeFirst(filters['transmission'].toString()),
        ),
      );
    }
    if (filters['fuel_type'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Fuel Type',
          _capitalizeFirst(filters['fuel_type'].toString()),
        ),
      );
    }
    if (filters['body_type'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Body Type',
          _capitalizeFirst(filters['body_type'].toString()),
        ),
      );
    }
    if (filters['color'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Color',
          _capitalizeFirst(filters['color'].toString()),
        ),
      );
    }
    if (filters['drive_type'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Drive Type',
          filters['drive_type'].toString().toUpperCase(),
        ),
      );
    }
    if (filters['region_specs'] != null) {
      final code = filters['region_specs'].toString().trim().toLowerCase();
      filterItems.add(
        _buildFilterDetailItem(
          AppLocalizations.of(context)!.regionSpecsLabel,
          carRegionSpecDisplayLabel(code),
        ),
      );
    }
    if (filters['cylinder_count'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Cylinder Count',
          filters['cylinder_count'].toString(),
        ),
      );
    }
    if (filters['seating'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Seating',
          '${filters['seating'].toString()} seats',
        ),
      );
    }
    if (filters['engine_size'] != null) {
      final es = filters['engine_size'].toString().trim();
      final plain = double.tryParse(es) != null;
      filterItems.add(
        _buildFilterDetailItem('Engine Size', plain ? '${es}L' : es),
      );
    }

    // Location and Other
    if (filters['city'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'City',
          _capitalizeFirst(filters['city'].toString()),
        ),
      );
    }
    if (filters['title_status'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Title Status',
          _capitalizeFirst(filters['title_status'].toString()),
        ),
      );
    }
    if (filters['damaged_parts'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Damaged Parts',
          filters['damaged_parts'].toString(),
        ),
      );
    }
    if (filters['sort_by'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Sort By',
          _capitalizeFirst(filters['sort_by'].toString()),
        ),
      );
    }
    if (filters['owners'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Number of Owners',
          filters['owners'].toString(),
        ),
      );
    }
    if (filters['vin'] != null) {
      filterItems.add(_buildFilterDetailItem('VIN', filters['vin'].toString()));
    }
    if (filters['accident_history'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Accident History',
          _capitalizeFirst(filters['accident_history'].toString()),
        ),
      );
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
            Icon(Icons.info_outline, color: Colors.grey[400], size: 20),
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

    return Wrap(spacing: 8, runSpacing: 6, children: filterItems);
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
    // No dedicated "default" asset; use a safe built-in icon.
    return 'assets/body_types_png/sedan.png';
  }

  // Try direct label match from dynamic map
  // We store labels in title case keys (e.g., 'Mini Truck'), so we normalize here
  String normalizeTitle(String s) {
    final words = s
        .replaceAll(RegExp(r'[_\\-]+'), ' ')
        .trim()
        .split(RegExp(r'\\s+'));
    return words
        .map((w) {
          if (w.isEmpty) return w;
          final lettersOnly = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
          // Preserve short acronyms like "ATV" / "UTV".
          if (lettersOnly.isNotEmpty && lettersOnly.length <= 3) {
            return w.toUpperCase();
          }
          return w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '');
        })
        .join(' ');
  }

  final String titleKey = normalizeTitle(bodyType);
  if (globalBodyTypeAssetMap.containsKey(titleKey)) {
    return globalBodyTypeAssetMap[titleKey]!;
  }

  // Fallback to known static mappings for common names
  final normalized = bodyType
      .toLowerCase()
      .replaceAll(RegExp(r'[_\\-]+'), ' ')
      .trim();

  switch (normalized) {
    case 'micro':
      return 'assets/body_types_png/micro.png';
    case 'cuv':
      return 'assets/body_types_png/cuv.png';
    case 'sedan':
      return 'assets/body_types_png/sedan.png';
    case 'suv':
      return 'assets/body_types_png/suv.png';
    case 'hatchback':
      return 'assets/body_types_png/hatchback.png';
    case 'coupe':
      return 'assets/body_types_png/coupe.png';
    case 'wagon':
    case 'station wagon':
    case 'estate':
      // No dedicated wagon asset; use hatchback as closest match.
      return 'assets/body_types_png/hatchback.png';
    case 'pickup':
      return 'assets/body_types_png/pickup.png';
    case 'roadster':
      return 'assets/body_types_png/roadster.png';
    case 'truck':
      return 'assets/body_types_png/truck.png';
    case 'minitruck':
    case 'mini truck':
      return 'assets/body_types_png/minitruck.png';
    case 'bigtruck':
    case 'big truck':
      return 'assets/body_types_png/bigtruck.png';
    case 'van':
      return 'assets/body_types_png/van.png';
    case 'minivan':
    case 'mini van':
    case 'mpv':
      // No dedicated minivan asset; use van icon.
      return 'assets/body_types_png/van.png';
    case 'supercar':
      return 'assets/body_types_png/supercar.png';
    case 'cabriolet':
    case 'convertible':
    case 'cabrio':
      return 'assets/body_types_png/cabriolet.png';
    case 'motorcycle':
      return 'assets/body_types_png/motorcycle.png';
    case 'utv':
      return 'assets/body_types_png/UTV.png';
    case 'atv':
      return 'assets/body_types_png/ATV.png';
    default:
      return 'assets/body_types_png/sedan.png';
  }
}


// Car Comparison Page
class CarComparisonPage extends StatelessWidget {
  const CarComparisonPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pageIsDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: pageIsDark ? null : AppThemes.lightAppBackground,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.specificationsLabel),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.shareAction,
            onPressed: () async {
              try {
                final store = Provider.of<CarComparisonStore>(
                  context,
                  listen: false,
                );
                final cars = store.comparisonCars;
                final text = cars
                    .map(
                      (c) =>
                          '${c['title'] ?? ''} • ${c['year'] ?? ''} • ${c['price'] ?? ''}',
                    )
                    .join('\n');
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
                        content: Text(
                          AppLocalizations.of(context)!.clearFilters,
                        ),
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
            decoration: pageIsDark
                ? AppThemes.shellBackgroundDecoration(Brightness.dark)
                : const BoxDecoration(color: AppThemes.lightAppBackground),
          ),
          Consumer<CarComparisonStore>(
            builder: (context, comparisonStore, child) {
              final cars = comparisonStore.comparisonCars;
              final double columnWidth = 260.0;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final cs = Theme.of(context).colorScheme;
              final lightInk = AppThemes.darkHomeShellBackground;
              final lightInkMuted = lightInk.withOpacity(0.72);

              if (cars.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.compare_arrows,
                        size: 84,
                        color: isDark
                            ? Colors.white24
                            : cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                      SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.noCarsFound,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : lightInk,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.tapToSelectBrand,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white54 : lightInkMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.pushReplacementNamed(context, '/'),
                        icon: Icon(Icons.search),
                        label: Text(AppLocalizations.of(context)!.navHome),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
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
                      color: isDark
                          ? Colors.white.withOpacity(0.06)
                          : AppThemes.lightAppBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white10 : cs.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.compare_arrows,
                          color: Color(0xFFFF6B00),
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.specificationsLabel,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : lightInk,
                                ),
                              ),
                              Text(
                                '${AppLocalizations.of(context)!.sortBy}: ${cars.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white70
                                      : lightInkMuted,
                                ),
                              ),
                              SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: Color(0xFFFF6B00),
                                      ),
                                      foregroundColor: isDark
                                          ? Colors.white
                                          : lightInk,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pushReplacementNamed(
                                        context,
                                        '/',
                                      );
                                    },
                                    icon: Icon(
                                      Icons.add,
                                      color: Color(0xFFFF6B00),
                                      size: 18,
                                    ),
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.addMorePhotos,
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: isDark
                                            ? Colors.white24
                                            : cs.outlineVariant,
                                      ),
                                      foregroundColor: isDark
                                          ? Colors.white
                                          : lightInk,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    onPressed: () {
                                      Provider.of<CarComparisonStore>(
                                        context,
                                        listen: false,
                                      ).clearComparison();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _comparisonClearedTextGlobal(
                                              context,
                                            ),
                                          ),
                                          backgroundColor: Color(0xFFFF6B00),
                                        ),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: isDark
                                          ? Colors.white70
                                          : lightInkMuted,
                                      size: 18,
                                    ),
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
                      final double horizontalPadding =
                          32.0; // padding inside row containers
                      final bool isTwoCars = cars.length == 2;
                      final double availableWidth = constraints.maxWidth;
                      final double effectiveRowWidth =
                          availableWidth - horizontalPadding;
                      final int numColumns = cars.isEmpty ? 1 : cars.length;
                      final double baseColumnWidth =
                          (effectiveRowWidth - labelWidth) / numColumns;
                      final double columnWidth = isTwoCars
                          ? (baseColumnWidth < 96.0 ? 96.0 : baseColumnWidth)
                          : baseColumnWidth.clamp(120.0, 260.0).toDouble();
                      final double requiredWidth =
                          labelWidth +
                          (numColumns * columnWidth) +
                          horizontalPadding;
                      final double tableWidth = requiredWidth > availableWidth
                          ? requiredWidth
                          : availableWidth;
                      final double imageSize = isTwoCars
                          ? ((columnWidth - 16).clamp(88.0, 120.0)).toDouble()
                          : 120.0;
                      final double headerTitleHeight = 52.0;
                      final double headerPriceHeight = 22.0;

                      final table = Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.06)
                              : AppThemes.lightAppBackground,
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
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                // Keep the orange accent in light mode, but soften it.
                                color: Color(0xFFFF6B00).withOpacity(
                                  isDark ? 0.12 : 0.10,
                                ),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: isTwoCars
                                    ? MainAxisAlignment.center
                                    : MainAxisAlignment.start,
                                children: isTwoCars
                                    ? [
                                        // Left car
                                        SizedBox(
                                          width: columnWidth,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Column(
                                              children: [
                                                Container(
                                                  height: imageSize,
                                                  width: imageSize,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.white10,
                                                    ),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: _buildCarImage(
                                                      cars[0],
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 8),
                                                SizedBox(
                                                  height: headerTitleHeight,
                                                  child: Center(
                                                    child: AutoSizeText(
                                                      (cars[0]['title'] ?? '')
                                                          .toString(),
                                                      textScaleFactor: 1.0,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                        color: isDark
                                                            ? Colors.white
                                                            : lightInk,
                                                        height: 1.15,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      minFontSize: 9,
                                                      stepGranularity: 0.5,
                                                      overflow:
                                                          TextOverflow.clip,
                                                      softWrap: true,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                SizedBox(
                                                  height: headerPriceHeight,
                                                  child: Center(
                                                    child: Text(
                                                      _formatCurrencyGlobal(
                                                        context,
                                                        cars[0]['price']
                                                                ?.toString() ??
                                                            '0',
                                                      ),
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFFFF6B00,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 8),
                                                IconButton(
                                                  onPressed: () {
                                                    comparisonStore
                                                        .removeCarFromComparison(
                                                          cars[0]['id'],
                                                        );
                                                  },
                                                  icon: Icon(
                                                    Icons.close,
                                                    color: Colors.red,
                                                    size: 24,
                                                  ),
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
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Column(
                                              children: [
                                                Container(
                                                  height: imageSize,
                                                  width: imageSize,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.white10,
                                                    ),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: _buildCarImage(
                                                      cars[1],
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 8),
                                                SizedBox(
                                                  height: headerTitleHeight,
                                                  child: Center(
                                                    child: AutoSizeText(
                                                      (cars[1]['title'] ?? '')
                                                          .toString(),
                                                      textScaleFactor: 1.0,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                        color: isDark
                                                            ? Colors.white
                                                            : lightInk,
                                                        height: 1.15,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      minFontSize: 9,
                                                      stepGranularity: 0.5,
                                                      overflow:
                                                          TextOverflow.clip,
                                                      softWrap: true,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                SizedBox(
                                                  height: headerPriceHeight,
                                                  child: Center(
                                                    child: Text(
                                                      _formatCurrencyGlobal(
                                                        context,
                                                        cars[1]['price']
                                                                ?.toString() ??
                                                            '0',
                                                      ),
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFFFF6B00,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 8),
                                                IconButton(
                                                  onPressed: () {
                                                    comparisonStore
                                                        .removeCarFromComparison(
                                                          cars[1]['id'],
                                                        );
                                                  },
                                                  icon: Icon(
                                                    Icons.close,
                                                    color: Colors.red,
                                                    size: 24,
                                                  ),
                                                  constraints: BoxConstraints(),
                                                  padding: EdgeInsets.zero,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ]
                                    : [
                                        SizedBox(
                                          width: labelWidth,
                                        ), // Space for property names
                                        ...cars.map(
                                          (car) => SizedBox(
                                            width: columnWidth,
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 8,
                                              ),
                                              child: Column(
                                                children: [
                                                  Container(
                                                    height: 110,
                                                    width: 110,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors.white10,
                                                      ),
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: _buildCarImage(
                                                        car,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(height: 8),
                                                  SizedBox(
                                                    height: headerTitleHeight,
                                                    child: Center(
                                                      child: AutoSizeText(
                                                        [
                                                              _localizedCarTitleForCard(
                                                                context,
                                                                car,
                                                              ),
                                                              _localizedTrimForCard(
                                                                context,
                                                                car,
                                                              ),
                                                            ]
                                                            .where(
                                                              (s) =>
                                                                  s.isNotEmpty,
                                                            )
                                                            .join(' '),
                                                        textScaleFactor: 1.0,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 14,
                                                          color: isDark
                                                              ? Colors.white
                                                              : lightInk,
                                                          height: 1.15,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 2,
                                                        minFontSize: 9,
                                                        stepGranularity: 0.5,
                                                        overflow:
                                                            TextOverflow.clip,
                                                        softWrap: true,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(height: 4),
                                                  SizedBox(
                                                    height: headerPriceHeight,
                                                    child: Center(
                                                      child: Text(
                                                        _formatCurrencyGlobal(
                                                          context,
                                                          car['price']
                                                                  ?.toString() ??
                                                              '0',
                                                        ),
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFFFF6B00,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(height: 8),
                                                  IconButton(
                                                    onPressed: () {
                                                      comparisonStore
                                                          .removeCarFromComparison(
                                                            car['id'],
                                                          );
                                                    },
                                                    icon: Icon(
                                                      Icons.close,
                                                      color: Colors.red,
                                                      size: 24,
                                                    ),
                                                    constraints:
                                                        BoxConstraints(),
                                                    padding: EdgeInsets.zero,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                              ),
                            ),
                            SizedBox(height: 12),

                            // Comparison Rows
                            ..._buildComparisonRows(
                              context,
                              cars,
                              columnWidth,
                              labelWidth,
                            ),
                          ],
                        ),
                      );

                      if (isTwoCars) {
                        return SizedBox(width: availableWidth, child: table);
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: BouncingScrollPhysics(),
                        child: SizedBox(width: tableWidth, child: table),
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
      final built = _buildFullImageUrl(imageUrl);
      return _listingNetworkImage(built, fit: BoxFit.cover);
    }
    return Container(
      color: Colors.white10,
      child: Icon(Icons.directions_car, color: Colors.white24),
    );
  }

  List<Widget> _buildComparisonRows(
    BuildContext context,
    List<Map<String, dynamic>> cars,
    double columnWidth,
    double labelWidth,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final lightInk = AppThemes.darkHomeShellBackground;
    final lightInkMuted = lightInk.withOpacity(0.72);
    final sections = [
      {
        'title': AppLocalizations.of(context)!.brandLabel,
        'icon': Icons.info_outline,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.brandLabel,
            'key': 'brand',
            'icon': Icons.directions_car,
          },
          {
            'label': AppLocalizations.of(context)!.modelLabel,
            'key': 'model',
            'icon': Icons.badge_outlined,
          },
          {
            'label': AppLocalizations.of(context)!.trimLabel,
            'key': 'trim',
            'icon': Icons.layers,
          },
          {
            'label': AppLocalizations.of(context)!.yearLabel,
            'key': 'year',
            'icon': Icons.calendar_today,
          },
          {
            'label': AppLocalizations.of(context)!.cityLabel,
            'key': 'city',
            'icon': Icons.location_city,
          },
          {
            'label': AppLocalizations.of(context)!.priceLabel,
            'key': 'price',
            'icon': Icons.attach_money,
          },
        ],
      },
      {
        'title': AppLocalizations.of(context)!.specificationsLabel,
        'icon': Icons.speed,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.mileageLabel,
            'key': 'mileage',
            'suffix': ' ${AppLocalizations.of(context)!.unit_km}',
            'icon': Icons.speed,
          },
          {
            'label': AppLocalizations.of(context)!.engineSizeL,
            'key': 'engine_size',
            'suffix': AppLocalizations.of(context)!.unit_liter_suffix,
            'icon': Icons.settings,
          },
          {
            'label': AppLocalizations.of(context)!.detail_cylinders,
            'key': 'cylinder_count',
            'suffix': '',
            'icon': Icons.precision_manufacturing,
          },
          {
            'label': AppLocalizations.of(context)!.seating,
            'key': 'seating',
            'suffix': '',
            'icon': Icons.event_seat,
          },
        ],
      },
      {
        'title': AppLocalizations.of(context)!.moreFilters,
        'icon': Icons.tune,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.detail_condition,
            'key': 'condition',
            'icon': Icons.verified,
          },
          {
            'label': AppLocalizations.of(context)!.transmissionLabel,
            'key': 'transmission',
            'icon': Icons.settings_suggest,
          },
          {
            'label': AppLocalizations.of(context)!.detail_fuel,
            'key': 'fuel_type',
            'icon': Icons.local_gas_station,
          },
          {
            'label': AppLocalizations.of(context)!.detail_body,
            'key': 'body_type',
            'icon': Icons.directions_car_filled,
          },
          {
            'label': AppLocalizations.of(context)!.driveType,
            'key': 'drive_type',
            'icon': Icons.all_inclusive,
          },
          {
            'label': AppLocalizations.of(context)!.regionSpecsLabel,
            'key': 'region_specs',
            'icon': Icons.public,
          },
          {
            'label': AppLocalizations.of(context)!.detail_color,
            'key': 'color',
            'icon': Icons.color_lens,
          },
        ],
      },
      {
        'title': _statusTitleGlobal(context),
        'icon': Icons.assignment_turned_in,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.titleStatus,
            'key': 'title_status',
            'icon': Icons.assignment,
          },
          {
            'label': AppLocalizations.of(context)!.damagedParts,
            'key': 'damaged_parts',
            'suffix': '',
            'icon': Icons.build,
          },
          {
            'label': _quickSellTextGlobal(context),
            'key': 'is_quick_sell',
            'isBoolean': true,
            'icon': Icons.flash_on,
          },
        ],
      },
    ];

    final List<Widget> out = [];
    for (int s = 0; s < sections.length; s++) {
      final section = sections[s] as Map<String, dynamic>;
      out.add(
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: EdgeInsets.only(top: s == 0 ? 0 : 16),
          decoration: BoxDecoration(
            // Keep the orange accent in light mode, but soften it.
            color: Color(0xFFFF6B00).withOpacity(isDark ? 0.12 : 0.10),
            borderRadius: BorderRadius.circular(12),
            border: isDark ? null : Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              if (section['icon'] is IconData)
                Icon(
                  section['icon'] as IconData,
                  color: Color(0xFFFF6B00),
                  size: 18,
                )
              else
                Icon(Icons.toc, color: Color(0xFFFF6B00), size: 18),
              SizedBox(width: 8),
              Text(
                section['title'].toString(),
                style: TextStyle(
                  color: isDark ? Colors.white : lightInk,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );

      final List rows = section['rows'] as List;
      for (int i = 0; i < rows.length; i++) {
        final property = Map<String, dynamic>.from(rows[i] as Map);
        final bool isOdd = i % 2 == 1;
        out.add(
          Container(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: isOdd
                  ? (isDark
                      ? Colors.white.withOpacity(0.02)
                      : Colors.black.withOpacity(0.02))
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white12 : cs.outlineVariant,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: cars.length == 2
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (cars.length == 2) ...[
                  SizedBox(
                    width: columnWidth,
                    child: _buildCellValue(context, cars[0], property),
                  ),
                  SizedBox(
                    width: labelWidth,
                    child: Center(
                      child: Builder(
                        builder: (context) {
                          final bool isDamagedParts =
                              (property['key']?.toString() ?? '') ==
                              'damaged_parts';
                          final double gap = isDamagedParts ? 2 : 4;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                (rows[i]['icon'] is IconData)
                                    ? (rows[i]['icon'] as IconData)
                                    : Icons.label_outline,
                                color: isDark ? Colors.white54 : lightInkMuted,
                                size: 16,
                              ),
                              SizedBox(width: gap),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: (labelWidth - 16 - gap).clamp(
                                    48.0,
                                    labelWidth,
                                  ),
                                ),
                                child: AutoSizeText(
                                  property['label']!.toString(),
                                  textScaleFactor: 1.0,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : lightInkMuted,
                                    height: 1.15,
                                  ),
                                  textAlign: isDamagedParts
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  maxLines: 2,
                                  minFontSize: 8,
                                  stepGranularity: 0.5,
                                  overflow: TextOverflow.clip,
                                  softWrap: true,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: columnWidth,
                    child: _buildCellValue(context, cars[1], property),
                  ),
                ] else ...[
                  SizedBox(
                    width: labelWidth,
                    child: Center(
                      child: Builder(
                        builder: (context) {
                          final bool isDamagedParts =
                              (property['key']?.toString() ?? '') ==
                              'damaged_parts';
                          final double gap = isDamagedParts ? 2 : 4;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                (rows[i]['icon'] is IconData)
                                    ? (rows[i]['icon'] as IconData)
                                    : Icons.label_outline,
                                color: isDark ? Colors.white54 : lightInkMuted,
                                size: 16,
                              ),
                              SizedBox(width: gap),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: (labelWidth - 16 - gap).clamp(
                                    48.0,
                                    labelWidth,
                                  ),
                                ),
                                child: AutoSizeText(
                                  property['label']!.toString(),
                                  textScaleFactor: 1.0,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : lightInkMuted,
                                    height: 1.15,
                                  ),
                                  textAlign: isDamagedParts
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  maxLines: 2,
                                  minFontSize: 8,
                                  stepGranularity: 0.5,
                                  overflow: TextOverflow.clip,
                                  softWrap: true,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: cars
                          .map(
                            (car) => SizedBox(
                              width: columnWidth,
                              child: _buildCellValue(context, car, property),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }
    }
    return out;
  }

  Widget _buildCellValue(
    BuildContext context,
    Map<String, dynamic> car,
    Map<String, dynamic> property,
  ) {
    final text = _formatPropertyValue(context, car, property);
    final isBool =
        property['isBoolean'] == true || property['isBoolean'] == 'true';
    if (isBool) {
      final boolVal = text.toLowerCase() == 'yes';
      return Align(
        alignment: Alignment.center,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: boolVal
                ? Colors.green.withOpacity(0.18)
                : Colors.red.withOpacity(0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: boolVal
                  ? Colors.greenAccent.withOpacity(0.3)
                  : Colors.redAccent.withOpacity(0.3),
            ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        color: isDark ? Colors.white : AppThemes.darkHomeShellBackground,
        fontWeight: FontWeight.w600,
      ),
      textAlign: TextAlign.center,
    );
  }

  String _formatPropertyValue(
    BuildContext context,
    Map<String, dynamic> car,
    Map<String, dynamic> property,
  ) {
    final key = property['key']!;
    final value = car[key];

    if (value == null) return '-';
    if (key == 'price') {
      return _formatCurrencyGlobal(context, value);
    }
    if (key == 'region_specs') {
      final c = value.toString().trim().toLowerCase();
      if (!isValidCarRegionSpecCode(c)) return '-';
      return carRegionSpecDisplayLabel(c);
    }

    if (property['isBoolean'] == true || property['isBoolean'] == 'true') {
      return value == true || value == 'true'
          ? _yesTextGlobal(context)
          : _noTextGlobal(context);
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
      // Upload full-resolution images to improve YOLO/OCR accuracy
      final files = await _imagePicker.pickMultiImage();
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
      actions: [const ThemeToggleWidget(), buildLanguageMenu()],
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
                            Text(
                              CarNameTranslations.getLocalizedBrand(context, selectedBrand).isNotEmpty
                                  ? CarNameTranslations.getLocalizedBrand(context, selectedBrand)
                                  : selectedBrand!,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
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
                      selectedModel != null
                          ? (CarNameTranslations.getLocalizedModel(context, selectedBrand, selectedModel).isNotEmpty
                              ? CarNameTranslations.getLocalizedModel(context, selectedBrand, selectedModel)
                              : selectedModel!)
                          : AppLocalizations.of(context)!.tapToSelectBrand,
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
                onChanged: (v) {
                  setState(() => selectedCondition = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
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
                onChanged: (v) {
                  setState(() => selectedTransmission = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.transmissionLabel : null,
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.fuelTypeLabel),
                value: selectedFuelType != null && fuelTypes.contains(selectedFuelType) ? selectedFuelType : null,
                items: fuelTypes.map((f) => DropdownMenuItem(value: f, child: Text(_translateValueGlobal(context, f) ?? f))).toList(),
                onChanged: (v) {
                  setState(() => selectedFuelType = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
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
                                        onTap: () {
                                          Navigator.pop(context, bodyTypeName);
                                          final parent = context.findAncestorStateOfType<_SellCarPageState>();
                                          if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                                        },
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
                      final parent = context.findAncestorStateOfType<_SellCarPageState>();
                      if (parent != null) unawaited(parent._saveSellDraftSnapshot());
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
                                        onTap: () {
                                          Navigator.pop(context, colorName);
                                          final parent = context.findAncestorStateOfType<_SellCarPageState>();
                                          if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                                        },
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
                      final parent = context.findAncestorStateOfType<_SellCarPageState>();
                      if (parent != null) unawaited(parent._saveSellDraftSnapshot());
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
                onChanged: (v) {
                  setState(() => selectedDriveType = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectDriveType : null,
              ),
              SizedBox(height: 12),
              // Cylinder Count Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.cylinderCount),
                value: selectedCylinderCount != null && getAddCarAvailableCylinderCounts().contains(selectedCylinderCount) ? selectedCylinderCount : null,
                items: getAddCarAvailableCylinderCounts().map((c) => DropdownMenuItem(value: c, child: Text(_localizeDigitsGlobal(context, c)))).toList(),
                onChanged: (v) {
                  setState(() => selectedCylinderCount = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectCylinderCount : null,
              ),
              SizedBox(height: 12),
              // Seating Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.seating),
                value: selectedSeating != null && getAddCarAvailableSeatings().contains(selectedSeating) ? selectedSeating : null,
                items: getAddCarAvailableSeatings().map((s) => DropdownMenuItem(value: s, child: Text(_localizeDigitsGlobal(context, s)))).toList(),
                onChanged: (v) {
                  setState(() => selectedSeating = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectSeating : null,
              ),
              SizedBox(height: 12),
              // Engine Size Dropdown / Manual input
              Row(
                children: [
                  Expanded(
                    child: isInlineEngineSizeDropdown
                        ? DropdownButtonFormField<String>(
                            decoration: InputDecoration(labelText: AppLocalizations.of(context)!.engineSizeL),
                            value: selectedEngineSize != null && getAddCarAvailableEngineSizes().contains(selectedEngineSize) ? selectedEngineSize : null,
                            items: getAddCarAvailableEngineSizes()
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      '${_localizeDigitsGlobal(context, e)}${AppLocalizations.of(context)!.unit_liter_suffix}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              setState(() => selectedEngineSize = v);
                              final parent = context.findAncestorStateOfType<_SellCarPageState>();
                              if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                            },
                            validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectEngineSize : null,
                          )
                        : TextFormField(
                            decoration: InputDecoration(labelText: AppLocalizations.of(context)!.engineSizeL),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) => setState(() => selectedEngineSize = v.isEmpty ? null : v),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return AppLocalizations.of(context)!.selectEngineSize;
                              }
                              final parsed = double.tryParse(v);
                              if (parsed == null || parsed <= 0) {
                                return AppLocalizations.of(context)!.invalidField;
                              }
                              return null;
                            },
                          ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => setState(() {
                      isInlineEngineSizeDropdown = !isInlineEngineSizeDropdown;
                    }),
                    icon: Icon(
                      isInlineEngineSizeDropdown ? Icons.edit : Icons.list,
                      color: const Color(0xFFFF6B00),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              // City Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.cityLabel),
                value: selectedCity != null && cities.contains(selectedCity) ? selectedCity : null,
                items: cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) {
                  setState(() => selectedCity = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectCity : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.whatsappLabel, 
                  hintText: '7XX XXX XXXX',
                  prefixText: '+964 ',
                  prefixStyle: TextStyle(
                    color: Color(0xFFFF6B00),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  services.FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                  services.LengthLimitingTextInputFormatter(10),
                ],
                onChanged: (v) {
                  setState(() => contactPhone = '+964' + v.trim());
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return AppLocalizations.of(context)!.enterWhatsAppNumber;
                  if (v.trim().length < 10) {
                    return _trLegacyText(
                      context,
                      'Please enter a valid phone number',
                      ar: 'يرجى إدخال رقم هاتف صحيح',
                      ku: 'تکایە ژمارەی دروست بنووسە',
                    );
                  }
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
                          child: FutureBuilder<String?>(
                            future: generateVideoThumbnail(x.path),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data != null) {
                                return Stack(
                                  children: [
                                    Image.file(
                                      File(snapshot.data!),
                                      width: 90,
                                      height: 90,
                                      fit: BoxFit.cover,
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
                                );
                              } else {
                                return Stack(
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
                                );
                              }
                            },
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
                  label: Text(
                    _selectedVideos.isEmpty
                        ? _trLegacyText(
                            context,
                            'Add Videos',
                            ar: 'إضافة فيديوهات',
                            ku: 'ڤیدیۆ زیاد بکە',
                          )
                        : _trLegacyText(
                            context,
                            'Add More Videos',
                            ar: 'إضافة المزيد من الفيديوهات',
                            ku: 'ڤیدیۆی زیاتر زیاد بکە',
                          ),
                  ),
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
                            _quickSellTextGlobal(context),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          Text(
                            _trLegacyText(
                              context,
                              'Enable this to make your listing stand out with a special banner',
                              ar: 'فعّل هذا الخيار ليظهر إعلانك بشارة خاصة',
                              ku:
                                  'ئەمە چالاک بکە بۆ ئەوەی ڕیکلامەکەت بە بانەری تایبەت دیار بێت',
                            ),
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
                  final engineSize = OnlineSpecVariant.parseLeadingEngineLiters(
                        selectedEngineSize ?? '',
                      ) ??
                      double.tryParse(selectedEngineSize ?? '');
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
                    final url = Uri.parse(getApiBase() + '/api/cars');
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
                          videoRequest.files.add(await _buildVideoMultipartFile(video));
                        }
                        final videoUploadResp = await videoRequest.send();
                        if (videoUploadResp.statusCode != 200 &&
                            videoUploadResp.statusCode != 201) {
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
    extendBody: true,
    bottomNavigationBar: buildFloatingBottomNav(
      context,
      currentIndex: 0,
      onTap: (idx) {
        switch (idx) {
          case 0:
            _switchMainTabNoAnimation(context, '/');
            break;
          case 1:
            _switchMainTabNoAnimation(context, '/favorites');
            break;
          case 2:
            _switchMainTabNoAnimation(context, '/dealers');
            break;
          case 3:
            if (ApiService.accessToken == null ||
                ApiService.accessToken!.isEmpty) {
              Navigator.pushReplacementNamed(context, '/login');
            } else {
              _switchMainTabNoAnimation(context, '/profile');
            }
            break;
        }
      },
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
  const FavoritesPage({super.key});

  @override
  _FavoritesPageState createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;
  String? _error;
  bool _loginRequired = false;

  int _favoritedAtMs(Map<String, dynamic> m) {
    final raw = (m['favorited_at'] ?? m['favoritedAt'])?.toString().trim();
    if (raw == null || raw.isEmpty) return -1;
    try {
      return DateTime.parse(raw).millisecondsSinceEpoch;
    } catch (_) {
      return -1;
    }
  }

  @override
  void initState() {
    super.initState();
    ListingLayoutPrefs.load();
    // Delay loading until after first frame so that inherited widgets
    // like Localizations are available when _loadFavorites runs.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFavorites());
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _loading = true;
      _error = null;
      _loginRequired = false;
    });
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        setState(() {
          _loginRequired = true;
          _loading = false;
        });
        return;
      }
      final sp = await SharedPreferences.getInstance();
      final cacheKey = 'cache_favorites';
      final cached = sp.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          final data = json.decode(cached);
          if (data is List) {
            setState(() {
              _favorites = data.cast<Map<String, dynamic>>();
              _favorites.sort(
                (a, b) => _favoritedAtMs(b).compareTo(_favoritedAtMs(a)),
              );
              _loading = false;
            });
          }
        } catch (_) {}
      }
      // Backend endpoint is /api/user/favorites
      final url = Uri.parse('${getApiBase()}/api/user/favorites');
      final resp = await http.get(
        url,
        headers: {'Authorization': 'Bearer $tok'},
      );
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        final data = (decoded is Map && decoded['cars'] is List)
            ? decoded['cars']
            : ((decoded is Map && decoded['favorites'] is List)
                  ? decoded['favorites']
                  : decoded);
        if (data is List) {
          setState(() {
            _favorites = data.cast<Map<String, dynamic>>();
            _favorites.sort(
              (a, b) => _favoritedAtMs(b).compareTo(_favoritedAtMs(a)),
            );
          });
          unawaited(sp.setString(cacheKey, json.encode(_favorites)));
        }
      } else if (resp.statusCode == 401) {
        setState(() {
          _loginRequired = true;
        });
      } else {
        setState(() {
          _error = AppLocalizations.of(context)!.couldNotSubmitListing;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite(String carId) async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) return;
      // Use API service so endpoint + auth stays consistent.
      final res = await ApiService.toggleFavorite(carId);
      final bool favorited =
          (res['is_favorited'] == true) || (res['favorited'] == true);
      if (!favorited) {
        setState(() {
          _favorites.removeWhere((c) {
            final cid = (c['public_id'] ?? c['id'] ?? '').toString();
            return cid == carId;
          });
        });
      } else {
        unawaited(AnalyticsService.trackFavorite(carId));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.favoritesTitle)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          if (_loading)
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
              ),
            )
          else if (_loginRequired)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.notLoggedIn,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      child: Text(AppLocalizations.of(context)!.loginAction),
                    ),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Center(
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            )
          else if (_favorites.isEmpty)
            Center(
              child: Text(
                AppLocalizations.of(context)!.noFavoritesYet,
                style: TextStyle(color: muted),
              ),
            )
          else
            RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: _loadFavorites,
              child: ValueListenableBuilder<int>(
                valueListenable: ListingLayoutPrefs.columns,
                builder: (context, cols, _) {
                  final listingColumns = (cols == 1) ? 1 : 2;
                  return GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 110),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: listingColumns,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: listingColumns == 2
                          ? (Platform.isIOS ? 0.66 : 0.61)
                          : 2.78,
                    ),
                    itemCount: _favorites.length,
                    itemBuilder: (context, index) {
                      final carMap = Map<String, dynamic>.from(_favorites[index]);
                      final card = buildGlobalCarCard(
                        context,
                        mapListingToGlobalCarCardData(context, carMap),
                        listLayout: listingColumns == 1,
                      );
                      final String carId =
                          (carMap['public_id'] ?? carMap['id'] ?? '').toString();
                      if (carId.isEmpty) return card;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          card,
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _toggleFavorite(carId),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.favorite,
                                    color: Color(0xFFFF6B00),
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 1,
        onTap: (idx) {
          switch (idx) {
            case 0:
              _switchMainTabNoAnimation(context, '/');
              break;
            case 1:
              // Already on favorites
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              _switchMainTabNoAnimation(context, '/profile');
              break;
          }
        },
      ),
    );
  }
}

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  _ChatListPageState createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  @override
  Widget build(BuildContext context) {
    return const carzo_chat.ChatListPage();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

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
    setState(() {
      _loading = true;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/');
    } catch (e) {
      if (!mounted) return;
      developer.log('Login failed', name: 'LoginPage', error: e);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: const Text(
            'Login failed. Please check your credentials and try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.loginTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.emailOrPhoneLabel,
                  hintText: AppLocalizations.of(context)!.enterEmailOrPhoneHint,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? AppLocalizations.of(context)!.emailOrPhoneRequired
                    : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.passwordLabel,
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? AppLocalizations.of(context)!.requiredField
                    : null,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(AppLocalizations.of(context)!.navLogin),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/forgot-password'),
                child: Text(AppLocalizations.of(context)!.forgotPasswordLink),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/signup'),
                child: Text(AppLocalizations.of(context)!.createAccount),
              ),
            ],
          ),
        ),
      ),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        onTap: (idx) {
          switch (idx) {
            case 0:
              _switchMainTabNoAnimation(context, '/');
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              // Already on login
              break;
          }
        },
      ),
    );
  }
}

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _dealershipNameController = TextEditingController();
  final _dealershipPhoneController = TextEditingController();
  final _dealershipLocationController = TextEditingController();
  bool _loading = false;
  bool _otpSent = false;
  String _authType = 'email'; // 'email' or 'phone'
  bool _isDealer = false;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _dealershipNameController.dispose();
    _dealershipPhoneController.dispose();
    _dealershipLocationController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_isDealer) {
      final dn = _dealershipNameController.text.trim();
      final dp = _dealershipPhoneController.text.trim();
      final dl = _dealershipLocationController.text.trim();
      if (dn.isEmpty || dp.isEmpty || dl.isEmpty) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.errorTitle),
            content: const Text(
              'Please fill dealership name, phone, and location before sending the code.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
        return;
      }
    }
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(AppLocalizations.of(context)!.enterPhoneNumber),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final url = Uri.parse('${getApiBase()}/api/auth/send_otp');
      final Map<String, dynamic> otpBody = {
        'phone': '+964$phone',
        if (_isDealer) ...<String, dynamic>{
          'is_dealer': true,
          'dealership_name': _dealershipNameController.text.trim(),
          'dealership_phone': _dealershipPhoneController.text.trim(),
          'dealership_location': _dealershipLocationController.text.trim(),
        },
      };
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(otpBody),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final bool sent = data['sent'] == true;
        setState(() {
          _otpSent = true;
        });
        if (sent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.verificationCodeSent),
            ),
          );
        } else if (data['dev_code'] != null && kDebugMode) {
          final String code = data['dev_code'].toString();
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.devCodeTitle),
              content: Text(
                AppLocalizations.of(context)!.useCodeToVerify(code),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.okAction),
                ),
              ],
            ),
          );
        } else {
          final String err =
              data['error']?.toString() ??
              AppLocalizations.of(context)!.couldNotSubmitListing;
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.errorTitle),
              content: Text(err),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.okAction),
                ),
              ],
            ),
          );
        }
      } else {
        String msg = resp.body.isNotEmpty
            ? resp.body
            : AppLocalizations.of(context)!.couldNotSubmitListing;
        if (resp.statusCode == 429 && resp.body.isNotEmpty) {
          try {
            final data = json.decode(resp.body) as Map<String, dynamic>?;
            final message = data?['message']?.toString() ?? msg;
            final retryAfter = data?['retry_after'];
            final seconds = retryAfter is int
                ? retryAfter
                : (retryAfter is num ? retryAfter.toInt() : null);
            if (seconds != null && seconds > 0) {
              final minutes = (seconds / 60).ceil();
              msg =
                  '$message Try again in $minutes minute${minutes == 1 ? '' : 's'}.';
            }
          } catch (_) {}
        }
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.errorTitle),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _signup() async {
    if (!_acceptedTerms) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trLegacyText(
              context,
              'Please accept the Terms and Privacy Policy',
              ar: 'يرجى الموافقة على الشروط وسياسة الخصوصية',
              ku: 'تکایە مەرج و سیاسەتی تایبەتمەندی قبوڵ بکە',
            ),
          ),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final username = _usernameController.text.trim();
    if (!_isDealer && username.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(
            '${AppLocalizations.of(context)!.usernameLabel} is required',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (_authType == 'email') {
        await authService.registerEmailWithVerification(
          username: _isDealer ? null : username,
          email: _emailController.text.trim(),
          password: _passwordController.text,
          firstName: _isDealer
              ? _dealershipNameController.text.trim()
              : username,
          lastName: _isDealer ? '' : '',
          phoneNumber: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          isDealer: _isDealer,
          dealershipName: _dealershipNameController.text.trim(),
          dealershipPhone: _dealershipPhoneController.text.trim(),
          dealershipLocation: _dealershipLocationController.text.trim(),
        );
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Success'),
            content: const Text(
              'We sent a confirmation link to your email. '
              'Please verify your email to finish creating your account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
        return;
      }
      // Phone path: keep existing API calls for send_otp/signup, then persist tokens via ApiService
      final url = Uri.parse('${getApiBase()}/api/auth/signup');
      final Map<String, dynamic> requestBody = <String, dynamic>{
        'password': _passwordController.text,
        'auth_type': _authType,
        if (!_isDealer) 'username': username,
        'phone': '+964${_phoneController.text.trim()}',
        'otp_code': _otpController.text.trim(),
        'is_dealer': _isDealer,
        if (_isDealer) ...<String, dynamic>{
          'dealership_name': _dealershipNameController.text.trim(),
          'dealership_phone': _dealershipPhoneController.text.trim(),
          'dealership_location': _dealershipLocationController.text.trim(),
        },
      };
      final resp = await http
          .post(
            url,
            headers: <String, String>{'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final String? legacyToken = (data['token'] as String?)?.trim();
        final String? access = (data['access_token'] as String?)?.trim();
        final String? refresh = (data['refresh_token'] as String?)?.trim();
        final String? token = (legacyToken != null && legacyToken.isNotEmpty)
            ? legacyToken
            : access;
        if (token != null && token.isNotEmpty) {
          await ApiService.setAccessToken(token);
          if (refresh != null && refresh.isNotEmpty) {
            await ApiService.setRefreshToken(refresh);
          }
          await authService.initialize();
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/');
          return;
        }
        // No token: try login so we get tokens and profile
        try {
          final loginIdent = _authType == 'phone'
              ? '+964${_phoneController.text.trim()}'
              : username;
          await authService.login(loginIdent, _passwordController.text);
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/');
        } catch (_) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.errorTitle),
              content: const Text(
                'Signup succeeded. Please log in to continue.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.okAction),
                ),
              ],
            ),
          );
        }
        return;
      }
      final msg = resp.body.isNotEmpty
          ? resp.body
          : AppLocalizations.of(context)!.couldNotSubmitListing;
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      developer.log('Signup failed', name: 'SignupPage', error: e);
      String message =
          'Signup failed. Please check your details and try again.';
      if (e is ApiException) {
        if (e.statusCode == 409) {
          message =
              'An account with this email already exists. Try logging in or use Forgot password.';
        } else if (kDebugMode) {
          message = e.message;
        }
      }
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final textColor = isLightShell ? Colors.black87 : Colors.white;
    final mutedTextColor = isLightShell ? Colors.black54 : Colors.white70;
    final fillColor = isLightShell ? Colors.grey.shade100 : Colors.white10;
    final borderColor = isLightShell ? Colors.grey.shade400 : Colors.white54;

    InputDecoration authDecoration({
      required String labelText,
      String? hintText,
      Widget? prefixIcon,
      String? prefixText,
    }) {
      return InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: prefixIcon,
        prefixText: prefixText,
        filled: true,
        fillColor: fillColor,
        labelStyle: TextStyle(color: mutedTextColor),
        hintStyle: TextStyle(color: mutedTextColor),
        prefixStyle: TextStyle(
          color: Color(0xFFFF6B00),
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFF6B00), width: 2),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.signupTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 110),
            children: [
              // Authentication Type Selection
              Text(
                'Choose Authentication Method:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text(
                        'Email',
                        style: TextStyle(color: textColor),
                      ),
                      value: 'email',
                      groupValue: _authType,
                      onChanged: (value) {
                        setState(() {
                          _authType = value!;
                          _otpSent = false;
                          _otpController.clear();
                        });
                      },
                      activeColor: Color(0xFFFF6B00),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text(
                        'Phone',
                        style: TextStyle(color: textColor),
                      ),
                      value: 'phone',
                      groupValue: _authType,
                      onChanged: (value) {
                        setState(() {
                          _authType = value!;
                          _otpSent = false;
                          _otpController.clear();
                        });
                      },
                      activeColor: Color(0xFFFF6B00),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                'Account type',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'I am registering as a dealership / dealer',
                  style: TextStyle(color: textColor),
                ),
                subtitle: Text(
                  _isDealer
                      ? 'Dealership details required; approval is pending until reviewed.'
                      : 'Leave off for a normal personal account.',
                  style: TextStyle(color: mutedTextColor, fontSize: 13),
                ),
                value: _isDealer,
                onChanged: (v) => setState(() => _isDealer = v),
              ),
              if (_isDealer) ...[
                SizedBox(height: 8),
                TextFormField(
                  controller: _dealershipNameController,
                  style: TextStyle(color: textColor),
                  decoration: authDecoration(labelText: 'Dealership name'),
                  validator: (v) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (v == null || v.trim().isEmpty) {
                      return 'Dealership name is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _dealershipPhoneController,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.phone,
                  decoration: authDecoration(labelText: 'Dealership phone'),
                  validator: (v) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (v == null || v.trim().isEmpty) {
                      return 'Dealership phone is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _dealershipLocationController,
                  style: TextStyle(color: textColor),
                  decoration: authDecoration(labelText: 'Dealership location'),
                  validator: (v) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (v == null || v.trim().isEmpty) {
                      return 'Dealership location is required';
                    }
                    return null;
                  },
                ),
              ],
              SizedBox(height: 16),

              // Conditional fields based on auth type
              if (_authType == 'email') ...[
                TextFormField(
                  controller: _emailController,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.emailAddress,
                  decoration: authDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter your email address',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!RegExp(
                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                    ).hasMatch(v.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
              ] else ...[
                TextFormField(
                  controller: _phoneController,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.phone,
                  decoration: authDecoration(
                    labelText: AppLocalizations.of(context)!.enterPhoneNumber,
                    hintText: '7XX XXX XXXX',
                    prefixText: '+964 ',
                  ),
                  inputFormatters: [
                    services.FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9]'),
                    ),
                    services.LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? AppLocalizations.of(context)!.requiredField
                      : null,
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _otpController,
                        style: TextStyle(color: textColor),
                        decoration: authDecoration(
                          labelText: AppLocalizations.of(context)!.sendCode,
                        ),
                        validator: (v) => (!_otpSent)
                            ? AppLocalizations.of(context)!.sendCodeFirst
                            : ((v == null || v.trim().isEmpty)
                                  ? AppLocalizations.of(context)!.requiredField
                                  : null),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _loading ? null : _sendOtp,
                      child: Text(_otpSent ? 'Resend' : 'Send code'),
                    ),
                  ],
                ),
              ],
              if (!_isDealer) ...[
                SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  style: TextStyle(color: textColor),
                  decoration: authDecoration(
                    labelText: AppLocalizations.of(context)!.usernameLabel,
                    hintText: 'Choose a username',
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) {
                      return '${AppLocalizations.of(context)!.usernameLabel} is required';
                    }
                    if (value.length < 3) {
                      return 'Username must be at least 3 characters';
                    }
                    return null;
                  },
                ),
              ],
              SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                style: TextStyle(color: textColor),
                obscureText: true,
                decoration: authDecoration(
                  labelText: AppLocalizations.of(context)!.passwordLabel,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return AppLocalizations.of(context)!.requiredField;
                  }
                  if (v.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  if (!RegExp(r'[A-Z]').hasMatch(v)) {
                    return 'Password must contain at least one uppercase letter';
                  }
                  if (!RegExp(r'[a-z]').hasMatch(v)) {
                    return 'Password must contain at least one lowercase letter';
                  }
                  if (!RegExp(r'\d').hasMatch(v)) {
                    return 'Password must contain at least one number';
                  }
                  if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(v)) {
                    return 'Password must contain at least one special character';
                  }
                  return null;
                },
              ),
              SizedBox(height: 12),
              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _acceptedTerms = v == true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _trLegacyText(
                        context,
                        'I agree to the ',
                        ar: 'أوافق على ',
                        ku: 'ڕازیم بە ',
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LegalDocumentPage(
                            document: LegalDocument.terms,
                          ),
                        ),
                      ),
                      child: Text(
                        _trLegacyText(
                          context,
                          'Terms',
                          ar: 'الشروط',
                          ku: 'مەرجەکان',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text(
                      _trLegacyText(context, ' and ', ar: ' و', ku: ' و'),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LegalDocumentPage(
                            document: LegalDocument.privacy,
                          ),
                        ),
                      ),
                      child: Text(
                        _trLegacyText(
                          context,
                          'Privacy Policy',
                          ar: 'سياسة الخصوصية',
                          ku: 'تایبەتمەندی',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              ElevatedButton(
                onPressed: (_loading || !_acceptedTerms) ? null : _signup,
                child: _loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(AppLocalizations.of(context)!.createAccount),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/login'),
                child: Text(AppLocalizations.of(context)!.haveAccountLogin),
              ),
            ],
          ),
        ),
      ),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        onTap: (idx) {
          switch (idx) {
            case 0:
              _switchMainTabNoAnimation(context, '/');
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                _switchMainTabNoAnimation(context, '/profile');
              }
              break;
          }
        },
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  BoxDecoration _shellDecoration(BuildContext context) =>
      AppThemes.shellBackgroundDecoration(Theme.of(context).brightness);

  bool _profileLightShell(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  Color _profileCardFill(BuildContext context) {
    if (_profileLightShell(context)) return Colors.white;
    return Color.alphaBlend(
      Colors.white.withOpacity(0.085),
      AppThemes.darkHomeShellBackground,
    );
  }

  Color _profileBorderColor(BuildContext context) {
    if (_profileLightShell(context)) return const Color(0xFFE0E0E0);
    return Colors.white.withOpacity(0.12);
  }

  Color _profilePrimaryInk(BuildContext context) {
    if (_profileLightShell(context)) return Colors.grey[800]!;
    return const Color(0xFFECECEC);
  }

  Color _profileSecondaryInk(BuildContext context) {
    if (_profileLightShell(context)) return Colors.grey[600]!;
    return Colors.white70;
  }

  BoxDecoration _profileCardDecoration(
    BuildContext context, {
    double radius = 16,
    double blur = 12,
    double shadowOpacity = 0.06,
  }) {
    final light = _profileLightShell(context);
    return BoxDecoration(
      color: _profileCardFill(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _profileBorderColor(context), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(light ? shadowOpacity : 0.45),
          blurRadius: light ? blur : 20,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Map<String, dynamic>? me;
  bool _loading = true;
  late final AuthService _authService;
  int _unreadChatCount = 0;
  StreamSubscription<Map<String, dynamic>>? _chatNotificationSub;

  @override
  void initState() {
    super.initState();
    _loadMe();
    // Listen to auth service changes
    _authService = Provider.of<AuthService>(context, listen: false);
    _authService.addListener(_onAuthChange);
    _chatNotificationSub = WebSocketService.notifications.listen((
      notification,
    ) {
      if (!mounted) return;
      final type = (notification['notification_type'] ?? '').toString();
      if (type == 'message') {
        _loadUnreadChatCount();
      }
    });
  }

  @override
  void dispose() {
    // Do not use context in dispose; the element is being deactivated.
    _authService.removeListener(_onAuthChange);
    _chatNotificationSub?.cancel();
    super.dispose();
  }

  void _onAuthChange() {
    if (mounted) {
      _loadMe();
    }
  }

  Future<void> _loadMe() async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        setState(() {
          _loading = false;
          _unreadChatCount = 0;
        });
        return;
      }
      final url = Uri.parse('${getApiBase()}/api/auth/me');
      final resp = await http.get(
        url,
        headers: {'Authorization': 'Bearer $tok'},
      );
      if (resp.statusCode == 200) {
        me = json.decode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    await _loadUnreadChatCount();
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadUnreadChatCount() async {
    final tok = ApiService.accessToken;
    if (tok == null || tok.isEmpty) {
      if (mounted) {
        setState(() => _unreadChatCount = 0);
      } else {
        _unreadChatCount = 0;
      }
      return;
    }
    try {
      final count = await ApiService.getUnreadChatCount();
      if (mounted) {
        setState(() => _unreadChatCount = count);
      } else {
        _unreadChatCount = count;
      }
    } catch (_) {}
  }

  void refreshProfile() {
    _loadMe();
  }

  Future<void> _showAuthRequiredDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.loginTitle),
          content: Text(AppLocalizations.of(ctx)!.notLoggedIn),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx)!.cancelAction),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushReplacementNamed(context, '/signup');
              },
              child: Text(AppLocalizations.of(ctx)!.signupTitle),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: Text(AppLocalizations.of(ctx)!.loginAction),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    await AuthStore.saveToken(null);
    await ApiService.setAccessToken(null);
    await ApiService.logout(); // Clear ApiService tokens too
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Widget _buildNotLoggedInState(BuildContext context) {
    return Stack(
      children: [
        Container(decoration: _shellDecoration(context)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: _profileCardDecoration(
                    context,
                    radius: 20,
                    blur: 18,
                    shadowOpacity: 0.1,
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
                          color: _profilePrimaryInk(context),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Sign in to access your profile and manage your account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _profileSecondaryInk(context),
                        ),
                      ),
                      SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.pushReplacementNamed(context, '/login'),
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      TextButton(
                        onPressed: () =>
                            Navigator.pushReplacementNamed(context, '/signup'),
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
      ],
    );
  }

  Widget _buildLoggedInState(BuildContext context) {
    final isLoggedIn =
        ApiService.accessToken != null && ApiService.accessToken!.isNotEmpty;
    final isLightShell = _profileLightShell(context);
    return Stack(
      children: [
        Container(decoration: _shellDecoration(context)),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          child: Column(
            children: [
              if (!isLoggedIn) ...[
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(18),
                  decoration: _profileCardDecoration(context),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Color(0xFFFF6B00).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person_outline,
                          color: Color(0xFFFF6B00),
                          size: 26,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Guest',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: _profilePrimaryInk(context),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Sign in to access your profile features.',
                              style: TextStyle(
                                fontSize: 13,
                                color: _profileSecondaryInk(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.pushReplacementNamed(context, '/login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 1,
                        ),
                        child: Text(AppLocalizations.of(context)!.loginAction),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
              ],
              if (isLoggedIn) ...[
                // Profile Header
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(24),
                  decoration: _profileCardDecoration(
                    context,
                    radius: 20,
                    blur: 16,
                    shadowOpacity: 0.08,
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Color(0xFFFF6B00).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child:
                            (me?['profile_picture'] != null &&
                                me!['profile_picture'].toString().isNotEmpty)
                            ? CircleAvatar(
                                radius: 24,
                                backgroundImage: NetworkImage(
                                  '${getApiBase()}/static/${me!['profile_picture']}',
                                ),
                                backgroundColor: isLightShell
                                    ? Colors.grey[200]
                                    : Colors.white.withOpacity(0.12),
                              )
                            : Icon(
                                Icons.person,
                                size: 48,
                                color: Color(0xFFFF6B00),
                              ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        () {
                          final at =
                              (me?['account_type'] ?? 'user').toString().trim();
                          final dn =
                              (me?['dealership_name'] ?? '').toString().trim();
                          final fn =
                              (me?['first_name'] ?? '').toString().trim();
                          final ln =
                              (me?['last_name'] ?? '').toString().trim();
                          final full = '$fn $ln'.trim();
                          if (at == 'dealer' && dn.isNotEmpty) return dn;
                          if (at == 'dealer' && full.isNotEmpty) return full;
                          if (at == 'dealer') return 'Dealer';
                          return me?['username']?.toString() ?? 'User';
                        }(),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _profilePrimaryInk(context),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        () {
                          final e = me?['email']?.toString() ?? '';
                          final p =
                              me?['phone_number']?.toString() ??
                              me?['phone']?.toString() ??
                              '';
                          final realEmail =
                              e.isNotEmpty && !e.endsWith('@phone.local');
                          return realEmail ? e : (p.isNotEmpty ? p : e);
                        }(),
                        style: TextStyle(
                          fontSize: 16,
                          color: _profileSecondaryInk(context),
                        ),
                      ),
                      SizedBox(height: 10),
                      Builder(
                        builder: (ctx) {
                          final accountType =
                              (me?['account_type'] ?? 'user').toString();
                          final dealerStatus =
                              (me?['dealer_status'] ?? 'none').toString();
                          final isVerifiedDealer =
                              dealerStatus == 'approved' ||
                              accountType == 'dealer';
                          final isPending = dealerStatus == 'pending';
                          final isRejected = dealerStatus == 'rejected';
                          late final String label;
                          late final Color bg;
                          late final Color fg;
                          if (isVerifiedDealer) {
                            label = 'Verified dealer';
                            bg = Colors.green.withValues(alpha: 0.15);
                            fg = isLightShell
                                ? Colors.green.shade800
                                : Colors.green.shade200;
                          } else if (isPending) {
                            label = 'Dealer application pending';
                            bg = Colors.orange.withValues(alpha: 0.15);
                            fg = isLightShell
                                ? Colors.orange.shade800
                                : Colors.orange.shade200;
                          } else if (isRejected) {
                            label = 'Dealer application declined';
                            bg = Colors.red.withValues(alpha: 0.12);
                            fg = isLightShell
                                ? Colors.red.shade800
                                : Colors.red.shade200;
                          } else {
                            label = 'Personal account';
                            if (isLightShell) {
                              bg = Colors.grey.shade200;
                              fg = Colors.grey.shade700;
                            } else {
                              bg = Colors.white.withOpacity(0.1);
                              fg = Colors.white.withOpacity(0.88);
                            }
                          }
                          return Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: fg,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),

                // User Information Card
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: _profileCardDecoration(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _profilePrimaryInk(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...(() {
                        final loc = AppLocalizations.of(context)!;
                        final isDealer =
                            (me?['account_type'] ?? 'user').toString() ==
                                'dealer';
                        final rows = <Widget>[];
                        if (!isDealer) {
                          rows.add(
                            _buildInfoRow(
                              Icons.person_outline,
                              loc.usernameLabel,
                              me?['username']?.toString() ?? '',
                            ),
                          );
                        }
                        final emailStr = me?['email']?.toString() ?? '';
                        if (emailStr.isNotEmpty &&
                            !emailStr.endsWith('@phone.local')) {
                          rows.add(
                            _buildInfoRow(
                              Icons.email_outlined,
                              loc.emailLabel,
                              emailStr,
                            ),
                          );
                        }
                        final phoneStr =
                            (me?['phone_number'] ?? me?['phone'] ?? '')
                                .toString();
                        if (phoneStr.trim().isNotEmpty) {
                          rows.add(
                            _buildInfoRow(
                              Icons.phone_outlined,
                              loc.phoneLabel,
                              phoneStr,
                            ),
                          );
                        }
                        final dealership =
                            (me?['dealership_name'] ?? '').toString().trim();
                        if (dealership.isNotEmpty) {
                          rows.add(
                            _buildInfoRow(
                              Icons.storefront_outlined,
                              'Dealership',
                              dealership,
                            ),
                          );
                        }
                        return [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0) const SizedBox(height: 12),
                            rows[i],
                          ],
                        ];
                      })(),
                    ],
                  ),
                ),
                SizedBox(height: 24),
              ],

              // Action Buttons
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: _profileCardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.accountActionsTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _profilePrimaryInk(context),
                      ),
                    ),
                    SizedBox(height: 20),
                    _buildActionButton(
                      Icons.directions_car_outlined,
                      AppLocalizations.of(context)!.myListingsTitle,
                      () {
                        if (ApiService.accessToken == null ||
                            ApiService.accessToken!.isEmpty) {
                          _showAuthRequiredDialog(context);
                          return;
                        }
                        Navigator.pushNamed(context, '/my_listings');
                      },
                    ),
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.history,
                      _trLegacyText(
                        context,
                        'Recently viewed',
                        ar: 'شوهد مؤخراً',
                        ku: 'دواتر بینراو',
                      ),
                      () {
                        if (ApiService.accessToken == null ||
                            ApiService.accessToken!.isEmpty) {
                          _showAuthRequiredDialog(context);
                          return;
                        }
                        Navigator.pushNamed(context, '/recently-viewed');
                      },
                    ),
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.bookmark_outline,
                      AppLocalizations.of(context)!.savedSearchesTitle,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SavedSearchesPage(),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.settings_outlined,
                      AppLocalizations.of(context)!.settingsTitle,
                      () {
                        Navigator.pushNamed(context, '/settings');
                      },
                    ),
                    if (me?['is_admin'] == true) ...[
                      SizedBox(height: 12),
                      _buildActionButton(
                        Icons.verified_user_outlined,
                        'Dealer approvals (admin)',
                        () {
                          if (ApiService.accessToken == null ||
                              ApiService.accessToken!.isEmpty) {
                            _showAuthRequiredDialog(context);
                            return;
                          }
                          Navigator.pushNamed(context, '/admin/dealers');
                        },
                      ),
                      SizedBox(height: 12),
                      _buildActionButton(
                        Icons.flag_outlined,
                        _trLegacyText(
                          context,
                          'Reports queue (admin)',
                          ar: 'قائمة البلاغات (مسؤول)',
                          ku: 'ڕیزبەندی ڕاپۆرت (بەڕێوەبەر)',
                        ),
                        () {
                          if (ApiService.accessToken == null ||
                              ApiService.accessToken!.isEmpty) {
                            _showAuthRequiredDialog(context);
                            return;
                          }
                          Navigator.pushNamed(context, '/admin/reports');
                        },
                      ),
                    ],
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.chat_outlined,
                      AppLocalizations.of(context)!.chatTitle,
                      () async {
                        if (ApiService.accessToken == null ||
                            ApiService.accessToken!.isEmpty) {
                          _showAuthRequiredDialog(context);
                          return;
                        }
                        await Navigator.pushNamed(context, '/chat');
                        if (!mounted) return;
                        _loadUnreadChatCount();
                      },
                      badgeCount: _unreadChatCount,
                    ),
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.compare_arrows,
                      AppLocalizations.of(context)!.carComparisonCount,
                      () {
                        Navigator.pushNamed(context, '/comparison');
                      },
                    ),
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.edit_outlined,
                      AppLocalizations.of(context)!.editProfileAction,
                      () async {
                        if (ApiService.accessToken == null ||
                            ApiService.accessToken!.isEmpty) {
                          _showAuthRequiredDialog(context);
                          return;
                        }
                        final result = await Navigator.pushNamed(
                          context,
                          '/edit-profile',
                        );
                        // Refresh profile data if changes were made
                        if (result == true) {
                          _loadMe();
                        }
                      },
                    ),
                    if ((me?['account_type'] ?? 'user').toString() == 'dealer') ...[
                      SizedBox(height: 12),
                      _buildActionButton(
                        Icons.storefront_outlined,
                        _trLegacyText(
                          context,
                          'Edit dealer page',
                          ar: 'تعديل صفحة الوكيل',
                          ku: 'دەستکاری پەڕەی وەکیل',
                        ),
                        () async {
                          if (ApiService.accessToken == null ||
                              ApiService.accessToken!.isEmpty) {
                            _showAuthRequiredDialog(context);
                            return;
                          }
                          final result = await Navigator.pushNamed(
                            context,
                            '/dealer/edit',
                          );
                          if (result == true) {
                            _loadMe();
                          }
                        },
                      ),
                    ],
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.contact_mail_outlined,
                      AppLocalizations.of(context)!.helpSupportTitle,
                      () {
                        Navigator.pushNamed(context, '/help');
                      },
                    ),
                    if (ApiService.accessToken != null &&
                        ApiService.accessToken!.isNotEmpty) ...[
                      SizedBox(height: 12),
                      _buildActionButton(
                        Icons.delete_forever_outlined,
                        AppLocalizations.of(context)!.deleteAccountTitle,
                        () {
                          _showDeleteAccountDialog(context);
                        },
                        color: Colors.red,
                      ),
                    ],
                  ],
                ),
              ),
              if (isLoggedIn) ...[
                SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      _showLogoutDialog(context);
                    },
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final c = context;
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
                  color: _profileSecondaryInk(c),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: _profilePrimaryInk(c),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? color,
    int badgeCount = 0,
  }) {
    final accent = color ?? Color(0xFFFF6B00);
    final light = _profileLightShell(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: light
              ? Colors.grey[100]
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: light
                ? Colors.grey[300]!
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: color ?? _profilePrimaryInk(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            Spacer(),
            if (badgeCount > 0) ...[
              Container(
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  badgeCount > 99 ? '99' : badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(width: 10),
            ],
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: light ? Colors.grey[400]! : Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final passwordController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Delete account',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will permanently delete your account and all your data (listings, messages, favorites). This cannot be undone.',
                ),
                SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password (optional)',
                    hintText: 'Confirm with password if you have one',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  autocorrect: false,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            TextButton(
              onPressed: () async {
                final password = passwordController.text.trim();
                Navigator.of(ctx).pop();
                try {
                  await AuthService().deleteAccount(
                    password: password.isEmpty ? null : password,
                  );
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Your account has been deleted')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().replaceFirst('Exception: ', ''),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: Text(
                'Delete my account',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
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
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.profileTitle)),
      body: _loading
          ? Stack(
              children: [
                Container(decoration: _shellDecoration(context)),
                const Center(child: CircularProgressIndicator()),
              ],
            )
          : _buildLoggedInState(context),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        onTap: (idx) {
          switch (idx) {
            case 0:
              _switchMainTabNoAnimation(context, '/');
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                _switchMainTabNoAnimation(context, '/profile');
              }
              break;
          }
        },
      ),
    );
  }
}

class EditListingPage extends StatefulWidget {
  final Map car;
  const EditListingPage({super.key, required this.car});
  @override
  _EditListingPageState createState() => _EditListingPageState();
}

class _EditListingPageState extends State<EditListingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.editListingTitle),
      ),
      body: Center(child: Text(AppLocalizations.of(context)!.editListingTitle)),
    );
  }
}

class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  _MyListingsPageState createState() => _MyListingsPageState();
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _pushEnabled = true;
  final GlobalKey<PopupMenuButtonState<String?>> _languageMenuKey =
      GlobalKey<PopupMenuButtonState<String?>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _setLocale(String? code) async {
    if (code == null) {
      await LocaleController.setLocale(null);
    } else {
      await LocaleController.setLocale(Locale(code));
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pushEnabled = sp.getBool('push_enabled') ?? true;
    });
  }

  Future<void> _togglePush(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('push_enabled', v);
    if (!mounted) return;
    setState(() {
      _pushEnabled = v;
    });
    final token = sp.getString('push_token');
    if (token != null && token.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('${getApiBase()}/api/push/preferences'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'push_token': token, 'enabled': v}),
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = context.watch<ThemeProvider>();
    final currentLocale = LocaleController.currentLocale.value?.languageCode;
    final isLightShell = Theme.of(context).brightness == Brightness.light;

    final tileFill = isLightShell
        ? Colors.white
        : Color.alphaBlend(
            Colors.white.withOpacity(0.06),
            AppThemes.darkHomeShellBackground,
          );
    final tileBorder = isLightShell ? Colors.grey.shade200 : Colors.white12;
    final titleColor = isLightShell ? Colors.grey.shade900 : Colors.white;
    final subtitleColor = isLightShell ? Colors.grey.shade600 : Colors.white70;
    final dividerColor = isLightShell ? Colors.grey.shade200 : Colors.white12;

    String localeLabel(String? code) {
      if (code == null) return loc.settingsSystem;
      switch (code) {
        case 'en':
          return 'English';
        case 'ar':
          return 'العربية';
        case 'ku':
          return 'کوردی';
        default:
          return code;
      }
    }

    Widget rowTile({
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B00).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFFFF6B00), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.orbitron(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: subtitleColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      );
    }

    Widget settingsCard(List<Widget> children) {
      return Container(
        decoration: BoxDecoration(
          color: tileFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: tileBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isLightShell ? 0.05 : 0.20),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(children: children),
        ),
      );
    }

    final bodyChild = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        settingsCard(
          [
            rowTile(
              icon: Icons.language,
              title: loc.settingsLanguageTitle,
              subtitle: localeLabel(currentLocale),
              trailing: PopupMenuButton<String?>(
                key: _languageMenuKey,
                tooltip: '',
                position: PopupMenuPosition.under,
                onSelected: (v) => _setLocale(v),
                itemBuilder: (context) => [
                  PopupMenuItem<String?>(
                    value: null,
                    child: Text(loc.settingsSystem),
                  ),
                  const PopupMenuItem<String?>(
                    value: 'en',
                    child: Text('English'),
                  ),
                  const PopupMenuItem<String?>(
                    value: 'ar',
                    child: Text('العربية'),
                  ),
                  const PopupMenuItem<String?>(
                    value: 'ku',
                    child: Text('کوردی'),
                  ),
                ],
                icon: Icon(
                  Icons.expand_more,
                  color: isLightShell ? Colors.grey.shade700 : Colors.white70,
                ),
              ),
              onTap: () => _languageMenuKey.currentState?.showButtonMenu(),
            ),
            Divider(height: 1, color: dividerColor),
            rowTile(
              icon: theme.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              title: loc.settingsThemeTitle,
              subtitle: theme.themeMode == ThemeMode.system
                  ? loc.settingsSystem
                  : theme.themeMode == ThemeMode.dark
                      ? loc.settingsDark
                      : loc.settingsLight,
              trailing: Icon(
                theme.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                color: isLightShell ? Colors.grey.shade700 : Colors.white70,
              ),
              onTap: theme.toggleTheme,
            ),
            Divider(height: 1, color: dividerColor),
            rowTile(
              icon: Icons.notifications_active_outlined,
              title: loc.settingsEnablePush,
              subtitle: _pushEnabled ? loc.enabledLabel : loc.disabledLabel,
              trailing: Switch.adaptive(
                value: _pushEnabled,
                activeColor: const Color(0xFFFF6B00),
                onChanged: _togglePush,
              ),
              onTap: () => _togglePush(!_pushEnabled),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      appBar: AppBar(
        title: Text(loc.settingsTitle),
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLightShell
          ? Padding(
              padding: const EdgeInsets.only(bottom: 110),
              child: bodyChild,
            )
          : Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 110),
                child: bodyChild,
              ),
            ),
    );
  }
}

class _MyListingsPageState extends State<MyListingsPage> {
  static const String _draftSnapshotKey = 'legacy_sell_draft_snapshot_v1';
  static const String _draftCurrentStepKey = 'legacy_sell_draft_current_step_v1';
  List<Map<String, dynamic>> myListings = [];
  bool isLoading = true;
  bool isLoadingDraft = true;
  String? error;
  Map<String, dynamic>? _draftSnapshot;

  @override
  void initState() {
    super.initState();
    ListingLayoutPrefs.load();
    _loadSellDraftSnapshot();
    _loadMyListings();
  }

  Future<ListingAnalytics> _fetchListingAnalytics(
    String listingId,
    Map<String, dynamic> listing,
  ) async {
    try {
      final a = await AnalyticsService.getListingAnalytics(listingId);
      if (a.listingId.toString().isNotEmpty) return a;
    } catch (_) {
      // fall through
    }

    // Fallback: try list endpoint (may be backed by /my_listings).
    try {
      final all = await AnalyticsService.getUserListingsAnalytics();
      for (final a in all) {
        if (a.listingId.toString() == listingId) return a;
      }
    } catch (_) {
      // fall through
    }

    int parseInt(dynamic v, {int fallback = 0}) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    double parseDouble(dynamic v, {double fallback = 0}) {
      if (v == null) return fallback;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }

    return ListingAnalytics(
      listingId: listingId,
      title: (listing['title'] ?? '').toString(),
      brand: (listing['brand'] ?? '').toString(),
      model: (listing['model'] ?? '').toString(),
      year: parseInt(listing['year']),
      price: parseDouble(listing['price']),
      imageUrl: null,
      mileage: null,
      city: (listing['city'] ?? listing['location'])?.toString(),
      views: 0,
      messages: 0,
      calls: 0,
      shares: 0,
      favorites: 0,
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
  }

  void _showListingAnalyticsPopup(Map<String, dynamic> listing, String listingId) {
    if (listingId.isEmpty) return;
    final loc = AppLocalizations.of(context)!;
    final future = _fetchListingAnalytics(listingId, listing);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(loc.analyticsTitle),
          content: SizedBox(
            width: 360,
            child: FutureBuilder<ListingAnalytics>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(snapshot.error.toString());
                }
                final a = snapshot.data;
                if (a == null) return const Text('No analytics available.');

                Widget metricRow(IconData icon, String label, String value) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: const Color(0xFFFF6B00)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                final resolvedTitle = (a.title).trim().isNotEmpty
                    ? prettyTitleCase(a.title)
                    : prettyTitleCase(a.carTitle);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resolvedTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    metricRow(
                      Icons.visibility_outlined,
                      loc.viewsLabel,
                      '${a.views}',
                    ),
                    metricRow(
                      Icons.message_outlined,
                      loc.messagesLabel,
                      '${a.messages}',
                    ),
                    metricRow(
                      Icons.phone_outlined,
                      loc.callsLabel,
                      '${a.calls}',
                    ),
                    metricRow(
                      Icons.share_outlined,
                      loc.sharesLabel,
                      '${a.shares}',
                    ),
                    metricRow(
                      Icons.favorite_outline,
                      loc.favoritesLabel,
                      '${a.favorites}',
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc.cancelAction),
            ),
          ],
        );
      },
    );
  }

  void _showOverallAnalyticsPopup() {
    final loc = AppLocalizations.of(context)!;
    final future = AnalyticsService.getAnalyticsSummary();

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(loc.analyticsOverview),
          content: SizedBox(
            width: 360,
            child: FutureBuilder<AnalyticsSummary>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(snapshot.error.toString());
                }
                final s = snapshot.data;
                if (s == null) return const Text('No analytics available.');

                Widget metricRow(IconData icon, String label, String value) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: const Color(0xFFFF6B00)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    metricRow(
                      Icons.directions_car_outlined,
                      loc.listingsLabel,
                      '${s.totalListings}',
                    ),
                    const SizedBox(height: 8),
                    metricRow(
                      Icons.visibility_outlined,
                      loc.viewsLabel,
                      '${s.totalViews}',
                    ),
                    metricRow(
                      Icons.message_outlined,
                      loc.messagesLabel,
                      '${s.totalMessages}',
                    ),
                    metricRow(
                      Icons.phone_outlined,
                      loc.callsLabel,
                      '${s.totalCalls}',
                    ),
                    metricRow(
                      Icons.share_outlined,
                      loc.sharesLabel,
                      '${s.totalShares}',
                    ),
                    metricRow(
                      Icons.favorite_outline,
                      loc.favoritesLabel,
                      '${s.totalFavorites}',
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc.cancelAction),
            ),
          ],
        );
      },
    );
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

      final url = Uri.parse('${getApiBase()}/api/my_listings');
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
        _debugLog('MyListings loaded: ${myListings.length} listings');
      } else if (response.statusCode == 401) {
        setState(() {
          error = 'Please log in to view your listings';
          isLoading = false;
        });
        _debugLog('MyListings API returned 401 - Authentication failed');
      } else {
        setState(() {
          error = 'Failed to load listings. Please try again.';
          isLoading = false;
        });
        _debugLog(
          'MyListings API error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      setState(() {
        error = 'Network error. Please check your connection.';
        isLoading = false;
      });
    }
  }

  dynamic _draftValue(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num || value is bool) return value;
    if (value is XFile) return value.path;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _draftValue(v)));
    }
    if (value is Iterable) {
      return value.map(_draftValue).toList();
    }
    return value.toString();
  }

  Future<void> _loadSellDraftSnapshot() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftSnapshotKey);
      if (raw == null || raw.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _draftSnapshot = null;
          isLoadingDraft = false;
        });
        return;
      }
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        if (!mounted) return;
        setState(() {
          _draftSnapshot = null;
          isLoadingDraft = false;
        });
        return;
      }
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      final rawCarData = data['carData'];
      final carData = rawCarData is Map
          ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
          : <String, dynamic>{};
      final jsonStep = _readSellDraftStepDynamic(data['currentStep']);
      final prefsStep = sp.getInt(_draftCurrentStepKey);
      final mergedStep = _mergeSellDraftStep(
        jsonStep: jsonStep,
        prefsStep: prefsStep,
      );
      if (!mounted) return;
      setState(() {
        _draftSnapshot = <String, dynamic>{
          if (data['draftId'] != null) 'draftId': data['draftId'],
          'currentStep': mergedStep,
          'carData': carData,
          if (data['isPlaceholder'] == true) 'isPlaceholder': true,
          if (data['updatedAt'] != null) 'updatedAt': data['updatedAt'],
        };
        isLoadingDraft = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _draftSnapshot = null;
        isLoadingDraft = false;
      });
    }
  }

  Future<void> _discardSellDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_draftSnapshotKey);
      await sp.remove(_draftCurrentStepKey);
      await sp.remove('legacy_sell_draft_step1_v1');
      await sp.remove('legacy_sell_draft_step2_v1');
      await sp.remove('legacy_sell_draft_step3_v1');
      await sp.remove('legacy_sell_draft_step4_v1');
      if (!mounted) return;
      setState(() {
        _draftSnapshot = null;
      });
    } catch (_) {}
  }

  Future<void> _resumeSellDraft() async {
    final snapshot = _draftSnapshot;
    if (snapshot == null) {
      Navigator.pushNamed(context, '/sell');
      return;
    }
    Navigator.pushNamed(
      context,
      '/sell',
      arguments: {'draftSnapshot': snapshot},
    );
  }

  String _draftTitle(Map<String, dynamic> carData) {
    final brand = (carData['brand'] ?? '').toString().trim();
    final model = (carData['model'] ?? '').toString().trim();
    final trim = (carData['trim'] ?? '').toString().trim();
    final year = (carData['year'] ?? '').toString().trim();
    final parts = <String>[brand, model];
    final title = parts.where((s) => s.isNotEmpty).join(' ');
    final suffix = [trim, year].where((s) => s.isNotEmpty).join(' • ');
    if (title.isEmpty && suffix.isEmpty) return 'Untitled draft';
    if (title.isEmpty) return suffix;
    if (suffix.isEmpty) return title;
    return '$title • $suffix';
  }

  Widget _buildDraftSection({required bool listLayout}) {
    final snapshot = _draftSnapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final carData = snapshot['carData'] is Map
        ? Map<String, dynamic>.from((snapshot['carData'] as Map).cast<String, dynamic>())
        : <String, dynamic>{};
    final currentStep = _readSellDraftStepDynamic(snapshot['currentStep']);
    final stepLabel = [
      'Step 1: Basic info',
      'Step 2: Details',
      'Step 3: Pricing',
      'Step 4: Photos',
      'Step 5: Review',
    ];
    final stepText = stepLabel[currentStep.clamp(0, 4).toInt()];

    final draftListing = <String, dynamic>{
      ...carData,
      'title': _draftTitle(carData),
      'price': carData['price']?.toString().trim(),
      'images': (carData['images'] is List)
          ? List<dynamic>.from(carData['images'] as List)
          : const <dynamic>[],
      'videos': (carData['videos'] is List)
          ? List<dynamic>.from(carData['videos'] as List)
          : const <dynamic>[],
      'is_quick_sell': carData['is_quick_sell'] ?? false,
    };

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: buildGlobalCarCard(
              context,
              draftListing,
              listLayout: listLayout,
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _resumeSellDraft,
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.62),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'DRAFT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Material(
              color: Colors.black.withOpacity(0.62),
              shape: const CircleBorder(),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _discardSellDraft,
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: 'Discard draft',
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.62),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                stepText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final bodyChild = isLoading
        ? Center(child: CircularProgressIndicator())
        : error != null
        ? _buildErrorState()
        : (myListings.isEmpty && _draftSnapshot == null && !isLoadingDraft)
        ? _buildEmptyState()
        : _buildListingsGrid();
    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.myListingsTitle),
        backgroundColor: Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: _loadMyListings),
        ],
      ),
      body: isLightShell
          ? Padding(
              padding: const EdgeInsets.only(bottom: 110),
              child: bodyChild,
            )
          : Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 110),
                child: bodyChild,
              ),
            ),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        onTap: (idx) {
          switch (idx) {
            case 0:
              _switchMainTabNoAnimation(context, '/');
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                _switchMainTabNoAnimation(context, '/profile');
              }
              break;
          }
        },
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
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            SizedBox(height: 16),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
              child: Text(AppLocalizations.of(context)!.retryAction),
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
              AppLocalizations.of(context)!.noListingsYet,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.noListingsEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
                  Text(AppLocalizations.of(context)!.addYourFirstCar),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListingsGrid() {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isLightShell ? const Color(0xFF131722) : Colors.white,
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
                Flexible(
                  flex: 0,
                  fit: FlexFit.loose,
                  child: Text(
                    AppLocalizations.of(
                      context,
                    )!.yourListingsCount(myListings.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isLightShell ? Colors.white : Colors.grey[800],
                    ),
                  ),
                ),
                // Slightly more flex before the button nudges it right while
                // keeping spacing roughly balanced.
                const Expanded(flex: 5, child: SizedBox.shrink()),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/sell'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFF6B00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.addNewButton,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Expanded(flex: 4, child: SizedBox.shrink()),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showOverallAnalyticsPopup,
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Overall analytics'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B00),
                side: const BorderSide(color: Color(0xFFFF6B00), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        SizedBox(height: 0),
        Expanded(
          child: (myListings.isEmpty && _draftSnapshot == null)
              ? _buildEmptyState()
              : ValueListenableBuilder<int>(
                  valueListenable: ListingLayoutPrefs.columns,
                  builder: (context, cols, _) {
                    final listingColumns = (cols == 1) ? 1 : 2;
                    final hasDraft = _draftSnapshot != null;
                    final totalCards = myListings.length + (hasDraft ? 1 : 0);
                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        listingColumns == 1 ? 4 : 8,
                        8,
                        listingColumns == 1 ? 4 : 8,
                        8,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: listingColumns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: listingColumns == 2
                            ? (Platform.isIOS ? 0.66 : 0.61)
                            : 2.78,
                      ),
                      itemCount: totalCards,
                      itemBuilder: (context, index) {
                        if (hasDraft && index == 0) {
                          return _buildDraftSection(
                            listLayout: listingColumns == 1,
                          );
                        }

                        final listing = myListings[hasDraft ? index - 1 : index];
                        final id =
                            (listing['id'] ?? listing['public_id'] ?? '').toString();
                        final mapped = mapListingToGlobalCarCardData(context, listing);
                        final card = buildGlobalCarCard(
                          context,
                          mapped,
                          listLayout: listingColumns == 1,
                        );

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            card,
                            if (id.isNotEmpty)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Material(
                                  color: const Color(0xFFFF6B00),
                                  borderRadius: BorderRadius.circular(6),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () => _showListingAnalyticsPopup(
                                      listing,
                                      id,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      child: Text(
                                        AppLocalizations.of(context)!.analyticsTitle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

}

