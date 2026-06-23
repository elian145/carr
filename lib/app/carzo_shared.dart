import 'package:flutter/material.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart' as services;
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/auth/token_store.dart';
import '../shared/i18n/locale_formatting.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/i18n/region_spec_labels.dart' as region_spec_labels;
export '../shared/i18n/region_spec_labels.dart';
import '../shared/listings/body_type_assets.dart' as body_type_assets;
export '../shared/listings/body_type_assets.dart';
import '../shared/i18n/digits.dart';
import '../shared/debug/app_log.dart';
import '../shared/i18n/listing_field_labels.dart';
import '../shared/i18n/listing_value_labels.dart';
import '../shared/i18n/sort_api_mapping.dart';
import '../shared/listings/transmission_filter.dart';
import '../features/home/home_feed_errors.dart';
import '../shared/listings/listing_events.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/listings/listing_card_data.dart' as listing_card_data;
import '../shared/prefs/listing_layout_prefs.dart';
import '../state/locale_controller.dart' as app_state;
import '../l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../features/saved_searches/saved_search_home_bridge.dart';
import '../pages/saved_searches_page.dart';
export '../pages/comparison_page.dart';
export '../pages/car_details_page.dart';
export '../features/listing/car_listing_specs_grid.dart';
import '../features/listing/listing_mappers.dart';
import '../data/car_catalog.dart';
import '../data/car_name_translations.dart';
import '../services/car_spec_index.dart';
import '../services/saved_search_service.dart';
import '../models/online_spec_variant.dart';
export '../features/sell/sell_flow.dart' show SellCarPage;
export '../features/sell/sell_entry.dart';
import '../shared/listings/body_type_image_widget.dart' as body_type_image;
export 'legacy_fallback_routes.dart' show buildLegacyFallbackRoutes;
import 'widgets/main_shell_navigation.dart' as main_shell_navigation;
export 'widgets/main_shell_navigation.dart';
export '../pages/production_auth_pages.dart';
export '../pages/production_account_pages.dart';
import '../features/home/widgets/home_feed_states.dart';
export '../features/home/widgets/home_feed_states.dart';
import 'app_api_base.dart';
import '../data/brand_logo_filenames.dart';
import 'widgets/global_listing_card.dart';
import 'widgets/home_search_dialog.dart';
export 'widgets/global_listing_card.dart'
    show
        buildGlobalCarCard,
        localizedCarTitleForCard,
        localizedTrimForCard,
        mapListingToGlobalCarCardData;
export 'widgets/listing_galleries.dart'
    show FullScreenGalleryPage, ListingPreviewGalleryPage;
export 'widgets/home_search_dialog.dart' show HomeSearchDialog;
part '../features/home/home_page.dart';

// Part libraries cannot see imports; forward region-spec helpers for home UIs.
const List<String> kCarRegionSpecCodes = region_spec_labels.kCarRegionSpecCodes;

String carRegionSpecDisplayLabel(String code) =>
    region_spec_labels.carRegionSpecDisplayLabel(code);

String carRegionSpecDisplayLabelLocalized(BuildContext context, String code) =>
    region_spec_labels.carRegionSpecDisplayLabelLocalized(context, code);

bool isValidCarRegionSpecCode(String? s) =>
    region_spec_labels.isValidCarRegionSpecCode(s);

// Part libraries cannot see imports; forward body-type asset state for home UIs.
List<String> get globalBodyTypes => body_type_assets.globalBodyTypes;
set globalBodyTypes(List<String> value) =>
    body_type_assets.globalBodyTypes = value;

Map<String, String> get globalBodyTypeAssetMap =>
    body_type_assets.globalBodyTypeAssetMap;
set globalBodyTypeAssetMap(Map<String, String> value) =>
    body_type_assets.globalBodyTypeAssetMap = value;

String _getBodyTypeAsset(String bodyType) =>
    body_type_assets.getBodyTypeAsset(bodyType);

Widget _buildBodyTypeImage(String assetPath) =>
    body_type_image.buildBodyTypeImage(assetPath);

String _trLegacyText(
  BuildContext context,
  String en, {
  String? ar,
  String? ku,
}) =>
    trLegacyText(context, en, ar: ar, ku: ku);

String _translatePlateTypeLegacy(BuildContext context, String raw) =>
    translatePlateTypeLabel(context, raw);

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




String? _translateValueGlobal(BuildContext context, String? raw) =>
    translateListingValue(context, raw);

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

// Locale-aware currency formatting with digit localization
String _formatCurrencyGlobal(BuildContext context, dynamic raw) =>
    formatCurrency(context, raw);

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
  main_shell_navigation.navigateMainShellTab(context, routeName);
}

/// Callable from standalone shell pages (e.g. dealers directory).
void navigateMainShellTab(BuildContext context, String routeName) {
  main_shell_navigation.navigateMainShellTab(context, routeName);
}

Widget buildFloatingBottomNav(
  BuildContext context, {
  required int currentIndex,
  required ValueChanged<int> onTap,
  bool solidBackground = false,
}) =>
    main_shell_navigation.buildFloatingBottomNav(
      context,
      currentIndex: currentIndex,
      onTap: onTap,
      solidBackground: solidBackground,
    );

String _cancelTextGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.cancelAction;
}

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
  const AuthGuard({
    super.key,
    required this.child,
    this.allowWhenLoggedOut = false,
    this.promptSellAuthWhenLoggedOut = false,
  });
  final Widget child;
  final bool allowWhenLoggedOut;
  final bool promptSellAuthWhenLoggedOut;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    if (auth.isAuthenticated || allowWhenLoggedOut) {
      return child;
    }
    if (auth.isLoading || ApiService.isAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (promptSellAuthWhenLoggedOut) {
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

