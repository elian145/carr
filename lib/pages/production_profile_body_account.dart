part of 'production_account_pages.dart';

mixin _ProfilePageBodyAccount on _ProfilePageBodyGuest {
  List<Widget> _buildProfileAccountSection(
    BuildContext context,
    Map<String, dynamic>? profile,
    bool isLightShell,
  ) {
    final accountType = (profile?['account_type'] ?? 'user')
        .toString()
        .trim()
        .toLowerCase();
    final coverPath = (profile?['dealership_cover_picture'] ?? '')
        .toString()
        .trim();
    final profilePicturePath = (profile?['profile_picture'] ?? '')
        .toString()
        .trim();
    final profilePictureUrl = profilePicturePath.isNotEmpty
        ? buildLegacyFullImageUrl(profilePicturePath)
        : '';
    final dealerCoverUrl = accountType == 'dealer' && coverPath.isNotEmpty
        ? buildMediaUrl(coverPath)
        : '';
    final hasDealerCover = dealerCoverUrl.isNotEmpty;
    final headerDecoration =
        _profileCardDecoration(
          context,
          radius: 20,
          blur: 16,
          shadowOpacity: 0.08,
        ).copyWith(
          image: hasDealerCover
              ? DecorationImage(
                  image: listingCachedNetworkImageProvider(dealerCoverUrl),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.48),
                    BlendMode.darken,
                  ),
                )
              : null,
        );
    final displayName = () {
      final at = (profile?['account_type'] ?? 'user').toString().trim();
      final dn = (profile?['dealership_name'] ?? '').toString().trim();
      final fn = (profile?['first_name'] ?? '').toString().trim();
      final ln = (profile?['last_name'] ?? '').toString().trim();
      final full = '$fn $ln'.trim();
      if (at == 'dealer' && dn.isNotEmpty) return dn;
      if (at == 'dealer' && full.isNotEmpty) return full;
      if (at == 'dealer') return 'Dealer';
      final phone = (profile?['phone_number'] ?? '').toString().trim();
      if (phone.isNotEmpty) return phone;
      return 'User';
    }();
    final avatar = Container(
      width: 88,
      height: 88,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: hasDealerCover
            ? Colors.white.withValues(alpha: 0.88)
            : AppColors.brandOrange.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: hasDealerCover
            ? Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3)
            : null,
      ),
      child: profilePictureUrl.isNotEmpty
          ? listingNetworkImage(
              profilePictureUrl,
              width: 88,
              height: 88,
              fit: BoxFit.cover,
              errorWidget:
                  const Icon(Icons.person, size: 48, color: AppColors.brandOrange),
            )
          : const Icon(Icons.person, size: 48, color: AppColors.brandOrange),
    );
    final name = Text(
      displayName,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: hasDealerCover ? Colors.white : _profilePrimaryInk(context),
        shadows: hasDealerCover
            ? const [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
    );
    final statusBadge = Builder(
      builder: (ctx) {
        final accountType = (profile?['account_type'] ?? 'user').toString();
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
          fg = isLightShell ? Colors.green.shade800 : Colors.green.shade200;
        } else if (isPending) {
          label = AppLocalizations.of(context)!.dealerApplicationPendingLabel;
          bg = Colors.orange.withValues(alpha: 0.15);
          fg = isLightShell ? Colors.orange.shade800 : Colors.orange.shade200;
        } else if (needsChanges) {
          label = AppLocalizations.of(context)!.dealerApplicationNeedsChanges;
          bg = Colors.amber.withValues(alpha: 0.15);
          fg = isLightShell ? Colors.amber.shade900 : Colors.amber.shade200;
        } else if (isRejected) {
          label = AppLocalizations.of(context)!.dealerApplicationDeclinedLabel;
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
              ? () => Navigator.of(context).pushNamed('/dealer-onboarding')
              : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    );

    return [
      // Profile Header
      Container(
        width: double.infinity,
        padding: EdgeInsets.all(24),
        decoration: headerDecoration,
        child: hasDealerCover
            ? SizedBox(
                height: 172,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      avatar,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            name,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: statusBadge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  avatar,
                  const SizedBox(height: 16),
                  name,
                  const SizedBox(height: 12),
                  statusBadge,
                ],
              ),
      ),
      SizedBox(height: 24),
    ];
  }
}
