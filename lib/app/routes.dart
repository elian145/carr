import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../pages/analytics_page.dart';
import '../pages/auth_pages.dart' as auth;
import '../pages/chat_pages.dart' as chat;
import '../pages/change_password_page.dart';
import '../pages/edit_profile_page.dart';
import '../pages/carzo_app/home_page.dart' as modern;
import '../pages/carzo_app/favorites_page.dart' as favorites;
import '../pages/carzo_app/profile_page.dart' as profile;
import '../pages/reset_password_page.dart';
import '../pages/verify_email_page.dart';
import '../pages/carzo_app/sell_page.dart' as sell;
import '../pages/carzo_app/settings_page.dart' as settings;
import '../pages/carzo_app/car_detail_page.dart' as details;
import '../pages/my_listings_page.dart' as mine;
import '../pages/carzo_app/comparison_page.dart' as comparison;
import '../pages/admin_dealers_page.dart';
import '../pages/dealer_profile_page.dart';
import '../pages/dealers_directory_page.dart';
import '../pages/edit_dealer_page.dart';
import '../pages/edit_listing_page.dart';
import '../pages/recently_viewed_page.dart';
import '../services/auth_service.dart';

class _AuthRequiredPage extends StatelessWidget {
  const _AuthRequiredPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.isAuthenticated) return child;
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _RouteArgsErrorPage extends StatelessWidget {
  final String routeName;
  const _RouteArgsErrorPage({required this.routeName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Navigation error')),
      body: Center(
        child: Text('Invalid or missing arguments for "$routeName"'),
      ),
    );
  }
}

Map<String, WidgetBuilder> buildAppRoutes() {
  Map<String, dynamic>? argsMap(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    return args is Map<String, dynamic> ? args : null;
  }

  return {
    '/': (context) => const modern.HomePage(),
    '/sell': (context) {
      final args = argsMap(context);
      final draftSnapshot = args?['draftSnapshot'];
      return sell.SellPage(
        startFresh: args?['startFresh'] == true,
        initialDraftSnapshot: draftSnapshot is Map
            ? Map<String, dynamic>.from(draftSnapshot.cast<String, dynamic>())
            : null,
        editListing: args?['editListing'] == true,
      );
    },
    '/settings': (context) => const settings.SettingsPage(),
    '/favorites': (context) => const favorites.FavoritesPage(),
    '/chat': (context) => const chat.ChatListPage(),
    '/notifications': (context) => const chat.NotificationsPage(),
    '/login': (context) => const auth.LoginPage(),
    '/signup': (context) => const auth.RegisterPage(),
    '/register': (context) => const auth.RegisterPage(),
    '/forgot-password': (context) => const auth.ForgotPasswordPage(),
    '/reset-password': (context) => const ResetPasswordPage(),
    '/verify-email': (context) {
      final args = argsMap(context);
      final token = args != null ? (args['token'] ?? '').toString().trim() : '';
      return VerifyEmailPage(initialToken: token.isNotEmpty ? token : null);
    },
    '/change-password': (context) =>
        const _AuthRequiredPage(child: ChangePasswordPage()),
    '/profile': (context) => const profile.ProfilePage(),
    '/edit-profile': (context) =>
        const _AuthRequiredPage(child: EditProfilePage()),
    '/car_detail': (context) {
      final args = argsMap(context);
      final carId = args?['carId'];
      if (carId == null) {
        return const _RouteArgsErrorPage(routeName: '/car_detail');
      }
      return details.CarDetailPage(carId: carId.toString());
    },
    '/chat/conversation': (context) {
      final args = argsMap(context);
      if (args == null) {
        return const _RouteArgsErrorPage(routeName: '/chat/conversation');
      }
      final raw = (args['carId'] ?? args['conversationId'] ?? '').toString();
      if (raw.isEmpty) {
        return const _RouteArgsErrorPage(routeName: '/chat/conversation');
      }
      return chat.ChatConversationPage(
        carId: raw,
        receiverId: args['receiverId']?.toString(),
        receiverName: args['receiverName']?.toString(),
        carTitle: args['carTitle']?.toString(),
        carImageUrl: args['carImageUrl']?.toString(),
        initialDraft: args['initialDraft']?.toString(),
        initialListingPreview: args['listingPreview'] is Map
            ? Map<String, dynamic>.from(
                (args['listingPreview'] as Map).cast<String, dynamic>(),
              )
            : null,
      );
    },
    '/my_listings': (context) => const mine.MyListingsPage(),
    '/edit_listing': (context) {
      final args = argsMap(context);
      final car = args?['car'];
      if (car is! Map) {
        return const _RouteArgsErrorPage(routeName: '/edit_listing');
      }
      return EditListingPage(
        car: Map<String, dynamic>.from(car.cast<String, dynamic>()),
      );
    },
    '/comparison': (context) => const comparison.ComparisonPage(),
    '/recently-viewed': (context) => const RecentlyViewedPage(),
    '/analytics': (context) => AnalyticsPage(),
    '/admin/dealers': (context) => const AdminDealersPage(),
    '/dealers': (context) => const DealersDirectoryPage(),
    '/dealer/edit': (context) => const EditDealerPage(),
    '/dealer/profile': (context) {
      final args = argsMap(context);
      final dealerPublicId = (args?['dealerPublicId'] ?? '').toString().trim();
      if (dealerPublicId.isEmpty) {
        return const _RouteArgsErrorPage(routeName: '/dealer/profile');
      }
      return DealerProfilePage(dealerPublicId: dealerPublicId);
    },
  };
}
