part of 'home_flow.dart';

mixin _HomePageFilterLogic on _HomePageFilterPersist {
  String? get _homeSelectedBrand => homeFilterDecodeSingle(selectedBrand);

  String? get _homeSingleSelectedBrand => _homeSelectedBrand;

  List<String> get _homeSelectedBodyTypes =>
      homeFilterDecodeList(selectedBodyType);

  void _homeSetSelectedBrand(String? brand) {
    if (brand == null ||
        brand.trim().isEmpty ||
        brand.trim().toLowerCase() == 'any') {
      selectedBrand = null;
    } else {
      selectedBrand = homeFilterDecodeSingle(brand) ?? brand.trim();
    }
    selectedModel = null;
    selectedTrim = null;
  }

  void _homeToggleBrand(String brand) {
    if (_homeSelectedBrand == brand) {
      _homeSetSelectedBrand(null);
    } else {
      _homeSetSelectedBrand(brand);
    }
  }

  String _homeBrandFilterLabel(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final brand = _homeSelectedBrand;
    if (brand == null) return loc.any;
    final localized = CarNameTranslations.getLocalizedBrand(context, brand);
    return localized.isNotEmpty ? localized : brand;
  }

  void _homeSetSelectedBodyTypes(List<String> types) {
    selectedBodyType = homeFilterEncodeList(types);
  }

  void _homeToggleBodyType(String bodyType) {
    if (bodyType == 'Any') {
      _homeSetSelectedBodyTypes([]);
      return;
    }
    _homeSetSelectedBodyTypes(
      homeFilterToggleValue(_homeSelectedBodyTypes, bodyType),
    );
  }

  String _homeBodyTypeFilterLabel(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return homeFilterSummaryLabel(
      loc.any,
      _homeSelectedBodyTypes,
      (bodyType) =>
          _translateValueGlobal(context, bodyType) ?? bodyType,
    );
  }

  List<String> get _homeSelectedFuelTypes =>
      homeFilterDecodeList(selectedFuelType);

  List<String> get _homeSelectedDriveTypes =>
      homeFilterDecodeList(selectedDriveType);

  void _homeSetSelectedFuelTypes(List<String> types) {
    selectedFuelType = homeFilterEncodeList(types);
  }

  void _homeSetSelectedDriveTypes(List<String> types) {
    selectedDriveType = homeFilterEncodeList(types);
  }

  void _homeToggleFuelType(String fuelType) {
    if (fuelType == 'Any') {
      _homeSetSelectedFuelTypes([]);
      return;
    }
    _homeSetSelectedFuelTypes(
      homeFilterToggleValue(_homeSelectedFuelTypes, fuelType),
    );
  }

  void _homeToggleDriveType(String driveType) {
    if (driveType == 'Any') {
      _homeSetSelectedDriveTypes([]);
      return;
    }
    _homeSetSelectedDriveTypes(
      homeFilterToggleValue(_homeSelectedDriveTypes, driveType),
    );
  }

  String _homeFuelTypeFilterLabel(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return homeFilterSummaryLabel(
      loc.any,
      _homeSelectedFuelTypes,
      (fuel) => _translateValueGlobal(context, fuel) ?? fuel,
    );
  }

  String _homeDriveTypeFilterLabel(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return homeFilterSummaryLabel(
      loc.any,
      _homeSelectedDriveTypes,
      (drive) => _translateValueGlobal(context, drive) ?? drive,
    );
  }

  Future<List<String>?> _showHomeMultiValuePickerDialog(
    BuildContext context, {
    required String title,
    required List<String> options,
    required List<String> initialSelection,
    String Function(BuildContext, String)? labelForOption,
  }) {
    final selectable =
        options.where((o) => o != 'Any').toList(growable: false);
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        final selected = Set<String>.from(initialSelection);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void toggle(String value) {
              setDialogState(() {
                if (selected.contains(value)) {
                  selected.remove(value);
                } else {
                  selected.add(value);
                }
              });
            }

            return Dialog(
              backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ResponsiveDialogBody(
                maxHeight: AppResponsive.dialogMaxHeight(context, fraction: 0.75),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.orbitron(
                              color: const Color(0xFFFF6B00),
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, <String>[]),
                          child: Text(AppLocalizations.of(context)!.any),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                    if (selected.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _trLegacyText(
                            context,
                            '${selected.length} selected',
                            ar: '${selected.length} محدد',
                            ku: '${selected.length} هەڵبژێردراو',
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: selectable.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final value = selectable[index];
                          final isSelected = selected.contains(value);
                          final label = labelForOption?.call(context, value) ??
                              _translateValueGlobal(context, value) ??
                              value;
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => toggle(value),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFFF6B00)
                                      : Colors.white24,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Text(
                                label,
                                style: GoogleFonts.orbitron(
                                  fontSize: 14,
                                  color: isSelected
                                      ? const Color(0xFFFF6B00)
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          selected.toList(),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                        ),
                        child: Text(
                          _trLegacyText(
                            context,
                            'Apply',
                            ar: 'تطبيق',
                            ku: 'جێبەجێکردن',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

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
          _homeSetSelectedBrand(brand);
          clearFiltersOnVehicleChange();
        });
        onFilterChanged();
      },
      onModelSelected: (brand, model) {
        setState(() {
          _homeSetSelectedBrand(brand);
          selectedModel = model;
          selectedTrim = null;
          clearFiltersOnVehicleChange();
        });
        onFilterChanged();
      },
    );
  }
}
