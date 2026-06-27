import 'package:flutter/material.dart';

import '../../shared/i18n/region_spec_labels.dart';
import 'home_filter_chip_style.dart';
import 'home_filters_query.dart';
import 'home_multi_select_filter.dart';

/// One active home filter chip (label, value, clear key, presentation).
class HomeFilterChipDescriptor {
  const HomeFilterChipDescriptor({
    required this.label,
    required this.value,
    required this.filterType,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String filterType;
  final IconData icon;
  final Color color;
}

/// Localized field labels for [buildHomeFilterChipDescriptors].
class HomeFilterChipLabels {
  const HomeFilterChipLabels({
    required this.brand,
    required this.model,
    required this.trim,
    required this.price,
    required this.year,
    required this.mileage,
    required this.condition,
    required this.transmission,
    required this.fuel,
    required this.titleStatus,
    required this.bodyType,
    required this.color,
    required this.driveType,
    required this.regionSpecs,
    required this.cylinders,
    required this.seating,
    required this.engineSize,
    required this.city,
    required this.plateType,
    required this.plateCity,
    required this.sortBy,
    required this.minPrice,
    required this.maxPrice,
    required this.minYear,
    required this.maxYear,
    required this.minMileage,
    required this.maxMileage,
    required this.unitKm,
  });

  final String brand;
  final String model;
  final String trim;
  final String price;
  final String year;
  final String mileage;
  final String condition;
  final String transmission;
  final String fuel;
  final String titleStatus;
  final String bodyType;
  final String color;
  final String driveType;
  final String regionSpecs;
  final String cylinders;
  final String seating;
  final String engineSize;
  final String city;
  final String plateType;
  final String plateCity;
  final String sortBy;
  final String minPrice;
  final String maxPrice;
  final String minYear;
  final String maxYear;
  final String minMileage;
  final String maxMileage;
  final String unitKm;
}

/// Resolves display strings for chip values from raw filter fields.
class HomeFilterChipFormatters {
  const HomeFilterChipFormatters({
    required this.localizedBrand,
    required this.localizedModel,
    required this.translateValue,
    required this.localizeDigits,
    required this.formatCurrency,
    required this.engineSizeLabel,
    required this.plateTypeLabel,
    required this.regionSpecsLabel,
    required this.titleStatusDamagedWithParts,
  });

  final String Function(String? brand) localizedBrand;
  final String Function(String? brand, String? model) localizedModel;
  final String Function(String? raw) translateValue;
  final String Function(String raw) localizeDigits;
  final String Function(String? raw) formatCurrency;
  final String Function(String raw) engineSizeLabel;
  final String Function(String raw) plateTypeLabel;
  final String Function(String code) regionSpecsLabel;
  final String Function(String parts) titleStatusDamagedWithParts;
}

bool homeFilterChipValueActive(String? value) {
  if (value == null || value.isEmpty) return false;
  return value.toLowerCase() != 'any';
}

bool homeFilterSortChipActive(String? sortBy) {
  if (!homeFilterChipValueActive(sortBy)) return false;
  final lower = sortBy!.toLowerCase();
  return lower != 'default';
}

/// Clears one chip filter (and dependent fields) from [filters].
HomeFiltersSnapshot _homeFilterRemoveListValue(
  HomeFiltersSnapshot filters, {
  required String field,
  required String value,
}) {
  switch (field) {
    case 'brand':
      return filters.copyWith(
        clearBrand: true,
        clearModel: true,
        clearTrim: true,
      );
    case 'bodyType':
      final remaining = homeFilterDecodeList(filters.bodyType)
          .where((b) => b != value)
          .toList();
      if (remaining.isEmpty) {
        return filters.copyWith(clearBodyType: true);
      }
      return filters.copyWith(
        bodyType: homeFilterEncodeList(remaining),
      );
    case 'fuelType':
      final remaining = homeFilterDecodeList(filters.fuelType)
          .where((f) => f != value)
          .toList();
      if (remaining.isEmpty) {
        return filters.copyWith(clearFuelType: true);
      }
      return filters.copyWith(
        fuelType: homeFilterEncodeList(remaining),
      );
    case 'driveType':
      final remaining = homeFilterDecodeList(filters.driveType)
          .where((d) => d != value)
          .toList();
      if (remaining.isEmpty) {
        return filters.copyWith(clearDriveType: true);
      }
      return filters.copyWith(
        driveType: homeFilterEncodeList(remaining),
      );
    default:
      return filters;
  }
}

/// Clears one chip filter (and dependent fields) from [filters].
HomeFiltersSnapshot clearHomeFilterChip(
  HomeFiltersSnapshot filters,
  String filterType,
) {
  final parsed = homeFilterParseChipKey(filterType);
  if (parsed.$2 != null) {
    return _homeFilterRemoveListValue(
      filters,
      field: parsed.$1,
      value: parsed.$2!,
    );
  }

  switch (filterType) {
    case 'brand':
      return filters.copyWith(clearBrand: true, clearModel: true, clearTrim: true);
    case 'model':
      return filters.copyWith(clearModel: true, clearTrim: true);
    case 'trim':
      return filters.copyWith(clearTrim: true);
    case 'price':
      return filters.copyWith(clearMinPrice: true, clearMaxPrice: true);
    case 'year':
      return filters.copyWith(clearMinYear: true, clearMaxYear: true);
    case 'mileage':
      return filters.copyWith(clearMinMileage: true, clearMaxMileage: true);
    case 'condition':
      return filters.copyWith(clearCondition: true);
    case 'transmission':
      return filters.copyWith(clearTransmission: true);
    case 'fuelType':
      return filters.copyWith(clearFuelType: true);
    case 'titleStatus':
      return filters.copyWith(clearTitleStatus: true, clearDamagedParts: true);
    case 'damagedParts':
      return filters.copyWith(clearDamagedParts: true);
    case 'bodyType':
      return filters.copyWith(clearBodyType: true);
    case 'color':
      return filters.copyWith(clearColor: true);
    case 'driveType':
      return filters.copyWith(clearDriveType: true);
    case 'regionSpecs':
      return filters.copyWith(clearRegionSpecs: true);
    case 'cylinderCount':
      return filters.copyWith(clearCylinderCount: true);
    case 'seating':
      return filters.copyWith(clearSeating: true);
    case 'engineSize':
      return filters.copyWith(clearEngineSize: true);
    case 'city':
      return filters.copyWith(clearCity: true);
    case 'plateType':
      return filters.copyWith(clearPlateType: true);
    case 'plateCity':
      return filters.copyWith(clearPlateCity: true);
    case 'sortBy':
      return filters.copyWith(clearSortByUi: true);
    default:
      return filters;
  }
}

String _rangeText({
  required String? min,
  required String? max,
  required String Function(String v) format,
  required String minLabel,
  required String maxLabel,
  String suffix = '',
}) {
  if (min != null && max != null) {
    return '${format(min)} - ${format(max)}$suffix';
  }
  if (min != null) return '$minLabel: ${format(min)}$suffix';
  if (max != null) return '$maxLabel: ${format(max)}$suffix';
  return '';
}

String _titleStatusChipValue(
  String status,
  String? damagedParts,
  HomeFilterChipFormatters formatters,
) {
  if (status == 'damaged' && homeFilterChipValueActive(damagedParts)) {
    return formatters.titleStatusDamagedWithParts(
      formatters.localizeDigits(damagedParts!),
    );
  }
  final translated = formatters.translateValue(status);
  if (translated.isNotEmpty) return translated;
  if (status.isEmpty) return status;
  return status[0].toUpperCase() + status.substring(1);
}

/// Builds chip descriptors for all active filters in [filters].
List<HomeFilterChipDescriptor> buildHomeFilterChipDescriptors({
  required HomeFiltersSnapshot filters,
  required HomeFilterChipLabels labels,
  required HomeFilterChipFormatters formatters,
}) {
  const brandOrange = Color(0xFFFF6B00);
  final chips = <HomeFilterChipDescriptor>[];

  void add(
    String label,
    String value,
    String filterType,
    IconData icon,
    Color color,
  ) {
    if (value.isEmpty) return;
    chips.add(
      HomeFilterChipDescriptor(
        label: label,
        value: value,
        filterType: filterType,
        icon: icon,
        color: color,
      ),
    );
  }

  if (homeFilterChipValueActive(filters.brand)) {
    final brandValue = homeFilterDecodeSingle(filters.brand)!;
    final brand = formatters.localizedBrand(brandValue);
    add(
      labels.brand,
      brand.isNotEmpty ? brand : brandValue,
      'brand',
      Icons.directions_car,
      brandOrange,
    );
  }

  if (homeFilterChipValueActive(filters.model)) {
    final model = formatters.localizedModel(
      homeFilterDecodeSingle(filters.brand),
      filters.model,
    );
    add(
      labels.model,
      model.isNotEmpty ? model : filters.model!,
      'model',
      Icons.directions_car,
      brandOrange,
    );
  }

  if (homeFilterChipValueActive(filters.trim)) {
    add(labels.trim, filters.trim!, 'trim', Icons.settings, brandOrange);
  }

  if (filters.minPrice != null || filters.maxPrice != null) {
    add(
      labels.price,
      _rangeText(
        min: filters.minPrice,
        max: filters.maxPrice,
        format: (v) => formatters.formatCurrency(v),
        minLabel: labels.minPrice,
        maxLabel: labels.maxPrice,
      ),
      'price',
      Icons.attach_money,
      Colors.green,
    );
  }

  if (filters.minYear != null || filters.maxYear != null) {
    add(
      labels.year,
      _rangeText(
        min: filters.minYear,
        max: filters.maxYear,
        format: formatters.localizeDigits,
        minLabel: labels.minYear,
        maxLabel: labels.maxYear,
      ),
      'year',
      Icons.calendar_today,
      Colors.blue,
    );
  }

  if (filters.minMileage != null || filters.maxMileage != null) {
    add(
      labels.mileage,
      _rangeText(
        min: filters.minMileage,
        max: filters.maxMileage,
        format: formatters.localizeDigits,
        minLabel: labels.minMileage,
        maxLabel: labels.maxMileage,
        suffix: ' ${labels.unitKm}',
      ),
      'mileage',
      Icons.speed,
      Colors.orange,
    );
  }

  if (homeFilterChipValueActive(filters.condition)) {
    add(
      labels.condition,
      formatters.translateValue(filters.condition),
      'condition',
      Icons.check_circle,
      Colors.green,
    );
  }

  if (homeFilterChipValueActive(filters.transmission)) {
    add(
      labels.transmission,
      formatters.translateValue(filters.transmission),
      'transmission',
      Icons.settings,
      Colors.purple,
    );
  }

  for (final fuelValue in homeFilterDecodeList(filters.fuelType)) {
    add(
      labels.fuel,
      formatters.translateValue(fuelValue),
      homeFilterChipItemKey('fuelType', fuelValue),
      Icons.local_gas_station,
      Colors.orange,
    );
  }

  if (homeFilterChipValueActive(filters.titleStatus)) {
    add(
      labels.titleStatus,
      _titleStatusChipValue(
        filters.titleStatus!,
        filters.damagedParts,
        formatters,
      ),
      'titleStatus',
      filters.titleStatus == 'damaged' &&
              homeFilterChipValueActive(filters.damagedParts)
          ? Icons.report
          : Icons.verified,
      filters.titleStatus == 'damaged' &&
              homeFilterChipValueActive(filters.damagedParts)
          ? Colors.redAccent
          : Colors.green,
    );
  }

  for (final bodyTypeValue in homeFilterDecodeList(filters.bodyType)) {
    add(
      labels.bodyType,
      formatters.translateValue(bodyTypeValue),
      homeFilterChipItemKey('bodyType', bodyTypeValue),
      homeFilterBodyTypeIcon(bodyTypeValue),
      brandOrange,
    );
  }

  if (homeFilterChipValueActive(filters.color)) {
    add(
      labels.color,
      formatters.translateValue(filters.color),
      'color',
      Icons.palette,
      homeFilterNamedColor(filters.color!),
    );
  }

  for (final driveValue in homeFilterDecodeList(filters.driveType)) {
    add(
      labels.driveType,
      formatters.translateValue(driveValue),
      homeFilterChipItemKey('driveType', driveValue),
      Icons.directions_car,
      Colors.cyan,
    );
  }

  if (homeFilterChipValueActive(filters.regionSpecs) &&
      isValidCarRegionSpecCode(filters.regionSpecs)) {
    add(
      labels.regionSpecs,
      formatters.regionSpecsLabel(filters.regionSpecs!),
      'regionSpecs',
      Icons.public,
      Colors.blueGrey,
    );
  }

  if (homeFilterChipValueActive(filters.cylinderCount)) {
    add(
      labels.cylinders,
      formatters.localizeDigits(filters.cylinderCount!),
      'cylinderCount',
      Icons.engineering,
      Colors.red,
    );
  }

  if (homeFilterChipValueActive(filters.seating)) {
    add(
      labels.seating,
      formatters.localizeDigits(filters.seating!),
      'seating',
      Icons.airline_seat_recline_normal,
      Colors.indigo,
    );
  }

  if (homeFilterChipValueActive(filters.engineSize)) {
    add(
      labels.engineSize,
      formatters.engineSizeLabel(filters.engineSize!),
      'engineSize',
      Icons.engineering,
      Colors.deepOrange,
    );
  }

  if (homeFilterChipValueActive(filters.city)) {
    add(
      labels.city,
      formatters.translateValue(filters.city),
      'city',
      Icons.location_city,
      Colors.teal,
    );
  }

  if (homeFilterChipValueActive(filters.plateType)) {
    add(
      labels.plateType,
      formatters.plateTypeLabel(filters.plateType!),
      'plateType',
      Icons.confirmation_number_outlined,
      brandOrange,
    );
  }

  if (homeFilterChipValueActive(filters.plateCity)) {
    add(
      labels.plateCity,
      formatters.translateValue(filters.plateCity),
      'plateCity',
      Icons.location_on_outlined,
      brandOrange,
    );
  }

  if (homeFilterSortChipActive(filters.sortByUi)) {
    add(
      labels.sortBy,
      formatters.translateValue(filters.sortByUi),
      'sortBy',
      Icons.sort,
      Colors.grey,
    );
  }

  return chips;
}
