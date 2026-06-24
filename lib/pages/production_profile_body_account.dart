part of 'production_account_pages.dart';

mixin _ProfilePageBodyAccount on _ProfilePageBodyGuest {
  List<Widget> _buildProfileAccountSection(
    BuildContext context,
    Map<String, dynamic>? profile,
    bool isLightShell,
  ) {
    return [
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
    ];
  }
}
