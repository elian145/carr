part of 'dealers_directory_page.dart';

mixin _DealersDirectoryPageCore on _DealersDirectoryPageWidgets {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.navDealers ?? 'Dealerships'),
      ),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 2,
        onTap: (idx) {
          switch (idx) {
            case 0:
              navigateMainShellTab(context, '/');
              break;
            case 1:
              navigateMainShellTab(context, '/favorites');
              break;
            case 2:
              break;
            case 3:
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                navigateMainShellTab(context, '/profile');
              }
              break;
          }
        },
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          Column(
            children: [
              _buildSearchBar(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 48),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: OutlinedButton(
                                  onPressed: () => _load(refresh: true),
                                  child: Text(loc?.retryAction ?? 'Retry'),
                                ),
                              ),
                            ],
                          )
                        : RefreshIndicator(
                            onRefresh: () => _load(refresh: true),
                            child: _rows.isEmpty
                                ? ListView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    children: [
                                      SizedBox(
                                        height: MediaQuery.sizeOf(context).height * 0.2,
                                      ),
                                      Center(
                                        child: Text(
                                          _tr(
                                            'No dealerships match your search.',
                                            ar: 'لا توجد معارض مطابقة لبحثك.',
                                            ku: 'هیچ نمایشگەیەک لەگەڵ گەڕانەکەتدا ناگونجێت.',
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView.builder(
                                    controller: _scroll,
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.only(bottom: 100),
                                    itemCount: _rows.length + (_loadingMore ? 1 : 0),
                                    itemBuilder: (context, i) {
                                      if (i >= _rows.length) {
                                        return const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Center(
                                            child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      return _dealerCard(context, _rows[i]);
                                    },
                                  ),
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
