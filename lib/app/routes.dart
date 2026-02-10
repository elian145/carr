import 'package:flutter/material.dart';

import '../pages/analytics_page.dart';
import '../pages/edit_profile_page.dart';
import '../legacy/main_legacy.dart' as legacy;

Map<String, WidgetBuilder> buildAppRoutes() {
  return {
    '/': (context) => legacy.HomePage(),
    '/sell': (context) => legacy.SellCarPage(),
    '/settings': (context) => legacy.SettingsPage(),
    '/favorites': (context) => legacy.FavoritesPage(),
    '/chat': (context) => legacy.ChatListPage(),
    '/login': (context) => legacy.LoginPage(),
    '/signup': (context) => legacy.SignupPage(),
    '/profile': (context) => legacy.ProfilePage(),
    '/edit-profile': (context) => EditProfilePage(),
    '/payment/history': (context) => legacy.PaymentHistoryPage(),
    '/payment/initiate': (context) => legacy.PaymentInitiatePage(),
    '/car_detail': (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      return legacy.CarDetailsPage(carId: args['carId'].toString());
    },
    '/chat/conversation': (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      return legacy.ChatConversationPage(
        conversationId: args['conversationId'],
      );
    },
    '/payment/status': (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      return legacy.PaymentStatusPage(paymentId: args['paymentId']);
    },
    '/edit': (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      return legacy.EditListingPage(car: args['car']);
    },
    '/my_listings': (context) => legacy.MyListingsPage(),
    '/comparison': (context) => legacy.CarComparisonPage(),
    '/analytics': (context) => AnalyticsPage(),
  };
}
