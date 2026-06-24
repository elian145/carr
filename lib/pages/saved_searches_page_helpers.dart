part of 'saved_searches_page.dart';

extension _SavedSearchesPageHelpers on _SavedSearchesPageState {
  String _localizedSearchTitle(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final filters = item['filters'] as Map<String, dynamic>? ?? {};
    final brand = filters['brand']?.toString().trim() ?? '';
    final model = filters['model']?.toString().trim() ?? '';
    final parts = <String>[];
    if (brand.isNotEmpty) {
      parts.add(CarNameTranslations.getLocalizedBrand(context, brand));
    }
    if (model.isNotEmpty) {
      parts.add(
        CarNameTranslations.getLocalizedModel(context, brand, model),
      );
    }
    if (parts.isNotEmpty) return parts.join(' • ');
    final stored = item['name']?.toString().trim() ?? '';
    if (stored.isNotEmpty) return stored;
    return AppLocalizations.of(context)!.unnamedSearch;
  }

  Widget _buildFilterChips(BuildContext context, Map<String, dynamic> filters) {
    final chips = <Widget>[];
    final l = AppLocalizations.of(context)!;
    String tr(String? v) =>
        translateListingValue(context, v?.toString()) ?? v ?? '';

    if (filters['brand'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.brandLabel,
          CarNameTranslations.getLocalizedBrand(
            context,
            filters['brand'].toString(),
          ),
        ),
      );
    }
    if (filters['model'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.modelLabel,
          CarNameTranslations.getLocalizedModel(
            context,
            filters['brand']?.toString(),
            filters['model'].toString(),
          ),
        ),
      );
    }
    if (filters['trim'] != null) {
      chips.add(
        _buildFilterChip(context, l.trimLabel, filters['trim'].toString()),
      );
    }
    if (filters['city'] != null) {
      chips.add(
        _buildFilterChip(context, l.cityLabel, tr(filters['city'].toString())),
      );
    }
    if (filters['plate_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          trLegacyText(context, 'Plate type', ar: 'نوع اللوحة', ku: 'جۆری پڵەیت'),
          translatePlateTypeLabel(context, filters['plate_type'].toString()),
        ),
      );
    }
    if (filters['plate_city'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          trLegacyText(context, 'Plate city', ar: 'مدينة اللوحة', ku: 'شاری پڵەیت'),
          tr(filters['plate_city'].toString()),
        ),
      );
    }
    if (filters['min_price'] != null || filters['max_price'] != null) {
      final priceRange =
          '${filters['min_price'] ?? '0'} - ${filters['max_price'] ?? '∞'}';
      chips.add(_buildFilterChip(context, l.priceLabel, priceRange));
    }
    if (filters['min_year'] != null || filters['max_year'] != null) {
      final yearRange =
          '${filters['min_year'] ?? '0'} - ${filters['max_year'] ?? '∞'}';
      chips.add(_buildFilterChip(context, l.yearLabel, yearRange));
    }
    if (filters['min_mileage'] != null || filters['max_mileage'] != null) {
      final mileageRange =
          '${filters['min_mileage'] ?? '0'} - ${filters['max_mileage'] ?? '∞'} ${l.unit_km}';
      chips.add(_buildFilterChip(context, l.mileageLabel, mileageRange));
    }
    if (filters['transmission'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.transmissionLabel,
          tr(filters['transmission'].toString()),
        ),
      );
    }
    if (filters['condition'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.conditionLabel,
          tr(filters['condition'].toString()),
        ),
      );
    }
    if (filters['body_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.bodyTypeLabel,
          tr(filters['body_type'].toString()),
        ),
      );
    }
    if (filters['fuel_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.fuelTypeLabel,
          tr(filters['fuel_type'].toString()),
        ),
      );
    }
    if (filters['color'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.colorLabel,
          tr(filters['color'].toString()),
        ),
      );
    }
    if (filters['drive_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.driveType,
          tr(filters['drive_type'].toString()),
        ),
      );
    }
    if (filters['region_specs'] != null) {
      final code = filters['region_specs'].toString().trim().toLowerCase();
      chips.add(
        _buildFilterChip(
          context,
          l.regionSpecsLabel,
          carRegionSpecDisplayLabelLocalized(context, code),
        ),
      );
    }
    if (filters['cylinder_count'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.cylinderCount,
          filters['cylinder_count'].toString(),
        ),
      );
    }
    if (filters['seating'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.seating,
          filters['seating'].toString(),
        ),
      );
    }
    if (filters['engine_size'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.engineSizeL,
          engineSizeChipLabel(context, filters['engine_size'].toString()),
        ),
      );
    }
    if (filters['title_status'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.status,
          tr(filters['title_status'].toString()),
        ),
      );
    }
    if (filters['damaged_parts'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          'Damaged Parts',
          filters['damaged_parts'].toString(),
        ),
      );
    }
    if (filters['sort_by'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.sortBy,
          _capitalizeFirst(filters['sort_by'].toString()),
        ),
      );
    }
    if (filters['owners'] != null) {
      chips.add(
        _buildFilterChip(context, 'Owners', filters['owners'].toString()),
      );
    }
    if (filters['vin'] != null) {
      chips.add(_buildFilterChip(context, 'VIN', filters['vin'].toString()));
    }
    if (filters['accident_history'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          'Accident History',
          _capitalizeFirst(filters['accident_history'].toString()),
        ),
      );
    }

    if (chips.isEmpty) {
      return Text(
        l.noFiltersApplied,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      );
    }
    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }

  Widget _buildFilterChip(BuildContext context, String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFFF6B00).withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, color: Color(0xFFFF6B00)),
      ),
    );
  }

  String _formatDate(BuildContext context, String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);
      final l = AppLocalizations.of(context)!;
      final timeStr =
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

      if (difference.inDays == 0) {
        return '${l.today} $timeStr';
      } else if (difference.inDays == 1) {
        return '${l.yesterday} $timeStr';
      } else if (difference.inDays < 7) {
        return l.daysAgo(difference.inDays);
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateString;
    }
  }

  void _applySearch(Map<String, dynamic> filters) async {
    final normalized = SavedSearchService.normalizeFilters(filters);
    await SavedSearchHomeBridge.persistFiltersForHome(normalized);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final successText = trLegacyText(
      context,
      'Search applied successfully!',
      ar: 'تم تطبيق البحث بنجاح!',
      ku: 'گەڕان بە سەرکەوتوویی جێبەجێ کرا!',
    );

    final parent = widget.parentState;
    if (parent != null && parent.mounted) {
      Navigator.pop(context);
      parent.setState(() {
        parent.applyFiltersFromSavedSearch(normalized);
      });
      parent.fetchCars(bypassCache: true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(successText),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    Navigator.pop(context);
    await SavedSearchHomeBridge.markPendingFetch();
    if (!mounted) return;
    navigateMainShellTab(context, '/');
    messenger.showSnackBar(
      SnackBar(
        content: Text(successText),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showFilterDetails(String searchName, Map<String, dynamic> filters) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          searchName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.filter_list, color: Color(0xFFFF6B00), size: 20),
                  SizedBox(width: 8),
                  Text(
                    trLegacyText(
                      context,
                      'Applied Filters:',
                      ar: 'الفلاتر المطبقة:',
                      ku: 'فلتەرە جێبەجێکراوەکان:',
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              _buildDetailedFilterList(filters),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[400]),
            child: Text(
              trLegacyText(
                context,
                'Close',
                ar: 'إغلاق',
                ku: 'داخستن',
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _applySearch(filters);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF6B00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              trLegacyText(
                context,
                'Apply Search',
                ar: 'تطبيق البحث',
                ku: 'جێبەجێکردنی گەڕان',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedFilterList(Map<String, dynamic> filters) {
    final l = AppLocalizations.of(context)!;
    final any = l.anyOption;
    String tr(String? v) =>
        translateListingValue(context, v?.toString()) ?? v ?? '';
    final List<Widget> filterItems = [];

    // Vehicle Information
    if (filters['brand'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.brandLabel,
          CarNameTranslations.getLocalizedBrand(
            context,
            filters['brand'].toString(),
          ),
        ),
      );
    }
    if (filters['model'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.modelLabel,
          CarNameTranslations.getLocalizedModel(
            context,
            filters['brand']?.toString(),
            filters['model'].toString(),
          ),
        ),
      );
    }
    if (filters['trim'] != null) {
      filterItems.add(
        _buildFilterDetailItem(l.trimLabel, filters['trim'].toString()),
      );
    }

    // Price Range
    if (filters['min_price'] != null || filters['max_price'] != null) {
      final minPrice = filters['min_price']?.toString() ?? any;
      final maxPrice = filters['max_price']?.toString() ?? any;
      filterItems.add(
        _buildFilterDetailItem(l.priceLabel, '$minPrice - $maxPrice'),
      );
    }

    // Year Range
    if (filters['min_year'] != null || filters['max_year'] != null) {
      final minYear = filters['min_year']?.toString() ?? any;
      final maxYear = filters['max_year']?.toString() ?? any;
      filterItems.add(
        _buildFilterDetailItem(l.yearLabel, '$minYear - $maxYear'),
      );
    }

    // Mileage Range
    if (filters['min_mileage'] != null || filters['max_mileage'] != null) {
      final minMileage = filters['min_mileage']?.toString() ?? any;
      final maxMileage = filters['max_mileage']?.toString() ?? any;
      filterItems.add(
        _buildFilterDetailItem(
          l.mileageLabel,
          '$minMileage - $maxMileage ${l.unit_km}',
        ),
      );
    }

    // Vehicle Specifications
    if (filters['condition'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.conditionLabel,
          tr(filters['condition'].toString()),
        ),
      );
    }
    if (filters['transmission'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.transmissionLabel,
          tr(filters['transmission'].toString()),
        ),
      );
    }
    if (filters['fuel_type'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.fuelTypeLabel,
          tr(filters['fuel_type'].toString()),
        ),
      );
    }
    if (filters['body_type'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.bodyTypeLabel,
          tr(filters['body_type'].toString()),
        ),
      );
    }
    if (filters['color'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.colorLabel,
          tr(filters['color'].toString()),
        ),
      );
    }
    if (filters['drive_type'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.driveType,
          tr(filters['drive_type'].toString()),
        ),
      );
    }
    if (filters['region_specs'] != null) {
      final code = filters['region_specs'].toString().trim().toLowerCase();
      filterItems.add(
        _buildFilterDetailItem(
          l.regionSpecsLabel,
          carRegionSpecDisplayLabelLocalized(context, code),
        ),
      );
    }
    if (filters['cylinder_count'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.cylinderCount,
          filters['cylinder_count'].toString(),
        ),
      );
    }
    if (filters['seating'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.seating,
          filters['seating'].toString(),
        ),
      );
    }
    if (filters['engine_size'] != null) {
      final es = filters['engine_size'].toString().trim();
      filterItems.add(
        _buildFilterDetailItem(
          l.engineSizeL,
          engineSizeChipLabel(context, es),
        ),
      );
    }

    // Location and Other
    if (filters['city'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.cityLabel,
          tr(filters['city'].toString()),
        ),
      );
    }
    if (filters['title_status'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.status,
          tr(filters['title_status'].toString()),
        ),
      );
    }
    if (filters['damaged_parts'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          trLegacyText(
            context,
            'Damaged Parts',
            ar: 'الأجزاء التالفة',
            ku: 'پارچە زیان‌لێکەوتووەکان',
          ),
          filters['damaged_parts'].toString(),
        ),
      );
    }
    if (filters['sort_by'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          l.sortBy,
          tr(filters['sort_by'].toString()),
        ),
      );
    }
    if (filters['owners'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          trLegacyText(
            context,
            'Owners',
            ar: 'المالكون',
            ku: 'خاوەنەکان',
          ),
          filters['owners'].toString(),
        ),
      );
    }
    if (filters['vin'] != null) {
      filterItems.add(
        _buildFilterDetailItem('VIN', filters['vin'].toString()),
      );
    }
    if (filters['accident_history'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          trLegacyText(
            context,
            'Accident History',
            ar: 'سجل الحوادث',
            ku: 'مێژووی ڕووداو',
          ),
          tr(filters['accident_history'].toString()),
        ),
      );
    }

    if (filterItems.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Color(0xFF404040), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey[400], size: 20),
            SizedBox(width: 8),
            Text(
              l.noFiltersApplied,
              style: TextStyle(
                color: Colors.grey[400],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 6, children: filterItems);
  }

  Widget _buildFilterDetailItem(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(0xFF404040), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFFFF6B00),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}
