import 'package:flutter/material.dart';

import '../pages/analytics_page.dart';
import '../pages/auth_pages.dart' as auth;
import '../pages/chat_pages.dart' as chat;
import '../pages/edit_profile_page.dart';
import '../pages/home_page.dart' as modern;
import '../pages/favorites_page.dart' as favorites;
import '../pages/profile_page.dart' as profile;
import '../pages/sell_page.dart' as sell;
import '../pages/settings_page.dart' as settings;
import '../pages/car_detail_page.dart' as details;
import '../pages/my_listings_page.dart' as mine;
import '../pages/comparison_page.dart' as comparison;

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
    '/sell': (context) => const sell.SellPage(),
    '/settings': (context) => const settings.SettingsPage(),
    '/favorites': (context) => const favorites.FavoritesPage(),
    '/chat': (context) => const chat.ChatListPage(),
    '/login': (context) => const auth.LoginPage(),
    '/signup': (context) => const auth.RegisterPage(),
    '/register': (context) => const auth.RegisterPage(),
    '/forgot-password': (context) => const auth.ForgotPasswordPage(),
    '/profile': (context) => const profile.ProfilePage(),
    '/edit-profile': (context) => EditProfilePage(),
    '/car_detail': (context) {
      final args = argsMap(context);
      final carId = args?['carId'];
      if (carId == null) return const _RouteArgsErrorPage(routeName: '/car_detail');
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
      );
    },
    '/my_listings': (context) => const mine.MyListingsPage(),
    '/comparison': (context) => const comparison.ComparisonPage(),
    '/analytics': (context) => AnalyticsPage(),
  };
}
