import 'package:flutter/material.dart';

import '../app/route_helpers.dart';
import '../shared/auth/auth_guard.dart';
import 'main_legacy.dart';

Map<String, dynamic>? _legacySellDraftSnapshot(BuildContext context) {
  final args = readRouteArgs(context);
  if (args == null) return null;
  final draft = args['draftSnapshot'];
  if (draft is! Map) return null;
  return Map<String, dynamic>.from(draft.cast<String, dynamic>());
}

/// Legacy fallback routes (`/legacy_*`) for rollback and smoke tests.
Map<String, WidgetBuilder> buildLegacyFallbackRoutes() {
  return {
    '/legacy_home': (context) => LegacyHomePage(),
    '/legacy_home_filters': (context) => const LegacyHomeFiltersPage(),
    '/legacy_sell': (context) {
      final initialDraftSnapshot = _legacySellDraftSnapshot(context);
      if (initialDraftSnapshot != null) {
        return AuthGuard(
          sellFlow: true,
          child: SellCarPage(
            initialDraftSnapshot: initialDraftSnapshot,
          ),
        );
      }
      return AuthGuard(
        sellFlow: true,
        child: const SellCarPage(startFreshListing: true),
      );
    },
    '/legacy_car_detail': (context) {
      final args = readRouteArgs(context);
      final carId = (args?['carId'] ?? '').toString().trim();
      if (carId.isEmpty) {
        return navigationErrorScaffold('Missing listing id');
      }
      return CarDetailsPage(carId: carId);
    },
    '/legacy_comparison': (context) => CarComparisonPage(),
    '/legacy_favorites': (context) =>
        AuthGuard(allowGuest: true, child: FavoritesPage()),
    '/legacy_profile': (context) =>
        AuthGuard(allowGuest: true, child: ProfilePage()),
    '/legacy_settings': (context) => SettingsPage(),
    '/legacy_login': (context) => LoginPage(),
    '/legacy_saved_searches': (context) => const SavedSearchesPage(),
  };
}
