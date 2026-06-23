import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/widgets/main_shell_navigation.dart'
    show buildFloatingBottomNav, navigateMainShellTab;
import '../l10n/app_localizations.dart';
import '../pages/saved_searches_page.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/websocket_service.dart';
import '../shared/account/delete_account_dialog.dart';
import '../shared/debug/app_log.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/media/media_url.dart';
import '../state/locale_controller.dart';
import '../theme_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  BoxDecoration _shellDecoration(BuildContext context) =>
      AppThemes.shellBackgroundDecoration(Theme.of(context).brightness);

  bool _profileLightShell(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  Color _profileCardFill(BuildContext context) {
    if (_profileLightShell(context)) return Colors.white;
    return Color.alphaBlend(
      Colors.white.withValues(alpha: 0.085),
      AppThemes.darkHomeShellBackground,
    );
  }

  Color _profileBorderColor(BuildContext context) {
    if (_profileLightShell(context)) return const Color(0xFFE0E0E0);
    return Colors.white.withValues(alpha: 0.12);
  }

  Color _profilePrimaryInk(BuildContext context) {
    if (_profileLightShell(context)) return Colors.grey[800]!;
    return const Color(0xFFECECEC);
  }

  Color _profileSecondaryInk(BuildContext context) {
    if (_profileLightShell(context)) return Colors.grey[600]!;
    return Colors.white70;
  }

  BoxDecoration _profileCardDecoration(
    BuildContext context, {
    double radius = 16,
    double blur = 12,
    double shadowOpacity = 0.06,
  }) {
    final light = _profileLightShell(context);
    return BoxDecoration(
      color: _profileCardFill(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _profileBorderColor(context), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: light ? shadowOpacity : 0.45),
          blurRadius: light ? blur : 20,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Map<String, dynamic>? me;
  bool _loading = true;
  late final AuthService _authService;
  int _unreadChatCount = 0;
  StreamSubscription<Map<String, dynamic>>? _chatNotificationSub;

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _authService.addListener(_onAuthChange);
    final cached = _authService.currentUser;
    if (cached != null) {
      me = Map<String, dynamic>.from(cached);
    }
    _loadMe();
    _chatNotificationSub = WebSocketService.notifications.listen((
      notification,
    ) {
      if (!mounted) return;
      final type = (notification['notification_type'] ?? '').toString();
      if (type == 'message') {
        _loadUnreadChatCount();
      }
    });
  }

  @override
  void dispose() {
    // Do not use context in dispose; the element is being deactivated.
    _authService.removeListener(_onAuthChange);
    _chatNotificationSub?.cancel();
    super.dispose();
  }

  void _onAuthChange() {
    if (mounted) {
      _loadMe();
    }
  }

  Map<String, dynamic>? _effectiveProfile() => me ?? _authService.currentUser;

  Future<void> _loadMe() async {
    final cached = _authService.currentUser;
    if (cached != null) {
      me = Map<String, dynamic>.from(cached);
    }
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        setState(() {
          me = null;
          _loading = false;
          _unreadChatCount = 0;
        });
        return;
      }
      final response = await ApiService.getProfile();
      me = AuthService.profileFromResponse(response);
    } on ApiException catch (e, st) {
      logNonFatal(e, st);
    } catch (e, st) {
      logNonFatal(e, st);
    }
    if (me == null && _authService.currentUser != null) {
      me = Map<String, dynamic>.from(_authService.currentUser!);
    }
    await _loadUnreadChatCount();
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadUnreadChatCount() async {
    final tok = ApiService.accessToken;
    if (tok == null || tok.isEmpty) {
      if (mounted) {
        setState(() => _unreadChatCount = 0);
      } else {
        _unreadChatCount = 0;
      }
      return;
    }
    try {
      final count = await ApiService.getUnreadChatCount();
      if (mounted) {
        setState(() => _unreadChatCount = count);
      } else {
        _unreadChatCount = count;
      }
    } catch (e, st) { logNonFatal(e, st); }
  }

  void refreshProfile() {
    _loadMe();
  }

  Future<void> _showAuthRequiredDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.loginTitle),
          content: Text(AppLocalizations.of(ctx)!.notLoggedIn),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx)!.cancelAction),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushReplacementNamed(context, '/signup');
              },
              child: Text(AppLocalizations.of(ctx)!.signupTitle),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: Text(AppLocalizations.of(ctx)!.loginAction),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Widget _buildLoggedInState(BuildContext context) {
    final profile = _effectiveProfile();
    final isLoggedIn =
        ApiService.accessToken != null && ApiService.accessToken!.isNotEmpty;
    final isLightShell = _profileLightShell(context);
    return Stack(
      children: [
        Container(decoration: _shellDecoration(context)),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          child: Column(
            children: [
              if (!isLoggedIn) ...[
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(18),
                  decoration: _profileCardDecoration(context),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Color(0xFFFF6B00).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person_outline,
                          color: Color(0xFFFF6B00),
                          size: 26,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Guest',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: _profilePrimaryInk(context),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Sign in to access your profile features.',
                              style: TextStyle(
                                fontSize: 13,
                                color: _profileSecondaryInk(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.pushReplacementNamed(context, '/login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 1,
                        ),
                        child: Text(AppLocalizations.of(context)!.loginAction),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
              ],
              if (isLoggedIn) ...[
                // Profile Header
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(24),
                  decoration: _profileCardDecoration(
                    context,
                    radius: 20,
                    blur: 16,
                    shadowOpacity: 0.08,
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Color(0xFFFF6B00).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: () {
                          final picture =
                              profile?['profile_picture']?.toString() ?? '';
                          if (picture.isNotEmpty) {
                            return CircleAvatar(
                              radius: 24,
                              backgroundImage: NetworkImage(
                                buildLegacyFullImageUrl(picture),
                              ),
                              backgroundColor: isLightShell
                                  ? Colors.grey[200]
                                  : Colors.white.withValues(alpha: 0.12),
                            );
                          }
                          return Icon(
                            Icons.person,
                            size: 48,
                            color: Color(0xFFFF6B00),
                          );
                        }(),
                      ),
                      SizedBox(height: 16),
                      Text(
                        () {
                          final at =
                              (profile?['account_type'] ?? 'user').toString().trim();
                          final dn =
                              (profile?['dealership_name'] ?? '').toString().trim();
                          final fn =
                              (profile?['first_name'] ?? '').toString().trim();
                          final ln =
                              (profile?['last_name'] ?? '').toString().trim();
                          final full = '$fn $ln'.trim();
                          if (at == 'dealer' && dn.isNotEmpty) return dn;
                          if (at == 'dealer' && full.isNotEmpty) return full;
                          if (at == 'dealer') return 'Dealer';
                          return profile?['username']?.toString() ?? 'User';
                        }(),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _profilePrimaryInk(context),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        () {
                          final e = profile?['email']?.toString() ?? '';
                          final p =
                              profile?['phone_number']?.toString() ??
                              profile?['phone']?.toString() ??
                              '';
                          final realEmail =
                              e.isNotEmpty && !e.endsWith('@phone.local');
                          return realEmail ? e : (p.isNotEmpty ? p : e);
                        }(),
                        style: TextStyle(
                          fontSize: 16,
                          color: _profileSecondaryInk(context),
                        ),
                      ),
                      SizedBox(height: 10),
                      Builder(
                        builder: (ctx) {
                          final accountType =
                              (profile?['account_type'] ?? 'user').toString();
                          final dealerStatus =
                              (profile?['dealer_status'] ?? 'none').toString();
                          final isVerifiedDealer =
                              dealerStatus == 'approved' ||
                              accountType == 'dealer';
                          final isPending = dealerStatus == 'pending';
                          final isRejected = dealerStatus == 'rejected';
                          late final String label;
                          late final Color bg;
                          late final Color fg;
                          if (isVerifiedDealer) {
                            label = AppLocalizations.of(context)!
                                .verifiedDealerLabel;
                            bg = Colors.green.withValues(alpha: 0.15);
                            fg = isLightShell
                                ? Colors.green.shade800
                                : Colors.green.shade200;
                          } else if (isPending) {
                            label = AppLocalizations.of(context)!
                                .dealerApplicationPendingLabel;
                            bg = Colors.orange.withValues(alpha: 0.15);
                            fg = isLightShell
                                ? Colors.orange.shade800
                                : Colors.orange.shade200;
                          } else if (isRejected) {
                            label = AppLocalizations.of(context)!
                                .dealerApplicationDeclinedLabel;
                            bg = Colors.red.withValues(alpha: 0.12);
                            fg = isLightShell
                                ? Colors.red.shade800
                                : Colors.red.shade200;
                          } else {
                            label = AppLocalizations.of(context)!
                                .personalAccountLabel;
                            if (isLightShell) {
                              bg = Colors.grey.shade200;
                              fg = Colors.grey.shade700;
                            } else {
                              bg = Colors.white.withValues(alpha: 0.1);
                              fg = Colors.white.withValues(alpha: 0.88);
                            }
                          }
                          return Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: fg,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),

                // User Information Card
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: _profileCardDecoration(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.accountInformationTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _profilePrimaryInk(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...(() {
                        final loc = AppLocalizations.of(context)!;
                        final isDealer =
                            (profile?['account_type'] ?? 'user').toString() ==
                                'dealer';
                        final rows = <Widget>[];
                        if (!isDealer) {
                          rows.add(
                            _buildInfoRow(
                              Icons.person_outline,
                              loc.usernameLabel,
                              profile?['username']?.toString() ?? '',
                            ),
                          );
                        }
                        final emailStr = profile?['email']?.toString() ?? '';
                        if (emailStr.isNotEmpty &&
                            !emailStr.endsWith('@phone.local')) {
                          rows.add(
                            _buildInfoRow(
                              Icons.email_outlined,
                              loc.emailLabel,
                              emailStr,
                            ),
                          );
                        }
                        final phoneStr =
                            (profile?['phone_number'] ?? profile?['phone'] ?? '')
                                .toString();
                        if (phoneStr.trim().isNotEmpty) {
                          rows.add(
                            _buildInfoRow(
                              Icons.phone_outlined,
                              loc.phoneLabel,
                              phoneStr,
                            ),
                          );
                        }
                        final dealership =
                            (profile?['dealership_name'] ?? '').toString().trim();
                        if (dealership.isNotEmpty) {
                          rows.add(
                            _buildInfoRow(
                              Icons.storefront_outlined,
                              loc.dealershipLabel,
                              dealership,
                            ),
                          );
                        }
                        return [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0) const SizedBox(height: 12),
                            rows[i],
                          ],
                        ];
                      })(),
                    ],
                  ),
                ),
                SizedBox(height: 24),
              ],

              // Action Buttons
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: _profileCardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.accountActionsTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _profilePrimaryInk(context),
                      ),
                    ),
                    SizedBox(height: 20),
                    _buildActionButton(
                      Icons.directions_car_outlined,
                      AppLocalizations.of(context)!.myListingsTitle,
                      () {
                        if (ApiService.accessToken == null ||
                            ApiService.accessToken!.isEmpty) {
                          _showAuthRequiredDialog(context);
                          return;
                        }
                        Navigator.pushNamed(context, '/my_listings');
                      },
                    ),
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.history,
                      trLegacyText(
                        context,
                        'Recently viewed',
                        ar: 'شوهد مؤخراً',
                        ku: 'دواتر بینراو',
                      ),
                      () {
                        if (ApiService.accessToken == null ||
                            ApiService.accessToken!.isEmpty) {
                          _showAuthRequiredDialog(context);
                          return;
                        }
                        Navigator.pushReplacementNamed(
                          context,
                          '/recently-viewed',
                        );
                      },
                    ),
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.bookmark_outline,
                      AppLocalizations.of(context)!.savedSearchesTitle,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SavedSearchesPage(),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.settings_outlined,
                      AppLocalizations.of(context)!.settingsTitle,
                      () {
                        Navigator.pushNamed(context, '/settings');
                      },
                    ),
                    if (profile?['is_admin'] == true) ...[
                      SizedBox(height: 12),
                      _buildActionButton(
                        Icons.verified_user_outlined,
                        'Dealer approvals (admin)',
                        () {
                          if (ApiService.accessToken == null ||
                              ApiService.accessToken!.isEmpty) {
                            _showAuthRequiredDialog(context);
                            return;
                          }
                          Navigator.pushNamed(context, '/admin/dealers');
                        },
                      ),
                      SizedBox(height: 12),
                      _buildActionButton(
                        Icons.flag_outlined,
                        trLegacyText(
                          context,
                          'Reports queue (admin)',
                          ar: 'قائمة البلاغات (مسؤول)',
                          ku: 'ڕیزبەندی ڕاپۆرت (بەڕێوەبەر)',
                        ),
                        () {
                          if (ApiService.accessToken == null ||
                              ApiService.accessToken!.isEmpty) {
                            _showAuthRequiredDialog(context);
                            return;
                          }
                          Navigator.pushNamed(context, '/admin/reports');
                        },
                      ),
                    ],
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.chat_outlined,
                      AppLocalizations.of(context)!.chatTitle,
                      () async {
                        if (ApiService.accessToken == null ||
                            ApiService.accessToken!.isEmpty) {
                          _showAuthRequiredDialog(context);
                          return;
                        }
                        await Navigator.pushNamed(context, '/chat');
                        if (!mounted) return;
                        _loadUnreadChatCount();
                      },
                      badgeCount: _unreadChatCount,
                    ),
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.compare_arrows,
                      AppLocalizations.of(context)!.carComparisonCount,
                      () {
                        Navigator.pushNamed(context, '/comparison');
                      },
                    ),
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.edit_outlined,
                      AppLocalizations.of(context)!.editProfileAction,
                      () async {
                        if (ApiService.accessToken == null ||
                            ApiService.accessToken!.isEmpty) {
                          _showAuthRequiredDialog(context);
                          return;
                        }
                        final result = await Navigator.pushNamed(
                          context,
                          '/edit-profile',
                        );
                        // Refresh profile data if changes were made
                        if (result == true) {
                          _loadMe();
                        }
                      },
                    ),
                    if ((profile?['account_type'] ?? 'user').toString() == 'dealer') ...[
                      SizedBox(height: 12),
                      _buildActionButton(
                        Icons.storefront_outlined,
                        trLegacyText(
                          context,
                          'Edit dealer page',
                          ar: 'تعديل صفحة الوكيل',
                          ku: 'دەستکاری پەڕەی وەکیل',
                        ),
                        () async {
                          if (ApiService.accessToken == null ||
                              ApiService.accessToken!.isEmpty) {
                            _showAuthRequiredDialog(context);
                            return;
                          }
                          final result = await Navigator.pushNamed(
                            context,
                            '/dealer/edit',
                          );
                          if (result == true) {
                            _loadMe();
                          }
                        },
                      ),
                    ],
                    SizedBox(height: 12),
                    _buildActionButton(
                      Icons.contact_mail_outlined,
                      AppLocalizations.of(context)!.helpSupportTitle,
                      () {
                        Navigator.pushNamed(context, '/help');
                      },
                    ),
                    if (ApiService.accessToken != null &&
                        ApiService.accessToken!.isNotEmpty) ...[
                      SizedBox(height: 12),
                      _buildActionButton(
                        Icons.delete_forever_outlined,
                        AppLocalizations.of(context)!.deleteAccountTitle,
                        () {
                          _showDeleteAccountDialog(context);
                        },
                        color: Colors.red,
                      ),
                    ],
                  ],
                ),
              ),
              if (isLoggedIn) ...[
                SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      _showLogoutDialog(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout, size: 20),
                        SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.logout,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final c = context;
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color(0xFFFF6B00).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Color(0xFFFF6B00)),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: _profileSecondaryInk(c),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: _profilePrimaryInk(c),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? color,
    int badgeCount = 0,
  }) {
    final accent = color ?? Color(0xFFFF6B00);
    final light = _profileLightShell(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: light
              ? Colors.grey[100]
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: light
                ? Colors.grey[300]!
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: color ?? _profilePrimaryInk(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            Spacer(),
            if (badgeCount > 0) ...[
              Container(
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  badgeCount > 99 ? '99' : badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(width: 10),
            ],
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: light ? Colors.grey[400]! : Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final loc = AppLocalizations.of(context)!;
    final password = await showDeleteAccountPasswordDialog(context);
    if (password == null || !context.mounted) return;
    try {
      await AuthService().deleteAccount(
        password: password.isEmpty ? null : password,
      );
      if (!context.mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.accountDeletedSnackbar)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: loc.error,
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showLogoutDialog(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            loc.logout,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(loc.logoutConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                loc.cancelAction,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _logout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(loc.logout),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.profileTitle)),
      body: _loading
          ? Stack(
              children: [
                Container(decoration: _shellDecoration(context)),
                const Center(child: CircularProgressIndicator()),
              ],
            )
          : _buildLoggedInState(context),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        onTap: (idx) {
          switch (idx) {
            case 0:
              navigateMainShellTab(context, '/');
              break;
            case 1:
              navigateMainShellTab(context, '/favorites');
              break;
            case 2:
              navigateMainShellTab(context, '/dealers');
              break;
            case 3:
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                navigateMainShellTab(context, '/profile');
              }
              break;
          }
        },
      ),
    );
  }
}


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _pushEnabled = true;
  String? _pushDiagSubtitle;
  final GlobalKey<PopupMenuButtonState<String?>> _languageMenuKey =
      GlobalKey<PopupMenuButtonState<String?>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _setLocale(String? code) async {
    if (code == null) {
      await LocaleController.setLocale(null);
    } else {
      await LocaleController.setLocale(Locale(code));
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    final enabled = sp.getBool('push_enabled') ?? true;
    setState(() {
      _pushEnabled = enabled;
    });
    if (enabled) {
      await _refreshPushDiagnostics();
    }
  }

  Future<void> _togglePush(bool v) async {
    await PushNotificationService.setPushEnabled(v);
    if (!mounted) return;
    setState(() {
      _pushEnabled = v;
    });
    if (v) {
      await _refreshPushDiagnostics();
    }
  }

  Future<void> _refreshPushDiagnostics() async {
    final msg = await PushNotificationService.syncNowForDiagnostics();
    if (!mounted) return;
    setState(() => _pushDiagSubtitle = msg);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = context.watch<ThemeProvider>();
    final currentLocale = LocaleController.currentLocale.value?.languageCode;
    final isLightShell = Theme.of(context).brightness == Brightness.light;

    final tileFill = isLightShell
        ? Colors.white
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.06),
            AppThemes.darkHomeShellBackground,
          );
    final tileBorder = isLightShell ? Colors.grey.shade200 : Colors.white12;
    final titleColor = isLightShell ? Colors.grey.shade900 : Colors.white;
    final subtitleColor = isLightShell ? Colors.grey.shade600 : Colors.white70;
    final dividerColor = isLightShell ? Colors.grey.shade200 : Colors.white12;

    String localeLabel(String? code) {
      if (code == null) return loc.settingsSystem;
      switch (code) {
        case 'en':
          return 'English';
        case 'ar':
          return 'العربية';
        case 'ku':
          return 'کوردی';
        default:
          return code;
      }
    }

    Widget rowTile({
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B00).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFFFF6B00), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.orbitron(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: subtitleColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      );
    }

    Widget settingsCard(List<Widget> children) {
      return Container(
        decoration: BoxDecoration(
          color: tileFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: tileBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isLightShell ? 0.05 : 0.20),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(children: children),
        ),
      );
    }

    final bodyChild = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        settingsCard(
          [
            rowTile(
              icon: Icons.language,
              title: loc.settingsLanguageTitle,
              subtitle: localeLabel(currentLocale),
              trailing: PopupMenuButton<String?>(
                key: _languageMenuKey,
                tooltip: '',
                position: PopupMenuPosition.under,
                onSelected: (v) => _setLocale(v),
                itemBuilder: (context) => [
                  PopupMenuItem<String?>(
                    value: null,
                    child: Text(loc.settingsSystem),
                  ),
                  const PopupMenuItem<String?>(
                    value: 'en',
                    child: Text('English'),
                  ),
                  const PopupMenuItem<String?>(
                    value: 'ar',
                    child: Text('العربية'),
                  ),
                  const PopupMenuItem<String?>(
                    value: 'ku',
                    child: Text('کوردی'),
                  ),
                ],
                icon: Icon(
                  Icons.expand_more,
                  color: isLightShell ? Colors.grey.shade700 : Colors.white70,
                ),
              ),
              onTap: () => _languageMenuKey.currentState?.showButtonMenu(),
            ),
            Divider(height: 1, color: dividerColor),
            rowTile(
              icon: theme.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              title: loc.settingsThemeTitle,
              subtitle: theme.themeMode == ThemeMode.system
                  ? loc.settingsSystem
                  : theme.themeMode == ThemeMode.dark
                      ? loc.settingsDark
                      : loc.settingsLight,
              trailing: Icon(
                theme.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                color: isLightShell ? Colors.grey.shade700 : Colors.white70,
              ),
              onTap: theme.toggleTheme,
            ),
            Divider(height: 1, color: dividerColor),
            rowTile(
              icon: Icons.notifications_active_outlined,
              title: loc.settingsEnablePush,
              subtitle: _pushDiagSubtitle ??
                  (_pushEnabled ? loc.enabledLabel : loc.disabledLabel),
              trailing: Switch.adaptive(
                value: _pushEnabled,
                activeThumbColor: const Color(0xFFFF6B00),
                onChanged: _togglePush,
              ),
              onTap: () => _togglePush(!_pushEnabled),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      appBar: AppBar(
        title: Text(loc.settingsTitle),
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLightShell
          ? Padding(
              padding: const EdgeInsets.only(bottom: 110),
              child: bodyChild,
            )
          : Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 110),
                child: bodyChild,
              ),
            ),
    );
  }
}


