part of 'dealers_directory_page.dart';

mixin _DealersDirectoryPageLoad on _DealersDirectoryPageFields {
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
        perPage: _DealersDirectoryPageFields._perPage,
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
        perPage: _DealersDirectoryPageFields._perPage,
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
    } catch (e, st) { logNonFatal(e, st); 
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
}
