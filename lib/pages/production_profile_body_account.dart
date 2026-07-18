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
                final picture = profile?['profile_picture']?.toString() ?? '';
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
                return Icon(Icons.person, size: 48, color: Color(0xFFFF6B00));
              }(),
            ),
            SizedBox(height: 16),
            Text(
              () {
                final at = (profile?['account_type'] ?? 'user')
                    .toString()
                    .trim();
                final dn = (profile?['dealership_name'] ?? '')
                    .toString()
                    .trim();
                final fn = (profile?['first_name'] ?? '').toString().trim();
                final ln = (profile?['last_name'] ?? '').toString().trim();
                final full = '$fn $ln'.trim();
                if (at == 'dealer' && dn.isNotEmpty) return dn;
                if (at == 'dealer' && full.isNotEmpty) return full;
                if (at == 'dealer') return 'Dealer';
                final phone = (profile?['phone_number'] ?? '')
                    .toString()
                    .trim();
                if (phone.isNotEmpty) return phone;
                return 'User';
              }(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _profilePrimaryInk(context),
              ),
            ),
            SizedBox(height: 12),
            Builder(
              builder: (ctx) {
                final accountType = (profile?['account_type'] ?? 'user')
                    .toString();
                final rawApplication = profile?['dealer_application'];
                final applicationStatus = rawApplication is Map
                    ? rawApplication['status']
                    : null;
                final dealerStatus =
                    (profile?['dealer_application_status'] ??
                            applicationStatus ??
                            profile?['dealer_status'] ??
                            'none')
                        .toString();
                final isVerifiedDealer =
                    dealerStatus == 'approved' || accountType == 'dealer';
                final isPending =
                    dealerStatus == 'pending' ||
                    dealerStatus == 'submitted' ||
                    dealerStatus == 'under_review';
                final needsChanges = dealerStatus == 'needs_changes';
                final isRejected = dealerStatus == 'rejected';
                late final String label;
                late final Color bg;
                late final Color fg;
                if (isVerifiedDealer) {
                  label = AppLocalizations.of(context)!.verifiedDealerLabel;
                  bg = Colors.green.withValues(alpha: 0.15);
                  fg = isLightShell
                      ? Colors.green.shade800
                      : Colors.green.shade200;
                } else if (isPending) {
                  label = AppLocalizations.of(
                    context,
                  )!.dealerApplicationPendingLabel;
                  bg = Colors.orange.withValues(alpha: 0.15);
                  fg = isLightShell
                      ? Colors.orange.shade800
                      : Colors.orange.shade200;
                } else if (needsChanges) {
                  label = trLegacyText(
                    context,
                    'Dealer application needs changes',
                    ar: 'طلب الوكالة يحتاج إلى تعديلات',
                    ku: 'داواکاری فرۆشیار پێویستی بە گۆڕانکاری هەیە',
                  );
                  bg = Colors.amber.withValues(alpha: 0.15);
                  fg = isLightShell
                      ? Colors.amber.shade900
                      : Colors.amber.shade200;
                } else if (isRejected) {
                  label = AppLocalizations.of(
                    context,
                  )!.dealerApplicationDeclinedLabel;
                  bg = Colors.red.withValues(alpha: 0.12);
                  fg = isLightShell ? Colors.red.shade800 : Colors.red.shade200;
                } else {
                  label = AppLocalizations.of(context)!.personalAccountLabel;
                  if (isLightShell) {
                    bg = Colors.grey.shade200;
                    fg = Colors.grey.shade700;
                  } else {
                    bg = Colors.white.withValues(alpha: 0.1);
                    fg = Colors.white.withValues(alpha: 0.88);
                  }
                }
                return InkWell(
                  onTap: needsChanges || isRejected
                      ? () => Navigator.of(
                          context,
                        ).pushNamed('/dealer-onboarding')
                      : null,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      needsChanges || isRejected ? '$label →' : label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: fg,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      SizedBox(height: 24),
    ];
  }
}
