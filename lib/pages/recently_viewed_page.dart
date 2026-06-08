import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../legacy/main_legacy.dart'
    show buildGlobalCarCard, buildFloatingBottomNav, mapListingToGlobalCarCardData, navigateMainShellTab;
import '../services/api_service.dart';
import '../services/recently_viewed_service.dart';
import '../shared/auth/token_store.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_events.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/prefs/listing_layout_prefs.dart';

class RecentlyViewedPage extends StatefulWidget {
  const RecentlyViewedPage({super.key});

  @override
  State<RecentlyViewedPage> createState() => _RecentlyViewedPageState();
}

class _RecentlyViewedPageState extends State<RecentlyViewedPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _cars = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    ListingLayoutPrefs.load();
    _loadLocalFirst();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
    ListingEvents.deletedListingId.addListener(_onListingDeletedElsewhere);
  }

  @override
  void dispose() {
    ListingEvents.deletedListingId.removeListener(_onListingDeletedElsewhere);
    super.dispose();
  }

  void _onListingDeletedElsewhere() {
    final id = ListingEvents.deletedListingId.value;
    if (id == null || id.isEmpty || !mounted) return;
    setState(() {
      _cars.removeWhere((c) => listingMatchesId(c, id));
    });
  }

  Future<void> _loadLocalFirst() async {
    try {
      final local = await RecentlyViewedService.loadLocalDisplayList();
      if (!mounted || local.isEmpty) return;
      setState(() {
        _cars = local;
        _loading = false;
        _error = null;
      });
    } catch (_) {}
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() {
      _loading = _cars.isEmpty;
      _error = null;
    });
    try {
      await ApiService.initializeTokens();
      await TokenStore.load();
      final token = ApiService.accessToken ?? TokenStore.token;
      if (token == null || token.isEmpty) {
        final localOnly = await RecentlyViewedService.loadLocalDisplayList();
        if (!mounted) return;
        setState(() {
          _cars = localOnly;
          _loading = false;
          _error = localOnly.isEmpty
              ? (AppLocalizations.of(context)?.notLoggedIn ?? 'Not logged in')
              : null;
        });
        return;
      }
      final cars = await RecentlyViewedService.loadMerged();
      if (!mounted) return;
      setState(() {
        _cars = cars;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final fallback = await RecentlyViewedService.loadLocalDisplayList();
      setState(() {
        _cars = fallback;
        _loading = false;
        _error = fallback.isEmpty
            ? userErrorText(
                context,
                e,
                fallback:
                    AppLocalizations.of(context)?.failedToLoadListings ??
                    'Failed to load listings',
              )
            : null;
      });
    }
  }

  String _tr(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  Future<void> _confirmClearAll() async {
    final loc = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _tr(
            'Clear recently viewed?',
            ar: 'مسح السجل؟',
            ku: 'مێژووی بینین پاک بکەیتەوە؟',
          ),
        ),
        content: Text(
          _tr(
            'This removes all listings from your recently viewed history.',
            ar: 'سيؤدي هذا إلى إزالة جميع الإعلانات من سجل المشاهدة الأخيرة.',
            ku: 'ئەمە هەموو ڕیکلامەکان لە مێژووی بینینی دواتردا لادەبات.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.clearAll),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    await RecentlyViewedService.clearAll();
    if (!mounted) return;
    setState(() {
      _cars = [];
      _loading = false;
      _error = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            'Recently viewed cleared',
            ar: 'تم مسح السجل',
            ku: 'مێژووی بینین پاککرایەوە',
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemoveListing(String listingId) async {
    final loc = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _tr(
            'Remove from recently viewed?',
            ar: 'إزالة من السجل؟',
            ku: 'لە مێژووی بینین لاببرێت؟',
          ),
        ),
        content: Text(
          _tr(
            'This removes this listing from your recently viewed history.',
            ar: 'سيؤدي هذا إلى إزالة هذا الإعلان من سجل المشاهدة الأخيرة.',
            ku: 'ئەمە ئەم ڕیکلامە لە مێژووی بینینی دواتردا لادەبات.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.removeAction),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await RecentlyViewedService.removeOne(listingId);
    if (!mounted) return;
    setState(() {
      _cars = _cars
          .where((c) => !listingMatchesId(c, listingId))
          .toList();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            'Removed from recently viewed',
            ar: 'تمت الإزالة من السجل',
            ku: 'لە مێژووی بینین لابرا',
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: theme.colorScheme.onSurface.withOpacity(0.35),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListingGrid() {
    final loc = AppLocalizations.of(context)!;
    return ValueListenableBuilder<int>(
      valueListenable: ListingLayoutPrefs.columns,
      builder: (context, cols, _) {
        final listingColumns = (cols == 1) ? 1 : 2;
        final horizontalPadding = listingColumns == 1 ? 4.0 : 8.0;

        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            8,
            horizontalPadding,
            100,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: listingColumns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio:
                ListingLayoutPrefs.gridChildAspectRatio(listingColumns),
          ),
          itemCount: _cars.length,
          itemBuilder: (context, index) {
            final car = Map<String, dynamic>.from(_cars[index]);
            final cardData = mapListingToGlobalCarCardData(context, car);
            final listingId = listingPrimaryId(car);
            final card = buildGlobalCarCard(
              context,
              cardData,
              listLayout: listingColumns == 1,
            );
            if (listingId.isEmpty) return card;
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
                      onTap: () => _confirmRemoveListing(listingId),
                      child: Tooltip(
                        message: loc.deleteTooltip,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 22,
                          ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final title = _tr(
      'Recently viewed',
      ar: 'شوهد مؤخراً',
      ku: 'دواتر بینراو',
    );
    final empty = _tr(
      'You have not viewed any listings yet.\nOpen a car listing to add it here.',
      ar: 'لم تشاهد أي إعلانات بعد.\nافتح إعلان سيارة لإضافته هنا.',
      ku: 'هێشتا هیچ ڕیکلامێکت نەبینيوە.\nڕیکلامێکی ئۆتۆمبێل بکەرەوە بۆ زیادکردنی لێرە.',
    );

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _fetch,
                child: Text(loc.retryAction),
              ),
            ],
          ),
        ),
      );
    } else if (_cars.isEmpty) {
      body = _buildEmptyState(empty);
    } else {
      body = RefreshIndicator(
        onRefresh: _fetch,
        child: _buildListingGrid(),
      );
    }

    final loggedIn =
        ApiService.accessToken != null && ApiService.accessToken!.isNotEmpty;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => navigateMainShellTab(
            context,
            loggedIn ? '/profile' : '/login',
          ),
        ),
        title: Text(title),
        actions: [
          if (_cars.isNotEmpty && !_loading)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: loc.clearAll,
              onPressed: _confirmClearAll,
            ),
        ],
      ),
      body: body,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        solidBackground: true,
        onTap: (idx) {
          switch (idx) {
            case 0:
              navigateMainShellTab(context, '/');
              break;
            case 1:
              navigateMainShellTab(context, '/favorites');
              break;
            case 2:
              navigateMainShellTab(context, '/dealers');
              break;
            case 3:
              navigateMainShellTab(
                context,
                loggedIn ? '/profile' : '/login',
              );
              break;
          }
        },
      ),
    );
  }
}
