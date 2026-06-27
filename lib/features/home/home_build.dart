part of 'home_flow.dart';

mixin _HomePageBuild on _HomePageSlivers {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.appTitle,
          style: TextStyle(fontSize: 18),
        ),
        titleSpacing: NavigationToolbar.kMiddleSpacing,
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: AppResponsive.compactAppBarActions(context)
                ? IconButton(
                    tooltip: AppLocalizations.of(context)!.homeSearchHeading,
                    onPressed: () => _openHomeSearchFiltersPage(context),
                    icon: const Icon(Icons.search, color: Colors.white),
                  )
                : OutlinedButton.icon(
                    onPressed: () => _openHomeSearchFiltersPage(context),
                    icon: const Icon(Icons.search, color: Colors.white),
                    label: Text(
                      AppLocalizations.of(context)!.homeSearchHeading,
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              end: NavigationToolbar.kMiddleSpacing,
            ),
            child: AppResponsive.compactAppBarActions(context)
                ? IconButton(
                    tooltip: AppLocalizations.of(context)!.sellButton,
                    onPressed: () {
                      _persistCurrentHomeOffsetNow();
                      _switchMainTabNoAnimation(context, '/sell');
                    },
                    icon: const Icon(Icons.add, color: Colors.white),
                  )
                : OutlinedButton.icon(
                    onPressed: () {
                      _persistCurrentHomeOffsetNow();
                      _switchMainTabNoAnimation(context, '/sell');
                    },
                    icon: Icon(Icons.add, color: Colors.white),
                    label: Text(
                      AppLocalizations.of(context)!.sellButton,
                      style: TextStyle(color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
          ),
        ],
      ),
      // Pull-to-refresh is already provided inside the main content via internal scrollables
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 0,
        onTap: (idx) {
          if (idx != 0) {
            // Persist exact offset before route replacement to avoid stale restores.
            _persistCurrentHomeOffsetNow();
          }
          switch (idx) {
            case 0:
              _scrollHomeToTopAndResetCardImages();
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              _switchMainTabNoAnimation(context, '/profile');
              break;
          }
        },
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 0.0),
              child: CustomScrollView(
                controller: _homeScrollController,
                slivers: [
                  _buildHomeSearchCityBarSliver(context),
                  _buildFeaturedListingsSliver(context),
                  ..._buildHomeFeedSlivers(context),
                ],
              ),
            ),
            // Intentionally avoid full-screen obscuring overlay while scroll restores.
          ],
        ),
      ),
      floatingActionButton: null,
    );
  }
}
