part of 'my_listings_page.dart';

extension _MyListingsPageWidgets on _MyListingsPageState {
  Widget _buildListingFilters() {
    final filters = <(_MyListingsFilter, String)>[
      (_MyListingsFilter.all, _text('All', ar: 'الكل', ku: 'هەموو')),
      (_MyListingsFilter.active, _text('Active', ar: 'نشط', ku: 'چالاک')),
      (
        _MyListingsFilter.pending,
        AppLocalizations.of(context)?.myListingsPendingFilter ??
            _text('Pending', ar: 'قيد المراجعة', ku: 'چاوەڕوان'),
      ),
      (_MyListingsFilter.sold, _text('Sold', ar: 'مُباع', ku: 'فرۆشراو')),
      (_MyListingsFilter.draft, _text('Draft', ar: 'مسودة', ku: 'ڕەشنووس')),
    ];

    return SizedBox(
      height: 56,
      child: ListView.separated(
        key: const ValueKey('my-listings-filter-list'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (filter, label) = filters[index];
          return ChoiceChip(
            key: ValueKey('my-listings-filter-${filter.name}'),
            label: Text(label),
            selected: _filter == filter,
            onSelected: (_) => _selectFilter(filter),
            selectedColor: AppColors.brandOrange,
            labelStyle: TextStyle(
              color: _filter == filter ? Colors.white : null,
              fontWeight: FontWeight.w700,
            ),
            showCheckmark: false,
            tooltip: label,
          );
        },
      ),
    );
  }

  Widget _buildPendingExplainer() {
    final text = AppLocalizations.of(context)?.myListingsPendingExplainer ??
        _text(
          'These listings are not visible to buyers yet. We review new posts for quality and safety — most are approved quickly.',
          ar: 'هذه الإعلانات غير ظاهرة للمشترين بعد. نراجع المنشورات الجديدة للجودة والسلامة — معظمها يُعتمد بسرعة.',
          ku: 'ئەم ڕێکلامانە هێشتا بۆ کڕیاران دیار نین. پۆستە نوێیەکان بۆ کوالێتی و سەلامەتی پێداچوونەوەیان بۆ دەکرێت — زۆربەیان خێرا پەسەند دەکرێن.',
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF57C00).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFF57C00).withValues(alpha: 0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFF57C00),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      'Step 1: Photos',
      'Step 2: Basic info',
      'Step 3: Details',
      'Step 4: Pricing',
      'Step 5: Plates',
      'Step 6: Review',
    ];
    final label = labels[currentStep.clamp(0, 5).toInt()];
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

  Widget _buildEmptyState({required _MyListingsFilter filter}) {
    final loc = AppLocalizations.of(context);
    final (title, hint) = switch (filter) {
      _MyListingsFilter.active => (
        _text(
          'No active listings',
          ar: 'لا توجد إعلانات نشطة',
          ku: 'هیچ ڕێکلامێکی چالاک نییە',
        ),
        _text(
          'Listings available to buyers will appear here.',
          ar: 'الإعلانات المتاحة للمشترين ستظهر هنا.',
          ku: 'ڕێکلامە بەردەستەکان بۆ کڕیاران لێرە دەردەکەون.',
        ),
      ),
      _MyListingsFilter.pending => (
        loc?.myListingsNoPendingTitle ??
            _text(
              'No pending listings',
              ar: 'لا توجد إعلانات قيد المراجعة',
              ku: 'هیچ ڕێکلامێکی چاوەڕوان نییە',
            ),
        loc?.myListingsNoPendingHint ??
            _text(
              'Listings waiting for admin approval will appear here.',
              ar: 'الإعلانات بانتظار موافقة المشرف ستظهر هنا.',
              ku: 'ڕێکلامە چاوەڕوانی پەسەندکردنی بەڕێوەبەر لێرە دەردەکەون.',
            ),
      ),
      _MyListingsFilter.sold => (
        _text(
          'No sold listings',
          ar: 'لا توجد إعلانات مُباعة',
          ku: 'هیچ ڕێکلامێکی فرۆشراو نییە',
        ),
        _text(
          'Listings marked as sold will appear here.',
          ar: 'الإعلانات المحددة كمُباعة ستظهر هنا.',
          ku: 'ڕێکلامە فرۆشراوەکان لێرە دەردەکەون.',
        ),
      ),
      _MyListingsFilter.draft => (
        _text('No drafts', ar: 'لا توجد مسودات', ku: 'هیچ ڕەشنووسێک نییە'),
        _text(
          'Unfinished listings will appear here.',
          ar: 'الإعلانات غير المكتملة ستظهر هنا.',
          ku: 'ڕێکلامە تەواونەکراوەکان لێرە دەردەکەون.',
        ),
      ),
      _MyListingsFilter.all => (
        loc?.noListingsYet ?? 'No listings yet',
        loc?.noListingsEmptyHint ??
            'Create your first car listing to see it here.',
      ),
    };
    return EmptyStatePanel(
      icon: Icons.directions_car_outlined,
      title: title,
      hint: hint,
      actionLabel: loc?.addYourFirstCar ?? 'Add your first car',
      actionIcon: Icons.add,
      onAction: () => Navigator.pushReplacementNamed(context, '/sell'),
    );
  }
}
