import 'package:flutter/material.dart';

import '../pages/analytics_page.dart';
import '../pages/chat_pages.dart' as chat;
import '../pages/edit_profile_page.dart';
import '../legacy/main_legacy.dart' as legacy;

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
    '/': (context) => legacy.HomePage(),
    '/sell': (context) => legacy.SellCarPage(),
    '/settings': (context) => legacy.SettingsPage(),
    '/favorites': (context) => legacy.FavoritesPage(),
    '/chat': (context) => const chat.ChatListPage(),
    '/login': (context) => legacy.LoginPage(),
    '/signup': (context) => legacy.SignupPage(),
    '/profile': (context) => legacy.ProfilePage(),
    '/edit-profile': (context) => EditProfilePage(),
    '/payment/history': (context) => legacy.PaymentHistoryPage(),
    '/payment/initiate': (context) => legacy.PaymentInitiatePage(),
    '/car_detail': (context) {
      final args = argsMap(context);
      final carId = args?['carId'];
      if (carId == null) return const _RouteArgsErrorPage(routeName: '/car_detail');
      return legacy.CarDetailsPage(carId: carId.toString());
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
    '/payment/status': (context) {
      final args = argsMap(context);
      final paymentId = args?['paymentId'];
      if (paymentId == null) return const _RouteArgsErrorPage(routeName: '/payment/status');
      return legacy.PaymentStatusPage(paymentId: paymentId);
    },
    '/edit': (context) {
      final args = argsMap(context);
      final car = args?['car'];
      if (car == null) return const _RouteArgsErrorPage(routeName: '/edit');
      return legacy.EditListingPage(car: car);
    },
    '/my_listings': (context) => legacy.MyListingsPage(),
    '/comparison': (context) => legacy.CarComparisonPage(),
    '/analytics': (context) => AnalyticsPage(),
  };
}
