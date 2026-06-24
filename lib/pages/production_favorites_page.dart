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
    } catch (e, st) { logNonFatal(e, st); 
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
        } catch (e, st) { logNonFatal(e, st); }
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
    } catch (e, st) { logNonFatal(e, st); }
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
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
              ),
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
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            )
          else if (_favorites.isEmpty)
            Center(
              child: Text(
                AppLocalizations.of(context)!.noFavoritesYet,
                style: TextStyle(color: muted),
              ),
            )
          else
            RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: _loadFavorites,
              child: ValueListenableBuilder<int>(
                valueListenable: ListingLayoutPrefs.columns,
                builder: (context, cols, _) {
                  final listingColumns = (cols == 1) ? 1 : 2;
                  return GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 110),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: listingColumns,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio:
                          ListingLayoutPrefs.gridChildAspectRatio(
                        listingColumns,
                      ),
                    ),
                    itemCount: _favorites.length,
                    itemBuilder: (context, index) {
                      final carMap = Map<String, dynamic>.from(_favorites[index]);
                      final card = buildGlobalCarCard(
                        context,
                        mapListingToGlobalCarCardData(context, carMap),
                        listLayout: listingColumns == 1,
                      );
                      final String carId =
                          (carMap['public_id'] ?? carMap['id'] ?? '').toString();
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
                                    color: Color(0xFFFF6B00),
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
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 1,
        onTap: (idx) {
          switch (idx) {
            case 0:
              navigateMainShellTab(context, '/');
              break;
            case 1:
              // Already on favorites
              break;
            case 2:
              navigateMainShellTab(context, '/dealers');
              break;
            case 3:
              navigateMainShellTab(context, '/profile');
              break;
          }
        },
      ),
    );
  }
}
