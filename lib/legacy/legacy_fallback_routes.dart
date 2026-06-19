import 'package:flutter/material.dart';

import '../app/route_helpers.dart';
import '../pages/auth_pages.dart' as auth_pages;
import '../pages/car_detail_page.dart' as car_detail;
import '../pages/comparison_page.dart' as comparison;
import '../pages/favorites_page.dart' as favorites;
import '../pages/home_filters_page.dart';
import '../pages/home_page.dart' as home;
import '../pages/profile_page.dart' as profile;
import '../pages/saved_searches_page.dart' as saved_searches;
import '../pages/sell_entry_pages.dart';
import '../pages/sell_page.dart' as sell;
import '../pages/settings_page.dart' as settings;
import '../shared/auth/auth_guard.dart';

Map<String, dynamic>? _sellDraftSnapshot(Map<String, dynamic>? args) {
  if (args == null) return null;
  final draft = args['draftSnapshot'];
  if (draft is! Map) return null;
  return Map<String, dynamic>.from(draft.cast<String, dynamic>());
}

/// Legacy fallback routes (`/legacy_*`) for rollback and smoke tests.
///
/// Almost all `/legacy_*` URLs are aliases to the same modern screens as production.
Map<String, WidgetBuilder> buildLegacyFallbackRoutes() {
  return {
    '/legacy_home': (context) => const home.HomePage(),
    '/legacy_home_filters': (context) => const HomeFiltersPage(),
    '/legacy_sell': (context) {
      final args = readRouteArgs(context);
      final initialDraftSnapshot = _sellDraftSnapshot(args);
      final startFresh = args?['startFresh'] == true;
      final showDraftGate = args?['showDraftGate'] == true;
      if (initialDraftSnapshot != null) {
        return AuthGuard(
          sellFlow: true,
          child: sell.SellPage(
            initialDraftSnapshot: initialDraftSnapshot,
          ),
        );
      }
      if (startFresh) {
        return AuthGuard(
          sellFlow: true,
          child: const sell.SellPage(startFresh: true),
        );
      }
      if (showDraftGate) {
        return AuthGuard(
          sellFlow: true,
          child: const SellDraftGatePage(),
        );
      }
      return AuthGuard(
        sellFlow: true,
        child: const SellEntryRouterPage(),
      );
    },
    '/legacy_car_detail': (context) {
      final args = readRouteArgs(context);
      final carId = (args?['carId'] ?? '').toString().trim();
      if (carId.isEmpty) {
        return navigationErrorScaffold('Missing listing id');
      }
      return car_detail.CarDetailPage(carId: carId);
    },
    '/legacy_comparison': (context) => const comparison.ComparisonPage(),
    '/legacy_favorites': (context) => AuthGuard(
          allowGuest: true,
          child: const favorites.FavoritesPage(),
        ),
    '/legacy_profile': (context) => AuthGuard(
          allowGuest: true,
          child: const profile.ProfilePage(),
        ),
    '/legacy_settings': (context) => const settings.SettingsPage(),
    '/legacy_login': (context) => const auth_pages.LoginPage(),
    '/legacy_saved_searches': (context) =>
        const saved_searches.SavedSearchesPage(),
  };
}
