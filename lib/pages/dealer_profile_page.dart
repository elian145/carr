import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../navigation/app_page_route.dart';
import '../app/listing_shell.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../shared/maps/dealer_map_coords.dart';
import '../shared/maps/open_google_maps.dart';
import '../shared/media/media_url.dart';
import '../shared/prefs/listing_layout_prefs.dart';
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

  const DealerProfilePage({
    super.key,
    required this.dealerPublicId,
    this.allowOwnerEdit = false,
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
        : (fallbackName.isNotEmpty ? fallbackName : _tr('Dealer', ar: 'وكيل', ku: 'وەکیل'));
    final logoUrl = buildMediaUrl((dealer?['profile_picture'] ?? '').toString().trim());
    final coverUrl = buildMediaUrl(
      (dealer?['dealership_cover_picture'] ?? '').toString().trim(),
    );
    final bannerUrl = coverUrl.isNotEmpty ? coverUrl : _firstListingImage();
    final location = (dealer?['dealership_location'] ?? dealer?['location'] ?? '')
        .toString()
        .trim();
    final double? mapLat = parseDealerCoord(dealer?['dealership_latitude']);
    final double? mapLng = parseDealerCoord(dealer?['dealership_longitude']);
    final phones = _phonesFromAnySource(dealer);
    final email = (dealer?['email'] ?? '').toString().trim();
    final description = (dealer?['dealership_description'] ?? '').toString().trim();
    final currentUserPublicId = (auth.currentUser?['public_id'] ??
            auth.currentUser?['id'] ??
            auth.currentUser?['user_id'] ??
            '')
        .toString()
        .trim();
    final isDealerOwner =
        auth.isAuthenticated && currentUserPublicId == widget.dealerPublicId;
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
          if (auth.isAuthenticated && !isDealerOwner)
            IconButton(
              tooltip: _tr('Report user', ar: 'الإبلاغ عن المستخدم', ku: 'ڕاپۆرتکردنی بەکارهێنەر'),
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
                          FilledButton(onPressed: _load, child: Text(AppLocalizations.of(context)?.retryAction ?? 'Retry')),
                        ],
                      )
                    : ListView(
                        children: [
                      SizedBox(
                        height: bannerUrl.isNotEmpty ? 188 : 148,
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: bannerUrl.isNotEmpty
                                  ? Image.network(
                                      bannerUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const ColoredBox(color: Colors.black12),
                                    )
                                  : const ColoredBox(color: Colors.black12),
                            ),
                            if (bannerUrl.isNotEmpty)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.5),
                                    ],
                                  ),
                                ),
                              ),
                            Positioned(
                              left: 16,
                              bottom: 12,
                              child: Material(
                                elevation: 6,
                                shadowColor: Colors.black45,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: CircleAvatar(
                                  radius: 36,
                                  backgroundColor: Theme.of(context).colorScheme.surface,
                                  child: CircleAvatar(
                                    radius: 32,
                                    backgroundImage: logoUrl.isNotEmpty
                                        ? NetworkImage(logoUrl)
                                        : null,
                                    child: logoUrl.isEmpty
                                        ? Text(
                                            displayName.isNotEmpty
                                                ? displayName[0].toUpperCase()
                                                : 'D',
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                description,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (widget.allowOwnerEdit && isDealerOwner) ...[
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
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
                                icon: const Icon(Icons.edit_outlined),
                                label: Text(_tr('Edit dealer page', ar: 'تعديل صفحة الوكيل', ku: 'دەستکاری پەڕەی وەکیل')),
                              ),
                            ],
                            const SizedBox(height: 12),
                            SegmentedButton<_DealerSection>(
                              segments: [
                                ButtonSegment(
                                  value: _DealerSection.listings,
                                  label: Text(_tr('Listings', ar: 'الإعلانات', ku: 'ڕێکلامەکان')),
                                ),
                                ButtonSegment(
                                  value: _DealerSection.about,
                                  label: Text(_tr('About', ar: 'حول', ku: 'دەربارە')),
                                ),
                              ],
                              selected: {_section},
                              onSelectionChanged: (s) {
                                if (s.isEmpty) return;
                                setState(() => _section = s.first);
                              },
                            ),
                            const SizedBox(height: 12),
                            if (_section == _DealerSection.about) ...[
                            if (phones.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var i = 0; i < phones.length; i++)
                                      Padding(
                                        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                                        child: Tooltip(
                                          message: _tr('Tap to call • Hold to copy', ar: 'اضغط للاتصال • اضغط مطولاً للنسخ', ku: 'کرتە بکە بۆ پەیوەندی • چەند چرکە هەڵبگرە بۆ کۆپی'),
                                          child: SizedBox(
                                            width: double.infinity,
                                            child: FilledButton.icon(
                                              onPressed: () =>
                                                  _callDealer(phones[i]),
                                              onLongPress: () =>
                                                  _copyToClipboard(
                                                phones[i],
                                                _tr('Phone number copied to clipboard', ar: 'تم نسخ رقم الهاتف', ku: 'ژمارەی تەلەفۆن کۆپی کرا'),
                                              ),
                                              icon: const Icon(
                                                Icons.phone_outlined,
                                              ),
                                              label: Text(
                                                phones[i],
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            _infoRow(
                              Icons.location_on_outlined,
                              _tr('Location', ar: 'الموقع', ku: 'شوێن'),
                              location,
                            ),
                            if (mapLat != null &&
                                mapLng != null &&
                                isValidDealerLatLng(mapLat, mapLng)) ...[
                              const SizedBox(height: 10),
                              DealerLocationMapPreview(
                                latitude: mapLat,
                                longitude: mapLng,
                                onOpenInGoogleMaps: () => _openDealerOnGoogleMaps(
                                  mapLat,
                                  mapLng,
                                ),
                              ),
                            ],
                            if (email.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Tooltip(
                                  message: _tr('Tap to send email • Hold to copy', ar: 'اضغط لإرسال بريد • اضغط مطولاً للنسخ', ku: 'کرتە بکە بۆ ناردنی ئیمەیل • چەند چرکە هەڵبگرە بۆ کۆپی'),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _emailDealer(email),
                                      onLongPress: () => _copyToClipboard(
                                        email,
                                        _tr('Email copied to clipboard', ar: 'تم نسخ البريد الإلكتروني', ku: 'ئیمەیل کۆپی کرا'),
                                      ),
                                      icon: const Icon(Icons.email_outlined),
                                      label: Text(
                                        email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            _openingHoursTable(openingHours),
                            ],
                          ],
                        ),
                      ),
                      if (_section == _DealerSection.listings) ...[
                        const Divider(height: 1),
                        if (_listings.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(_tr('No active vehicles right now.', ar: 'لا توجد مركبات نشطة حالياً.', ku: 'لە ئێستادا هیچ ئۆتۆمبێلێکی چالاک نییە.')),
                          )
                        else
                          ValueListenableBuilder<int>(
                            valueListenable: ListingLayoutPrefs.columns,
                            builder: (context, cols, _) {
                              final listingColumns = (cols == 1) ? 1 : 2;
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.fromLTRB(
                                  listingColumns == 1 ? 4 : 12,
                                  12,
                                  listingColumns == 1 ? 4 : 12,
                                  12,
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
                                itemCount: _listings.length,
                                itemBuilder: (context, index) {
                                  final item = _listings[index];
                                  final mapped =
                                      mapListingToGlobalCarCardData(
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
