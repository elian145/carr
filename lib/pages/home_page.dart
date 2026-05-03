import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme_provider.dart';
import '../services/api_service.dart';
import '../shared/media/media_url.dart';
import '../shared/text/pretty_title_case.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _controller = ScrollController();

  final List<Map<String, dynamic>> _cars = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  String? _error;

  static const int _perPage = 20;

  @override
  void initState() {
    super.initState();

    _controller.addListener(() {
      if (!_hasNext || _loadingMore || _loading) return;
      final pos = _controller.position;
      if (pos.pixels >= (pos.maxScrollExtent - 500)) {
        _loadMore();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetch(refresh: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool refresh}) async {
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
      final data = await ApiService.getCars(page: _page, perPage: _perPage);

      final dynamic rawCars = (data['cars'] ?? data);
      final List<dynamic> list = rawCars is List ? rawCars : const <dynamic>[];
      final newCars = list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .toList();

      bool hasNext = false;
      final dynamic pagination = data['pagination'];
      if (pagination is Map && pagination['has_next'] is bool) {
        hasNext = pagination['has_next'] as bool;
      } else {
        hasNext = newCars.length >= _perPage;
      }

      if (!mounted) return;
      setState(() {
        _cars.addAll(newCars);
        _hasNext = hasNext;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
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

  Widget _carImage(Map<String, dynamic> car) {
    final primary = (car['image_url'] ?? '').toString();
    final url = buildMediaUrl(primary);
    if (url.isEmpty) {
      return Container(
        color: Colors.black12,
        child: const Center(child: Icon(Icons.directions_car)),
      );
    }

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
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = (loc?.appTitle ?? 'CARZO').toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: loc?.sellTitle ?? 'Sell',
            onPressed: () => Navigator.pushNamed(context, '/sell'),
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: loc?.favoritesTitle ?? 'Favorites',
            onPressed: () => Navigator.pushNamed(context, '/favorites'),
            icon: const Icon(Icons.favorite_border),
          ),
          IconButton(
            tooltip: loc?.profileTitle ?? 'Profile',
            onPressed: () => Navigator.pushNamed(context, '/profile'),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetch(refresh: true),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_cars.isEmpty && _error != null)
                ? ListView(
                    children: [
                      const SizedBox(height: 40),
                      Center(
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: OutlinedButton(
                          onPressed: () => _fetch(refresh: true),
                          child: Text(loc?.retryAction ?? 'Retry'),
                        ),
                      ),
                    ],
                  )
                : GridView.builder(
                    controller: _controller,
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _cars.length + (_hasNext ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _cars.length) {
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }

                      final car = _cars[index];
                      final carId = (car['id'] ?? car['public_id'] ?? '').toString();
                      final carTitleRaw = (car['title'] ?? '${car['brand'] ?? ''} ${car['model'] ?? ''}')
                          .toString()
                          .trim();
                      final carTitle = prettyTitleCase(carTitleRaw);
                      final price = (car['price'] ?? '').toString();
                      final location = (car['location'] ?? '').toString();
                      final year = (car['year'] ?? '').toString();

                      final isLight =
                          Theme.of(context).brightness == Brightness.light;
                      return InkWell(
                        onTap: () {
                          if (carId.isEmpty) return;
                          Navigator.pushNamed(
                            context,
                            '/car_detail',
                            arguments: {'carId': carId},
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isLight
                                ? AppThemes.listingCardFillGridOnLightShell()
                                : Colors.white.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AspectRatio(
                                aspectRatio: 16 / 10,
                                child: _carImage(car),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Reserve space so short titles don't collapse the card body.
                                      SizedBox(
                                        height: 34,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  carTitle.isEmpty
                                                      ? (loc?.carLabel ?? 'Car')
                                                      : carTitle,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: isLight
                                                        ? const Color(0xFFFF6B00)
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurface,
                                                    fontSize: 15,
                                                    height: 1.1,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (price.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                price,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: isLight
                                                      ? const Color(0xFFFF6B00)
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .onSurface,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        [year, location]
                                            .where((s) => s.isNotEmpty)
                                            .join(' • '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: isLight ? Colors.white70 : null,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

