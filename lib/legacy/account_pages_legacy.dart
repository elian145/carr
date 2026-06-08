part of 'main_legacy.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  BoxDecoration _shellDecoration(BuildContext context) =>
      AppThemes.shellBackgroundDecoration(Theme.of(context).brightness);

  bool _profileLightShell(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  Color _profileCardFill(BuildContext context) {
    if (_profileLightShell(context)) return Colors.white;
    return Color.alphaBlend(
      Colors.white.withOpacity(0.085),
      AppThemes.darkHomeShellBackground,
    );
  }

  Color _profileBorderColor(BuildContext context) {
    if (_profileLightShell(context)) return const Color(0xFFE0E0E0);
    return Colors.white.withOpacity(0.12);
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
          color: Colors.black.withOpacity(light ? shadowOpacity : 0.45),
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
    _loadMe();
    // Listen to auth service changes
    _authService = Provider.of<AuthService>(context, listen: false);
    _authService.addListener(_onAuthChange);
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

  Future<void> _loadMe() async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        setState(() {
          _loading = false;
          _unreadChatCount = 0;
        });
        return;
      }
      final url = Uri.parse('${getApiBase()}/api/auth/me');
      final resp = await http.get(
        url,
        headers: {'Authorization': 'Bearer $tok'},
      );
      if (resp.statusCode == 200) {
        me = json.decode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
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
    } catch (_) {}
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
    await AuthStore.saveToken(null);
    await ApiService.setAccessToken(null);
    await ApiService.logout(); // Clear ApiService tokens too
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Widget _buildNotLoggedInState(BuildContext context) {
    return Stack(
      children: [
        Container(decoration: _shellDecoration(context)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: _profileCardDecoration(
                    context,
                    radius: 20,
                    blur: 18,
                    shadowOpacity: 0.1,
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Color(0xFFFF6B00).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person_outline,
                          size: 64,
                          color: Color(0xFFFF6B00),
                        ),
                      ),
                      SizedBox(height: 24),
                      Text(
                        AppLocalizations.of(context)!.notLoggedIn,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: _profilePrimaryInk(context),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Sign in to access your profile and manage your account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _profileSecondaryInk(context),
                        ),
                      ),
                      SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.pushReplacementNamed(context, '/login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF6B00),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.loginAction,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      TextButton(
                        onPressed: () =>
                            Navigator.pushReplacementNamed(context, '/signup'),
                        child: Text(
                          AppLocalizations.of(context)!.createAccount,
                          style: TextStyle(
                            color: Color(0xFFFF6B00),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoggedInState(BuildContext context) {
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
                          color: Color(0xFFFF6B00).withOpacity(0.1),
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
                          color: Color(0xFFFF6B00).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child:
                            (me?['profile_picture'] != null &&
                                me!['profile_picture'].toString().isNotEmpty)
                            ? CircleAvatar(
                                radius: 24,
                                backgroundImage: NetworkImage(
                                  _buildFullImageUrl(
                                    me!['profile_picture'].toString(),
                                  ),
                                ),
                                backgroundColor: isLightShell
                                    ? Colors.grey[200]
                                    : Colors.white.withOpacity(0.12),
                              )
                            : Icon(
                                Icons.person,
                                size: 48,
                                color: Color(0xFFFF6B00),
                              ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        () {
                          final at =
                              (me?['account_type'] ?? 'user').toString().trim();
                          final dn =
                              (me?['dealership_name'] ?? '').toString().trim();
                          final fn =
                              (me?['first_name'] ?? '').toString().trim();
                          final ln =
                              (me?['last_name'] ?? '').toString().trim();
                          final full = '$fn $ln'.trim();
                          if (at == 'dealer' && dn.isNotEmpty) return dn;
                          if (at == 'dealer' && full.isNotEmpty) return full;
                          if (at == 'dealer') return 'Dealer';
                          return me?['username']?.toString() ?? 'User';
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
                          final e = me?['email']?.toString() ?? '';
                          final p =
                              me?['phone_number']?.toString() ??
                              me?['phone']?.toString() ??
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
                              (me?['account_type'] ?? 'user').toString();
                          final dealerStatus =
                              (me?['dealer_status'] ?? 'none').toString();
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
                              bg = Colors.white.withOpacity(0.1);
                              fg = Colors.white.withOpacity(0.88);
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
                            (me?['account_type'] ?? 'user').toString() ==
                                'dealer';
                        final rows = <Widget>[];
                        if (!isDealer) {
                          rows.add(
                            _buildInfoRow(
                              Icons.person_outline,
                              loc.usernameLabel,
                              me?['username']?.toString() ?? '',
                            ),
                          );
                        }
                        final emailStr = me?['email']?.toString() ?? '';
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
                            (me?['phone_number'] ?? me?['phone'] ?? '')
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
                            (me?['dealership_name'] ?? '').toString().trim();
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
                      _trLegacyText(
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
                    if (me?['is_admin'] == true) ...[
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
                        _trLegacyText(
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
                    if ((me?['account_type'] ?? 'user').toString() == 'dealer') ...[
                      SizedBox(height: 12),
                      _buildActionButton(
                        Icons.storefront_outlined,
                        _trLegacyText(
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
            color: Color(0xFFFF6B00).withOpacity(0.1),
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
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: light
                ? Colors.grey[300]!
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
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
            e.toString().replaceFirst('Exception: ', ''),
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
              _switchMainTabNoAnimation(context, '/');
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                _switchMainTabNoAnimation(context, '/profile');
              }
              break;
          }
        },
      ),
    );
  }
}

class EditListingPage extends StatefulWidget {
  final Map car;
  const EditListingPage({super.key, required this.car});
  @override
  _EditListingPageState createState() => _EditListingPageState();
}

class _EditListingPageState extends State<EditListingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.editListingTitle),
      ),
      body: Center(child: Text(AppLocalizations.of(context)!.editListingTitle)),
    );
  }
}

class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  _MyListingsPageState createState() => _MyListingsPageState();
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
            Colors.white.withOpacity(0.06),
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
                  color: const Color(0xFFFF6B00).withOpacity(0.12),
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
              color: Colors.black.withOpacity(isLightShell ? 0.05 : 0.20),
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
                activeColor: const Color(0xFFFF6B00),
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

class _MyListingsPageState extends State<MyListingsPage> {
  static const String _draftSnapshotKey = 'legacy_sell_draft_snapshot_v1';
  static const String _draftCurrentStepKey = 'legacy_sell_draft_current_step_v1';
  List<Map<String, dynamic>> myListings = [];
  bool isLoading = true;
  bool isLoadingDraft = true;
  String? error;
  Map<String, dynamic>? _draftSnapshot;

  @override
  void initState() {
    super.initState();
    ListingLayoutPrefs.load();
    _loadSellDraftSnapshot();
    _loadMyListings();
  }

  Future<ListingAnalytics> _fetchListingAnalytics(
    String listingId,
    Map<String, dynamic> listing,
  ) async {
    try {
      final a = await AnalyticsService.getListingAnalytics(listingId);
      if (a.listingId.toString().isNotEmpty) return a;
    } catch (_) {
      // fall through
    }

    // Fallback: try list endpoint (may be backed by /my_listings).
    try {
      final all = await AnalyticsService.getUserListingsAnalytics();
      for (final a in all) {
        if (a.listingId.toString() == listingId) return a;
      }
    } catch (_) {
      // fall through
    }

    int parseInt(dynamic v, {int fallback = 0}) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    double parseDouble(dynamic v, {double fallback = 0}) {
      if (v == null) return fallback;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }

    return ListingAnalytics(
      listingId: listingId,
      title: (listing['title'] ?? '').toString(),
      brand: (listing['brand'] ?? '').toString(),
      model: (listing['model'] ?? '').toString(),
      year: parseInt(listing['year']),
      price: parseDouble(listing['price']),
      imageUrl: null,
      mileage: null,
      city: (listing['city'] ?? listing['location'])?.toString(),
      views: 0,
      messages: 0,
      calls: 0,
      shares: 0,
      favorites: 0,
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
  }

  void _showListingAnalyticsPopup(Map<String, dynamic> listing, String listingId) {
    if (listingId.isEmpty) return;
    final loc = AppLocalizations.of(context)!;
    final future = _fetchListingAnalytics(listingId, listing);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(loc.analyticsTitle),
          content: SizedBox(
            width: 360,
            child: FutureBuilder<ListingAnalytics>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(snapshot.error.toString());
                }
                final a = snapshot.data;
                if (a == null) return const Text('No analytics available.');

                Widget metricRow(IconData icon, String label, String value) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: const Color(0xFFFF6B00)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                final resolvedTitle = (a.title).trim().isNotEmpty
                    ? prettyTitleCase(a.title)
                    : prettyTitleCase(a.carTitle);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resolvedTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    metricRow(
                      Icons.visibility_outlined,
                      loc.viewsLabel,
                      '${a.views}',
                    ),
                    metricRow(
                      Icons.message_outlined,
                      loc.messagesLabel,
                      '${a.messages}',
                    ),
                    metricRow(
                      Icons.phone_outlined,
                      loc.callsLabel,
                      '${a.calls}',
                    ),
                    metricRow(
                      Icons.share_outlined,
                      loc.sharesLabel,
                      '${a.shares}',
                    ),
                    metricRow(
                      Icons.favorite_outline,
                      loc.favoritesLabel,
                      '${a.favorites}',
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc.cancelAction),
            ),
          ],
        );
      },
    );
  }

  void _showOverallAnalyticsPopup() {
    final loc = AppLocalizations.of(context)!;
    final future = AnalyticsService.getAnalyticsSummary();

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(loc.analyticsOverview),
          content: SizedBox(
            width: 360,
            child: FutureBuilder<AnalyticsSummary>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(snapshot.error.toString());
                }
                final s = snapshot.data;
                if (s == null) return const Text('No analytics available.');

                Widget metricRow(IconData icon, String label, String value) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: const Color(0xFFFF6B00)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    metricRow(
                      Icons.directions_car_outlined,
                      loc.listingsLabel,
                      '${s.totalListings}',
                    ),
                    const SizedBox(height: 8),
                    metricRow(
                      Icons.visibility_outlined,
                      loc.viewsLabel,
                      '${s.totalViews}',
                    ),
                    metricRow(
                      Icons.message_outlined,
                      loc.messagesLabel,
                      '${s.totalMessages}',
                    ),
                    metricRow(
                      Icons.phone_outlined,
                      loc.callsLabel,
                      '${s.totalCalls}',
                    ),
                    metricRow(
                      Icons.share_outlined,
                      loc.sharesLabel,
                      '${s.totalShares}',
                    ),
                    metricRow(
                      Icons.favorite_outline,
                      loc.favoritesLabel,
                      '${s.totalFavorites}',
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc.cancelAction),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadMyListings() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) {
        setState(() {
          error = 'Please log in to view your listings';
          isLoading = false;
        });
        return;
      }

      final url = Uri.parse('${getApiBase()}/api/my_listings');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          myListings = data.cast<Map<String, dynamic>>();
          isLoading = false;
        });
        _debugLog('MyListings loaded: ${myListings.length} listings');
      } else if (response.statusCode == 401) {
        setState(() {
          error = 'Please log in to view your listings';
          isLoading = false;
        });
        _debugLog('MyListings API returned 401 - Authentication failed');
      } else {
        setState(() {
          error = 'Failed to load listings. Please try again.';
          isLoading = false;
        });
        _debugLog(
          'MyListings API error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      setState(() {
        error = 'Network error. Please check your connection.';
        isLoading = false;
      });
    }
  }

  dynamic _draftValue(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num || value is bool) return value;
    if (value is XFile) return value.path;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _draftValue(v)));
    }
    if (value is Iterable) {
      return value.map(_draftValue).toList();
    }
    return value.toString();
  }

  Future<void> _loadSellDraftSnapshot() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftSnapshotKey);
      if (raw == null || raw.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _draftSnapshot = null;
          isLoadingDraft = false;
        });
        return;
      }
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        if (!mounted) return;
        setState(() {
          _draftSnapshot = null;
          isLoadingDraft = false;
        });
        return;
      }
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      final rawCarData = data['carData'];
      final carData = rawCarData is Map
          ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
          : <String, dynamic>{};
      final jsonStep = _readSellDraftStepDynamic(data['currentStep']);
      final prefsStep = sp.getInt(_draftCurrentStepKey);
      final mergedStep = _mergeSellDraftStep(
        jsonStep: jsonStep,
        prefsStep: prefsStep,
      );
      if (!mounted) return;
      setState(() {
        _draftSnapshot = <String, dynamic>{
          if (data['draftId'] != null) 'draftId': data['draftId'],
          'currentStep': mergedStep,
          'carData': carData,
          if (data['isPlaceholder'] == true) 'isPlaceholder': true,
          if (data['updatedAt'] != null) 'updatedAt': data['updatedAt'],
        };
        isLoadingDraft = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _draftSnapshot = null;
        isLoadingDraft = false;
      });
    }
  }

  Future<void> _discardSellDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_draftSnapshotKey);
      await sp.remove(_draftCurrentStepKey);
      await sp.remove('legacy_sell_draft_step1_v1');
      await sp.remove('legacy_sell_draft_step2_v1');
      await sp.remove('legacy_sell_draft_step3_v1');
      await sp.remove('legacy_sell_draft_step4_v1');
      if (!mounted) return;
      setState(() {
        _draftSnapshot = null;
      });
    } catch (_) {}
  }

  Future<void> _resumeSellDraft() async {
    final snapshot = _draftSnapshot;
    if (snapshot == null) {
      Navigator.pushNamed(context, '/sell');
      return;
    }
    Navigator.pushNamed(
      context,
      '/sell',
      arguments: {'draftSnapshot': snapshot},
    );
  }

  String _draftTitle(Map<String, dynamic> carData) {
    final brand = (carData['brand'] ?? '').toString().trim();
    final model = (carData['model'] ?? '').toString().trim();
    final trim = (carData['trim'] ?? '').toString().trim();
    final year = (carData['year'] ?? '').toString().trim();
    final parts = <String>[brand, model];
    final title = parts.where((s) => s.isNotEmpty).join(' ');
    final suffix = [trim, year].where((s) => s.isNotEmpty).join(' • ');
    if (title.isEmpty && suffix.isEmpty) return 'Untitled draft';
    if (title.isEmpty) return suffix;
    if (suffix.isEmpty) return title;
    return '$title • $suffix';
  }

  Widget _buildDraftSection({required bool listLayout}) {
    final snapshot = _draftSnapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final carData = snapshot['carData'] is Map
        ? Map<String, dynamic>.from((snapshot['carData'] as Map).cast<String, dynamic>())
        : <String, dynamic>{};
    final currentStep = _readSellDraftStepDynamic(snapshot['currentStep']);
    final stepLabel = [
      'Step 1: Basic info',
      'Step 2: Details',
      'Step 3: Pricing',
      'Step 4: Photos',
      'Step 5: Review',
    ];
    final stepText = stepLabel[currentStep.clamp(0, 4).toInt()];

    final draftListing = <String, dynamic>{
      ...carData,
      'title': _draftTitle(carData),
      'price': carData['price']?.toString().trim(),
      'images': SellDraftMediaPersistence.resolveDynamicMediaList(
        (carData['images'] is List)
            ? List<dynamic>.from(carData['images'] as List)
            : (carData['image_paths'] is List)
                ? List<dynamic>.from(carData['image_paths'] as List)
                : null,
      ),
      'videos': (carData['videos'] is List)
          ? List<dynamic>.from(carData['videos'] as List)
          : const <dynamic>[],
      'is_quick_sell': carData['is_quick_sell'] ?? false,
    };

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: buildGlobalCarCard(
              context,
              draftListing,
              listLayout: listLayout,
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _resumeSellDraft,
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.62),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'DRAFT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Material(
              color: Colors.black.withOpacity(0.62),
              shape: const CircleBorder(),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _discardSellDraft,
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: 'Discard draft',
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.62),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                stepText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final bodyChild = isLoading
        ? Center(child: CircularProgressIndicator())
        : error != null
        ? _buildErrorState()
        : (myListings.isEmpty && _draftSnapshot == null && !isLoadingDraft)
        ? _buildEmptyState()
        : _buildListingsGrid();
    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.myListingsTitle),
        backgroundColor: Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: _loadMyListings),
        ],
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
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        onTap: (idx) {
          switch (idx) {
            case 0:
              _switchMainTabNoAnimation(context, '/');
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                _switchMainTabNoAnimation(context, '/profile');
              }
              break;
          }
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            SizedBox(height: 16),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadMyListings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFFF6B00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(AppLocalizations.of(context)!.retryAction),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xFFFF6B00).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_car_outlined,
                size: 64,
                color: Color(0xFFFF6B00),
              ),
            ),
            SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.noListingsYet,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.noListingsEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/sell'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFFF6B00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add),
                  SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.addYourFirstCar),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListingsGrid() {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isLightShell ? const Color(0xFF131722) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.directions_car, color: Color(0xFFFF6B00)),
                SizedBox(width: 12),
                Flexible(
                  flex: 0,
                  fit: FlexFit.loose,
                  child: Text(
                    AppLocalizations.of(
                      context,
                    )!.yourListingsCount(myListings.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isLightShell ? Colors.white : Colors.grey[800],
                    ),
                  ),
                ),
                // Slightly more flex before the button nudges it right while
                // keeping spacing roughly balanced.
                const Expanded(flex: 5, child: SizedBox.shrink()),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/sell'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFF6B00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.addNewButton,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Expanded(flex: 4, child: SizedBox.shrink()),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showOverallAnalyticsPopup,
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Overall analytics'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B00),
                side: const BorderSide(color: Color(0xFFFF6B00), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        SizedBox(height: 0),
        Expanded(
          child: (myListings.isEmpty && _draftSnapshot == null)
              ? _buildEmptyState()
              : ValueListenableBuilder<int>(
                  valueListenable: ListingLayoutPrefs.columns,
                  builder: (context, cols, _) {
                    final listingColumns = (cols == 1) ? 1 : 2;
                    final hasDraft = _draftSnapshot != null;
                    final totalCards = myListings.length + (hasDraft ? 1 : 0);
                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        listingColumns == 1 ? 4 : 8,
                        8,
                        listingColumns == 1 ? 4 : 8,
                        8,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: listingColumns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: listingColumns == 2
                            ? (Platform.isIOS ? 0.66 : 0.61)
                            : 2.78,
                      ),
                      itemCount: totalCards,
                      itemBuilder: (context, index) {
                        if (hasDraft && index == 0) {
                          return _buildDraftSection(
                            listLayout: listingColumns == 1,
                          );
                        }

                        final listing = myListings[hasDraft ? index - 1 : index];
                        final id =
                            (listing['id'] ?? listing['public_id'] ?? '').toString();
                        final mapped = mapListingToGlobalCarCardData(context, listing);
                        final card = buildGlobalCarCard(
                          context,
                          mapped,
                          listLayout: listingColumns == 1,
                        );

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            card,
                            if (id.isNotEmpty)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Material(
                                  color: const Color(0xFFFF6B00),
                                  borderRadius: BorderRadius.circular(6),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () => _showListingAnalyticsPopup(
                                      listing,
                                      id,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      child: Text(
                                        AppLocalizations.of(context)!.analyticsTitle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

}

