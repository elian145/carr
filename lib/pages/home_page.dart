import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme_provider.dart';
import '../shared/home/home_listings_fetch.dart';
import '../shared/home/home_filter_persistence.dart';
import '../shared/home/saved_search_apply.dart';
import '../shared/home/home_active_filter_chips.dart';
import '../shared/home/home_feed_toolbar.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../shared/shell/home_feed_scroll_persistence.dart';
import '../shared/shell/main_bottom_nav.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/media/media_url.dart';
import '../shared/listings/global_listing_card.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin<HomePage> {
  final ScrollController _controller = ScrollController();

  // Route replacement recreates Home; keep an in-memory snapshot for exact restore.
  static List<Map<String, dynamic>> _cacheCars = <Map<String, dynamic>>[];
  static bool _cacheHasNext = true;
  static int _cachePage = 1;
  static double _cacheOffset = 0;

  final List<Map<String, dynamic>> _cars = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  String? _error;
  int _activeFilterCount = 0;
  List<HomeActiveFilterChipSpec> _filterChips = const [];
  String? _selectedSortBy;

  static const int _perPage = 20;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ListingLayoutPrefs.load();

    _controller.addListener(() {
      if (_controller.hasClients) {
        HomeFeedScrollPersistence.savePixels(_controller.offset);
        _cacheOffset = _controller.offset;
      }
      if (!_hasNext || _loadingMore || _loading) return;
      final pos = _controller.position;
      if (pos.pixels >= (pos.maxScrollExtent - 500)) {
        _loadMore();
      }
    });

    if (_cacheCars.isNotEmpty) {
      _cars
        ..clear()
        ..addAll(_cacheCars.map((e) => Map<String, dynamic>.from(e)));
      _hasNext = _cacheHasNext;
      _page = _cachePage;
      _loading = false;
      _loadingMore = false;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScrollOffset());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _applyPendingSavedSearchIfNeeded();
        if (!mounted) return;
        if (_cars.isEmpty) {
          await _fetch(refresh: true);
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshFilterState();
    });
  }

  Future<void> _applyPendingSavedSearchIfNeeded() async {
    final oneTime = await SavedSearchApply.consumeOneTimeFilters();
    final pending = await SavedSearchApply.consumePendingFetch();
    if (oneTime != null) {
      await HomeFilterPersistence.saveMap(oneTime);
    }
    if (!mounted) return;
    if (oneTime != null || pending) {
      _cacheCars.clear();
      _cacheHasNext = true;
      _cachePage = 1;
      _cacheOffset = 0;
      HomeFeedScrollPersistence.markTop();
      await _refreshFilterState();
    }
  }

  Future<void> _refreshFilterState() async {
    final map = await HomeFilterPersistence.loadMap();
    if (!mounted) return;
    final specs = homeActiveFilterChipSpecs(context, map);
    final sortRaw = map['sort_by']?.toString().trim();
    setState(() {
      _filterChips = specs;
      _activeFilterCount = specs.length;
      _selectedSortBy =
          (sortRaw != null && sortRaw.isNotEmpty) ? sortRaw : null;
    });
  }

  Future<void> _applySort(String? localizedSort) async {
    await HomeFilterPersistence.updateSort(localizedSort);
    if (!mounted) return;
    await _refreshFilterState();
    await _fetch(refresh: true);
  }

  Future<void> _applyLayoutColumns(int columns) async {
    await ListingLayoutPrefs.setColumns(columns);
    if (mounted) setState(() {});
  }

  Future<void> _clearHomeFilter(String filterType) async {
    await HomeFilterPersistence.clearFilter(filterType);
    if (!mounted) return;
    await _refreshFilterState();
    await _fetch(refresh: true);
  }

  @override
  void dispose() {
    _persistCacheSnapshot();
    _controller.dispose();
    super.dispose();
  }

  void _persistCacheSnapshot() {
    _cacheCars = _cars.map((e) => Map<String, dynamic>.from(e)).toList();
    _cacheHasNext = _hasNext;
    _cachePage = _page;
    if (_controller.hasClients) {
      _cacheOffset = _controller.offset;
    }
  }

  void _restoreScrollOffset() {
    if (!_controller.hasClients || _cacheOffset <= 0) return;
    final max = _controller.position.maxScrollExtent;
    final target = _cacheOffset.clamp(0, max).toDouble();
    _controller.jumpTo(target);
    // If layout expands after first frame, retry once to reach exact previous offset.
    if (target < _cacheOffset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final max2 = _controller.position.maxScrollExtent;
        _controller.jumpTo(_cacheOffset.clamp(0, max2).toDouble());
      });
    }
  }

  Future<void> _fetch({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasNext = true;
        _cars.clear();
      });
    } else {
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }

    try {
      final result = await fetchHomeListingsPage(
        page: _page,
        perPage: _perPage,
        context: context,
      );

      if (!mounted) return;
      setState(() {
        _cars.addAll(result.cars);
        _hasNext = result.hasNext;
        _loading = false;
        _loadingMore = false;
      });
      _persistCacheSnapshot();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback:
              AppLocalizations.of(context)?.failedToLoadListings ??
              'Failed to load listings',
        );
        _loading = false;
        _loadingMore = false;
      });
      _persistCacheSnapshot();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext) return;
    _page += 1;
    await _fetch(refresh: false);
  }

  Widget _carImage(Map<String, dynamic> car) {
    final primary = (car['image_url'] ?? '').toString();
    final url = buildMediaUrl(primary);
    if (url.isEmpty) {
      return Container(
        color: Colors.black12,
        child: const Center(child: Icon(Icons.directions_car)),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.black12,
          child: const Center(child: Icon(Icons.broken_image)),
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black12,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }

  void _onShellTab(int idx) {
    if (idx == 0) {
      if (_controller.hasClients) {
        _controller.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
      HomeFeedScrollPersistence.markTop();
      return;
    }
    HomeFeedScrollPersistence.capture(_controller);
    final route = switch (idx) {
      1 => '/favorites',
      2 => '/dealers',
      3 => '/profile',
      _ => '/',
    };
    Navigator.of(context).pushReplacementNamed(route);
  }

  Future<void> _openFilters() async {
    final changed = await Navigator.of(context).pushNamed('/home_filters');
    if (!mounted) return;
    await _refreshFilterState();
    if (changed == true) {
      await _fetch(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final loc = AppLocalizations.of(context);
    final title = loc?.appTitle ?? 'CarNet';

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 18)),
        titleSpacing: NavigationToolbar.kMiddleSpacing,
        actions: [
          IconButton(
            tooltip: loc?.moreFilters ?? 'Filters',
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount'),
              child: const Icon(Icons.tune),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              end: NavigationToolbar.kMiddleSpacing,
            ),
            child: OutlinedButton.icon(
              onPressed: () {
                HomeFeedScrollPersistence.capture(_controller);
                Navigator.of(context).pushReplacementNamed('/sell');
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                loc?.sellButton ?? 'Sell',
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
        ],
      ),
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 0,
        onTap: _onShellTab,
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
            RefreshIndicator(
              onRefresh: () async {
                await _fetch(refresh: true);
                await _refreshFilterState();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildHomeActiveFilterChipWrap(
                    context,
                    specs: _filterChips,
                    onClearFilterType: _clearHomeFilter,
                  ),
                  buildHomeFeedToolbarWithLayoutListener(
                    context: context,
                    selectedSortBy: _selectedSortBy,
                    onSortSelected: _applySort,
                    onLayoutSelected: _applyLayoutColumns,
                  ),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: ListingLayoutPrefs.columns,
                      builder: (context, listingColumns, _) {
                        return _buildHomeScrollContent(
                          context,
                          loc: loc,
                          listingColumns: listingColumns,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeScrollContent(
    BuildContext context, {
    required AppLocalizations? loc,
    required int listingColumns,
  }) {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_cars.isEmpty && _error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Text(
              _error!,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: () => _fetch(refresh: true),
              child: Text(loc?.retryAction ?? 'Retry'),
            ),
          ),
        ],
      );
    }
    if (_cars.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Text(
              loc?.noCarsFound ?? 'No cars found',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    return GridView.builder(
      controller: _controller,
      key: const PageStorageKey<String>('home_grid'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: listingColumns == 1 ? 1 : 2,
        childAspectRatio: ListingLayoutPrefs.gridChildAspectRatio(
          listingColumns == 1 ? 1 : 2,
        ),
        crossAxisSpacing: listingColumns == 1 ? 4 : 8,
        mainAxisSpacing: listingColumns == 1 ? 4 : 8,
      ),
      itemCount: _cars.length + (_hasNext ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _cars.length) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final car = _cars[index];
        final card = buildGlobalCarCard(
          context,
          car,
          listLayout: listingColumns == 1,
        );
        if (listingColumns == 3) {
          return GestureDetector(
            onTap: () {
              Navigator.pushNamed(
                context,
                '/tiktok_scroll',
                arguments: {
                  'cars': _cars,
                  'initialIndex': index,
                },
              );
            },
            child: AbsorbPointer(child: card),
          );
        }
        return card;
      },
    );
  }
}

