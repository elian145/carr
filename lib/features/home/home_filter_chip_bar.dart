import 'package:flutter/material.dart';

import '../../data/car_name_translations.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/listing_field_labels.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/i18n/region_spec_labels.dart';
import '../../shared/i18n/sort_api_mapping.dart';
import 'home_filter_chips.dart';
import 'home_filters_query.dart';
import 'widgets/home_filter_chip.dart';

/// Localized active-filter chips used on Home and dealer inventory search.
List<Widget> buildLocalizedHomeFilterChips(
  BuildContext context, {
  required HomeFiltersSnapshot filters,
  required void Function(String filterType) onClear,
}) {
  final l10n = AppLocalizations.of(context)!;
  final descriptors = buildHomeFilterChipDescriptors(
    filters: filters,
    labels: HomeFilterChipLabels(
      brand: l10n.brandLabel,
      model: l10n.modelLabel,
      trim: l10n.trimLabel,
      price: l10n.priceLabel,
      year: l10n.yearLabel,
      mileage: l10n.mileageLabel,
      condition: l10n.detail_condition,
      transmission: l10n.transmissionLabel,
      fuel: l10n.detail_fuel,
      titleStatus: l10n.titleStatus,
      bodyType: l10n.bodyTypeLabel,
      color: l10n.colorLabel,
      driveType: l10n.driveType,
      regionSpecs: l10n.regionSpecsLabel,
      cylinders: l10n.detail_cylinders,
      seating: l10n.seating,
      engineSize: l10n.engineSizeL,
      plateType: l10n.labelPlateType,
      plateCity: l10n.labelPlateCity,
      sortBy: l10n.sortBy,
      minPrice: l10n.minPrice,
      maxPrice: l10n.maxPrice,
      minYear: l10n.minYear,
      maxYear: l10n.maxYear,
      minMileage: l10n.minMileage,
      maxMileage: l10n.maxMileage,
      unitKm: l10n.unit_km,
    ),
    formatters: HomeFilterChipFormatters(
      localizedBrand: (brand) =>
          CarNameTranslations.getLocalizedBrand(context, brand),
      localizedModel: (brand, model) =>
          CarNameTranslations.getLocalizedModel(context, brand, model!),
      translateValue: (raw) => translateListingValue(context, raw) ?? raw ?? '',
      localizeDigits: (raw) => localizeDigits(context, raw),
      formatCurrency: (raw) => formatCurrency(context, raw),
      engineSizeLabel: (raw) => engineSizeChipLabel(context, raw),
      plateTypeLabel: (raw) => translatePlateTypeLabel(context, raw),
      regionSpecsLabel: (code) =>
          carRegionSpecDisplayLabelLocalized(context, code),
      titleStatusDamagedWithParts: l10n.titleStatusDamagedWithParts,
      localizeSort: (raw) => localizeSortOption(context, raw),
    ),
  );
  return descriptors
      .map(
        (d) => HomeFilterChip(
          descriptor: d,
          onClear: () => onClear(d.filterType),
        ),
      )
      .toList();
}
