part of 'production_account_pages.dart';

mixin _ProfilePageBodyActions on _ProfilePageBodyAccount {
  List<Widget> _buildProfileActionsSection(
    BuildContext context,
    Map<String, dynamic>? profile,
    bool isLoggedIn,
  ) {
    return [
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
                  AppPageRoute(
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
    ];
  }
}
