import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/media/media_url.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _cars = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getFavorites(page: 1, perPage: 100);
      final dynamic raw = (data['cars'] ?? data['favorites'] ?? data);
      final list = raw is List ? raw : const <dynamic>[];
      final cars = list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .toList();
      if (!mounted) return;
      setState(() {
        _cars = cars;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.favoritesTitle ?? 'Favorites'),
      ),
      body: !auth.isAuthenticated
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
          : RefreshIndicator(
              onRefresh: _fetch,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_error != null)
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
                                onPressed: _fetch,
                                child: Text(loc?.retryAction ?? 'Retry'),
                              ),
                            ),
                          ],
                        )
                      : (_cars.isEmpty)
                          ? ListView(
                              children: [
                                const SizedBox(height: 40),
                                Center(
                                  child: Text(loc?.noFavoritesYet ?? 'No favorites yet'),
                                ),
                              ],
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.72,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _cars.length,
                              itemBuilder: (context, index) {
                                final car = _cars[index];
                                final carId = (car['id'] ?? car['public_id'] ?? '')
                                    .toString();
                                final carTitle =
                                    (car['title'] ?? '${car['brand'] ?? ''} ${car['model'] ?? ''}')
                                        .toString()
                                        .trim();
                                final price = (car['price'] ?? '').toString();
                                final location = (car['location'] ?? '').toString();
                                final year = (car['year'] ?? '').toString();

                                return InkWell(
                                  onTap: () {
                                    if (carId.isEmpty) return;
                                    Navigator.pushNamed(
                                      context,
                                      '/car_detail',
                                      arguments: {'carId': carId},
                                    );
                                  },
                                  child: Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AspectRatio(
                                          aspectRatio: 16 / 10,
                                          child: _carImage(car),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                carTitle.isEmpty ? 'Car' : carTitle,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                price,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                [year, location]
                                                    .where((s) => s.isNotEmpty)
                                                    .join(' • '),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
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

