import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../features/home/widgets/home_feed_states.dart';
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
///
/// F-05: `AuthService`'s own bounded profile-retry (`_scheduleProfileRetry`)
/// already recovers a *transient* `/auth/me` failure on its own — this
/// widget must not add a second retry mechanism. But `AuthService.isLoading`
/// only covers the very first `/auth/me` attempt (see
/// `AuthService._initializeOnce`); the automatic retries that follow run
/// with `isLoading == false` the whole time. So a *sustained* failure (the
/// retries exhaust with none of them succeeding, or genuinely never
/// resolve) leaves a real stranded combination:
///   `AuthService.isAuthenticated == false`
///   `AuthService.isLoading == false`
///   `ApiService.isAuthenticated == true` (token untouched — no 401 fired)
/// which used to spin a bare `CircularProgressIndicator` forever. This
/// widget now starts a bounded "terminal" timer the moment it observes that
/// combination and, once it fires, swaps the spinner for a recoverable
/// error state whose retry action calls the existing
/// `AuthService().refreshProfile()` (no new profile-loading mechanism).
class AuthGuard extends StatefulWidget {
  const AuthGuard({
    super.key,
    required this.child,
    this.allowWhenLoggedOut = false,
    this.promptSellAuthWhenLoggedOut = false,
  });
  final Widget child;
  final bool allowWhenLoggedOut;
  final bool promptSellAuthWhenLoggedOut;

  // How long this widget waits, once it observes the terminal stranded
  // state described above, before giving up on the spinner and showing a
  // recoverable error instead.
  //
  // Must comfortably exceed AuthService's own worst-case bounded retry
  // cascade, since the "stranded" window (as defined above) can begin as
  // early as the very first `/auth/me` failure, not just after all
  // retries are exhausted:
  //   initial attempt, cold-start adaptive timeout ........... 55s
  //   + retry 1 delay ......................................... 2s
  //   + retry 1 attempt (ApiService.warmRequestTimeout) ...... 20s
  //   + retry 2 delay ......................................... 5s
  //   + retry 2 attempt (warmRequestTimeout) ................. 20s
  //   + retry 3 delay ........................................ 10s
  //   + retry 3 attempt (warmRequestTimeout) ................. 20s
  //   = 132s worst case before AuthService's own retry budget is spent.
  // 180s leaves a ~48s margin above that worst case, so this can never
  // fire while a legitimate AuthService retry could still succeed.
  static const Duration _terminalTimeout = Duration(seconds: 180);

  /// Test-only override for [_terminalTimeout], so tests can reach the
  /// terminal error state deterministically without a real ~3-minute wait.
  /// Always `null` in production. Mirrors
  /// `AuthService.debugProfileRetryDelaysOverride`'s existing convention.
  @visibleForTesting
  static Duration? debugTerminalTimeoutOverride;

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  final AuthService _authService = AuthService();
  Timer? _terminalTimer;
  bool _terminalTimeoutFired = false;

  @override
  void initState() {
    super.initState();
    _authService.addListener(_handleAuthChanged);
    // Covers mounting directly into an already-stranded session (e.g. a
    // deep link into a protected route after the retry cascade already
    // ran its course elsewhere) — otherwise only a future
    // `notifyListeners()` call would ever (re-)evaluate the terminal timer.
    _handleAuthChanged();
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChanged);
    _terminalTimer?.cancel();
    super.dispose();
  }

  bool get _isStranded =>
      !_authService.isAuthenticated &&
      !_authService.isLoading &&
      ApiService.isAuthenticated;

  // Driven only by AuthService's own `notifyListeners()` (via the listener
  // added in `initState`), by `initState` itself, and by `_retry()` below —
  // deliberately never by `build()`, so repeated widget rebuilds can never
  // create a duplicate timer.
  void _handleAuthChanged() {
    if (_isStranded) {
      _terminalTimer ??= Timer(
        AuthGuard.debugTerminalTimeoutOverride ?? AuthGuard._terminalTimeout,
        _onTerminalTimeout,
      );
    } else {
      // Recovered, or tokens were cleared (definitive 401) — cancel any
      // pending terminal timer and clear a previously-fired one so a
      // *future* stranding (a different session) gets its own fresh timer.
      _cancelTerminalTimer();
      if (_terminalTimeoutFired && mounted) {
        setState(() => _terminalTimeoutFired = false);
      }
    }
  }

  void _cancelTerminalTimer() {
    _terminalTimer?.cancel();
    _terminalTimer = null;
  }

  void _onTerminalTimeout() {
    _terminalTimer = null;
    if (!mounted || !_isStranded) return;
    setState(() => _terminalTimeoutFired = true);
  }

  void _retry() {
    _cancelTerminalTimer();
    if (_terminalTimeoutFired) {
      setState(() => _terminalTimeoutFired = false);
    }
    // Reuses AuthService's existing single-flight profile fetch — no new
    // loading mechanism. A failed manual attempt does not itself call
    // notifyListeners() (AuthService's own automatic-retry budget is
    // already exhausted by the time this UI can show), so re-evaluate the
    // terminal timer once this attempt settles either way.
    unawaited(
      _authService.refreshProfile().whenComplete(() {
        if (mounted) _handleAuthChanged();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    if (auth.isAuthenticated || widget.allowWhenLoggedOut) {
      return widget.child;
    }
    if (_terminalTimeoutFired) {
      final loc = AppLocalizations.of(context)!;
      return Scaffold(
        body: HomeFeedErrorState(
          message: loc.failedToLoadUserData,
          onRetry: _retry,
        ),
      );
    }
    if (auth.isLoading || ApiService.isAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.promptSellAuthWhenLoggedOut) {
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
