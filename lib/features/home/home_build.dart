part of 'home_flow.dart';

mixin _HomePageBuild on _HomePageSlivers {
  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final appBarFg = isLight ? const Color(0xFF0A0A0A) : Colors.white;
    final searchPillBg = isLight
        ? AppColors.brandOrange.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.18);
    final searchPillBorder = isLight
        ? AppColors.brandOrange.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.35);
    final searchPillFg =
        isLight ? AppColors.brandOrange : Colors.white;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : null,
        foregroundColor: appBarFg,
        surfaceTintColor: Colors.transparent,
        elevation: isLight ? 0 : null,
        scrolledUnderElevation: isLight ? 0 : null,
        systemOverlayStyle: isLight
            ? const services.SystemUiOverlayStyle(
                statusBarColor: Colors.white,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              )
            : null,
        title: Image.asset(
          isLight
              ? 'assets/icon/splash_logo_light.png'
              : 'assets/icon/splash_logo.png',
          height: 32,
          width: 74,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          semanticLabel: AppLocalizations.of(context)!.appTitle,
        ),
        titleSpacing: NavigationToolbar.kMiddleSpacing,
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              end: NavigationToolbar.kMiddleSpacing,
            ),
            child: Material(
              color: searchPillBg,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => _openHomeSearchFiltersPage(
                  context,
                  focusSearchField: false,
                ),
                borderRadius: BorderRadius.circular(20),
                splashColor: searchPillFg.withValues(alpha: 0.2),
                highlightColor: searchPillFg.withValues(alpha: 0.12),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppResponsive.narrowAppBar(context) ? 10 : 14,
                    vertical: AppResponsive.narrowAppBar(context) ? 7 : 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: searchPillBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: searchPillFg,
                        size: AppResponsive.narrowAppBar(context) ? 17 : 18,
                      ),
                      SizedBox(
                        width: AppResponsive.narrowAppBar(context) ? 5 : 6,
                      ),
                      Text(
                        AppLocalizations.of(context)!.homeSearchHeading,
                        style: TextStyle(
                          color: searchPillFg,
                          fontSize:
                              AppResponsive.narrowAppBar(context) ? 12 : 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
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
              _switchMainTabNoAnimation(context, '/sell');
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
              child: RefreshIndicator(
                color: AppColors.brandOrange,
                onRefresh: refreshHomeFeed,
                child: CustomScrollView(
                  controller: _homeScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    _buildHomeSearchCityBarSliver(context),
                    _buildHomeActiveFiltersSliver(context),
                    _buildFeaturedListingsSliver(context),
                    ..._buildHomeFeedSlivers(context),
                  ],
                ),
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
