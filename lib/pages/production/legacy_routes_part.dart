part of 'carzo_pages.dart';

/// Optional rollback routes (`/legacy_*`) — not registered in [MyApp] by default.
/// Use in tests or temporary rollback by merging into [MaterialApp.routes].
Map<String, WidgetBuilder> buildLegacyFallbackRoutes() {
  Map<String, dynamic>? sellDraftSnapshot(BuildContext context) {
    final args = readRouteArgs(context);
    if (args == null) return null;
    final draft = args['draftSnapshot'];
    if (draft is! Map) return null;
    return Map<String, dynamic>.from(draft.cast<String, dynamic>());
  }

  return {
    '/legacy_home': (context) => HomePage(),
    '/legacy_home_filters': (context) => HomePage(),
    '/legacy_sell': (context) {
      final initialDraftSnapshot = sellDraftSnapshot(context);
      if (initialDraftSnapshot != null) {
        return AuthGuard(
          child: SellCarPage(initialDraftSnapshot: initialDraftSnapshot),
        );
      }
      return AuthGuard(child: const SellCarPage(startFreshListing: true));
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
    '/legacy_favorites': (context) => AuthGuard(child: FavoritesPage()),
    '/legacy_profile': (context) => AuthGuard(child: ProfilePage()),
    '/legacy_settings': (context) => SettingsPage(),
    '/legacy_login': (context) => LoginPage(),
    '/legacy_saved_searches': (context) => const SavedSearchesPage(),
  };
}
