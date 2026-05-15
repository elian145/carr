import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../theme_provider.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/config.dart';
import '../shared/media/media_url.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/listings/listing_share.dart';
import '../shared/text/pretty_title_case.dart';
import 'listing_image_gallery_page.dart';

class CarDetailPage extends StatefulWidget {
  final String carId;
  const CarDetailPage({super.key, required this.carId});

  @override
  State<CarDetailPage> createState() => _CarDetailPageState();
}

class _CarDetailPageState extends State<CarDetailPage> {
  String _tr(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  Map<String, dynamic>? _car;
  bool _loading = true;
  String? _error;
  bool _isFavorite = false;

  final PageController _page = PageController();
  int _pageIndex = 0;

  List<Map<String, dynamic>> _similar = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _related = <Map<String, dynamic>>[];
  bool _loadingSimilar = false;
  bool _loadingRelated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  static bool _imageEntryIsDamage(dynamic it) {
    if (it is! Map) return false;
    final k = (it['kind'] ?? '').toString().toLowerCase();
    return k == 'damage';
  }

  List<String> get _imageUrls {
    final car = _car;
    if (car == null) return const <String>[];
    final List<String> urls = [];
    final Set<String> seen = {};

    void addOne(String raw) {
      if (raw.trim().isEmpty) return;
      final full = buildMediaUrl(raw);
      if (full.isEmpty || seen.contains(full)) return;
      seen.add(full);
      urls.add(full);
    }

    final primary = (car['image_url'] ?? '').toString();
    if (primary.isNotEmpty) {
      addOne(primary);
    }

    final imgs = car['images'];
    if (imgs is List) {
      for (final it in imgs) {
        if (_imageEntryIsDamage(it)) continue;
        final s = it is Map
            ? (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
                  .toString()
            : it.toString();
        if (s.isEmpty) continue;
        addOne(s);
      }
    }

    return urls;
  }

  List<String> get _damageImageUrls {
    final car = _car;
    if (car == null) return const <String>[];
    final imgs = car['images'];
    if (imgs is! List) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final it in imgs) {
      if (!_imageEntryIsDamage(it)) continue;
      final s = it is Map
          ? (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
                .toString()
          : it.toString();
      if (s.trim().isEmpty) continue;
      final full = buildMediaUrl(s);
      if (full.isEmpty || seen.contains(full)) continue;
      seen.add(full);
      out.add(full);
    }
    return out;
  }

  static List<String> _normalizeVideoPaths(dynamic raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    final List<String> out = [];
    for (final dynamic it in raw) {
      final String s;
      if (it is String) {
        s = it.trim();
      } else if (it is Map) {
        s = (it['video_url'] ?? it['url'] ?? it['path'] ?? '').toString().trim();
      } else {
        s = it.toString().trim();
      }
      if (s.isNotEmpty && !s.startsWith('{') && s != 'null') {
        out.add(s);
      }
    }
    return out;
  }

  List<String> get _videoUrls {
    final car = _car;
    if (car == null) return const <String>[];
    final paths = _normalizeVideoPaths(car['videos']);
    final out = <String>[];
    for (final p in paths) {
      final full = buildMediaUrl(p);
      if (full.isNotEmpty && !out.contains(full)) out.add(full);
    }
    return out;
  }

  void _openImageGallery(
    BuildContext context,
    List<String> urls,
    int tappedIndex, {
    List<String>? videoUrls,
  }) {
    final videos = videoUrls ?? _videoUrls;
    if (urls.isEmpty && videos.isEmpty) return;
    final i = urls.isEmpty ? 0 : tappedIndex.clamp(0, urls.length - 1);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ListingImageGalleryPage(
          imageUrls: urls,
          videoUrls: videos,
          initialIndex: i,
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // 1) Load cached car immediately (offline-friendly).
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = sp.getString('cache_car_${widget.carId}');
      if (cached != null && cached.isNotEmpty) {
        final decoded = json.decode(cached);
        if (decoded is Map) {
          setState(() {
            _car = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
            _loading = false;
          });
        }
      }
    } catch (_) {}

    // 2) Load fresh from API.
    try {
      final data = await ApiService.getCar(widget.carId);
      Map<String, dynamic>? car;
      final inner = data['car'];
      if (inner is Map) {
        car = Map<String, dynamic>.from(inner.cast<String, dynamic>());
      } else {
        car = Map<String, dynamic>.from(data);
      }
      if (car == null) throw StateError('Invalid car response');

      if (!mounted) return;
      setState(() {
        _car = car;
        _loading = false;
      });

      // Persist cache (best-effort).
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('cache_car_${widget.carId}', json.encode(car));
      } catch (_) {}

      // Track view (auth-only, best-effort).
      final idForAnalytics = listingPrimaryId(car).isNotEmpty
          ? listingPrimaryId(car)
          : widget.carId;
      await AnalyticsService.trackView(idForAnalytics);

      // Favorite status (best-effort).
      await _loadFavoriteStatus();

      // Similar/related (best-effort).
      _loadSimilarAndRelated();
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

  Future<void> _loadFavoriteStatus() async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) return;
      final targetId = _car == null
          ? widget.carId
          : (listingPrimaryId(_car!).isNotEmpty
                ? listingPrimaryId(_car!)
                : widget.carId);
      final fav = await ApiService.isCarFavorited(targetId);
      if (!mounted) return;
      setState(() => _isFavorite = fav);
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.loginRequired ?? 'Login required',
            ),
          ),
        );
        return;
      }
      final targetId = _car == null
          ? widget.carId
          : (listingPrimaryId(_car!).isNotEmpty
                ? listingPrimaryId(_car!)
                : widget.carId);
      final res = await ApiService.toggleFavorite(targetId);
      final bool favorited =
          (res['is_favorited'] == true) || (res['favorited'] == true);
      if (!mounted) return;
      setState(() => _isFavorite = favorited);
      if (favorited) {
        await AnalyticsService.trackFavorite(targetId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _shareCar() async {
    final car = _car;
    if (car == null) return;
    final id = listingPrimaryId(car).isNotEmpty
        ? listingPrimaryId(car)
        : widget.carId;

    try {
      final title = (_car?['title'] ?? '').toString().trim();
      await shareListingAsLinkOnly(
        id,
        context: context,
        listingTitle: title.isNotEmpty ? title : null,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.errorTitle ?? 'Could not open share',
          ),
        ),
      );
    }
    try {
      await AnalyticsService.trackShare(id);
    } catch (_) {}
  }

  Future<void> _callSeller() async {
    final loc = AppLocalizations.of(context);
    final seller = (_car?['seller'] is Map) ? (_car?['seller'] as Map) : null;
    final raw = (seller?['phone_number'] ?? seller?['phone'] ?? '').toString();
    final phone = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loc?.sellerPhoneNotAvailable ?? 'Seller phone not available',
          ),
        ),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await canLaunchUrl(uri);
      if (ok) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw StateError('Cannot launch dialer');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc?.couldNotStartCall ?? 'Could not start a call'),
        ),
      );
    }
  }

  Future<void> _loadSimilarAndRelated() async {
    final car = _car;
    if (car == null) return;
    final brand = (car['brand'] ?? '').toString().trim();
    final model = (car['model'] ?? '').toString().trim();
    if (brand.isEmpty) return;

    setState(() {
      _loadingSimilar = true;
      _loadingRelated = true;
    });

    // Cached first (best-effort).
    try {
      final sp = await SharedPreferences.getInstance();
      final simCached = sp.getString('cache_similar_${widget.carId}');
      if (simCached != null && simCached.isNotEmpty) {
        final decoded = json.decode(simCached);
        if (decoded is List) {
          setState(() {
            _similar = decoded
                .whereType<Map>()
                .map(
                  (m) => Map<String, dynamic>.from(m.cast<String, dynamic>()),
                )
                .toList();
          });
        }
      }
      final relCached = sp.getString('cache_related_${widget.carId}');
      if (relCached != null && relCached.isNotEmpty) {
        final decoded = json.decode(relCached);
        if (decoded is List) {
          setState(() {
            _related = decoded
                .whereType<Map>()
                .map(
                  (m) => Map<String, dynamic>.from(m.cast<String, dynamic>()),
                )
                .toList();
          });
        }
      }
    } catch (_) {}

    try {
      // Similar: same brand + model (if model present)
      if (model.isNotEmpty) {
        final data = await ApiService.getCars(
          page: 1,
          perPage: 20,
          brand: brand,
          model: model,
        );
        final list = (data['cars'] is List) ? (data['cars'] as List) : const [];
        final items = list
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
            .where((m) => !listingMatchesId(m, widget.carId))
            .take(12)
            .toList();
        if (mounted) {
          setState(() => _similar = items);
        }
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.setString(
            'cache_similar_${widget.carId}',
            json.encode(items),
          );
        } catch (_) {}
      }

      // Related: same brand, newest first.
      final rel = await ApiService.getCars(page: 1, perPage: 20, brand: brand);
      final relList = (rel['cars'] is List) ? (rel['cars'] as List) : const [];
      final relItems = relList
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .where((m) => !listingMatchesId(m, widget.carId))
          .take(12)
          .toList();
      if (mounted) {
        setState(() => _related = relItems);
      }
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(
          'cache_related_${widget.carId}',
          json.encode(relItems),
        );
      } catch (_) {}
    } catch (_) {
      // ignore: non-critical
    } finally {
      if (mounted) {
        setState(() {
          _loadingSimilar = false;
          _loadingRelated = false;
        });
      }
    }
  }

  static String _brandLogoUrl(String brand) {
    if ((brand).trim().isEmpty) return '';
    final slug = brand
        .toString()
        .toLowerCase()
        .trim()
        .replaceAll(' ', '-')
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '');
    if (slug.isEmpty) return '';
    final base = effectiveApiBase().trim();
    return base.isEmpty ? '' : '$base/static/images/brands/$slug.png';
  }

  static String _firstNonEmptyFromMap(
    Map<dynamic, dynamic>? map,
    List<String> keys,
  ) {
    if (map == null) return '';
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return '';
  }

  static String _formatDateYmd(String raw) {
    if (raw.trim().isEmpty) return '';
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return raw;
    final y = parsed.year.toString().padLeft(4, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    final d = parsed.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void _showDescriptionDialog(String description) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context)?.descriptionTitle ?? 'Description'),
        content: SingleChildScrollView(child: Text(description)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_tr('Close', ar: 'إغلاق', ku: 'داخستن')),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerInfoSection(Map<dynamic, dynamic>? seller) {
    if (seller == null) return const SizedBox.shrink();

    final loc = AppLocalizations.of(context);
    final firstName = (seller['first_name'] ?? '').toString().trim();
    final lastName = (seller['last_name'] ?? '').toString().trim();
    final fullName = '$firstName $lastName'.trim();

    final name = _firstNonEmptyFromMap(seller, ['name', 'display_name']);
    final username = _firstNonEmptyFromMap(seller, ['username', 'handle']);
    final phone = _firstNonEmptyFromMap(seller, [
      'phone_number',
      'phone',
      'mobile',
    ]);
    final email = _firstNonEmptyFromMap(seller, ['email']);
    final city = _firstNonEmptyFromMap(seller, ['city', 'location']);
    final joinedRaw = _firstNonEmptyFromMap(seller, [
      'created_at',
      'joined_at',
      'member_since',
    ]);
    final joined = _formatDateYmd(joinedRaw);
    final avatarRaw = _firstNonEmptyFromMap(seller, [
      'profile_picture',
      'avatar',
      'avatar_url',
      'image_url',
      'photo_url',
    ]);
    final avatarUrl = buildMediaUrl(avatarRaw);

    final bool isVerified =
        seller['is_verified'] == true || seller['verified'] == true;
    final accountType = (seller['account_type'] ?? '').toString().trim();
    final dealerStatus = (seller['dealer_status'] ?? '').toString().trim();
    final dealershipName =
        (seller['dealership_name'] ?? '').toString().trim();
    final dealershipLocation =
        (seller['dealership_location'] ?? '').toString().trim();
    final dealershipDescription = _firstNonEmptyFromMap(seller, [
      'dealership_description',
      'dealer_description',
      'description',
    ]);
    final isApprovedDealer =
        accountType == 'dealer' && dealerStatus == 'approved';
    final isDealerSeller = accountType == 'dealer';
    final sellerTypeLabel = isDealerSeller
        ? _tr('Dealership', ar: 'معرض', ku: 'نمایشگا')
        : _tr('Private seller', ar: 'بائع فردي', ku: 'فرۆشیاری تاک');

    final displayName = (isApprovedDealer && dealershipName.isNotEmpty)
        ? dealershipName
        : (name.isNotEmpty
              ? name
              : (fullName.isNotEmpty
                    ? fullName
                    : (isDealerSeller
                          ? _tr('Dealer', ar: 'وكيل', ku: 'وەکیل')
                          : (username.isNotEmpty ? username : _tr('Seller', ar: 'البائع', ku: 'فرۆشیار')))));

    final locationShown =
        (isApprovedDealer && dealershipLocation.isNotEmpty)
            ? dealershipLocation
            : city;

    final initialsSource = displayName.trim();
    String initials = 'S';
    if (initialsSource.isNotEmpty) {
      final parts = initialsSource
          .split(RegExp(r'\s+'))
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else {
        initials = parts[0][0].toUpperCase();
      }
    }

    final List<Widget> details = [];
    void addRow(IconData icon, String label, String value) {
      if (value.trim().isEmpty) return;
      details.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '$label: ',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show direct contact details only for dealers.
    if (isDealerSeller) {
      addRow(Icons.phone_outlined, loc?.phoneLabel ?? 'Phone', phone);
      addRow(Icons.email_outlined, loc?.emailLabel ?? 'Email', email);
    }
    if (isDealerSeller) {
      addRow(
        Icons.location_on_outlined,
        loc?.locationLabel ?? 'Location',
        locationShown,
      );
      addRow(
        Icons.notes_outlined,
        loc?.descriptionTitle ?? 'Description',
        dealershipDescription,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(0.14),
                backgroundImage: avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        initials,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sellerTypeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (username.isNotEmpty && !isDealerSeller) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isDealerSeller && isVerified)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text(
                        _tr('Verified', ar: 'موثّق', ku: 'پشتڕاستکراوە'),
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (details.isNotEmpty) ...[const SizedBox(height: 12), ...details],
        ],
      ),
    );
  }

  Widget _buildSpecifications(Map<String, dynamic> car) {
    final loc = AppLocalizations.of(context);
    final List<MapEntry<String, String>> rows = [];
    void add(String label, dynamic value) {
      if (value == null) return;
      final s = value.toString().trim();
      if (s.isEmpty || s == '0') return;
      rows.add(MapEntry(label, s));
    }

    add(loc?.yearLabel ?? 'Year', car['year']);
    add(
      loc?.mileageLabel ?? 'Mileage',
      car['mileage'] != null ? '${car['mileage']} km' : null,
    );
    add(loc?.engineTypeLabel ?? 'Engine', car['engine_type']);
    add(loc?.driveType ?? 'Drive type', car['drive_type']);
    add(loc?.bodyTypeLabel ?? 'Body type', car['body_type']);
    add(loc?.conditionLabel ?? 'Condition', car['condition']);
    add(loc?.colorLabel ?? 'Color', car['color']);
    add(loc?.fuelEconomyLabel ?? 'Fuel economy', car['fuel_economy']);
    add(loc?.trimLabel ?? 'Trim', car['trim']);
    if (car['seating'] != null &&
        (car['seating'] is int || car['seating'] is String)) {
      final n = car['seating'].toString().trim();
      if (n.isNotEmpty && n != '0') {
        rows.add(MapEntry(loc?.seating ?? 'Seating', n));
      }
    }

    final titleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc?.specificationsLabel ?? 'Specifications',
          style: titleStyle,
        ),
        const SizedBox(height: 10),
        _buildTitleStatusRow(car, loc),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: rows.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.key,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(e.value, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTitleStatusRow(Map<String, dynamic> car, AppLocalizations? loc) {
    final damageUrls = _damageImageUrls;
    final titleRaw = (car['title_status'] ?? 'clean').toString().toLowerCase();
    final isDamaged = titleRaw == 'damaged';
    final parts = car['damaged_parts'];
    final String value;
    if (isDamaged) {
      value = parts != null
          ? (loc?.titleStatusDamagedWithParts(parts.toString()) ??
              'Damaged (${parts.toString()} parts)')
          : (loc?.value_title_damaged ?? 'Damaged');
    } else {
      value = loc?.value_title_clean ?? 'Clean';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  loc?.titleStatus ?? 'Title Status',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        if (damageUrls.isNotEmpty) ...[
          const SizedBox(width: 8),
          Tooltip(
            message:
                loc?.viewDamagePhotosTooltip ?? 'View damage or crash photos',
            child: IconButton.filledTonal(
              onPressed: () => _openImageGallery(
                context,
                damageUrls,
                0,
                videoUrls: const <String>[],
              ),
              icon: const Icon(Icons.photo_library_outlined),
            ),
          ),
        ],
      ],
    );
  }

  Widget _imageCarousel() {
    final urls = _imageUrls;
    if (urls.isEmpty) {
      return Container(
        color: Colors.black12,
        height: 280,
        child: const Center(child: Icon(Icons.directions_car, size: 64)),
      );
    }

    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          PageView.builder(
            controller: _page,
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _pageIndex = i),
            itemBuilder: (context, i) {
              final url = urls[i];
              return InkWell(
                onTap: () => _openImageGallery(context, urls, i),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.black12,
                      child: const Center(child: Icon(Icons.broken_image)),
                    );
                  },
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: Colors.black12,
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          if (urls.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_pageIndex + 1}/${urls.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _horizontalCars(List<Map<String, dynamic>> cars) {
    final listOnLight = Theme.of(context).brightness == Brightness.light;
    return SizedBox(
      height: 210,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: cars.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final c = cars[index];
          final id = listingPrimaryId(c);
          final title =
              (c['title'] ?? '${c['brand'] ?? ''} ${c['model'] ?? ''}')
                  .toString();
          final img = buildMediaUrl((c['image_url'] ?? '').toString());
          return InkWell(
            onTap: () {
              if (id.isEmpty) return;
              Navigator.pushReplacementNamed(
                context,
                '/car_detail',
                arguments: {'carId': id},
              );
            },
            child: SizedBox(
              width: 160,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: listOnLight
                        ? AppThemes.listingCardFillCompactOnLightShell()
                        : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 10,
                        child: img.isEmpty
                            ? Container(
                                color: Colors.black12,
                                child: const Center(
                                  child: Icon(Icons.directions_car),
                                ),
                              )
                            : Image.network(img, fit: BoxFit.cover),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: listOnLight ? Colors.white : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final car = _car;
    final isLightShell = Theme.of(context).brightness == Brightness.light;

    if (_loading && car == null) {
      return Scaffold(
        backgroundColor: isLightShell ? AppThemes.lightAppBackground : null,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (car == null) {
      return Scaffold(
        backgroundColor: isLightShell ? AppThemes.lightAppBackground : null,
        appBar: AppBar(title: Text(loc?.listingTitle ?? 'Listing')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(loc?.carNotFound ?? 'Car not found'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _load,
                child: Text(loc?.retryAction ?? 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final titleRaw = (car['title'] ?? '').toString().trim().isNotEmpty
        ? (car['title'] ?? '').toString()
        : '${car['brand'] ?? ''} ${car['model'] ?? ''} ${car['year'] ?? ''}'
              .trim();
    final title = prettyTitleCase(titleRaw);
    final brandStr = prettyTitleCase((car['brand'] ?? '').toString().trim());
    final modelStr = prettyTitleCase((car['model'] ?? '').toString().trim());
    final yearStr = (car['year'] ?? '').toString().trim().isNotEmpty
        ? (car['year'] ?? '').toString().trim()
        : RegExp(r'\b(19\d{2}|20\d{2})\b')
                .firstMatch(titleRaw)
                ?.group(0)
                ?.trim() ??
            '';
    final modelYearStr = prettyTitleCase(
      [modelStr, yearStr].where((s) => s.isNotEmpty).join(' '),
    );

    final price = (car['price'] ?? '').toString();
    final currency = (car['currency'] ?? '').toString();
    final location = (car['location'] ?? car['city'] ?? '').toString();
    final starterMessage =
        'Hi, I am interested in "$title". What is the price for this listing?';

    final seller = (car['seller'] is Map) ? (car['seller'] as Map) : null;
    final sellerAccountType =
        seller == null ? '' : (seller['account_type'] ?? '').toString().trim();
    final sellerDealerStatus =
        seller == null ? '' : (seller['dealer_status'] ?? '').toString().trim();
    final sellerIsDealer =
        sellerAccountType == 'dealer' && sellerDealerStatus == 'approved';
    final sellerPublicId = seller == null
        ? ''
        : (seller['public_id'] ?? seller['id'] ?? seller['user_id'] ?? '')
            .toString()
            .trim();
    final receiverId = seller == null
        ? null
        : (seller['id'] ??
                  seller['user_id'] ??
                  seller['seller_id'] ??
                  seller['owner_id'] ??
                  '')
              .toString();
    String? receiverName;
    if (seller != null) {
      final fullName =
          '${seller['first_name'] ?? ''} ${seller['last_name'] ?? ''}'.trim();
      final at = (seller['account_type'] ?? '').toString().trim();
      final ds = (seller['dealer_status'] ?? '').toString().trim();
      final dn = (seller['dealership_name'] ?? '').toString().trim();
      if (at == 'dealer' && ds == 'approved' && dn.isNotEmpty) {
        receiverName = dn;
      } else if (at == 'dealer') {
        receiverName = fullName.isNotEmpty ? fullName : 'Dealer';
      } else {
        receiverName = (seller['name'] ?? seller['username'] ?? '')
            .toString()
            .trim();
        if (receiverName.isEmpty && fullName.isNotEmpty) {
          receiverName = fullName;
        }
        if (receiverName.isEmpty) {
          receiverName = null;
        }
      }
    }

    final detailColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_brandLogoUrl((car['brand'] ?? '').toString()).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _brandLogoUrl((car['brand'] ?? '').toString()),
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(width: 40, height: 40),
                  ),
                ),
              ),
            Expanded(
              child: isLightShell
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (brandStr.isNotEmpty)
                          Text(
                            brandStr,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppThemes.darkHomeShellBackground,
                                ),
                          ),
                        if (modelStr.isNotEmpty) ...[
                          if (brandStr.isNotEmpty) const SizedBox(height: 4),
                          Text(
                            modelYearStr.isNotEmpty ? modelYearStr : modelStr,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                        if (brandStr.isEmpty &&
                            modelStr.isEmpty &&
                            title.isNotEmpty)
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppThemes.darkHomeShellBackground,
                                ),
                          ),
                      ],
                    )
                  : Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          [price, currency].where((s) => s.isNotEmpty).join(' '),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(location),
        const SizedBox(height: 16),
        _buildSpecifications(car),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.orange)),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  final listingId = listingPrimaryId(car).isNotEmpty
                      ? listingPrimaryId(car)
                      : widget.carId;
                  Navigator.pushNamed(
                    context,
                    '/chat/conversation',
                    arguments: {
                      'carId': listingId,
                      if (receiverId != null && receiverId.isNotEmpty)
                        'receiverId': receiverId,
                      if (receiverName != null && receiverName.isNotEmpty)
                        'receiverName': receiverName,
                      'initialDraft': starterMessage,
                      'listingPreview': {
                        'id': listingId,
                        'title': title,
                        'price': car['price'],
                        'currency': currency,
                        'location': location,
                        'image_url': car['image_url'],
                        'images': car['images'],
                        'brand': car['brand'],
                        'model': car['model'],
                        'trim': car['trim'],
                        'year': car['year'],
                      },
                    },
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(loc?.chatAction ?? 'Chat'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/favorites'),
                icon: const Icon(Icons.favorite_border),
                label: Text(loc?.favoritesAction ?? 'Favorites'),
              ),
            ),
          ],
        ),
        if (seller != null) ...[
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: (sellerIsDealer && sellerPublicId.isNotEmpty)
                  ? () => Navigator.pushNamed(
                        context,
                        '/dealer/profile',
                        arguments: {'dealerPublicId': sellerPublicId},
                      )
                  : null,
              child: _buildSellerInfoSection(seller),
            ),
          ),
          if (sellerIsDealer && sellerPublicId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _tr(
                  'Tap seller info to open dealership page',
                  ar: 'اضغط معلومات البائع لفتح صفحة المعرض',
                  ku: 'لە زانیاری فرۆشیار بکە بۆ کردنەوەی پەڕەی نمایشگا',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
        ],
        if ((car['description'] ?? '').toString().trim().isNotEmpty) ...[
          Text(
            loc?.descriptionTitle ?? 'Description',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _showDescriptionDialog(
                (car['description'] ?? '').toString(),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFFF6B00).withOpacity(0.28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        isLightShell ? 0.04 : 0.16,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B00),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.description_outlined,
                        size: 18,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _tr('View description', ar: 'عرض الوصف', ku: 'پیشاندانی وەسف'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isLightShell
                                  ? AppThemes.darkHomeShellBackground
                                  : Colors.white,
                            ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFFFF6B00),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_loadingSimilar || _similar.isNotEmpty) ...[
          Text(
            loc?.similarListings ?? 'Similar',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isLightShell ? AppThemes.darkHomeShellBackground : null,
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingSimilar && _similar.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            _horizontalCars(_similar),
          const SizedBox(height: 16),
        ],
        if (_loadingRelated || _related.isNotEmpty) ...[
          Text(
            loc?.relatedListings ?? 'Related',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isLightShell ? AppThemes.darkHomeShellBackground : null,
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingRelated && _related.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            _horizontalCars(_related),
          const SizedBox(height: 16),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: isLightShell ? AppThemes.lightAppBackground : null,
      appBar: AppBar(
        title: Text(loc?.listingTitle ?? 'Listing'),
        actions: [
          IconButton(
            tooltip: loc?.callAction ?? 'Call',
            onPressed: _callSeller,
            icon: const Icon(Icons.call_outlined),
          ),
          IconButton(
            tooltip: loc?.shareAction ?? 'Share',
            onPressed: _shareCar,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: loc?.favoriteAction ?? 'Favorite',
            onPressed: _toggleFavorite,
            icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            _imageCarousel(),
            if (isLightShell)
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppThemes.lightAppBackground,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(16),
                child: detailColumn,
              )
            else
              Padding(padding: const EdgeInsets.all(16), child: detailColumn),
          ],
        ),
      ),
    );
  }
}
