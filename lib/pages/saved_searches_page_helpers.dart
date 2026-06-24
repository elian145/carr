part of 'saved_searches_page.dart';

mixin _SavedSearchesPageHelpers on _SavedSearchesPageLoad {
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

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}
