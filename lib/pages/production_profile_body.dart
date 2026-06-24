part of 'production_account_pages.dart';

mixin _ProfilePageBody on _ProfilePageBodyActions {
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
              if (!isLoggedIn) ..._buildProfileGuestSection(context),
              if (isLoggedIn)
                ..._buildProfileAccountSection(context, profile, isLightShell),
              ..._buildProfileActionsSection(context, profile, isLoggedIn),
            ],
          ),
        ),
      ],
    );
  }
}
