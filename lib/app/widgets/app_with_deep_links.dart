import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/push_notification_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/i18n/legacy_inline_text.dart';

/// Wraps [MaterialApp] and initializes [DeepLinkService] after the first frame.
class AppWithDeepLinks extends StatefulWidget {
  const AppWithDeepLinks({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppWithDeepLinks> createState() => _AppWithDeepLinksState();
}

class _AppWithDeepLinksState extends State<AppWithDeepLinks>
    with WidgetsBindingObserver {
  AuthService? _authService;
  bool _checkingDealerProfile = false;
  bool _dealerPromptOpen = false;
  bool _refreshingProfile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.init(widget.navigatorKey);
      PushNotificationService.attachNavigator(widget.navigatorKey);
      _checkApprovedDealerProfile();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthService>();
    if (identical(auth, _authService)) return;
    _authService?.removeListener(_onAuthChanged);
    _authService = auth;
    auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkApprovedDealerProfile();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshProfileAfterResume();
    }
  }

  Future<void> _refreshProfileAfterResume() async {
    final auth = _authService;
    if (_refreshingProfile ||
        auth == null ||
        !auth.isAuthenticated ||
        auth.isLoading) {
      return;
    }
    _refreshingProfile = true;
    try {
      await auth.refreshProfile();
    } catch (e, st) {
      logNonFatal(e, st, 'AppWithDeepLinks.refreshDealerApproval');
    } finally {
      _refreshingProfile = false;
    }
  }

  bool _hasOpeningHours(dynamic value) {
    if (value is Map) return value.isNotEmpty;
    final text = (value ?? '').toString().trim().toLowerCase();
    return text.isNotEmpty && text != '{}' && text != 'null';
  }

  List<String> _missingPublicProfileItems(
    BuildContext context,
    Map<String, dynamic> user,
  ) {
    final missing = <String>[];
    if ((user['profile_picture'] ?? '').toString().trim().isEmpty) {
      missing.add(
        trLegacyText(
          context,
          'Dealership logo',
          ar: 'شعار الوكالة',
          ku: 'لۆگۆی ناوەندی فرۆشتن',
        ),
      );
    }
    if ((user['dealership_cover_picture'] ?? '').toString().trim().isEmpty) {
      missing.add(
        trLegacyText(
          context,
          'Cover image',
          ar: 'صورة الغلاف',
          ku: 'وێنەی کاڤەر',
        ),
      );
    }
    if (!_hasOpeningHours(user['dealership_opening_hours'])) {
      missing.add(
        trLegacyText(
          context,
          'Opening hours',
          ar: 'ساعات العمل',
          ku: 'کاتەکانی کردنەوە',
        ),
      );
    }
    return missing;
  }

  Future<void> _checkApprovedDealerProfile() async {
    if (!mounted || _checkingDealerProfile || _dealerPromptOpen) return;
    final auth = _authService;
    final user = auth?.currentUser;
    if (auth == null || auth.isLoading || user == null) return;

    final accountType = (user['account_type'] ?? '').toString().toLowerCase();
    final dealerStatus = (user['dealer_status'] ?? '').toString().toLowerCase();
    if (accountType != 'dealer' && dealerStatus != 'approved') return;

    final navigatorContext = widget.navigatorKey.currentContext;
    if (navigatorContext == null) return;
    final missing = _missingPublicProfileItems(navigatorContext, user);
    if (missing.isEmpty) return;

    _checkingDealerProfile = true;
    try {
      final application = user['dealer_application'];
      final reviewedAt = application is Map
          ? (application['reviewed_at'] ?? '').toString()
          : '';
      final userId = (user['id'] ?? user['public_id'] ?? 'dealer').toString();
      final marker = reviewedAt.isEmpty ? 'approved' : reviewedAt;
      final safeMarker = marker.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      final promptKey = 'dealer_public_profile_prompt_v1_${userId}_$safeMarker';
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(promptKey) == true || !mounted) return;

      await prefs.setBool(promptKey, true);
      _dealerPromptOpen = true;
      if (!navigatorContext.mounted) return;
      final completeNow = await showDialog<bool>(
        context: navigatorContext,
        barrierDismissible: false,
        builder: (dialogContext) {
          final colors = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            icon: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.verified_rounded,
                color: colors.primary,
                size: 32,
              ),
            ),
            title: Text(
              trLegacyText(
                dialogContext,
                'Your dealership is approved!',
                ar: 'تمت الموافقة على وكالتك!',
                ku: 'ناوەندی فرۆشتنەکەت پەسەند کرا!',
              ),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trLegacyText(
                    dialogContext,
                    'Complete your public dealer page so buyers can recognize your business and know when to contact you.',
                    ar: 'أكمل صفحة وكالتك العامة ليتمكن المشترون من التعرف على نشاطك ومعرفة أوقات التواصل.',
                    ku: 'پەڕەی گشتی ناوەندی فرۆشتنەکەت تەواو بکە بۆ ئەوەی کڕیاران بازرگانییەکەت بناسن و بزانن کەی پەیوەندی بکەن.',
                  ),
                  style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 16),
                ...missing.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: colors.primary,
                          size: 19,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  trLegacyText(
                    dialogContext,
                    'You can also review your contact details, location, description, and map pin.',
                    ar: 'يمكنك أيضاً مراجعة بيانات التواصل والموقع والوصف ونقطة الخريطة.',
                    ku: 'هەروەها دەتوانیت زانیاری پەیوەندی، شوێن، وەسف و خاڵی نەخشەکەت پێداچوونەوە بکەیت.',
                  ),
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  trLegacyText(
                    dialogContext,
                    'Later',
                    ar: 'لاحقاً',
                    ku: 'دواتر',
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  trLegacyText(
                    dialogContext,
                    'Complete profile',
                    ar: 'إكمال الملف',
                    ku: 'تەواوکردنی پڕۆفایل',
                  ),
                ),
              ),
            ],
          );
        },
      );
      if (completeNow == true && mounted) {
        widget.navigatorKey.currentState?.pushNamed('/dealer/edit');
      }
    } finally {
      _dealerPromptOpen = false;
      _checkingDealerProfile = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authService?.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
