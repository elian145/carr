import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/push_notification_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/ui/keyboard.dart';
import '../../l10n/app_localizations.dart';

final AppRouteTracker appRouteTracker = AppRouteTracker();

class AppRouteTracker extends NavigatorObserver {
  String? currentRouteName;

  void _onRouteChanged() {
    // Drop keyboard focus when leaving a screen so the next route starts clean (A-05).
    dismissAnyKeyboard();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRouteName = route.settings.name;
    _onRouteChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRouteName = previousRoute?.settings.name;
    _onRouteChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    currentRouteName = newRoute?.settings.name;
    _onRouteChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRouteName = previousRoute?.settings.name;
    _onRouteChanged();
  }
}

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
        AppLocalizations.of(context)!.dealershipLogo,
      );
    }
    if ((user['dealership_cover_picture'] ?? '').toString().trim().isEmpty) {
      missing.add(
        AppLocalizations.of(context)!.coverImage,
      );
    }
    if (!_hasOpeningHours(user['dealership_opening_hours'])) {
      missing.add(
        AppLocalizations.of(context)!.openingHours,
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

    _checkingDealerProfile = true;
    try {
      Map<String, dynamic>? approvalNotification;
      try {
        final response = await ApiService.getUserNotifications(
          unreadOnly: true,
          type: 'dealer_application',
          perPage: 20,
        );
        final notifications = response['notifications'];
        if (notifications is List) {
          for (final raw in notifications) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(
              raw.map((key, value) => MapEntry(key.toString(), value)),
            );
            final data = item['data'];
            final status = data is Map
                ? (data['status'] ?? '').toString().toLowerCase()
                : '';
            if (status == 'approved') {
              approvalNotification = item;
              break;
            }
          }
        }
      } catch (e, st) {
        logNonFatal(e, st, 'AppWithDeepLinks.loadApprovalNotification');
        return;
      }

      if (approvalNotification == null) {
        if (missing.isEmpty) return;
        final application = user['dealer_application'];
        final reviewedAt = application is Map
            ? (application['reviewed_at'] ?? '').toString()
            : '';
        final userId = (user['id'] ?? user['public_id'] ?? 'dealer').toString();
        final marker = reviewedAt.isEmpty ? 'approved' : reviewedAt;
        final safeMarker = marker.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
        final promptKey =
            'dealer_public_profile_prompt_v1_${userId}_$safeMarker';
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(promptKey) == true || !mounted) return;
        await prefs.setBool(promptKey, true);
      }

      _dealerPromptOpen = true;
      if (!navigatorContext.mounted) return;
      final alreadyEditing = appRouteTracker.currentRouteName == '/dealer/edit';
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
              alreadyEditing
                  ? AppLocalizations.of(dialogContext)!.setUpYourDealerPage
                  : AppLocalizations.of(dialogContext)!.yourDealershipIsApproved,
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alreadyEditing
                      ? AppLocalizations.of(dialogContext)!
                          .yourDealershipIsApprovedFillInTheInformationOnThisPageToFinishSettingUpT
                      : AppLocalizations.of(dialogContext)!
                          .completeYourPublicDealerPageSoBuyersCanRecognizeYourBusinessAndKnowWhenT,
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
                  AppLocalizations.of(dialogContext)!.youCanAlsoReviewYourContactDetailsLocationDescriptionAndMapPin,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
            actions: [
              if (alreadyEditing)
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    AppLocalizations.of(dialogContext)!.gotIt,
                  ),
                )
              else ...[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    AppLocalizations.of(dialogContext)!.later,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    AppLocalizations.of(dialogContext)!.completeProfile,
                  ),
                ),
              ],
            ],
          );
        },
      );
      final notificationId = (approvalNotification?['id'] ?? '')
          .toString()
          .trim();
      if (notificationId.isNotEmpty) {
        try {
          await ApiService.markUserNotificationRead(notificationId);
        } catch (e, st) {
          logNonFatal(e, st, 'AppWithDeepLinks.markApprovalNotificationRead');
        }
      }
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
