import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../legacy/main_legacy.dart' show buildFloatingBottomNav, navigateMainShellTab;
import '../services/api_service.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/media/media_url.dart';
import '../theme_provider.dart';

/// Browse and search approved dealerships (public API).
class DealersDirectoryPage extends StatefulWidget {
  const DealersDirectoryPage({super.key});

  @override
  State<DealersDirectoryPage> createState() => _DealersDirectoryPageState();
}

class _DealersDirectoryPageState extends State<DealersDirectoryPage> {
  static const Color _brandOrange = Color(0xFFFF6B00);

  final TextEditingController _query = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
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
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load(refresh: true));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.dispose();
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
    if (mounted) setState(() {});
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

  String _logoUrl(Map<String, dynamic> d) {
    final raw = (d['profile_picture'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    return buildMediaUrl(raw);
  }

  String _coverUrl(Map<String, dynamic> d) {
    final raw = (d['dealership_cover_picture'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    return buildMediaUrl(raw);
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final focused = _searchFocus.hasFocus;

    // One flat surface inside the border — avoid a second “grey panel” behind the text.
    final fill = isLight
        ? AppThemes.lightAppBackground
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.07),
            AppThemes.darkHomeShellBackground,
          );

    final borderColor = focused
        ? _brandOrange
        : scheme.outline.withValues(alpha: isLight ? 0.45 : 0.35);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor,
              width: focused ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isLight
                    ? _brandOrange.withValues(alpha: focused ? 0.12 : 0.04)
                    : Colors.black.withValues(alpha: 0.45),
                blurRadius: focused ? 16 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Row(
              children: [
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _brandOrange.withValues(alpha: isLight ? 0.1 : 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.search_rounded,
                      color: _brandOrange,
                      size: 22,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _query,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    cursorColor: _brandOrange,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      hintText: _tr(
                        'Search by name or location',
                        ar: 'ابحث بالاسم أو الموقع',
                        ku: 'گەڕان بە ناو یان شوێن',
                      ),
                      hintStyle: GoogleFonts.orbitron(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isLight
                            ? const Color(0xFF5C5C5C)
                            : scheme.onSurfaceVariant.withValues(alpha: 0.9),
                        letterSpacing: 0.2,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(context)
                                  .deleteButtonTooltip,
                              icon: Icon(
                                Icons.close_rounded,
                                color: scheme.onSurfaceVariant,
                                size: 22,
                              ),
                              onPressed: () {
                                _query.clear();
                                _searchFocus.requestFocus();
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
    );
  }

  Widget _dealerCard(BuildContext context, Map<String, dynamic> d) {
    final id = (d['id'] ?? '').toString().trim();
    final name = (d['dealership_name'] ?? '').toString().trim();
    final location = (d['dealership_location'] ?? '').toString().trim();
    final cover = _coverUrl(d);
    final logo = _logoUrl(d);
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    void openProfile() {
      if (id.isEmpty) return;
      Navigator.pushNamed(
        context,
        '/dealer/profile',
        arguments: {'dealerPublicId': id},
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: isLight
              ? Border.all(
                  color: scheme.outlineVariant,
                  width: 1,
                )
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          elevation: isLight ? 0 : 1,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: openProfile,
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: cover.isNotEmpty
                        ? Image.network(
                            cover,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.storefront,
                                size: 56,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(
                                Icons.storefront,
                                size: 56,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                            Colors.black.withValues(alpha: 0.78),
                          ],
                          stops: const [0.0, 0.35, 0.62, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Material(
                          elevation: 4,
                          shadowColor: Colors.black45,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: CircleAvatar(
                            radius: 30,
                            backgroundColor: scheme.surface,
                            child: CircleAvatar(
                              radius: 26,
                              backgroundColor: scheme.surfaceContainerHighest,
                              backgroundImage:
                                  logo.isNotEmpty ? NetworkImage(logo) : null,
                              child: logo.isEmpty
                                  ? Icon(
                                      Icons.business,
                                      color: scheme.onSurfaceVariant,
                                      size: 28,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name.isNotEmpty ? name : id,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      shadows: const [
                                        Shadow(
                                          blurRadius: 8,
                                          color: Colors.black54,
                                        ),
                                      ],
                                    ),
                              ),
                              if (location.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  location,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        shadows: const [
                                          Shadow(
                                            blurRadius: 6,
                                            color: Colors.black54,
                                          ),
                                        ],
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
