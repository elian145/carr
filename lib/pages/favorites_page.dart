import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../legacy/main_legacy.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;
import '../services/api_service.dart';
import '../services/auth_service.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _cars = <Map<String, dynamic>>[];

  /// Same gradient as [HomePage] body so [buildGlobalCarCard] fills match home.
  static const List<Color> _kHomeBodyGradientColors = [
    Color(0xFF0F1115),
    Color(0xFF131722),
    Color(0xFF0F1115),
  ];

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

  Future<void> _toggleFavorite(String carId) async {
    try {
      final res = await ApiService.toggleFavorite(carId);
      final bool favorited =
          (res['is_favorited'] == true) || (res['favorited'] == true);
      if (!favorited && mounted) {
        setState(() {
          _cars.removeWhere((c) {
            final cid = (c['public_id'] ?? c['id'] ?? '').toString();
            return cid == carId;
          });
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.favoritesTitle ?? 'Favorites'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: _kHomeBodyGradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          if (!auth.isAuthenticated)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc?.notLoggedIn ??
                          'You have to log in or sign up first.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      child: Text(loc?.loginAction ?? 'Log In'),
                    ),
                  ],
                ),
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _fetch,
              color: Colors.white,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
                      ),
                    )
                  : (_error != null)
                      ? ListView(
                          children: [
                            const SizedBox(height: 40),
                            Center(
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
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
                                  child: Text(
                                    loc?.noFavoritesYet ?? 'No favorites yet',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ],
                            )
                          : GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(8),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.62,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: _cars.length,
                              itemBuilder: (context, index) {
                                final carMap =
                                    Map<String, dynamic>.from(_cars[index]);
                                final card = buildGlobalCarCard(
                                  context,
                                  mapListingToGlobalCarCardData(
                                    context,
                                    carMap,
                                  ),
                                );
                                final carId = (carMap['public_id'] ??
                                        carMap['id'] ??
                                        '')
                                    .toString();
                                if (carId.isEmpty) return card;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    card,
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Material(
                                        color: Colors.black54,
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () => _toggleFavorite(carId),
                                          child: const Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Icon(
                                              Icons.favorite,
                                              color: Color(0xFFFF6B00),
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
            ),
        ],
      ),
    );
  }
}

