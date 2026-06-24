part of 'my_listings_page.dart';

extension _MyListingsPageWidgets on _MyListingsPageState {
  Widget _buildDraftCard(
    Map<String, dynamic> snapshot, {
    required bool listLayout,
  }) {
    final carData = snapshot['carData'] is Map
        ? Map<String, dynamic>.from(
            (snapshot['carData'] as Map).cast<String, dynamic>(),
          )
        : <String, dynamic>{};
    final currentStep = LegacySellDraftList.readStep(snapshot['currentStep']);
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
      'images': SellDraftMediaPersistence.resolveDynamicMediaList(
        (carData['images'] is List)
            ? List<dynamic>.from(carData['images'] as List)
            : (carData['image_paths'] is List)
                ? List<dynamic>.from(carData['image_paths'] as List)
                : null,
      ),
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
          buildGlobalCarCard(
            context,
            draftListing,
            listLayout: listLayout,
            onCardTap: () => unawaited(_resumeDraft(snapshot)),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
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
              color: Colors.black.withValues(alpha: 0.62),
              shape: const CircleBorder(),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(_discardDraft(snapshot)),
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
                color: Colors.black.withValues(alpha: 0.62),
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
                color: const Color(0xFFFF6B00).withValues(alpha: 0.1),
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
            top: 14,
            left: 14,
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
}
