import 'package:flutter/material.dart';

import '../../data/car_name_translations.dart';
import '../../l10n/app_localizations.dart';
import 'home_filter_labels.dart';

/// Compact filter summary chips for saved search list rows.
class SavedSearchFilterChips extends StatelessWidget {
  const SavedSearchFilterChips({super.key, required this.filters});

  final Map<String, dynamic> filters;

  @override
  Widget build(BuildContext context) {
    final chips = _buildChips(context);
    if (chips.isEmpty) {
      return Text(
        AppLocalizations.of(context)!.noFiltersApplied,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      );
    }
    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }

  List<Widget> _buildChips(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final chips = <Widget>[];
    String tr(String? v) =>
        homeFilterTranslateValue(context, v?.toString()) ?? v ?? '';

    void add(String label, String value) {
      chips.add(_chip('$label: $value'));
    }

    if (filters['brand'] != null) {
      add(
        l.brandLabel,
        CarNameTranslations.getLocalizedBrand(
          context,
          filters['brand'].toString(),
        ),
      );
    }
    if (filters['model'] != null) {
      add(
        l.modelLabel,
        CarNameTranslations.getLocalizedModel(
          context,
          filters['brand']?.toString(),
          filters['model'].toString(),
        ),
      );
    }
    if (filters['trim'] != null) {
      add(l.trimLabel, filters['trim'].toString());
    }
    if (filters['city'] != null) {
      add(l.cityLabel, tr(filters['city'].toString()));
    }
    if (filters['plate_type'] != null) {
      add(
        'Plate type',
        homeFilterPlateTypeLabel(context, filters['plate_type'].toString()),
      );
    }
    if (filters['plate_city'] != null) {
      add('Plate city', tr(filters['plate_city'].toString()));
    }
    if (filters['min_price'] != null || filters['max_price'] != null) {
      add(
        l.priceLabel,
        '${filters['min_price'] ?? '0'} - ${filters['max_price'] ?? '∞'}',
      );
    }
    if (filters['min_year'] != null || filters['max_year'] != null) {
      add(
        l.yearLabel,
        '${filters['min_year'] ?? '0'} - ${filters['max_year'] ?? '∞'}',
      );
    }
    if (filters['min_mileage'] != null || filters['max_mileage'] != null) {
      add(
        l.mileageLabel,
        '${filters['min_mileage'] ?? '0'} - ${filters['max_mileage'] ?? '∞'} ${l.unit_km}',
      );
    }
    if (filters['transmission'] != null) {
      add(l.transmissionLabel, tr(filters['transmission'].toString()));
    }
    if (filters['condition'] != null) {
      add(l.conditionLabel, tr(filters['condition'].toString()));
    }
    if (filters['body_type'] != null) {
      add(l.bodyTypeLabel, tr(filters['body_type'].toString()));
    }
    if (filters['fuel_type'] != null) {
      add(l.fuelTypeLabel, tr(filters['fuel_type'].toString()));
    }
    if (filters['color'] != null) {
      add(l.colorLabel, tr(filters['color'].toString()));
    }
    if (filters['drive_type'] != null) {
      add(l.driveType, tr(filters['drive_type'].toString()));
    }
    if (filters['region_specs'] != null) {
      add(
        l.regionSpecsLabel,
        homeFilterRegionSpecLabel(
          filters['region_specs'].toString().trim().toLowerCase(),
        ),
      );
    }
    if (filters['cylinder_count'] != null) {
      add(l.cylinderCount, filters['cylinder_count'].toString());
    }
    if (filters['seating'] != null) {
      add(l.seating, filters['seating'].toString());
    }
    if (filters['engine_size'] != null) {
      add(
        l.engineSizeL,
        homeFilterEngineSizeChipLabel(
          context,
          filters['engine_size'].toString(),
        ),
      );
    }
    if (filters['title_status'] != null) {
      add(l.status, tr(filters['title_status'].toString()));
    }
    if (filters['damaged_parts'] != null) {
      add('Damaged parts', filters['damaged_parts'].toString());
    }
    if (filters['sort_by'] != null) {
      final s = filters['sort_by'].toString();
      add(
        l.sortBy,
        s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase(),
      );
    }

    return chips;
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B00).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF6B00).withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Color(0xFFFF6B00)),
      ),
    );
  }
}

String savedSearchDisplayTitle(
  BuildContext context,
  Map<String, dynamic> item,
) {
  final filters = item['filters'] is Map
      ? Map<String, dynamic>.from(
          (item['filters'] as Map).cast<String, dynamic>(),
        )
      : <String, dynamic>{};
  final brand = filters['brand']?.toString().trim() ?? '';
  final model = filters['model']?.toString().trim() ?? '';
  final parts = <String>[];
  if (brand.isNotEmpty) {
    parts.add(CarNameTranslations.getLocalizedBrand(context, brand));
  }
  if (model.isNotEmpty) {
    parts.add(CarNameTranslations.getLocalizedModel(context, brand, model));
  }
  if (parts.isNotEmpty) return parts.join(' • ');
  final stored = item['name']?.toString().trim() ?? '';
  if (stored.isNotEmpty) return stored;
  return AppLocalizations.of(context)!.unnamedSearch;
}
