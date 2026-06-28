import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../models/analytics_model.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_events.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/prefs/sell_listing_draft_prefs.dart';
import '../shared/ui/responsive.dart';
import '../shared/prefs/sell_draft_media_persistence.dart';
import '../shared/prefs/legacy_sell_draft_list.dart';
import '../shared/text/pretty_title_case.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../features/listing/listing_mappers.dart';
import '../app/listing_shell.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;

part 'my_listings_page_widgets.dart';

class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  final ScrollController _controller = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  String? _error;
  bool _loadingDraft = true;
  List<Map<String, dynamic>> _drafts = <Map<String, dynamic>>[];

  final List<Map<String, dynamic>> _cars = <Map<String, dynamic>>[];

  String _text(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  @override
  void initState() {
    super.initState();
    // Keep consistent layout (grid vs list) with the rest of the app.
    ListingLayoutPrefs.load();
    _loadDrafts();
    _controller.addListener(() {
      if (_loading || _loadingMore || !_hasNext) return;
      final pos = _controller.position;
      if (pos.pixels >= (pos.maxScrollExtent - 500)) {
        _loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch(refresh: true));
    ListingEvents.deletedListingId.addListener(_onListingDeletedElsewhere);
  }

  @override
  void dispose() {
    ListingEvents.deletedListingId.removeListener(_onListingDeletedElsewhere);
    _controller.dispose();
    super.dispose();
  }

  void _onListingDeletedElsewhere() {
    final id = ListingEvents.deletedListingId.value;
    if (id == null || id.isEmpty || !mounted) return;
    setState(() {
      _cars.removeWhere((c) => listingMatchesId(c, id));
    });
  }

  Future<void> _fetch({required bool refresh}) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context)?.loginRequired ?? 'Login required';
      });
      return;
    }

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
      final data = await ApiService.getMyListings(page: _page, perPage: 20);
      final items = listingMapsFromApiResponse(data);

      bool hasNext = false;
      final pagination = data['pagination'];
      if (pagination is Map && pagination['has_next'] is bool) {
        hasNext = pagination['has_next'] as bool;
      } else {
        hasNext = items.length >= 20;
      }

      if (!mounted) return;
      setState(() {
        _cars.addAll(items);
        _hasNext = hasNext;
        _loading = false;
        _loadingMore = false;
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
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext) return;
    _page += 1;
    await _fetch(refresh: false);
  }

  Future<void> _loadDrafts() async {
    try {
      final drafts = <Map<String, dynamic>>[];
      final ownerKey = _buildDraftOwnerKey();
      final modernDraft = await SellListingDraftPrefs.load(ownerKey);
      if (modernDraft != null && _hasMeaningfulDraftData(modernDraft)) {
        drafts.add(<String, dynamic>{
          'draftId': 'modern_$ownerKey',
          'currentStep': modernDraft['complete'] == true ? 4 : 0,
          'carData': modernDraft,
          'isModern': true,
        });
      }
      drafts.addAll(await LegacySellDraftList.loadVisible());
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _loadingDraft = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _drafts = <Map<String, dynamic>>[];
        _loadingDraft = false;
      });
    }
  }

  Future<void> _discardDraft(Map<String, dynamic> draft) async {
    final draftId = (draft['draftId'] ?? '').toString();
    if (draft['isModern'] == true) {
      await SellListingDraftPrefs.clear(_buildDraftOwnerKey());
    } else {
      await LegacySellDraftList.discard(draft);
    }
    if (!mounted) return;
    setState(() {
      _drafts.removeWhere((item) => item['draftId']?.toString() == draftId);
    });
  }

  Future<void> _resumeDraft(Map<String, dynamic> draft) async {
    if (draft['isModern'] == true) {
      final carData = draft['carData'] is Map
          ? Map<String, dynamic>.from(
              (draft['carData'] as Map).cast<String, dynamic>(),
            )
          : <String, dynamic>{};
      await Navigator.pushNamed(
        context,
        '/sell',
        arguments: <String, dynamic>{
          'draftSnapshot': <String, dynamic>{
            'currentStep': draft['currentStep'] ?? 0,
            'carData': carData,
          },
        },
      );
    } else {
      final prepared = await LegacySellDraftList.prepareForResume(draft);
      if (!mounted) return;
      await Navigator.pushNamed(
        context,
        '/sell',
        arguments: <String, dynamic>{
          'draftSnapshot': prepared,
        },
      );
    }
    if (mounted) await _loadDrafts();
  }

  String _buildDraftOwnerKey() {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    final raw = (user?['public_id'] ??
            user?['id'] ??
            user?['username'] ??
            user?['email'] ??
            'guest')
        .toString()
        .trim();
    return raw.isEmpty ? 'guest' : raw;
  }

  bool _hasMeaningfulDraftData(Map<String, dynamic> data) {
    return data.values.any((value) {
      if (value == null) return false;
      if (value is String) return value.trim().isNotEmpty;
      if (value is num) return value != 0;
      if (value is bool) return value;
      if (value is Iterable) return value.isNotEmpty;
      if (value is Map) return value.isNotEmpty;
      return value.toString().trim().isNotEmpty;
    });
  }

  String _draftTitle(Map<String, dynamic> carData) {
    final brand = (carData['brand'] ?? '').toString().trim();
    final model = (carData['model'] ?? '').toString().trim();
    final trim = (carData['trim'] ?? '').toString().trim();
    final year = (carData['year'] ?? '').toString().trim();
    final title = [brand, model].where((v) => v.isNotEmpty).join(' ');
    final suffix = [trim, year].where((v) => v.isNotEmpty).join(' • ');
    if (title.isEmpty && suffix.isEmpty) return 'Untitled draft';
    if (title.isEmpty) return suffix;
    if (suffix.isEmpty) return title;
    return '$title • $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final auth = context.watch<AuthService>();

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final authenticatedBody = RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_fetch(refresh: true), _loadDrafts()]);
      },
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? ListView(
                  children: [
                    const SizedBox(height: 40),
                    Center(child: Text(_error!)),
                    const SizedBox(height: 12),
                    Center(
                      child: OutlinedButton(
                        onPressed: () => _fetch(refresh: true),
                        child: Text(loc?.retryAction ?? 'Retry'),
                      ),
                    ),
                  ],
                )
              : ValueListenableBuilder<int>(
                  valueListenable: ListingLayoutPrefs.columns,
                  builder: (context, cols, _) {
                    final listingColumns = (cols == 1) ? 1 : 2;
                    final draftCount = _drafts.length;
                    final totalCards = _cars.length + draftCount;
                    return Column(
                      children: [
                        Expanded(
                          child: totalCards == 0
                              ? ListView(
                                  controller: _controller,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    12,
                                  ),
                                  children: [
                                    if (_loadingDraft)
                                      const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 24),
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      )
                                    else
                                      _buildEmptyState(),
                                  ],
                                )
                              : GridView.builder(
                                  controller: _controller,
                                  padding: EdgeInsets.fromLTRB(
                                    listingColumns == 1 ? 4 : 8,
                                    8,
                                    listingColumns == 1 ? 4 : 8,
                                    8 + bottomInset,
                                  ),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: listingColumns,
                                    childAspectRatio:
                                        ListingLayoutPrefs.gridChildAspectRatio(
                                      listingColumns,
                                    ),
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                                  itemCount: totalCards + (_hasNext ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index >= totalCards) {
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

                                    if (index < draftCount) {
                                      return _buildDraftCard(
                                        _drafts[index],
                                        listLayout: listingColumns == 1,
                                      );
                                    }

                                    final car = _cars[index - draftCount];
                                    final id = listingPrimaryId(car);

                                    final mapped = mapListingToGlobalCarCardData(
                                      context,
                                      car,
                                    );
                                    final card = buildGlobalCarCard(
                                      context,
                                      mapped,
                                      listLayout: listingColumns == 1,
                                      allowOwnerManagementOnOpen: true,
                                    );

                                    return _buildOwnedListingTile(
                                      car: car,
                                      id: id,
                                      card: card,
                                      loc: loc,
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
    );

    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final bodyChild = !auth.isAuthenticated
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(loc?.loginRequired ?? 'Login required'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                    child: Text(loc?.loginAction ?? 'Login'),
                  ),
                ],
              ),
            ),
          )
        : authenticatedBody;

    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      appBar: AppBar(
        title: Text(loc?.myListingsTitle ?? 'My listings'),
      ),
      body: isLightShell
          ? bodyChild
          : Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
              child: bodyChild,
            ),
      floatingActionButton: auth.isAuthenticated
          ? FloatingActionButton(
              onPressed: () => Navigator.pushNamed(context, '/sell'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
