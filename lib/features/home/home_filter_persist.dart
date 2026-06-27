part of 'home_flow.dart';

mixin _HomePageFilterPersist on _HomePageFilterCatalog {
  void _resetAllFiltersInMemory() {
    selectedBrand = null;
    selectedModel = null;
    selectedTrim = null;
    selectedMinPrice = null;
    selectedMaxPrice = null;
    selectedMinYear = null;
    selectedMaxYear = null;
    selectedMinMileage = null;
    selectedMaxMileage = null;
    selectedCondition = null;
    selectedTransmission = null;
    selectedFuelType = null;
    selectedBodyType = null;
    selectedColor = null;
    selectedDriveType = null;
    selectedRegionSpecs = null;
    selectedCylinderCount = null;
    selectedSeating = null;
    selectedEngineSize = null;
    selectedCity = null;
    selectedPlateType = null;
    selectedPlateCity = null;
    selectedTitleStatus = null;
    selectedDamagedParts = null;
    contactPhone = null;
    selectedSortBy = null;
  }

  String? _filterStr(dynamic value) => homeFilterNormalizeStr(value);

  void _applyParsedHomeFilterFields(HomeFilterParsedFields parsed) {
    selectedBrand = homeFilterDecodeSingle(parsed.brand);
    selectedModel = parsed.model;
    selectedTrim = parsed.trim;
    selectedMinPrice = parsed.minPrice;
    selectedMaxPrice = parsed.maxPrice;
    selectedMinYear = parsed.minYear;
    selectedMaxYear = parsed.maxYear;
    selectedMinMileage = parsed.minMileage;
    selectedMaxMileage = parsed.maxMileage;
    selectedCondition = parsed.condition;
    selectedTransmission = parsed.transmission;
    selectedFuelType = parsed.fuelType;
    selectedBodyType = parsed.bodyType;
    selectedColor = parsed.color;
    selectedDriveType = parsed.driveType;
    selectedRegionSpecs = parsed.regionSpecs;
    selectedCylinderCount = parsed.cylinderCount;
    selectedSeating = parsed.seating;
    selectedEngineSize = parsed.engineSize;
    selectedCity = parsed.city;
    selectedPlateType = parsed.plateType;
    selectedPlateCity = parsed.plateCity;
    selectedTitleStatus = parsed.titleStatus;
    selectedDamagedParts = parsed.damagedParts;
    selectedSortBy = parsed.sortBy;
  }

  void _applyHomeFiltersSnapshot(HomeFiltersSnapshot snap) {
    selectedBrand = homeFilterDecodeSingle(snap.brand);
    selectedModel = snap.model;
    selectedTrim = snap.trim;
    selectedMinPrice = snap.minPrice;
    selectedMaxPrice = snap.maxPrice;
    selectedMinYear = snap.minYear;
    selectedMaxYear = snap.maxYear;
    selectedMinMileage = snap.minMileage;
    selectedMaxMileage = snap.maxMileage;
    selectedCondition = snap.condition;
    selectedTransmission = snap.transmission;
    selectedFuelType = snap.fuelType;
    selectedBodyType = snap.bodyType;
    selectedColor = snap.color;
    selectedDriveType = snap.driveType;
    selectedRegionSpecs = snap.regionSpecs;
    selectedCylinderCount = snap.cylinderCount;
    selectedSeating = snap.seating;
    selectedEngineSize = snap.engineSize;
    selectedCity = snap.city;
    selectedPlateType = snap.plateType;
    selectedPlateCity = snap.plateCity;
    selectedTitleStatus = snap.titleStatus;
    selectedDamagedParts = snap.damagedParts;
    selectedSortBy = snap.sortByUi;
  }

  /// Apply filters from a saved-search map (`min_price`, `cylinder_count`, etc.).
  void applyFiltersFromSavedSearch(Map<String, dynamic> normalized) {
    _resetAllFiltersInMemory();
    _applyParsedHomeFilterFields(
      HomeFilterParsedFields.fromSavedSearchMap(normalized),
    );
    _syncHomeFilterTextControllersFromSelection();
  }

  /// Apply filters stored in [home_filters_v1] / one-time home persist shape.
  void applyFiltersFromHomePersistMap(Map<String, dynamic> map) {
    _resetAllFiltersInMemory();
    _applyParsedHomeFilterFields(
      HomeFilterParsedFields.fromHomePersistMap(map),
    );
    _syncHomeFilterTextControllersFromSelection();
  }

  /// Clears only fields shown in the More Filters dialog (not brand/model/trim/sort).
  Future<void> _resetFiltersFromMoreFiltersDialog(
    VoidCallback refreshDialog,
  ) async {
    setState(() {
      selectedMinPrice = null;
      selectedMaxPrice = null;
      selectedMinYear = null;
      selectedMaxYear = null;
      selectedMinMileage = null;
      selectedMaxMileage = null;
      selectedCondition = null;
      selectedTransmission = null;
      selectedFuelType = null;
      selectedBodyType = null;
      selectedColor = null;
      selectedDriveType = null;
      selectedRegionSpecs = null;
      selectedCylinderCount = null;
      selectedSeating = null;
      selectedEngineSize = null;
      selectedPlateType = null;
      selectedPlateCity = null;
      selectedTitleStatus = null;
      selectedDamagedParts = null;
      _moreFiltersDialogFieldGeneration++;
      isPriceDropdown = true;
      isYearDropdown = true;
      isMileageDropdown = true;
      isEngineSizeDropdown = true;
      _minPriceController.clear();
      _maxPriceController.clear();
      _minYearController.clear();
      _maxYearController.clear();
      _minMileageController.clear();
      _maxMileageController.clear();
      _engineSizeController.clear();
    });
    refreshDialog();
    await _persistFilters();
    onFilterChanged();
  }

  Future<void> _restoreFilters() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_HomePageFields._filtersKey);
      if (raw == null || raw.isEmpty) return;
      final map = json.decode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _applyParsedHomeFilterFields(
          HomeFilterParsedFields.fromHomePersistMap(map),
        );
      });
      _syncHomeFilterTextControllersFromSelection();
    } catch (e, st) { logNonFatal(e, st); }
  }

  void _syncHomeFilterTextControllersFromSelection() {
    _minPriceController.text = selectedMinPrice ?? '';
    _maxPriceController.text = selectedMaxPrice ?? '';
    _minYearController.text = selectedMinYear ?? '';
    _maxYearController.text = selectedMaxYear ?? '';
    _minMileageController.text = selectedMinMileage ?? '';
    _maxMileageController.text = selectedMaxMileage ?? '';
    _engineSizeController.text = selectedEngineSize ?? '';
  }

  Map<String, dynamic> _moreFiltersDialogSnapshot() {
    return <String, dynamic>{
      'price_min': selectedMinPrice,
      'price_max': selectedMaxPrice,
      'year_min': selectedMinYear,
      'year_max': selectedMaxYear,
      'min_mileage': selectedMinMileage,
      'max_mileage': selectedMaxMileage,
      'condition': selectedCondition,
      'transmission': selectedTransmission,
      'fuel_type': selectedFuelType,
      'body_type': selectedBodyType,
      'color': selectedColor,
      'drive_type': selectedDriveType,
      'region_specs': selectedRegionSpecs,
      'cylinders': selectedCylinderCount,
      'seating': selectedSeating,
      'engine_size': selectedEngineSize,
      'plate_type': selectedPlateType,
      'plate_city': selectedPlateCity,
      'title_status': selectedTitleStatus,
      'damaged_parts': selectedDamagedParts,
      'isPriceDropdown': isPriceDropdown,
      'isYearDropdown': isYearDropdown,
      'isMileageDropdown': isMileageDropdown,
      'isEngineSizeDropdown': isEngineSizeDropdown,
    };
  }

  void _restoreMoreFiltersDialogSnapshot(Map<String, dynamic> snap) {
    setState(() {
      selectedMinPrice = _filterStr(snap['price_min']);
      selectedMaxPrice = _filterStr(snap['price_max']);
      selectedMinYear = _filterStr(snap['year_min']);
      selectedMaxYear = _filterStr(snap['year_max']);
      selectedMinMileage = _filterStr(snap['min_mileage']);
      selectedMaxMileage = _filterStr(snap['max_mileage']);
      selectedCondition = _filterStr(snap['condition']);
      selectedTransmission = _filterStr(snap['transmission']);
      selectedFuelType = _filterStr(snap['fuel_type']);
      selectedBodyType = _filterStr(snap['body_type']);
      selectedColor = _filterStr(snap['color']);
      selectedDriveType = _filterStr(snap['drive_type']);
      final rsRaw = homeFilterNormalizeRegionSpecs(
        homeFilterNormalizeStr(snap['region_specs']),
      );
      selectedRegionSpecs = rsRaw;
      selectedCylinderCount = _filterStr(snap['cylinders']);
      selectedSeating = _filterStr(snap['seating']);
      selectedEngineSize = _filterStr(snap['engine_size']);
      selectedPlateType = _filterStr(snap['plate_type']);
      selectedPlateCity = _filterStr(snap['plate_city']);
      selectedTitleStatus = _filterStr(snap['title_status']);
      selectedDamagedParts = _filterStr(snap['damaged_parts']);
      isPriceDropdown = snap['isPriceDropdown'] == true;
      isYearDropdown = snap['isYearDropdown'] == true;
      isMileageDropdown = snap['isMileageDropdown'] == true;
      isEngineSizeDropdown = snap['isEngineSizeDropdown'] == true;
      _syncHomeFilterTextControllersFromSelection();
    });
  }

  Future<void> _persistFilters() async {
    try {
      if (!_homeFiltersSnapshot().hasActiveFilters) {
        await _clearFiltersOnly();
        return;
      }
      final sp = await SharedPreferences.getInstance();
      final map = homeFilterHomePersistMap(_homeFiltersSnapshot());
      await sp.setString(_HomePageFields._filtersKey, json.encode(map));
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _clearFiltersOnly() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_HomePageFields._filtersKey);
      await sp.remove(_HomePageFields._sellFiltersKey);
      await sp.remove(_HomePageFields._savedSearchesKey);
      // Don't clear cached car data to improve reliability
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _saveCurrentSearch() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final List<dynamic> raw = json.decode(
        sp.getString(_HomePageFields._savedSearchesKey) ?? '[]',
      );
      final currentFilters = SavedSearchService.normalizeFilters(
        _getCurrentFilterState(),
      );
      final searchName = _generateSearchName();

      Map<String, dynamic>? existing;
      for (final item in raw) {
        if (item is! Map) continue;
        final filters = item['filters'] is Map
            ? Map<String, dynamic>.from(
                (item['filters'] as Map).cast<String, dynamic>(),
              )
            : <String, dynamic>{};
        if (SavedSearchService.filtersEqual(filters, currentFilters)) {
          existing = Map<String, dynamic>.from(item.cast<String, dynamic>());
          break;
        }
      }

      final Map<String, dynamic> payload = existing != null
          ? {
              ...existing,
              'name': searchName,
              'filters': currentFilters,
              'notify': existing['notify'] ?? true,
              'created_at': DateTime.now().toIso8601String(),
            }
          : {
              'id': DateTime.now().millisecondsSinceEpoch.toString(),
              'name': searchName,
              'filters': currentFilters,
              'notify': true,
              'created_at': DateTime.now().toIso8601String(),
            };

      final withoutDup = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .where(
            (e) => !SavedSearchService.filtersEqual(
              e['filters'] is Map
                  ? Map<String, dynamic>.from(
                      (e['filters'] as Map).cast<String, dynamic>(),
                    )
                  : null,
              currentFilters,
            ),
          )
          .toList();
      withoutDup.insert(0, payload);
      final deduped = SavedSearchService.dedupeByFilters(withoutDup);

      await sp.setString(_HomePageFields._savedSearchesKey, json.encode(deduped));
      if (deduped.isNotEmpty) {
        unawaited(SavedSearchService.pushItemToServer(
          Map<String, dynamic>.from(deduped.first),
        ));
        unawaited(SavedSearchService.persistLocal(deduped));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.saved)),
      );
      // Analytics tracking for saved search
      // Navigate to saved searches for quick edit
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SavedSearchesPage(parentState: this)),
      );
    } catch (e, st) { logNonFatal(e, st); }
  }

  // Get current filter state as a map
  Map<String, dynamic> _getCurrentFilterState() {
    final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
    return homeFiltersToSavedSearchJson(
      _homeFiltersSnapshot(),
      apiSortValue: apiSortValue,
    );
  }

  String _generateSearchName() {
    final parts = <String>[];
    final brand = homeFilterDecodeSingle(selectedBrand);
    if (brand != null) {
      parts.add(
        CarNameTranslations.getLocalizedBrand(context, brand),
      );
    }
    if (brand != null && selectedModel?.isNotEmpty == true) {
      parts.add(
        CarNameTranslations.getLocalizedModel(
          context,
          brand,
          selectedModel!,
        ),
      );
    }
    if (selectedCity?.isNotEmpty == true) {
      parts.add(_translateValueGlobal(context, selectedCity) ?? selectedCity!);
    }
    if (selectedMaxPrice?.isNotEmpty == true) {
      parts.add('\$${selectedMaxPrice ?? ''}');
    }
    return parts.isEmpty
        ? AppLocalizations.of(context)!.defaultSort
        : parts.join(' • ');
  }
}
