part of 'production_auth_pages.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final ScrollController _controller = ScrollController();

  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  int _fetchGeneration = 0;
  String? _error;
  bool _loginRequired = false;

  static const int _perPage = 20;

  int _favoritedAtMs(Map<String, dynamic> m) {
    final raw = (m['favorited_at'] ?? m['favoritedAt'])?.toString().trim();
    if (raw == null || raw.isEmpty) return -1;
    try {
      return DateTime.parse(raw).millisecondsSinceEpoch;
    } catch (e, st) {
      logNonFatal(e, st);
      return -1;
    }
  }

  String _carIdOf(Map<String, dynamic> m) =>
      (m['public_id'] ?? m['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    ListingLayoutPrefs.load();
    _controller.addListener(() {
      if (_loading || _loadingMore || !_hasNext) return;
      final pos = _controller.position;
      if (pos.pixels >= (pos.maxScrollExtent - 500)) {
        _loadMore();
      }
    });
    // Delay loading until after first frame so that inherited widgets
    // like Localizations are available when _fetch runs.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fetch(refresh: true),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Loads (or reloads) the favorites feed.
  ///
  /// [refresh] == true resets pagination back to page 1 and replaces the
  /// list (used by initial load and pull-to-refresh); == false appends the
  /// next page (infinite scroll / "load more").
  Future<void> _fetch({required bool refresh}) async {
    final requestGeneration = refresh ? ++_fetchGeneration : _fetchGeneration;
    final tok = ApiService.accessToken;
    if (tok == null || tok.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loginRequired = true;
        _loading = false;
        _loadingMore = false;
      });
      return;
    }

    if (refresh) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
        _loginRequired = false;
        _page = 1;
        _hasNext = true;
      });

      // Show a cached page-1 snapshot instantly while the network request
      // for a fresh page 1 is in flight (this is a best-effort perceived-
      // performance optimization, not the source of truth).
      try {
        final sp = await SharedPreferences.getInstance();
        final cached = sp.getString('cache_favorites');
        if (cached != null &&
            cached.isNotEmpty &&
            mounted &&
            requestGeneration == _fetchGeneration) {
          final data = json.decode(cached);
          if (data is List) {
            final parsed = listingMapsFromApiList(data);
            parsed.sort(
              (a, b) => _favoritedAtMs(b).compareTo(_favoritedAtMs(a)),
            );
            setState(() {
              _favorites = parsed;
            });
          }
        }
      } catch (e, st) {
        logNonFatal(e, st);
      }
    } else {
      if (_loadingMore || !_hasNext) return;
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }

    try {
      final decoded = await ApiService.getFavorites(
        page: _page,
        perPage: _perPage,
      );
      final items = listingMapsFromFavoritesResponse(decoded);

      bool hasNext = false;
      final pagination = decoded['pagination'];
      if (pagination is Map && pagination['has_next'] is bool) {
        hasNext = pagination['has_next'] as bool;
      } else {
        hasNext = items.length >= _perPage;
      }
      // A short/empty page always ends the list, even if the server didn't
      // send an explicit `has_next` flag.
      if (items.isEmpty) hasNext = false;

      if (!mounted || requestGeneration != _fetchGeneration) return;
      setState(() {
        if (refresh) {
          _favorites = items;
          _favorites.sort(
            (a, b) => _favoritedAtMs(b).compareTo(_favoritedAtMs(a)),
          );
        } else {
          // De-dupe against everything already shown: a favorite added/
          // removed elsewhere mid-scroll can shift page boundaries and
          // hand back a listing the first page already rendered.
          final seen = _favorites.map(_carIdOf).toSet();
          for (final item in items) {
            final id = _carIdOf(item);
            if (id.isEmpty || !seen.add(id)) continue;
            _favorites.add(item);
          }
        }
        _hasNext = hasNext;
        _loading = false;
        _loadingMore = false;
      });

      if (refresh) {
        final sp = await SharedPreferences.getInstance();
        unawaited(sp.setString('cache_favorites', json.encode(_favorites)));
      }
    } on ApiException catch (e) {
      if (!mounted || requestGeneration != _fetchGeneration) return;
      if (e.statusCode == 401) {
        setState(() {
          _loginRequired = true;
          _loading = false;
          _loadingMore = false;
        });
      } else {
        setState(() {
          _error = AppLocalizations.of(context)!.failedToLoadListings;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (!mounted || requestGeneration != _fetchGeneration) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)!.error,
        );
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadFavorites() => _fetch(refresh: true);

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasNext) return;
    _page += 1;
    await _fetch(refresh: false);
  }

  Future<void> _toggleFavorite(String carId) async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) return;
      unawaited(AppHaptics.light());
      // Use API service so endpoint + auth stays consistent.
      final res = await ApiService.toggleFavorite(carId);
      final bool favorited =
          (res['is_favorited'] == true) || (res['favorited'] == true);
      if (!favorited) {
        setState(() {
          _favorites.removeWhere((c) => _carIdOf(c) == carId);
        });
      } else {
        unawaited(AnalyticsService.trackFavorite(carId));
      }
    } catch (e, st) {
      logNonFatal(e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)!.error,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.favoritesTitle)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          if (_loading)
            ValueListenableBuilder<int>(
              valueListenable: ListingLayoutPrefs.columns,
              builder: (context, cols, _) {
                final screenWidth = MediaQuery.sizeOf(context).width;
                final listingColumns =
                    ListingLayoutPrefs.effectiveColumnsForWidth(
                      cols == 1 ? 1 : 2,
                      screenWidth,
                    );
                return ListingFeedSkeleton(
                  columns: listingColumns,
                  itemCount: listingColumns == 1 ? 4 : listingColumns * 3,
                );
              },
            )
          else if (_loginRequired)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.notLoggedIn,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      child: Text(AppLocalizations.of(context)!.loginAction),
                    ),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadFavorites,
                      child: Text(AppLocalizations.of(context)!.retryAction),
                    ),
                  ],
                ),
              ),
            )
          else if (_favorites.isEmpty)
            EmptyStatePanel(
              icon: Icons.favorite_border,
              title: AppLocalizations.of(context)!.noFavoritesYet,
              hint: AppLocalizations.of(context)!.favoritesEmptyHint,
              actionLabel: AppLocalizations.of(context)!.browseCarsAction,
              actionIcon: Icons.search,
              onAction: () => navigateMainShellTab(context, '/'),
            )
          else
            RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: _loadFavorites,
              child: ValueListenableBuilder<int>(
                valueListenable: ListingLayoutPrefs.columns,
                builder: (context, cols, _) {
                  final screenWidth = MediaQuery.sizeOf(context).width;
                  final listingColumns =
                      ListingLayoutPrefs.effectiveColumnsForWidth(
                        cols == 1 ? 1 : 2,
                        screenWidth,
                      );
                  return GridView.builder(
                    controller: _controller,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      listingColumns == 1 ? 4 : 8,
                      8,
                      listingColumns == 1 ? 4 : 8,
                      16,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: listingColumns,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio:
                          ListingLayoutPrefs.gridChildAspectRatioForWidth(
                            listingColumns,
                            screenWidth,
                          ),
                    ),
                    itemCount: _favorites.length + (_hasNext ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _favorites.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        );
                      }
                      final carMap = Map<String, dynamic>.from(
                        _favorites[index],
                      );
                      final card = buildGlobalCarCard(
                        context,
                        mapListingToGlobalCarCardData(context, carMap),
                        listLayout: listingColumns == 1,
                      );
                      final String carId = _carIdOf(carMap);
                      if (carId.isEmpty) return card;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          card,
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _toggleFavorite(carId),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.favorite,
                                    color: AppColors.brandOrange,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
