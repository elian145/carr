import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../legacy/main_legacy.dart'
    show buildGlobalCarCard, buildFloatingBottomNav, mapListingToGlobalCarCardData, navigateMainShellTab;
import '../services/api_service.dart';
import '../services/recently_viewed_service.dart';
import '../shared/auth/token_store.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../theme_provider.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService.initializeTokens();
      await TokenStore.load();
      final token = ApiService.accessToken ?? TokenStore.token;
      if (token == null || token.isEmpty) {
        final localOnly = await RecentlyViewedService.loadMerged();
        if (!mounted) return;
        setState(() {
          _cars = localOnly;
          _loading = false;
          _error = _cars.isEmpty
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
      });
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
      });
    }
  }

  String _tr(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
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
      'You have not viewed any listings yet.',
      ar: 'لم تشاهد أي إعلانات بعد.',
      ku: 'هێشتا هیچ ڕیکلامێکت نەبینيوە.',
    );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      extendBody: true,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
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
            )
          : _cars.isEmpty
          ? Center(child: Text(empty, style: TextStyle(color: Colors.grey[600])))
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                itemCount: _cars.length,
                itemBuilder: (context, index) {
                  final car = Map<String, dynamic>.from(_cars[index]);
                  final cardData = mapListingToGlobalCarCardData(context, car);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: buildGlobalCarCard(
                      context,
                      cardData,
                      listLayout: true,
                    ),
                  );
                },
              ),
            ),
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
