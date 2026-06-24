part of 'production_account_pages.dart';

extension _ProfilePageBody on _ProfilePageState {
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
}
