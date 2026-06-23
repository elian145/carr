import 'package:flutter/material.dart';

import '../pages/admin_dealers_page.dart';
import '../pages/admin_reports_page.dart';
import '../pages/analytics_page.dart';
import '../pages/forgot_password_page.dart';
import '../pages/change_password_page.dart';
import '../features/chat/chat_pages.dart' as carzo_chat;
import '../pages/dealer_profile_page.dart';
import '../pages/dealers_directory_page.dart';
import '../pages/edit_dealer_page.dart';
import '../pages/edit_listing_page.dart' as modern_edit;
import '../pages/edit_profile_page.dart';
import '../pages/help_center_page.dart';
import '../pages/my_listings_page.dart' as modern_listings;
import '../pages/recently_viewed_page.dart';
import '../pages/reset_password_page.dart';
import '../pages/tiktok_scroll_page.dart';
import '../pages/verify_email_page.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/navigation/route_args.dart';
import 'carzo_shared.dart';

Map<String, WidgetBuilder> buildProductionRoutes() {
  return {
                '/': (context) => HomePage(),
                '/sell': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  final initialDraftSnapshot = args is Map
                      ? (args['draftSnapshot'] is Map
                          ? Map<String, dynamic>.from(
                              (args['draftSnapshot'] as Map).cast<String, dynamic>(),
                            )
                          : null)
                      : null;
                  final startFresh = args is Map && args['startFresh'] == true;
                  final showDraftGate = args is Map && args['showDraftGate'] == true;
                  if (initialDraftSnapshot != null) {
                    return AuthGuard(
                      child: SellCarPage(
                        initialDraftSnapshot: initialDraftSnapshot,
                      ),
                    );
                  }
                  if (startFresh) {
                    return AuthGuard(
                      child: const SellCarPage(startFreshListing: true),
                    );
                  }
                  if (showDraftGate) {
                    return AuthGuard(
                      child: const SellDraftGatePage(),
                    );
                  }
                  return AuthGuard(
                    child: const SellEntryRouterPage(),
                  );
                },
                '/settings': (context) => SettingsPage(),
                '/favorites': (context) =>
                    AuthGuard(allowWhenLoggedOut: true, child: FavoritesPage()),
                '/dealers': (context) => const DealersDirectoryPage(),
                '/chat': (context) => AuthGuard(child: ChatListPage()),
                '/login': (context) => LoginPage(),
                '/signup': (context) => SignupPage(),
                '/profile': (context) =>
                    AuthGuard(allowWhenLoggedOut: true, child: ProfilePage()),
                '/edit-profile': (context) =>
                    AuthGuard(child: EditProfilePage()),
                '/car_detail': (context) {
                  final args = readRouteArgs(context);
                  final carId = (args?['carId'] ?? '').toString().trim();
                  if (carId.isEmpty) {
                    return navigationErrorScaffold('Missing listing id');
                  }
                  return CarDetailsPage(carId: carId);
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
                  final rawId = (args?['carId'] ?? args?['conversationId'] ?? '')
                      .toString()
                      .trim();
                  if (rawId.isEmpty) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Navigation error')),
                      body: Center(
                        child: Text('Missing chat conversation id'),
                      ),
                    );
                  }
                  return AuthGuard(
                    child: carzo_chat.ChatConversationPage(
                      carId: rawId,
                      receiverId: args?['receiverId']?.toString(),
                      initialDraft: args?['initialDraft']?.toString(),
                      initialListingPreview: args?['listingPreview'] is Map
                          ? Map<String, dynamic>.from(
                              (args?['listingPreview'] as Map)
                                  .cast<String, dynamic>(),
                            )
                          : null,
                    ),
                  );
                },
                '/edit': (context) {
                  final args = readRouteArgs(context);
                  final car = args?['car'];
                  if (car is! Map) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Navigation error')),
                      body: const Center(child: Text('Missing listing data')),
                    );
                  }
                  return AuthGuard(
                    child: modern_edit.EditListingPage(
                      car: Map<String, dynamic>.from(
                        car.cast<String, dynamic>(),
                      ),
                    ),
                  );
                },
                '/edit_listing': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  final car = args is Map ? args['car'] : null;
                  if (car is! Map) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Navigation error')),
                      body: const Center(child: Text('Missing listing data')),
                    );
                  }
                  return AuthGuard(
                    child: modern_edit.EditListingPage(
                      car: Map<String, dynamic>.from(
                        car.cast<String, dynamic>(),
                      ),
                    ),
                  );
                },
                '/my_listings': (context) =>
                    AuthGuard(child: modern_listings.MyListingsPage()),
                '/comparison': (context) => CarComparisonPage(),
                '/recently-viewed': (context) =>
                    AuthGuard(child: const RecentlyViewedPage()),
                '/analytics': (context) => AnalyticsPage(),
                '/reset-password': (context) => ResetPasswordPage(),
                '/verify-email': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  final token = args is Map
                      ? (args['token'] ?? '').toString().trim()
                      : '';
                  return VerifyEmailPage(
                    initialToken: token.isNotEmpty ? token : null,
                  );
                },
                '/forgot-password': (context) => const ForgotPasswordPage(),
                '/change-password': (context) =>
                    AuthGuard(child: const ChangePasswordPage()),
                '/admin/dealers': (context) =>
                    AuthGuard(child: AdminDealersPage()),
                '/admin/reports': (context) =>
                    AuthGuard(child: const AdminReportsPage()),
                '/help': (context) => const HelpCenterPage(),
                '/dealer/edit': (context) =>
                    AuthGuard(child: EditDealerPage()),
                '/dealer/profile': (context) {
                  final args =
                      ModalRoute.of(context)?.settings.arguments
                          as Map<String, dynamic>?;
                  final dealerPublicId =
                      (args?['dealerPublicId'] ?? '').toString().trim();
                  if (dealerPublicId.isEmpty) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Navigation error')),
                      body: Center(
                        child: Text(
                          trLegacyText(
                            context,
                            'Missing dealer id',
                            ar: 'معرّف الوكيل مفقود',
                            ku: 'ناسنامەی وەکیل ونە',
                          ),
                        ),
                      ),
                    );
                  }
                  return DealerProfilePage(dealerPublicId: dealerPublicId);
                },
              };
}
