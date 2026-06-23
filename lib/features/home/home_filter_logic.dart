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
      switch (filterType) {
        case 'brand':
          selectedBrand = null;
          selectedModel = null;
          selectedTrim = null;
          break;
        case 'model':
          selectedModel = null;
          selectedTrim = null;
          break;
        case 'trim':
          selectedTrim = null;
          break;
        case 'price':
          selectedMinPrice = null;
          selectedMaxPrice = null;
          break;
        case 'year':
          selectedMinYear = null;
          selectedMaxYear = null;
          break;
        case 'mileage':
          selectedMinMileage = null;
          selectedMaxMileage = null;
          break;
        case 'condition':
          selectedCondition = null;
          break;
        case 'transmission':
          selectedTransmission = null;
          break;
        case 'fuelType':
          selectedFuelType = null;
          break;
        case 'titleStatus':
          selectedTitleStatus = null;
          selectedDamagedParts = null;
          break;
        case 'damagedParts':
          selectedDamagedParts = null;
          break;
        case 'bodyType':
          selectedBodyType = null;
          break;
        case 'color':
          selectedColor = null;
          break;
        case 'driveType':
          selectedDriveType = null;
          break;
        case 'regionSpecs':
          selectedRegionSpecs = null;
          break;
        case 'cylinderCount':
          selectedCylinderCount = null;
          break;
        case 'seating':
          selectedSeating = null;
          break;
        case 'engineSize':
          selectedEngineSize = null;
          break;
        case 'city':
          selectedCity = null;
          break;
        case 'plateType':
          selectedPlateType = null;
          break;
        case 'plateCity':
          selectedPlateCity = null;
          break;
        case 'sortBy':
          selectedSortBy = null;
          break;
      }
      _syncHomeFilterTextControllersFromSelection();
    });
    unawaited(_persistFilters());
    onFilterChanged();
  }

  // Helper method to build active filter chips
  List<Widget> _buildActiveFilterChips() {
    List<Widget> chips = [];

    // Brand filter
    if (selectedBrand != null && selectedBrand!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.brandLabel,
          CarNameTranslations.getLocalizedBrand(
                context,
                selectedBrand,
              ).isNotEmpty
              ? CarNameTranslations.getLocalizedBrand(context, selectedBrand)
              : selectedBrand!,
          'brand',
          Icons.directions_car,
          Color(0xFFFF6B00),
        ),
      );
    }

    // Model filter
    if (selectedModel != null && selectedModel!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.modelLabel,
          CarNameTranslations.getLocalizedModel(
                context,
                selectedBrand,
                selectedModel,
              ).isNotEmpty
              ? CarNameTranslations.getLocalizedModel(
                  context,
                  selectedBrand,
                  selectedModel,
                )
              : selectedModel!,
          'model',
          Icons.directions_car,
          Color(0xFFFF6B00),
        ),
      );
    }

    // Trim filter
    if (selectedTrim != null && selectedTrim!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.trimLabel,
          selectedTrim!,
          'trim',
          Icons.settings,
          Color(0xFFFF6B00),
        ),
      );
    }

    // Price range filter
    if (selectedMinPrice != null || selectedMaxPrice != null) {
      String priceText = '';
      if (selectedMinPrice != null && selectedMaxPrice != null) {
        priceText =
            '${_formatCurrencyGlobal(context, selectedMinPrice!)} - ${_formatCurrencyGlobal(context, selectedMaxPrice!)}';
      } else if (selectedMinPrice != null) {
        priceText =
            '${AppLocalizations.of(context)!.minPrice}: ${_formatCurrencyGlobal(context, selectedMinPrice!)}';
      } else if (selectedMaxPrice != null) {
        priceText =
            '${AppLocalizations.of(context)!.maxPrice}: ${_formatCurrencyGlobal(context, selectedMaxPrice!)}';
      }
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.priceLabel,
          priceText,
          'price',
          Icons.attach_money,
          Colors.green,
        ),
      );
    }

    // Year range filter
    if (selectedMinYear != null || selectedMaxYear != null) {
      String yearText = '';
      if (selectedMinYear != null && selectedMaxYear != null) {
        yearText =
            '${_localizeDigitsGlobal(context, selectedMinYear!)} - ${_localizeDigitsGlobal(context, selectedMaxYear!)}';
      } else if (selectedMinYear != null) {
        yearText =
            '${AppLocalizations.of(context)!.minYear}: ${_localizeDigitsGlobal(context, selectedMinYear!)}';
      } else if (selectedMaxYear != null) {
        yearText =
            '${AppLocalizations.of(context)!.maxYear}: ${_localizeDigitsGlobal(context, selectedMaxYear!)}';
      }
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.yearLabel,
          yearText,
          'year',
          Icons.calendar_today,
          Colors.blue,
        ),
      );
    }

    // Mileage range filter
    if (selectedMinMileage != null || selectedMaxMileage != null) {
      String mileageText = '';
      if (selectedMinMileage != null && selectedMaxMileage != null) {
        mileageText =
            '${_localizeDigitsGlobal(context, selectedMinMileage!)} - ${_localizeDigitsGlobal(context, selectedMaxMileage!)} ${AppLocalizations.of(context)!.unit_km}';
      } else if (selectedMinMileage != null) {
        mileageText =
            '${AppLocalizations.of(context)!.minMileage}: ${_localizeDigitsGlobal(context, selectedMinMileage!)} ${AppLocalizations.of(context)!.unit_km}';
      } else if (selectedMaxMileage != null) {
        mileageText =
            '${AppLocalizations.of(context)!.maxMileage}: ${_localizeDigitsGlobal(context, selectedMaxMileage!)} ${AppLocalizations.of(context)!.unit_km}';
      }
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.mileageLabel,
          mileageText,
          'mileage',
          Icons.speed,
          Colors.orange,
        ),
      );
    }

    // Condition filter
    if (selectedCondition != null &&
        selectedCondition!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.detail_condition,
          _translateValueGlobal(context, selectedCondition) ??
              selectedCondition!,
          'condition',
          Icons.check_circle,
          Colors.green,
        ),
      );
    }

    // Transmission filter
    if (selectedTransmission != null &&
        selectedTransmission!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.transmissionLabel,
          _translateValueGlobal(context, selectedTransmission) ??
              selectedTransmission!,
          'transmission',
          Icons.settings,
          Colors.purple,
        ),
      );
    }

    // Fuel type filter
    if (selectedFuelType != null && selectedFuelType!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.detail_fuel,
          _translateValueGlobal(context, selectedFuelType) ?? selectedFuelType!,
          'fuelType',
          Icons.local_gas_station,
          Colors.orange,
        ),
      );
    }

    // Title/parts filter
    if (selectedTitleStatus != null && selectedTitleStatus!.isNotEmpty) {
      if (selectedTitleStatus == 'damaged' &&
          selectedDamagedParts != null &&
          selectedDamagedParts!.isNotEmpty) {
        chips.add(
          _buildFilterChip(
            AppLocalizations.of(context)!.titleStatus,
            AppLocalizations.of(context)!.titleStatusDamagedWithParts(
              _localizeDigitsGlobal(context, selectedDamagedParts!),
            ),
            'titleStatus',
            Icons.report,
            Colors.redAccent,
          ),
        );
      } else {
        chips.add(
          _buildFilterChip(
            AppLocalizations.of(context)!.titleStatus,
            _translateValueGlobal(context, selectedTitleStatus) ??
                selectedTitleStatus!.substring(0, 1).toUpperCase() +
                    selectedTitleStatus!.substring(1),
            'titleStatus',
            Icons.verified,
            Colors.green,
          ),
        );
      }
    }

    // Body type filter
    if (selectedBodyType != null && selectedBodyType!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.bodyTypeLabel,
          _translateValueGlobal(context, selectedBodyType) ?? selectedBodyType!,
          'bodyType',
          _getBodyTypeIcon(selectedBodyType!),
          Color(0xFFFF6B00),
        ),
      );
    }

    // Color filter
    if (selectedColor != null && selectedColor!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.colorLabel,
          _translateValueGlobal(context, selectedColor) ?? selectedColor!,
          'color',
          Icons.palette,
          _getColorValue(selectedColor!),
        ),
      );
    }

    // Drive type filter
    if (selectedDriveType != null &&
        selectedDriveType!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.driveType,
          _translateValueGlobal(context, selectedDriveType) ??
              selectedDriveType!,
          'driveType',
          Icons.directions_car,
          Colors.cyan,
        ),
      );
    }

    if (selectedRegionSpecs != null &&
        selectedRegionSpecs!.isNotEmpty &&
        isValidCarRegionSpecCode(selectedRegionSpecs)) {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.regionSpecsLabel,
          carRegionSpecDisplayLabelLocalized(
            context,
            selectedRegionSpecs!,
          ),
          'regionSpecs',
          Icons.public,
          Colors.blueGrey,
        ),
      );
    }

    // Cylinder count filter
    if (selectedCylinderCount != null &&
        selectedCylinderCount!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.detail_cylinders,
          _localizeDigitsGlobal(context, selectedCylinderCount!),
          'cylinderCount',
          Icons.engineering,
          Colors.red,
        ),
      );
    }

    // Seating filter
    if (selectedSeating != null && selectedSeating!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.seating,
          _localizeDigitsGlobal(context, selectedSeating!),
          'seating',
          Icons.airline_seat_recline_normal,
          Colors.indigo,
        ),
      );
    }

    // Engine Size filter
    if (selectedEngineSize != null &&
        selectedEngineSize!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.engineSizeL,
          _engineSizeChipLabel(context, selectedEngineSize!),
          'engineSize',
          Icons.engineering,
          Colors.deepOrange,
        ),
      );
    }

    // City filter
    if (selectedCity != null && selectedCity!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.cityLabel,
          _translateValueGlobal(context, selectedCity) ?? selectedCity!,
          'city',
          Icons.location_city,
          Colors.teal,
        ),
      );
    }

    // Plate type filter
    if (selectedPlateType != null &&
        selectedPlateType!.isNotEmpty &&
        selectedPlateType!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          _trLegacyText(context, 'Plate type', ar: 'نوع اللوحة', ku: 'جۆری پڵەیت'),
          _translatePlateTypeLegacy(context, selectedPlateType!),
          'plateType',
          Icons.confirmation_number_outlined,
          const Color(0xFFFF6B00),
        ),
      );
    }

    // Plate city filter
    if (selectedPlateCity != null &&
        selectedPlateCity!.isNotEmpty &&
        selectedPlateCity!.toLowerCase() != 'any') {
      chips.add(
        _buildFilterChip(
          _trLegacyText(context, 'Plate city', ar: 'مدينة اللوحة', ku: 'شاری پڵەیت'),
          _translateValueGlobal(context, selectedPlateCity) ?? selectedPlateCity!,
          'plateCity',
          Icons.location_on_outlined,
          const Color(0xFFFF6B00),
        ),
      );
    }

    // Sort by filter
    if (selectedSortBy != null &&
        selectedSortBy!.toLowerCase() != 'any' &&
        selectedSortBy!.toLowerCase() != 'default') {
      chips.add(
        _buildFilterChip(
          AppLocalizations.of(context)!.sortBy,
          _translateValueGlobal(context, selectedSortBy) ?? selectedSortBy!,
          'sortBy',
          Icons.sort,
          Colors.grey,
        ),
      );
    }

    return chips;
  }

  // Helper method to build individual filter chips
  Widget _buildFilterChip(
    String label,
    String value,
    String filterType,
    IconData icon,
    Color color,
  ) {
    final chipLabel = '$label: $value';
    return Semantics(
      button: true,
      label: '${AppLocalizations.of(context)!.clearFilters}, $chipLabel',
      child: GestureDetector(
        onTap: () => _clearFilter(filterType),
        child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 10),
            SizedBox(width: 4),
            Text(
              '$label: $value',
              style: GoogleFonts.orbitron(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(width: 4),
            Icon(Icons.close, color: color, size: 9),
          ],
        ),
      ),
    ),
    );
  }

  // Helper function to get body type icon
  IconData _getBodyTypeIcon(String bodyType) {
    switch (bodyType.toLowerCase()) {
      case 'sedan':
        return Icons.directions_car;
      case 'suv':
        return Icons.directions_car_filled;
      case 'hatchback':
        return Icons.directions_car;
      case 'coupe':
        return Icons.directions_car;
      case 'wagon':
        return Icons.directions_car;
      case 'pickup':
        return Icons.local_shipping;
      case 'van':
        return Icons.airport_shuttle;
      case 'minivan':
        return Icons.airport_shuttle;
      case 'motorcycle':
        return Icons.motorcycle;
      case 'utv':
        return Icons.directions_car;
      case 'atv':
        return Icons.directions_car;
      default:
        return Icons.directions_car;
    }
  }

  // Helper function to get color value
  Color _getColorValue(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'silver':
        return Colors.grey[300]!;
      case 'gray':
        return Colors.grey[600]!;
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'brown':
        return Colors.brown;
      case 'beige':
        return Color(0xFFF5F5DC);
      case 'gold':
        return Color(0xFFFFD700);
      default:
        return Colors.grey;
    }
  }

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => HomeSearchDialog(
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
          Navigator.pop(context);
        },
        onModelSelected: (brand, model) {
          setState(() {
            selectedBrand = brand;
            selectedModel = model;
            selectedTrim = null;
            clearFiltersOnVehicleChange();
          });
          onFilterChanged();
          Navigator.pop(context);
        },
      ),
    );
  }
}
