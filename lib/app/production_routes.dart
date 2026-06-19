import 'package:flutter/material.dart';

import '../pages/admin_dealers_page.dart';
import '../pages/admin_reports_page.dart';
import '../pages/analytics_page.dart';
import '../pages/auth_pages.dart' as auth_pages;
import '../pages/car_detail_page.dart' as modern_detail;
import '../pages/change_password_page.dart';
import '../pages/chat_pages.dart' as carzo_chat;
import '../pages/comparison_page.dart' as modern_comparison;
import '../pages/dealer_profile_page.dart';
import '../pages/dealers_directory_page.dart';
import '../pages/edit_dealer_page.dart';
import '../pages/edit_listing_page.dart' as modern_edit;
import '../pages/edit_profile_page.dart';
import '../pages/favorites_page.dart' as modern_favorites;
import '../pages/help_center_page.dart';
import '../pages/home_filters_page.dart' as modern_filters;
import '../pages/home_page.dart' as modern_home;
import '../pages/my_listings_page.dart' as modern_listings;
import '../pages/profile_page.dart' as modern_profile;
import '../pages/recently_viewed_page.dart';
import '../pages/reset_password_page.dart';
import '../pages/saved_searches_page.dart' as modern_saved_searches;
import '../pages/sell_entry_pages.dart';
import '../pages/sell_page.dart' as modern_sell;
import '../pages/settings_page.dart' as modern_settings;
import '../pages/tiktok_scroll_page.dart';
import '../pages/verify_email_page.dart';
import '../shared/auth/auth_guard.dart';
import 'route_helpers.dart';

Map<String, dynamic>? _sellDraftSnapshot(Map<String, dynamic>? args) {
  if (args == null) return null;
  final draft = args['draftSnapshot'];
  if (draft is! Map) return null;
  return Map<String, dynamic>.from(draft.cast<String, dynamic>());
}

/// Modern production routes used by [MyApp] (legacy fallbacks merged separately).
Map<String, WidgetBuilder> buildProductionRoutes() {
  return {
    '/': (context) => const modern_home.HomePage(),
    '/home_filters': (context) => const modern_filters.HomeFiltersPage(),
    '/sell': (context) {
      final args = readRouteArgs(context);
      final initialDraftSnapshot = _sellDraftSnapshot(args);
      final startFresh = args?['startFresh'] == true;
      final showDraftGate = args?['showDraftGate'] == true;
      if (initialDraftSnapshot != null) {
        return AuthGuard(
          sellFlow: true,
          child: modern_sell.SellPage(
            initialDraftSnapshot: initialDraftSnapshot,
          ),
        );
      }
      if (startFresh) {
        return AuthGuard(
          sellFlow: true,
          child: const modern_sell.SellPage(startFresh: true),
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
    '/settings': (context) => const modern_settings.SettingsPage(),
    '/favorites': (context) => AuthGuard(
          allowGuest: true,
          child: const modern_favorites.FavoritesPage(),
        ),
    '/dealers': (context) => const DealersDirectoryPage(),
    '/chat': (context) =>
        AuthGuard(child: const carzo_chat.ChatListPage()),
    '/login': (context) => const auth_pages.LoginPage(),
    '/signup': (context) => const auth_pages.RegisterPage(),
    '/profile': (context) => AuthGuard(
          allowGuest: true,
          child: const modern_profile.ProfilePage(),
        ),
    '/edit-profile': (context) =>
        AuthGuard(child: const EditProfilePage()),
    '/car_detail': (context) {
      final args = readRouteArgs(context);
      final carId = (args?['carId'] ?? '').toString().trim();
      if (carId.isEmpty) {
        return navigationErrorScaffold('Missing listing id');
      }
      return modern_detail.CarDetailPage(carId: carId);
    },
    '/tiktok_scroll': (context) {
      final args = readRouteArgs(context);
      final cars = (args?['cars'] as List?)
              ?.whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList() ??
          <Map<String, dynamic>>[];
      final initialIndex = (args?['initialIndex'] as int?) ?? 0;
      return TikTokScrollPage(
        cars: cars,
        initialIndex: initialIndex,
      );
    },
    '/chat/conversation': (context) {
      final args = readRouteArgs(context);
      final rawId =
          (args?['carId'] ?? args?['conversationId'] ?? '').toString().trim();
      if (rawId.isEmpty) {
        return navigationErrorScaffold('Missing chat conversation id');
      }
      return AuthGuard(
        child: carzo_chat.ChatConversationPage(
          carId: rawId,
          receiverId: args?['receiverId']?.toString(),
          initialDraft: args?['initialDraft']?.toString(),
          initialListingPreview: args?['listingPreview'] is Map
              ? Map<String, dynamic>.from(
                  (args?['listingPreview'] as Map).cast<String, dynamic>(),
                )
              : null,
        ),
      );
    },
    '/edit': (context) {
      final args = readRouteArgs(context);
      final car = args?['car'];
      if (car is! Map) {
        return navigationErrorScaffold('Missing listing data');
      }
      return AuthGuard(
        child: modern_edit.EditListingPage(
          car: Map<String, dynamic>.from(car.cast<String, dynamic>()),
        ),
      );
    },
    '/edit_listing': (context) {
      final args = readRouteArgs(context);
      final car = args?['car'];
      if (car is! Map) {
        return navigationErrorScaffold('Missing listing data');
      }
      return AuthGuard(
        child: modern_edit.EditListingPage(
          car: Map<String, dynamic>.from(car.cast<String, dynamic>()),
        ),
      );
    },
    '/my_listings': (context) =>
        AuthGuard(child: modern_listings.MyListingsPage()),
    '/comparison': (context) => const modern_comparison.ComparisonPage(),
    '/saved-searches': (context) =>
        const modern_saved_searches.SavedSearchesPage(),
    '/recently-viewed': (context) =>
        AuthGuard(child: const RecentlyViewedPage()),
    '/analytics': (context) => const AnalyticsPage(),
    '/change-password': (context) =>
        AuthGuard(child: const ChangePasswordPage()),
    '/notifications': (context) =>
        AuthGuard(child: const carzo_chat.NotificationsPage()),
    '/reset-password': (context) => ResetPasswordPage(),
    '/verify-email': (context) {
      final args = readRouteArgs(context);
      final token = (args?['token'] ?? '').toString().trim();
      return VerifyEmailPage(
        initialToken: token.isNotEmpty ? token : null,
      );
    },
    '/forgot-password': (context) => auth_pages.ForgotPasswordPage(),
    '/admin/dealers': (context) => AuthGuard(child: AdminDealersPage()),
    '/admin/reports': (context) =>
        AuthGuard(child: const AdminReportsPage()),
    '/help': (context) => const HelpCenterPage(),
    '/dealer/edit': (context) => AuthGuard(child: EditDealerPage()),
    '/dealer/profile': (context) {
      final args = readRouteArgs(context);
      final dealerPublicId = (args?['dealerPublicId'] ?? '').toString().trim();
      if (dealerPublicId.isEmpty) {
        return navigationErrorScaffold('Missing dealer id');
      }
      return DealerProfilePage(dealerPublicId: dealerPublicId);
    },
  };
}
