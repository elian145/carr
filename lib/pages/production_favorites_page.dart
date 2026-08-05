part of 'production_auth_pages.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;
  String? _error;
  bool _loginRequired = false;

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

  @override
  void initState() {
    super.initState();
    ListingLayoutPrefs.load();
    // Delay loading until after first frame so that inherited widgets
    // like Localizations are available when _loadFavorites runs.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFavorites());
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _loading = true;
      _error = null;
      _loginRequired = false;
    });
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        setState(() {
          _loginRequired = true;
          _loading = false;
        });
        return;
      }
      final sp = await SharedPreferences.getInstance();
      final cacheKey = 'cache_favorites';
      final cached = sp.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          final data = json.decode(cached);
          if (data is List) {
            setState(() {
              _favorites = listingMapsFromApiList(data);
              _favorites.sort(
                (a, b) => _favoritedAtMs(b).compareTo(_favoritedAtMs(a)),
              );
              _loading = false;
            });
          }
        } catch (e, st) {
          logNonFatal(e, st);
        }
      }
      final decoded = await ApiService.getFavorites();
      final parsed = listingMapsFromFavoritesResponse(decoded);
      setState(() {
        _favorites = parsed;
        _favorites.sort(
          (a, b) => _favoritedAtMs(b).compareTo(_favoritedAtMs(a)),
        );
      });
      unawaited(sp.setString(cacheKey, json.encode(_favorites)));
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        setState(() {
          _loginRequired = true;
        });
      } else {
        setState(() {
          _error = AppLocalizations.of(context)!.failedToLoadListings;
        });
      }
    } catch (e) {
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)!.error,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
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
          _favorites.removeWhere((c) {
            final cid = (c['public_id'] ?? c['id'] ?? '').toString();
            return cid == carId;
          });
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
                    itemCount: _favorites.length,
                    itemBuilder: (context, index) {
                      final carMap = Map<String, dynamic>.from(
                        _favorites[index],
                      );
                      final card = buildGlobalCarCard(
                        context,
                        mapListingToGlobalCarCardData(context, carMap),
                        listLayout: listingColumns == 1,
                      );
                      final String carId =
                          (carMap['public_id'] ?? carMap['id'] ?? '')
                              .toString();
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
