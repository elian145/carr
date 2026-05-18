import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../legacy/main_legacy.dart'
    show buildGlobalCarCard, buildFloatingBottomNav, mapListingToGlobalCarCardData, navigateMainShellTab;
import '../services/api_service.dart';
import '../services/recently_viewed_service.dart';
import '../shared/auth/token_store.dart';
import '../shared/errors/user_error_text.dart';
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

  double _listCardHeight(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width - 24;
    return (w > 0 ? w : 360) / 2.78;
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
    final cardHeight = _listCardHeight(context);

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
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          itemCount: _cars.length,
          itemBuilder: (context, index) {
            final car = Map<String, dynamic>.from(_cars[index]);
            final cardData = mapListingToGlobalCarCardData(context, car);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                height: cardHeight,
                child: buildGlobalCarCard(
                  context,
                  cardData,
                  listLayout: true,
                ),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 0,
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
              final loggedIn =
                  ApiService.accessToken != null &&
                  ApiService.accessToken!.isNotEmpty;
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
