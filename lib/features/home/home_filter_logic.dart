part of 'home_flow.dart';

mixin _HomePageFilterLogic on _HomePageFilterPersist {
  bool _hasActiveFilters() => _homeFiltersSnapshot().hasActiveFilters;

  // Helper method to clear all filters
  void _clearAllFilters() {
    setState(() {
      _resetAllFiltersInMemory();
      _syncHomeFilterTextControllersFromSelection();
    });
    unawaited(_clearFiltersOnly());
    onFilterChanged();
  }

  // Helper method to clear a specific filter
  void _clearFilter(String filterType) {
    setState(() {
      _applyHomeFiltersSnapshot(
        clearHomeFilterChip(_homeFiltersSnapshot(), filterType),
      );
      _syncHomeFilterTextControllersFromSelection();
    });
    unawaited(_persistFilters());
    onFilterChanged();
  }

  // Helper method to build active filter chips
  List<Widget> _buildActiveFilterChips() {
    final l10n = AppLocalizations.of(context)!;
    final descriptors = buildHomeFilterChipDescriptors(
      filters: _homeFiltersSnapshot(),
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
        city: l10n.cityLabel,
        plateType: _trLegacyText(
          context,
          'Plate type',
          ar: 'نوع اللوحة',
          ku: 'جۆری پڵەیت',
        ),
        plateCity: _trLegacyText(
          context,
          'Plate city',
          ar: 'مدينة اللوحة',
          ku: 'شاری پڵەیت',
        ),
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
        translateValue: (raw) => _translateValueGlobal(context, raw) ?? raw ?? '',
        localizeDigits: (raw) => _localizeDigitsGlobal(context, raw),
        formatCurrency: (raw) => _formatCurrencyGlobal(context, raw),
        engineSizeLabel: (raw) => _engineSizeChipLabel(context, raw),
        plateTypeLabel: (raw) => _translatePlateTypeLegacy(context, raw),
        regionSpecsLabel: (code) =>
            carRegionSpecDisplayLabelLocalized(context, code),
        titleStatusDamagedWithParts: (parts) =>
            l10n.titleStatusDamagedWithParts(parts),
      ),
    );
    return descriptors
        .map(
          (d) => HomeFilterChip(
            descriptor: d,
            onClear: () => _clearFilter(d.filterType),
          ),
        )
        .toList();
  }

  void _showSearchDialog(BuildContext context) {
    showHomeBrandModelSearchDialog(
      context: context,
      brands: homeBrands,
      models: models,
      onBrandSelected: (brand) {
        setState(() {
          selectedBrand = brand;
          selectedModel = null;
          selectedTrim = null;
          clearFiltersOnVehicleChange();
        });
        onFilterChanged();
      },
      onModelSelected: (brand, model) {
        setState(() {
          selectedBrand = brand;
          selectedModel = model;
          selectedTrim = null;
          clearFiltersOnVehicleChange();
        });
        onFilterChanged();
      },
    );
  }
}
