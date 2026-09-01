part of 'production_account_pages.dart';

mixin _ProfilePageBodyGuest on _ProfilePageWidgets {
  List<Widget> _buildProfileGuestSection(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final icon = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandOrange.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.person_outline,
        color: AppColors.brandOrange,
        size: 26,
      ),
    );
    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.guest,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _profilePrimaryInk(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          loc.signInToAccessYourProfileFeatures,
          style: TextStyle(
            fontSize: 13,
            color: _profileSecondaryInk(context),
          ),
        ),
      ],
    );
    final loginButton = ElevatedButton(
      onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 1,
      ),
      child: Text(
        loc.loginAction,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _profileCardDecoration(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useStackedLayout = constraints.maxWidth < 420;
            if (useStackedLayout) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(child: textBlock),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: loginButton),
                ],
              );
            }

            return Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(child: textBlock),
                const SizedBox(width: 10),
                Flexible(child: loginButton),
              ],
            );
          },
        ),
      ),
      const SizedBox(height: 16),
    ];
  }
}
