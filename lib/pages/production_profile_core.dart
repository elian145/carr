part of 'production_account_pages.dart';

mixin _ProfilePageCore on _ProfilePageBody {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(AppLocalizations.of(context)!.profileTitle),
      ),
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
              navigateMainShellTab(context, '/sell');
              break;
            case 2:
              navigateMainShellTab(context, '/dealers');
              break;
            case 3:
              // Already on Profile (guest or logged-in). Do not bounce to Login.
              break;
          }
        },
      ),
    );
  }
}
