import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../legacy/main_legacy.dart' show buildFloatingBottomNav, navigateMainShellTab;
import '../services/api_service.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/media/media_url.dart';

/// Browse and search approved dealerships (public API).
class DealersDirectoryPage extends StatefulWidget {
  const DealersDirectoryPage({super.key});

  @override
  State<DealersDirectoryPage> createState() => _DealersDirectoryPageState();
}

class _DealersDirectoryPageState extends State<DealersDirectoryPage> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasNext = false;
  static const int _perPage = 20;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _query.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load(refresh: true));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _tr(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) unawaited(_load(refresh: true));
    });
  }

  void _onScroll() {
    if (!_hasNext || _loadingMore || _loading) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 400) {
      unawaited(_loadMore());
    }
  }

  Future<void> _load({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _rows.clear();
      });
    }
    try {
      final data = await ApiService.searchDealers(
        q: _query.text,
        page: 1,
        perPage: _perPage,
      );
      final raw = data['dealers'];
      final list = raw is List ? raw : const <dynamic>[];
      final dealers = list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .toList();
      bool hasNext = false;
      final pag = data['pagination'];
      if (pag is Map && pag['has_next'] is bool) {
        hasNext = pag['has_next'] as bool;
      }
      if (!mounted) return;
      setState(() {
        _rows = dealers;
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
          fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
        );
        _loading = false;
        _loadingMore = false;
        if (refresh) _rows = [];
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasNext || _loadingMore || _loading) return;
    final next = _page + 1;
    setState(() => _loadingMore = true);
    try {
      final data = await ApiService.searchDealers(
        q: _query.text,
        page: next,
        perPage: _perPage,
      );
      final raw = data['dealers'];
      final list = raw is List ? raw : const <dynamic>[];
      final dealers = list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .toList();
      bool hasNext = false;
      final pag = data['pagination'];
      if (pag is Map && pag['has_next'] is bool) {
        hasNext = pag['has_next'] as bool;
      }
      if (!mounted) return;
      setState(() {
        _page = next;
        _rows.addAll(dealers);
        _hasNext = hasNext;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  String _avatarUrl(Map<String, dynamic> d) {
    final raw = (d['profile_picture'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    return buildMediaUrl(raw);
  }

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _tr(
                  'Search by name or location',
                  ar: 'ابحث بالاسم أو الموقع',
                  ku: 'گەڕان بە ناو یان شوێن',
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
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
                              SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
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
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              final d = _rows[i];
                              final id = (d['id'] ?? '').toString().trim();
                              final name =
                                  (d['dealership_name'] ?? '').toString().trim();
                              final location = (d['dealership_location'] ?? '')
                                  .toString()
                                  .trim();
                              final avatar = _avatarUrl(d);
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.surfaceContainerHighest,
                                  backgroundImage: avatar.isNotEmpty
                                      ? NetworkImage(avatar)
                                      : null,
                                  child: avatar.isEmpty
                                      ? Icon(
                                          Icons.storefront,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        )
                                      : null,
                                ),
                                title: Text(
                                  name.isNotEmpty ? name : id,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: location.isNotEmpty
                                    ? Text(
                                        location,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                                onTap: id.isEmpty
                                    ? null
                                    : () {
                                        Navigator.pushNamed(
                                          context,
                                          '/dealer/profile',
                                          arguments: {'dealerPublicId': id},
                                        );
                                      },
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
