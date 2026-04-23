import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/text/pretty_title_case.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../legacy/main_legacy.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;

class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  final ScrollController _controller = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  String? _error;

  final List<Map<String, dynamic>> _cars = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    // Keep consistent layout (grid vs list) with the rest of the app.
    ListingLayoutPrefs.load();
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

  Future<void> _deleteListing(String carId) async {
    final loc = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc?.deleteListingTitle ?? 'Delete listing?'),
        content: Text(
          loc?.deleteListingBody ?? 'This will remove it from public listings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc?.cancelAction ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc?.deleteAction ?? 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ApiService.deleteCar(carId);
      if (!mounted) return;
      setState(() {
        _cars.removeWhere((c) => (c['id'] ?? '').toString() == carId);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _editListing(Map<String, dynamic> car) async {
    final carId = (car['id'] ?? car['public_id'] ?? '').toString();
    if (carId.isEmpty) return;

    final loc = AppLocalizations.of(context);
    final title = (car['title'] ?? '').toString();
    final priceController = TextEditingController(text: (car['price'] ?? '').toString());
    final locationController = TextEditingController(text: (car['location'] ?? '').toString());
    final descriptionController = TextEditingController(text: (car['description'] ?? '').toString());

    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          final bottom = MediaQuery.of(context).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? (loc?.editListingTitle ?? 'Edit listing') : title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: loc?.priceLabel ?? 'Price'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: locationController,
                      decoration: InputDecoration(
                        labelText: loc?.locationLabel ?? 'Location',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: loc?.descriptionTitle ?? 'Description',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(loc?.cancelAction ?? 'Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(loc?.save ?? 'Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (saved != true) return;

      final price = double.tryParse(priceController.text.trim());
      final payload = <String, dynamic>{
        if (price != null) 'price': price,
        'location': locationController.text.trim(),
        'description': descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
      };

      final res = await ApiService.updateCar(carId, payload);
      final updated = (res['car'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(res['car'])
          : null;
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          final idx = _cars.indexWhere((c) => (c['id'] ?? '').toString() == carId);
          if (idx >= 0) _cars[idx] = {..._cars[idx], ...updated};
        });
      }
    } finally {
      priceController.dispose();
      locationController.dispose();
      descriptionController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final auth = context.watch<AuthService>();

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
                    return GridView.builder(
                      controller: _controller,
                      padding: EdgeInsets.fromLTRB(
                        listingColumns == 1 ? 4 : 12,
                        12,
                        listingColumns == 1 ? 4 : 12,
                        12,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: listingColumns,
                        childAspectRatio: listingColumns == 2 ? 0.62 : 2.78,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _cars.length + (_hasNext ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _cars.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }

                        final car = _cars[index];
                        final id =
                            (car['id'] ?? car['public_id'] ?? '').toString();

                        final mapped =
                            mapListingToGlobalCarCardData(context, car);
                        final card = buildGlobalCarCard(
                          context,
                          mapped,
                          listLayout: listingColumns == 1,
                        );

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
                                child: PopupMenuButton<String>(
                                  tooltip: 'More',
                                  onSelected: (v) {
                                    if (v == 'edit') _editListing(car);
                                    if (v == 'delete') _deleteListing(id);
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text(loc?.editAction ?? 'Edit'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(loc?.deleteAction ?? 'Delete'),
                                    ),
                                  ],
                                  icon: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.more_vert,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(loc?.myListingsTitle ?? 'My listings'),
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
          : authenticatedBody,
      floatingActionButton: auth.isAuthenticated
          ? FloatingActionButton(
              onPressed: () => Navigator.pushNamed(context, '/sell'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

