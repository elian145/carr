import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../models/analytics_model.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/listings/listing_management.dart';
import '../shared/prefs/sell_listing_draft_prefs.dart';
import '../shared/text/pretty_title_case.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../legacy/main_legacy.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;

int _readLegacySellDraftStepForListings(dynamic raw, {int maxIdx = 4}) {
  if (raw == null) return 0;
  if (raw is int) return raw.clamp(0, maxIdx);
  if (raw is double) {
    if (raw.isNaN || raw.isInfinite) return 0;
    return raw.round().clamp(0, maxIdx);
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return 0;
  final d = double.tryParse(s);
  if (d != null) return d.round().clamp(0, maxIdx);
  return int.tryParse(s)?.clamp(0, maxIdx) ?? 0;
}

class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  static const String _draftSnapshotKey = 'legacy_sell_draft_snapshot_v1';
  static const String _draftCurrentStepKey = 'legacy_sell_draft_current_step_v1';
  final ScrollController _controller = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  String? _error;
  bool _loadingDraft = true;
  Map<String, dynamic>? _draftSnapshot;

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
    _loadDraftSnapshot();
    _controller.addListener(() {
      if (_loading || _loadingMore || !_hasNext) return;
      final pos = _controller.position;
      if (pos.pixels >= (pos.maxScrollExtent - 500)) {
        _loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch(refresh: true));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      final list = (data['cars'] is List) ? (data['cars'] as List) : const [];
      final items = list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .toList();

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

  Future<void> _loadDraftSnapshot() async {
    try {
      final ownerKey = _buildDraftOwnerKey();
      final modernDraft = await SellListingDraftPrefs.load(ownerKey);
      if (modernDraft != null && _hasMeaningfulDraftData(modernDraft)) {
        if (!mounted) return;
        setState(() {
          _draftSnapshot = <String, dynamic>{
            'currentStep': modernDraft['complete'] == true ? 4 : 0,
            'carData': modernDraft,
          };
          _loadingDraft = false;
        });
        return;
      }

      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftSnapshotKey);
      if (raw == null || raw.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _draftSnapshot = null;
          _loadingDraft = false;
        });
        return;
      }
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        if (!mounted) return;
        setState(() {
          _draftSnapshot = null;
          _loadingDraft = false;
        });
        return;
      }
      final map = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      final rawCarData = map['carData'];
      final carData = rawCarData is Map
          ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
          : <String, dynamic>{};
      final hasMeaningfulContent = carData.values.any((value) {
        if (value == null) return false;
        if (value is String) return value.trim().isNotEmpty;
        if (value is num) return value != 0;
        if (value is bool) return value;
        if (value is Iterable) return value.isNotEmpty;
        if (value is Map) return value.isNotEmpty;
        return value.toString().trim().isNotEmpty;
      });
      if (!mounted) return;
      if (!hasMeaningfulContent) {
        await sp.remove(_draftSnapshotKey);
        await sp.remove('legacy_sell_draft_current_step_v1');
        await sp.remove('legacy_sell_draft_step1_v1');
        await sp.remove('legacy_sell_draft_step2_v1');
        await sp.remove('legacy_sell_draft_step3_v1');
        await sp.remove('legacy_sell_draft_step4_v1');
        setState(() {
          _draftSnapshot = null;
          _loadingDraft = false;
        });
        return;
      }
      final prefsStep = sp.getInt(_draftCurrentStepKey);
      final j = _readLegacySellDraftStepForListings(map['currentStep']);
      final mergedStep = prefsStep == null
          ? j
          : (j > prefsStep.clamp(0, 4) ? j : prefsStep.clamp(0, 4));
      setState(() {
        _draftSnapshot = <String, dynamic>{
          if (map['draftId'] != null) 'draftId': map['draftId'],
          'currentStep': mergedStep,
          'carData': carData,
          if (map['isPlaceholder'] == true) 'isPlaceholder': true,
          if (map['updatedAt'] != null) 'updatedAt': map['updatedAt'],
        };
        _loadingDraft = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _draftSnapshot = null;
        _loadingDraft = false;
      });
    }
  }

  Future<void> _discardDraft() async {
    final ownerKey = _buildDraftOwnerKey();
    await SellListingDraftPrefs.clear(ownerKey);
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_draftSnapshotKey);
    await sp.remove('legacy_sell_draft_current_step_v1');
    await sp.remove('legacy_sell_draft_step1_v1');
    await sp.remove('legacy_sell_draft_step2_v1');
    await sp.remove('legacy_sell_draft_step3_v1');
    await sp.remove('legacy_sell_draft_step4_v1');
    if (!mounted) return;
    setState(() {
      _draftSnapshot = null;
    });
  }

  void _resumeDraft() {
    final snapshot = _draftSnapshot;
    if (snapshot != null && snapshot.isNotEmpty) {
      Navigator.pushNamed(
        context,
        '/sell',
        arguments: <String, dynamic>{
          'draftSnapshot': Map<String, dynamic>.from(snapshot),
        },
      );
      return;
    }
    Navigator.pushNamed(context, '/sell');
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

  Widget _buildDraftCard({required bool listLayout}) {
    final snapshot = _draftSnapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final carData = snapshot['carData'] is Map
        ? Map<String, dynamic>.from(
            (snapshot['carData'] as Map).cast<String, dynamic>(),
          )
        : <String, dynamic>{};
    final currentStep = int.tryParse(snapshot['currentStep']?.toString() ?? '') ?? 0;
    const labels = [
      'Step 1: Basic info',
      'Step 2: Details',
      'Step 3: Pricing',
      'Step 4: Photos',
      'Step 5: Review',
    ];
    final label = labels[currentStep.clamp(0, 4).toInt()];
    final draftListing = <String, dynamic>{
      ...carData,
      'title': _draftTitle(carData),
      'price': carData['price']?.toString().trim(),
      'images': (carData['images'] is List)
          ? List<dynamic>.from(carData['images'] as List)
          : (carData['image_paths'] is List)
              ? List<dynamic>.from(carData['image_paths'] as List)
          : const <dynamic>[],
      'videos': (carData['videos'] is List)
          ? List<dynamic>.from(carData['videos'] as List)
          : (carData['video_paths'] is List)
              ? List<dynamic>.from(carData['video_paths'] as List)
          : const <dynamic>[],
      'is_quick_sell': carData['is_quick_sell'] ?? false,
    };

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: buildGlobalCarCard(
              context,
              draftListing,
              listLayout: listLayout,
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _resumeDraft,
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.62),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'DRAFT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Material(
              color: Colors.black.withOpacity(0.62),
              shape: const CircleBorder(),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _discardDraft,
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: _text(
                  'Discard draft',
                  ar: 'حذف المسودة',
                  ku: 'سڕینەوەی ڕەشنووس',
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.62),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B00).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_car_outlined,
                size: 64,
                color: Color(0xFFFF6B00),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              loc?.noListingsYet ?? 'No listings yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              loc?.noListingsEmptyHint ??
                  'Create your first car listing to see it here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushReplacementNamed(context, '/sell'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(loc?.addYourFirstCar ?? 'Add your first car'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteListing(String carId) async {
    final deleted = await confirmAndDeleteListing(context, carId);
    if (!deleted || !mounted) return;
    setState(() {
      _cars.removeWhere((c) => listingMatchesId(c, carId));
    });
  }

  Future<void> _editListing(Map<String, dynamic> car) async {
    final carId = listingPrimaryId(car);
    if (carId.isEmpty) return;

    final updated = await openEditListingPage(context, car);
    if (!mounted || updated == null) return;
    setState(() {
      final idx = _cars.indexWhere((c) => listingMatchesId(c, carId));
      if (idx >= 0) _cars[idx] = {..._cars[idx], ...updated};
    });
  }

  Widget _ownerOverlayIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color background = const Color(0xCC000000),
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// Same full-cell card as home, with compact owner controls overlaid on top.
  Widget _buildOwnedListingTile({
    required Map<String, dynamic> car,
    required String id,
    required Widget card,
    required AppLocalizations? loc,
  }) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        card,
        if (id.isNotEmpty)
          Positioned(
            top: 6,
            left: 6,
            child: Material(
              color: const Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _showListingAnalyticsPopup(car, id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    loc?.analyticsTitle ?? 'Analytics',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (id.isNotEmpty)
          Positioned(
            top: 6,
            right: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ownerOverlayIcon(
                  icon: Icons.edit_outlined,
                  tooltip: loc?.editAction ?? 'Edit',
                  onTap: () => _editListing(car),
                ),
                const SizedBox(width: 4),
                _ownerOverlayIcon(
                  icon: Icons.delete_outline,
                  tooltip: loc?.deleteAction ?? 'Delete',
                  background: const Color(0xCCB3261E),
                  onTap: () => _deleteListing(id),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<ListingAnalytics> _fetchListingAnalytics(
    String listingId,
    Map<String, dynamic> car,
  ) async {
    try {
      final a = await AnalyticsService.getListingAnalytics(listingId);
      if (a.listingId.toString().isNotEmpty) return a;
      // If backend returned an empty id (unlikely), fall back to defaults.
    } catch (_) {
      // Fall through to fallback below.
    }

    // Fallback: try to find it within the user's listings analytics list.
    try {
      final all = await AnalyticsService.getUserListingsAnalytics();
      for (final a in all) {
        if (a.listingId.toString() == listingId) return a;
      }
    } catch (_) {
      // Ignore; we'll still show a dialog with safe defaults.
    }

    int parseInt(dynamic v, {int fallback = 0}) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    double parseDouble(dynamic v, {double fallback = 0}) {
      if (v == null) return fallback;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }

    return ListingAnalytics(
      listingId: listingId,
      title: (car['title'] ?? '').toString(),
      brand: (car['brand'] ?? '').toString(),
      model: (car['model'] ?? '').toString(),
      year: parseInt(car['year']),
      price: parseDouble(car['price']),
      imageUrl: null,
      mileage: null,
      city: (car['city'] ?? car['location'])?.toString(),
      views: 0,
      messages: 0,
      calls: 0,
      shares: 0,
      favorites: 0,
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
  }

  void _showListingAnalyticsPopup(
    Map<String, dynamic> car,
    String listingId,
  ) {
    final loc = AppLocalizations.of(context);
    if (listingId.isEmpty) return;

    final future = _fetchListingAnalytics(listingId, car);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(loc?.analyticsTitle ?? 'Analytics'),
          content: SizedBox(
            width: 360,
            child: FutureBuilder<ListingAnalytics>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(snapshot.error.toString());
                }
                final a = snapshot.data;
                if (a == null) return const Text('No analytics available.');

                Widget metricRow(
                  IconData icon,
                  String label,
                  String value,
                ) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: const Color(0xFFFF6B00)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                final title = (a.title).trim().isNotEmpty
                    ? prettyTitleCase(a.title)
                    : prettyTitleCase(a.carTitle);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    metricRow(Icons.visibility_outlined, 'Views', '${a.views}'),
                    metricRow(
                      Icons.message_outlined,
                      'Messages',
                      '${a.messages}',
                    ),
                    metricRow(Icons.phone_outlined, 'Calls', '${a.calls}'),
                    metricRow(Icons.share_outlined, 'Shares', '${a.shares}'),
                    metricRow(
                      Icons.favorite_outline,
                      'Favorites',
                      '${a.favorites}',
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc?.cancelAction ?? 'Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final auth = context.watch<AuthService>();

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final authenticatedBody = RefreshIndicator(
      onRefresh: () => _fetch(refresh: true),
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
                    final hasDraft = _draftSnapshot != null;
                    final totalCards = _cars.length + (hasDraft ? 1 : 0);
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
                                    childAspectRatio: listingColumns == 2
                                        ? (Platform.isIOS ? 0.66 : 0.61)
                                        : 2.78,
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

                                    if (hasDraft && index == 0) {
                                      return _buildDraftCard(
                                        listLayout: listingColumns == 1,
                                      );
                                    }

                                    final car = _cars[hasDraft ? index - 1 : index];
                                    final id = listingPrimaryId(car);

                                    final mapped = mapListingToGlobalCarCardData(
                                      context,
                                      car,
                                    );
                                    final card = buildGlobalCarCard(
                                      context,
                                      mapped,
                                      listLayout: listingColumns == 1,
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

