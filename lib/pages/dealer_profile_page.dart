import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../navigation/app_page_route.dart';
import '../app/listing_shell.dart'
    show
        FullScreenGalleryPage,
        buildGlobalCarCard,
        mapListingToGlobalCarCardData;
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../shared/maps/dealer_map_coords.dart';
import '../shared/maps/open_google_maps.dart';
import '../shared/i18n/opening_hours_time_parse.dart';
import '../shared/media/media_url.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../shared/ui/responsive.dart';
import '../features/listing/listing_mappers.dart';
import '../shared/errors/user_error_text.dart';
import '../theme_provider.dart';
import '../widgets/dealer_location_map_preview.dart';
import 'edit_dealer_page.dart';
import '../shared/trust/report_dialog.dart';
import '../shared/debug/app_log.dart';

part 'dealer_profile_page_helpers.dart';

class DealerProfilePage extends StatefulWidget {
  final String dealerPublicId;

  /// When false (default), the owner cannot edit from this browse view.
  final bool allowOwnerEdit;

  /// Shows the public-facing page without owner-only behavior.
  final bool previewAsVisitor;

  const DealerProfilePage({
    super.key,
    required this.dealerPublicId,
    this.allowOwnerEdit = false,
    this.previewAsVisitor = false,
  });

  @override
  State<DealerProfilePage> createState() => _DealerProfilePageState();
}

class _DealerProfilePageState extends State<DealerProfilePage> {
  _DealerSection _section = _DealerSection.listings;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _dealer;
  List<Map<String, dynamic>> _listings = const [];

  @override
  void initState() {
    super.initState();
    ListingLayoutPrefs.load();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getDealerProfile(widget.dealerPublicId);
      final dealerRaw = data['dealer'];
      final listingsRaw = data['listings'];
      setState(() {
        _dealer = dealerRaw is Map
            ? Map<String, dynamic>.from(dealerRaw.cast<String, dynamic>())
            : null;
        _listings = listingsRaw is List
            ? listingMapsFromApiList(listingsRaw)
            : <Map<String, dynamic>>[];
      });
    } catch (e) {
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback:
              AppLocalizations.of(context)?.failedToLoadListings ??
              'Failed to load listings',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectSection(_DealerSection section) {
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final dealer = _dealer;
    final dealershipName = (dealer?['dealership_name'] ?? '').toString().trim();
    final firstName = (dealer?['first_name'] ?? '').toString().trim();
    final lastName = (dealer?['last_name'] ?? '').toString().trim();
    final fallbackName = ('$firstName $lastName').trim();
    final displayName = dealershipName.isNotEmpty
        ? dealershipName
        : (fallbackName.isNotEmpty
              ? fallbackName
              : _tr('Dealer', ar: 'وكيل', ku: 'وەکیل'));
    final logoUrl = buildMediaUrl(
      (dealer?['profile_picture'] ?? '').toString().trim(),
    );
    final coverUrl = buildMediaUrl(
      (dealer?['dealership_cover_picture'] ?? '').toString().trim(),
    );
    final bannerUrl = coverUrl.isNotEmpty ? coverUrl : _firstListingImage();
    final location =
        (dealer?['dealership_location'] ?? dealer?['location'] ?? '')
            .toString()
            .trim();
    final double? mapLat = parseDealerCoord(dealer?['dealership_latitude']);
    final double? mapLng = parseDealerCoord(dealer?['dealership_longitude']);
    final phones = _phonesFromAnySource(dealer);
    final email = (dealer?['email'] ?? '').toString().trim();
    final description = (dealer?['dealership_description'] ?? '')
        .toString()
        .trim();
    final currentUserPublicId =
        (auth.currentUser?['public_id'] ??
                auth.currentUser?['id'] ??
                auth.currentUser?['user_id'] ??
                '')
            .toString()
            .trim();
    final isActualDealerOwner =
        auth.isAuthenticated && currentUserPublicId == widget.dealerPublicId;
    final isDealerOwner = isActualDealerOwner && !widget.previewAsVisitor;
    final openingHours = _openingHoursFromAnySource(
      dealer,
      _listings,
      auth.currentUser,
      isDealerOwner,
    );
    final isLightShell = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Dealer', ar: 'الوكيل', ku: 'وەکیل')),
        actions: [
          if (auth.isAuthenticated && !isActualDealerOwner)
            IconButton(
              tooltip: _tr(
                'Report user',
                ar: 'الإبلاغ عن المستخدم',
                ku: 'ڕاپۆرتکردنی بەکارهێنەر',
              ),
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => showReportUserDialog(
                context,
                userPublicId: widget.dealerPublicId,
              ),
            ),
        ],
      ),
      backgroundColor: isLightShell ? AppThemes.lightAppBackground : null,
      body: Stack(
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: Text(
                          AppLocalizations.of(context)?.retryAction ?? 'Retry',
                        ),
                      ),
                    ],
                  )
                : ListView(
                    children: [
                      _buildDealerHero(
                        bannerUrl: bannerUrl,
                        logoUrl: logoUrl,
                        displayName: displayName,
                        isLightShell: isLightShell,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    height: 1.15,
                                    color: isLightShell
                                        ? AppThemes.darkHomeShellBackground
                                        : const Color(0xFFF7F7F7),
                                  ),
                            ),
                            if (location.isNotEmpty ||
                                _listings.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (location.isNotEmpty)
                                    _metaChip(
                                      icon: Icons.location_on_rounded,
                                      label: location,
                                      isLight: isLightShell,
                                    ),
                                  _metaChip(
                                    icon: Icons.directions_car_filled_rounded,
                                    label: _listings.length == 1
                                        ? _tr(
                                            '1 listing',
                                            ar: 'إعلان واحد',
                                            ku: '١ ڕێکلام',
                                          )
                                        : _tr(
                                            '${_listings.length} listings',
                                            ar: '${_listings.length} إعلانات',
                                            ku: '${_listings.length} ڕێکلام',
                                          ),
                                    isLight: isLightShell,
                                  ),
                                ],
                              ),
                            ],
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                description,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      height: 1.4,
                                      color: isLightShell
                                          ? const Color(0xFF5C5C5C)
                                          : const Color(0xFFD8D8D8),
                                    ),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (widget.allowOwnerEdit && isDealerOwner) ...[
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFFF6B00),
                                  side: BorderSide(
                                    color: const Color(
                                      0xFFFF6B00,
                                    ).withValues(alpha: 0.45),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () async {
                                  final changed = await Navigator.push<bool>(
                                    context,
                                    AppPageRoute(
                                      builder: (_) => const EditDealerPage(),
                                    ),
                                  );
                                  if (changed == true) {
                                    await _load();
                                  }
                                },
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: Text(
                                  _tr(
                                    'Edit dealer page',
                                    ar: 'تعديل صفحة الوكيل',
                                    ku: 'دەستکاری پەڕەی وەکیل',
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _buildSectionControl(isLightShell),
                            const SizedBox(height: 16),
                            if (_section == _DealerSection.about)
                              _buildAboutSection(
                                phones: phones,
                                email: email,
                                location: location,
                                mapLat: mapLat,
                                mapLng: mapLng,
                                openingHours: openingHours,
                                isLightShell: isLightShell,
                              ),
                          ],
                        ),
                      ),
                      if (_section == _DealerSection.listings) ...[
                        if (_listings.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 28,
                              ),
                              decoration: _softCardDecoration(isLightShell),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.directions_car_outlined,
                                    size: 36,
                                    color: const Color(
                                      0xFFFF6B00,
                                    ).withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _tr(
                                      'No active vehicles right now.',
                                      ar: 'لا توجد مركبات نشطة حالياً.',
                                      ku: 'لە ئێستادا هیچ ئۆتۆمبێلێکی چالاک نییە.',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isLightShell
                                          ? const Color(0xFF5C5C5C)
                                          : Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ValueListenableBuilder<int>(
                            valueListenable: ListingLayoutPrefs.columns,
                            builder: (context, cols, _) {
                              final screenWidth = MediaQuery.sizeOf(
                                context,
                              ).width;
                              final listingColumns =
                                  ListingLayoutPrefs.effectiveColumnsForWidth(
                                    cols == 1 ? 1 : 2,
                                    screenWidth,
                                  );
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.fromLTRB(
                                  listingColumns == 1 ? 4 : 12,
                                  0,
                                  listingColumns == 1 ? 4 : 12,
                                  16,
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: listingColumns,
                                      childAspectRatio:
                                          ListingLayoutPrefs.gridChildAspectRatioForWidth(
                                            listingColumns,
                                            screenWidth,
                                          ),
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                    ),
                                itemCount: _listings.length,
                                itemBuilder: (context, index) {
                                  final item = _listings[index];
                                  final mapped = mapListingToGlobalCarCardData(
                                    context,
                                    item,
                                  );
                                  return buildGlobalCarCard(
                                    context,
                                    mapped,
                                    listLayout: listingColumns == 1,
                                  );
                                },
                              );
                            },
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

enum _DealerSection { about, listings }
