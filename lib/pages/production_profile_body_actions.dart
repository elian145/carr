part of 'production_account_pages.dart';

mixin _ProfilePageBodyActions on _ProfilePageBodyAccount {
  /// Prominent favorites entry (UX-03) — above the long account-actions list.
  Widget _buildFavoritesQuickAccess(BuildContext context, bool isLoggedIn) {
    final accent = AppColors.brandOrange;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (!isLoggedIn) {
            _showAuthRequiredDialog(context);
            return;
          }
          Navigator.pushNamed(context, '/favorites');
        },
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: _profileCardDecoration(context).copyWith(
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.favorite_rounded, color: accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.favoritesTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _profilePrimaryInk(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.navSaved,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _profilePrimaryInk(context).withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: _profilePrimaryInk(context).withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
              Icons.notifications_outlined,
              AppLocalizations.of(context)!.notificationsTitle,
              () async {
                if (ApiService.accessToken == null ||
                    ApiService.accessToken!.isEmpty) {
                  _showAuthRequiredDialog(context);
                  return;
                }
                await Navigator.pushNamed(context, '/notifications');
                if (!mounted) return;
                _loadUnreadNotificationCount();
              },
              badgeCount: _unreadNotificationCount,
            ),
            SizedBox(height: 12),
            _buildActionButton(
              Icons.history,
              AppLocalizations.of(context)!.recentlyViewed,
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
                Navigator.pushNamed(context, '/saved-searches');
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
            if ((profile?['account_type'] ?? 'user').toString() == 'dealer') ...[
              SizedBox(height: 12),
              _buildActionButton(
                Icons.storefront_outlined,
                AppLocalizations.of(context)!.editDealerPage,
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
