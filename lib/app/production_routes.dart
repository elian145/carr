import 'package:flutter/material.dart';

import '../pages/admin_dealers_page.dart';
import '../pages/admin_reports_page.dart';
import '../pages/analytics_page.dart';
import '../pages/auth_pages.dart';
import '../pages/car_detail_page.dart';
import '../pages/change_password_page.dart';
import '../pages/chat_pages.dart';
import '../pages/comparison_page.dart';
import '../pages/dealer_profile_page.dart';
import '../pages/dealers_directory_page.dart';
import '../pages/edit_dealer_page.dart';
import '../pages/edit_listing_page.dart';
import '../pages/edit_profile_page.dart';
import '../pages/favorites_page.dart';
import '../pages/help_center_page.dart';
import '../pages/home_filters_page.dart';
import '../pages/home_page.dart';
import '../pages/my_listings_page.dart';
import '../pages/profile_page.dart';
import '../pages/recently_viewed_page.dart';
import '../pages/reset_password_page.dart';
import '../pages/saved_searches_page.dart';
import '../pages/sell_entry_pages.dart';
import '../pages/sell_page.dart';
import '../pages/settings_page.dart';
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

Widget _editListingRoute(BuildContext context) {
  final args = readRouteArgs(context);
  final car = args?['car'];
  if (car is! Map) {
    return navigationErrorScaffold('Missing listing data');
  }
  return AuthGuard(
    child: EditListingPage(
      car: Map<String, dynamic>.from(car.cast<String, dynamic>()),
    ),
  );
}

/// Production routes for [ProductionApp].
Map<String, WidgetBuilder> buildProductionRoutes() {
  return <String, WidgetBuilder>{
    '/': (context) => const HomePage(),
    '/home_filters': (context) => const HomeFiltersPage(),
    '/sell': (context) {
      final args = readRouteArgs(context);
      final initialDraftSnapshot = _sellDraftSnapshot(args);
      final startFresh = args?['startFresh'] == true;
      final showDraftGate = args?['showDraftGate'] == true;
      if (initialDraftSnapshot != null) {
        return AuthGuard(
          sellFlow: true,
          child: SellPage(
            initialDraftSnapshot: initialDraftSnapshot,
          ),
        );
      }
      if (startFresh) {
        return AuthGuard(
          sellFlow: true,
          child: const SellPage(startFresh: true),
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
    '/settings': (context) => const SettingsPage(),
    '/favorites': (context) => AuthGuard(
          allowGuest: true,
          child: const FavoritesPage(),
        ),
    '/dealers': (context) => const DealersDirectoryPage(),
    '/chat': (context) => AuthGuard(child: const ChatListPage()),
    '/login': (context) => const LoginPage(),
    '/signup': (context) => const RegisterPage(),
    '/profile': (context) => AuthGuard(
          allowGuest: true,
          child: const ProfilePage(),
        ),
    '/edit-profile': (context) => AuthGuard(child: const EditProfilePage()),
    '/car_detail': (context) {
      final args = readRouteArgs(context);
      final carId = (args?['carId'] ?? '').toString().trim();
      if (carId.isEmpty) {
        return navigationErrorScaffold('Missing listing id');
      }
      return CarDetailPage(carId: carId);
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
        child: ChatConversationPage(
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
    '/edit': _editListingRoute,
    '/edit_listing': _editListingRoute,
    '/my_listings': (context) => AuthGuard(child: MyListingsPage()),
    '/comparison': (context) => const ComparisonPage(),
    '/saved-searches': (context) => const SavedSearchesPage(),
    '/recently-viewed': (context) =>
        AuthGuard(child: const RecentlyViewedPage()),
    '/analytics': (context) => const AnalyticsPage(),
    '/change-password': (context) =>
        AuthGuard(child: const ChangePasswordPage()),
    '/notifications': (context) =>
        AuthGuard(child: const NotificationsPage()),
    '/reset-password': (context) => ResetPasswordPage(),
    '/verify-email': (context) {
      final args = readRouteArgs(context);
      final token = (args?['token'] ?? '').toString().trim();
      return VerifyEmailPage(
        initialToken: token.isNotEmpty ? token : null,
      );
    },
    '/forgot-password': (context) => ForgotPasswordPage(),
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
