import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/config.dart';
import '../shared/media/media_url.dart';

class CarDetailPage extends StatefulWidget {
  final String carId;
  const CarDetailPage({super.key, required this.carId});

  @override
  State<CarDetailPage> createState() => _CarDetailPageState();
}

class _CarDetailPageState extends State<CarDetailPage> {
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

  List<String> get _imageUrls {
    final car = _car;
    if (car == null) return const <String>[];
    final List<String> urls = [];

    final primary = (car['image_url'] ?? '').toString();
    if (primary.isNotEmpty) urls.add(buildMediaUrl(primary));

    final imgs = car['images'];
    if (imgs is List) {
      for (final it in imgs) {
        final s = it is Map
            ? (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
                .toString()
            : it.toString();
        if (s.isEmpty) continue;
        final full = buildMediaUrl(s);
        if (full.isNotEmpty && !urls.contains(full)) urls.add(full);
      }
    }

    return urls;
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
      final idForAnalytics =
          (car['id'] ?? car['public_id'] ?? widget.carId).toString();
      await AnalyticsService.trackView(idForAnalytics);

      // Favorite status (best-effort).
      await _loadFavoriteStatus();

      // Similar/related (best-effort).
      _loadSimilarAndRelated();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadFavoriteStatus() async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) return;
      final targetId =
          (_car?['id'] ?? _car?['public_id'] ?? widget.carId).toString();
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
            content:
                Text(AppLocalizations.of(context)?.loginRequired ?? 'Login required'),
          ),
        );
        return;
      }
      final targetId =
          (_car?['id'] ?? _car?['public_id'] ?? widget.carId).toString();
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
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _shareCar() async {
    final car = _car;
    if (car == null) return;
    final id = (car['id'] ?? car['public_id'] ?? widget.carId).toString();
    final title = (car['title'] ?? '${car['brand'] ?? ''} ${car['model'] ?? ''}')
        .toString()
        .trim();
    final price = (car['price'] ?? '').toString();
    final currency = (car['currency'] ?? '').toString();
    final location = (car['location'] ?? car['city'] ?? '').toString();
    final text = [
      title,
      [price, currency].where((s) => s.isNotEmpty).join(' '),
      location,
    ].where((s) => s.trim().isNotEmpty).join('\n');

    try {
      await Share.share(text);
    } catch (_) {}
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
        SnackBar(content: Text(loc?.couldNotStartCall ?? 'Could not start a call')),
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
                .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
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
                .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
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
            .where((m) => (m['id'] ?? '').toString() != widget.carId)
            .take(12)
            .toList();
        if (mounted) {
          setState(() => _similar = items);
        }
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.setString('cache_similar_${widget.carId}', json.encode(items));
        } catch (_) {}
      }

      // Related: same brand, newest first.
      final rel = await ApiService.getCars(page: 1, perPage: 20, brand: brand);
      final relList =
          (rel['cars'] is List) ? (rel['cars'] as List) : const [];
      final relItems = relList
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .where((m) => (m['id'] ?? '').toString() != widget.carId)
          .take(12)
          .toList();
      if (mounted) {
        setState(() => _related = relItems);
      }
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('cache_related_${widget.carId}', json.encode(relItems));
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
    add(loc?.mileageLabel ?? 'Mileage', car['mileage'] != null ? '${car['mileage']} km' : null);
    add(loc?.transmissionLabel ?? 'Transmission', car['transmission']);
    add(loc?.engineTypeLabel ?? 'Engine', car['engine_type']);
    add(loc?.driveType ?? 'Drive type', car['drive_type']);
    add(loc?.bodyTypeLabel ?? 'Body type', car['body_type']);
    add(loc?.conditionLabel ?? 'Condition', car['condition']);
    add(loc?.colorLabel ?? 'Color', car['color']);
    add('Fuel economy', car['fuel_economy']);
    add(loc?.trimLabel ?? 'Trim', car['trim']);
    if (car['seating'] != null && (car['seating'] is int || car['seating'] is String)) {
      final n = car['seating'].toString().trim();
      if (n.isNotEmpty && n != '0') rows.add(MapEntry(loc?.seating ?? 'Seating', n));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc?.specificationsLabel ?? 'Specifications',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: rows.map((e) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
        const SizedBox(height: 16),
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
              return Image.network(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    return SizedBox(
      height: 210,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: cars.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final c = cars[index];
          final id = (c['id'] ?? '').toString();
          final title = (c['title'] ?? '${c['brand'] ?? ''} ${c['model'] ?? ''}')
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
              child: Card(
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
                      ),
                    ),
                  ],
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

    if (_loading && car == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (car == null) {
      return Scaffold(
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

    final title = (car['title'] ?? '').toString().trim().isNotEmpty
        ? (car['title'] ?? '').toString()
        : '${car['brand'] ?? ''} ${car['model'] ?? ''} ${car['year'] ?? ''}'
            .trim();

    final price = (car['price'] ?? '').toString();
    final currency = (car['currency'] ?? '').toString();
    final location = (car['location'] ?? car['city'] ?? '').toString();

    final seller = (car['seller'] is Map) ? (car['seller'] as Map) : null;
    final receiverId = seller == null ? null : (seller['id'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.listingTitle ?? 'Listing'),
        actions: [
          IconButton(
            tooltip: loc?.shareAction ?? 'Share',
            onPressed: _shareCar,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: loc?.callAction ?? 'Call',
            onPressed: _callSeller,
            icon: const Icon(Icons.call_outlined),
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
            Padding(
              padding: const EdgeInsets.all(16),
                child: Column(
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
                        child: Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
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
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              '/chat/conversation',
                              arguments: {
                                'carId': (car['id'] ?? car['public_id'] ?? widget.carId).toString(),
                                if (receiverId != null && receiverId.isNotEmpty)
                                  'receiverId': receiverId,
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
                  const SizedBox(height: 16),
                  if ((car['description'] ?? '').toString().trim().isNotEmpty) ...[
                    Text(
                      loc?.descriptionTitle ?? 'Description',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text((car['description'] ?? '').toString()),
                    const SizedBox(height: 16),
                  ],
                  if (_loadingSimilar || _similar.isNotEmpty) ...[
                    Text(
                      loc?.similarListings ?? 'Similar',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
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
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

