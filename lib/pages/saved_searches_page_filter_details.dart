part of 'saved_searches_page.dart';

mixin _SavedSearchesPageFilterDetails on _SavedSearchesPageHelpers {
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
}
