import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/auth/token_store.dart';
import '../state/locale_controller.dart' as app_state;
import 'widgets/main_shell_navigation.dart' as main_shell_navigation;

export '../features/home/home_flow.dart' show HomePage;
export '../features/home/widgets/home_feed_states.dart';
export '../features/listing/car_listing_specs_grid.dart';
export '../features/sell/sell_entry.dart';
export '../features/sell/sell_flow.dart' show SellCarPage;
export '../pages/car_details_page.dart';
export '../pages/comparison_page.dart';
export '../pages/production_account_pages.dart';
export '../pages/production_auth_pages.dart';
export '../shared/i18n/region_spec_labels.dart';
export '../shared/listings/body_type_assets.dart';
export 'legacy_fallback_routes.dart' show buildLegacyFallbackRoutes;
export 'widgets/global_listing_card.dart'
    show
        buildGlobalCarCard,
        localizedCarTitleForCard,
        localizedTrimForCard,
        mapListingToGlobalCarCardData;
export 'widgets/home_search_dialog.dart' show HomeSearchDialog;
export 'widgets/listing_galleries.dart'
    show FullScreenGalleryPage, ListingPreviewGalleryPage;
export 'widgets/main_shell_navigation.dart';

// Sideload build flag to disable services that require entitlements on iOS
const bool kSideloadBuild = bool.fromEnvironment(
  'SIDELOAD_BUILD',
  defaultValue: false,
);

/// Navigator key for deep link handling (e.g. reset-password from email link).
final GlobalKey<NavigatorState> productionNavigatorKey =
    GlobalKey<NavigatorState>();

// Build commit SHA for on-device verification
const String kBuildSha = String.fromEnvironment(
  'BUILD_COMMIT_SHA',
  defaultValue: 'dev',
);

// Fallback delegates to provide Material/Cupertino/Widgets localizations for 'ku'
class KuMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const KuMaterialLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<MaterialLocalizations> load(Locale locale) {
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
    return GlobalWidgetsLocalizations.delegate.load(const Locale('ar'));
  }

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<WidgetsLocalizations> old,
  ) => false;
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

class AuthStore {
  static String? get token => TokenStore.token;
  static Future<void> saveToken(String? t) async {
    await TokenStore.save(t);
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
              main_shell_navigation.navigateMainShellTab(context, '/');
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
