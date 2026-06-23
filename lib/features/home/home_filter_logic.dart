part of 'home_flow.dart';

mixin _HomePageFilterLogic on _HomePageFetch {
  void _invalidateHomeCatalogFilterCaches() {
    _homeMotorOptsCacheKey = null;
    _homeMotorOptsCache = null;
    _homeFilterSpecVariantsCacheKey = null;
    _homeFilterSpecVariantsCache = null;
  }

  /// Parsed min/max year from the home filter (empty string = unbounded). Swaps if inverted.
  ({int? minY, int? maxY}) _homeFilterYearBounds() {
    var minY = int.tryParse((selectedMinYear ?? '').trim());
    var maxY = int.tryParse((selectedMaxYear ?? '').trim());
    if (minY != null && maxY != null && minY > maxY) {
      final t = minY;
      minY = maxY;
      maxY = t;
    }
    return (minY: minY, maxY: maxY);
  }

  void _afterHomeYearBoundsChanged() {
    _invalidateHomeCatalogFilterCaches();
    _pruneHomeMotorFilterSelectionsIfInvalid();
  }

  /// Spec rows for correlating engine ↔ cylinders in More Filters (cached per scope).
  List<OnlineSpecVariant> _homeMoreFiltersSpecVariants() {
    final b = selectedBrand?.trim();
    final m = selectedModel?.trim();
    if (b == null || b.isEmpty || m == null || m.isEmpty) return const [];
    final idx = _homeCarSpecIdx;
    if (idx == null) return const [];
    final trimKey = selectedTrim?.trim() ?? '';
    final yb = _homeFilterYearBounds();
    final key =
        'sv|$b|\x1e|$m|\x1e|$trimKey|\x1e|${yb.minY ?? ''}|\x1e|${yb.maxY ?? ''}';
    if (_homeFilterSpecVariantsCacheKey == key &&
        _homeFilterSpecVariantsCache != null) {
      return _homeFilterSpecVariantsCache!;
    }
    final appTrim = trimKey.isEmpty
        ? CarSpecIndex.catalogAutofillModelOnly
        : trimKey;
    final list = idx.homeFilterSpecVariantsUnion(
      b,
      m,
      appTrim,
      rangeMinYear: yb.minY,
      rangeMaxYear: yb.maxY,
    );
    _homeFilterSpecVariantsCacheKey = key;
    _homeFilterSpecVariantsCache = list;
    return list;
  }

  /// When catalog data ties engine size to cylinders, align cylinder count with engine.
  /// Only runs if the user already chose a concrete cylinder count (not Any / unset).
  void _applyMoreFiltersCylinderSyncFromEngine(String? engineLabel) {
    if (engineLabel == null || engineLabel.trim().isEmpty) return;
    final prevCyl = selectedCylinderCount;
    if (prevCyl == null || prevCyl.isEmpty || prevCyl.toLowerCase() == 'any') {
      return;
    }
    final vs = _homeMoreFiltersSpecVariants();
    if (vs.isEmpty) return;

    final t = engineLabel.trim();
    var narrowed = vs.where((v) {
      if (v.engineSizeLiters == null || v.engineSizeLiters! <= 0.001) {
        return false;
      }
      final label =
          '${v.engineSizeLiters!.toStringAsFixed(1)}${v.displacementSuffix}';
      return label == t;
    }).toList();

    if (narrowed.isEmpty) {
      final lit = OnlineSpecVariant.parseLeadingEngineLiters(t);
      if (lit == null) return;
      final lit1 = double.parse(lit.toStringAsFixed(1));
      narrowed = vs.where((v) {
        if (v.engineSizeLiters == null) return false;
        return (v.engineSizeLiters! - lit1).abs() < 0.06;
      }).toList();
    }
    if (narrowed.isEmpty) return;

    final cyls = narrowed
        .map((v) => v.cylinderCount)
        .whereType<int>()
        .where((c) => c > 0)
        .toSet();
    if (cyls.isEmpty) return;

    int? nextCyl;
    if (cyls.length == 1) {
      nextCyl = cyls.first;
    } else {
      final lit = OnlineSpecVariant.parseLeadingEngineLiters(t);
      final lit1 = lit == null ? null : double.parse(lit.toStringAsFixed(1));
      final pick = OnlineSpecVariant.matchBestAnchored(narrowed, {
        'e',
      }, engineLiters: lit1);
      if (pick?.cylinderCount != null && pick!.cylinderCount! > 0) {
        nextCyl = pick.cylinderCount;
      }
    }
    if (nextCyl == null) return;

    final nextStr = '$nextCyl';
    if (selectedCylinderCount == nextStr) return;
    if (!getAvailableCylinderCounts().contains(nextStr)) return;

    selectedCylinderCount = nextStr;
    _moreFiltersDialogFieldGeneration++;
  }

  /// When catalog data ties cylinder count to engine size, align engine with cylinders.
  /// Only runs if the user already chose a concrete engine size (not Any / unset).
  void _applyMoreFiltersEngineSyncFromCylinder(String? newCylinderStr) {
    final prevEng = selectedEngineSize;
    if (prevEng == null || prevEng.isEmpty || prevEng.toLowerCase() == 'any') {
      return;
    }
    if (newCylinderStr == null ||
        newCylinderStr.isEmpty ||
        newCylinderStr.toLowerCase() == 'any') {
      return;
    }
    final cyl = int.tryParse(newCylinderStr);
    if (cyl == null || cyl <= 0) return;

    final vs = _homeMoreFiltersSpecVariants();
    if (vs.isEmpty) return;

    final narrowed = vs
        .where((v) => v.cylinderCount != null && v.cylinderCount == cyl)
        .toList();
    if (narrowed.isEmpty) return;

    String? labelFromVariant(OnlineSpecVariant v) {
      if (v.engineSizeLiters == null || v.engineSizeLiters! <= 0.001) {
        return null;
      }
      return '${v.engineSizeLiters!.toStringAsFixed(1)}${v.displacementSuffix}';
    }

    final labels = narrowed.map(labelFromVariant).whereType<String>().toSet();
    if (labels.isEmpty) return;

    String? nextLabel;
    if (labels.length == 1) {
      nextLabel = labels.first;
    } else {
      final prevLit = OnlineSpecVariant.parseLeadingEngineLiters(prevEng);
      final prevLit1 = prevLit == null
          ? null
          : double.parse(prevLit.toStringAsFixed(1));
      final pick = OnlineSpecVariant.matchBestAnchored(
        narrowed,
        {'c'},
        cylinders: cyl,
        engineLiters: prevLit1,
      );
      nextLabel = pick == null ? null : labelFromVariant(pick);
    }
    if (nextLabel == null || nextLabel.isEmpty) return;
    if (selectedEngineSize == nextLabel) return;
    if (!getAvailableEngineSizes().contains(nextLabel)) return;

    selectedEngineSize = nextLabel;
    _engineSizeController.text = nextLabel;
    _moreFiltersDialogFieldGeneration++;
  }

  /// Catalog-backed engine/cylinder unions for the current brand + model (+ trim), or null.
  ({List<String> engines, List<String> cylinders})?
  _catalogMotorFilterOptions() {
    final b = selectedBrand?.trim();
    final m = selectedModel?.trim();
    if (b == null || b.isEmpty || m == null || m.isEmpty) return null;
    final idx = _homeCarSpecIdx;
    if (idx == null) return null;
    final trimKey = selectedTrim?.trim() ?? '';
    final yb = _homeFilterYearBounds();
    final key =
        '$b|\x1e|$m|\x1e|$trimKey|\x1e|${yb.minY ?? ''}|\x1e|${yb.maxY ?? ''}';
    if (_homeMotorOptsCacheKey == key && _homeMotorOptsCache != null) {
      return _homeMotorOptsCache;
    }
    final appTrim = trimKey.isEmpty
        ? CarSpecIndex.catalogAutofillModelOnly
        : trimKey;
    final raw = idx.homeFilterEngineCylinderOptions(
      b,
      m,
      appTrim,
      rangeMinYear: yb.minY,
      rangeMaxYear: yb.maxY,
    );
    if (raw == null) {
      return null;
    }
    if (raw.engineSizes.isEmpty &&
        raw.cylinderCounts.isEmpty &&
        yb.minY == null &&
        yb.maxY == null) {
      return null;
    }
    _homeMotorOptsCacheKey = key;
    _homeMotorOptsCache = (
      engines: raw.engineSizes,
      cylinders: raw.cylinderCounts,
    );
    return _homeMotorOptsCache;
  }

  void _pruneHomeMotorFilterSelectionsIfInvalid() {
    final eng = selectedEngineSize;
    if (eng != null &&
        eng.isNotEmpty &&
        eng.toLowerCase() != 'any' &&
        !getAvailableEngineSizes().contains(eng)) {
      selectedEngineSize = null;
      _engineSizeController.clear();
    }
    final cyl = selectedCylinderCount;
    if (cyl != null &&
        cyl.isNotEmpty &&
        cyl.toLowerCase() != 'any' &&
        !getAvailableCylinderCounts().contains(cyl)) {
      selectedCylinderCount = null;
    }
  }

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

  String? _filterStr(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Apply filters from a saved-search map (`min_price`, `cylinder_count`, etc.).
  void applyFiltersFromSavedSearch(Map<String, dynamic> normalized) {
    _resetAllFiltersInMemory();
    selectedBrand = _filterStr(normalized['brand']);
    selectedModel = _filterStr(normalized['model']);
    selectedTrim = _filterStr(normalized['trim']);
    selectedMinPrice = _filterStr(normalized['min_price']);
    selectedMaxPrice = _filterStr(normalized['max_price']);
    selectedMinYear = _filterStr(normalized['min_year']);
    selectedMaxYear = _filterStr(normalized['max_year']);
    selectedMinMileage = _filterStr(normalized['min_mileage']);
    selectedMaxMileage = _filterStr(normalized['max_mileage']);
    selectedCondition = _filterStr(normalized['condition']);
    selectedTransmission = _filterStr(normalized['transmission']);
    selectedFuelType = _filterStr(normalized['fuel_type']);
    selectedBodyType = _filterStr(normalized['body_type']);
    selectedColor = _filterStr(normalized['color']);
    selectedDriveType = _filterStr(normalized['drive_type']);
    final rsApply =
        _filterStr(normalized['region_specs'])?.toLowerCase();
    selectedRegionSpecs =
        (rsApply != null && rsApply.isNotEmpty && isValidCarRegionSpecCode(rsApply))
        ? rsApply
        : null;
    selectedCylinderCount = _filterStr(normalized['cylinder_count']);
    selectedSeating = _filterStr(normalized['seating']);
    selectedEngineSize = _filterStr(normalized['engine_size']);
    selectedCity = _filterStr(normalized['city']);
    selectedPlateType = _filterStr(normalized['plate_type']);
    selectedPlateCity = _filterStr(normalized['plate_city']);
    selectedTitleStatus = _filterStr(normalized['title_status']);
    selectedDamagedParts = _filterStr(normalized['damaged_parts']);
    selectedSortBy = _filterStr(normalized['sort_by']);
    _syncHomeFilterTextControllersFromSelection();
  }

  /// Apply filters stored in [home_filters_v1] / one-time home persist shape.
  void applyFiltersFromHomePersistMap(Map<String, dynamic> map) {
    applyFiltersFromSavedSearch({
      'brand': map['brand'],
      'model': map['model'],
      'trim': map['trim'],
      'min_price': map['price_min'],
      'max_price': map['price_max'],
      'min_year': map['year_min'],
      'max_year': map['year_max'],
      'min_mileage': map['min_mileage'],
      'max_mileage': map['max_mileage'],
      'condition': map['condition'],
      'transmission': map['transmission'],
      'fuel_type': map['fuel_type'],
      'body_type': map['body_type'],
      'color': map['color'],
      'drive_type': map['drive_type'],
      'region_specs': map['region_specs'],
      'cylinder_count': map['cylinders'],
      'seating': map['seating'],
      'engine_size': map['engine_size'],
      'city': map['city'],
      'plate_type': map['plate_type'],
      'plate_city': map['plate_city'],
      'title_status': map['title_status'],
      'damaged_parts': map['damaged_parts'],
      'sort_by': map['sort_by'],
    });
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
        selectedBrand = _filterStr(map['brand']);
        selectedModel = _filterStr(map['model']);
        selectedTrim = _filterStr(map['trim']);
        selectedMinPrice = _filterStr(map['price_min']);
        selectedMaxPrice = _filterStr(map['price_max']);
        selectedMinYear = _filterStr(map['year_min']);
        selectedMaxYear = _filterStr(map['year_max']);
        selectedMinMileage = _filterStr(map['min_mileage']);
        selectedMaxMileage = _filterStr(map['max_mileage']);
        selectedCondition = _filterStr(map['condition']);
        selectedTransmission = _filterStr(map['transmission']);
        selectedFuelType = _filterStr(map['fuel_type']);
        selectedBodyType = _filterStr(map['body_type']);
        selectedColor = _filterStr(map['color']);
        selectedDriveType = _filterStr(map['drive_type']);
        final rsRaw = _filterStr(map['region_specs'])?.toLowerCase();
        selectedRegionSpecs =
            (rsRaw != null && rsRaw.isNotEmpty && isValidCarRegionSpecCode(rsRaw))
            ? rsRaw
            : null;
        selectedCylinderCount = _filterStr(map['cylinders']);
        selectedSeating = _filterStr(map['seating']);
        selectedEngineSize = _filterStr(map['engine_size']);
        selectedCity = _filterStr(map['city']);
        selectedPlateType = _filterStr(map['plate_type']);
        selectedPlateCity = _filterStr(map['plate_city']);
        selectedTitleStatus = _filterStr(map['title_status']);
        selectedDamagedParts = _filterStr(map['damaged_parts']);
        selectedSortBy = _filterStr(map['sort_by']);
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
      final rsRaw = _filterStr(snap['region_specs'])?.toLowerCase();
      selectedRegionSpecs =
          (rsRaw != null && rsRaw.isNotEmpty && isValidCarRegionSpecCode(rsRaw))
          ? rsRaw
          : null;
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
      if (!_hasActiveFilters()) {
        await _clearFiltersOnly();
        return;
      }
      final sp = await SharedPreferences.getInstance();
      final Map<String, dynamic> map = {
        'brand': selectedBrand,
        'model': selectedModel,
        'trim': selectedTrim,
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
        'city': selectedCity,
        'plate_type': selectedPlateType,
        'plate_city': selectedPlateCity,
        'title_status': selectedTitleStatus,
        'damaged_parts': selectedDamagedParts,
        'sort_by': selectedSortBy,
      };
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
    final Map<String, dynamic> filters = {};

    // Brand and Model filters
    if (selectedBrand?.isNotEmpty == true) filters['brand'] = selectedBrand!;
    if (selectedModel?.isNotEmpty == true) filters['model'] = selectedModel!;
    if (selectedTrim?.isNotEmpty == true) filters['trim'] = selectedTrim!;

    // Price filters - apply individually, not requiring both
    if (selectedMinPrice?.isNotEmpty == true) {
      filters['min_price'] = selectedMinPrice!;
    }
    if (selectedMaxPrice?.isNotEmpty == true) {
      filters['max_price'] = selectedMaxPrice!;
    }

    // Year filters - apply individually, not requiring both
    if (selectedMinYear?.isNotEmpty == true) {
      filters['min_year'] = selectedMinYear!;
    }
    if (selectedMaxYear?.isNotEmpty == true) {
      filters['max_year'] = selectedMaxYear!;
    }

    // Mileage filters - apply individually, not requiring both
    if (selectedMinMileage?.isNotEmpty == true) {
      filters['min_mileage'] = selectedMinMileage!;
    }
    if (selectedMaxMileage?.isNotEmpty == true) {
      filters['max_mileage'] = selectedMaxMileage!;
    }

    // Vehicle condition and specifications
    if (selectedCondition?.isNotEmpty == true && selectedCondition != 'Any') {
      filters['condition'] = selectedCondition!.toLowerCase();
    }
    if (selectedTransmission?.isNotEmpty == true &&
        selectedTransmission != 'Any') {
      filters['transmission'] = selectedTransmission!.toLowerCase();
    }
    if (selectedFuelType?.isNotEmpty == true && selectedFuelType != 'Any') {
      filters['fuel_type'] = selectedFuelType!.toLowerCase();
    }
    if (selectedBodyType?.isNotEmpty == true && selectedBodyType != 'Any') {
      filters['body_type'] = selectedBodyType!.toLowerCase();
    }
    if (selectedColor?.isNotEmpty == true && selectedColor != 'Any') {
      filters['color'] = selectedColor!.toLowerCase();
    }
    if (selectedDriveType?.isNotEmpty == true && selectedDriveType != 'Any') {
      filters['drive_type'] = selectedDriveType!.toLowerCase();
    }
    if (selectedRegionSpecs?.isNotEmpty == true &&
        isValidCarRegionSpecCode(selectedRegionSpecs)) {
      filters['region_specs'] = selectedRegionSpecs!.trim().toLowerCase();
    }
    if (selectedCylinderCount?.isNotEmpty == true &&
        selectedCylinderCount != 'Any') {
      filters['cylinder_count'] = selectedCylinderCount!;
    }
    if (selectedSeating?.isNotEmpty == true && selectedSeating != 'Any') {
      filters['seating'] = selectedSeating!;
    }

    // Location and other filters
    if (selectedCity?.isNotEmpty == true) filters['city'] = selectedCity!;
    // Convert localized sort option to backend API value
    final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
    if (apiSortValue?.isNotEmpty == true) filters['sort_by'] = apiSortValue!;

    // Title status and damaged parts
    if (selectedTitleStatus?.isNotEmpty == true) {
      filters['title_status'] = selectedTitleStatus!;
      if (selectedTitleStatus == 'damaged' &&
          selectedDamagedParts?.isNotEmpty == true) {
        filters['damaged_parts'] = selectedDamagedParts!;
      }
    }

    return filters;
  }

  String _generateSearchName() {
    final parts = <String>[];
    if (selectedBrand?.isNotEmpty == true) {
      parts.add(
        CarNameTranslations.getLocalizedBrand(context, selectedBrand!),
      );
    }
    if (selectedModel?.isNotEmpty == true) {
      parts.add(
        CarNameTranslations.getLocalizedModel(
          context,
          selectedBrand,
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

  void clearFiltersOnVehicleChange() {
    // Clear filters that are specific to vehicle specifications
    selectedBodyType = null;
    selectedTransmission = null;
    selectedFuelType = null;
    selectedDriveType = null;
    selectedCylinderCount = null;
    selectedSeating = null;
    selectedEngineSize = null;
    selectedColor = null;
  }

  // Helper methods to get available options based on selected vehicle
  List<String> getAvailableEngineSizes() {
    final mot = _catalogMotorFilterOptions();
    if (mot != null) {
      if (mot.engines.isNotEmpty) {
        return ['Any', ...mot.engines];
      }
      return const ['Any'];
    }

    if (selectedBrand != null &&
        selectedModel != null &&
        selectedTrim != null) {
      final specs =
          globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
      if (specs != null && specs['engineSizes'] != null) {
        return ['Any', ...specs['engineSizes']];
      }
    }
    return engineSizes;
  }

  List<String> getAvailableConditions() {
    return conditions;
  }

  List<String> getAvailableBodyTypes() {
    if (selectedBrand == null ||
        selectedModel == null ||
        selectedTrim == null) {
      return bodyTypes;
    }

    final specs =
        globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['bodyTypes'] != null) {
      return ['Any', ...specs['bodyTypes']];
    }
    return bodyTypes;
  }

  List<String> getAvailableTransmissions() {
    final List<String> base;
    if (selectedBrand == null ||
        selectedModel == null ||
        selectedTrim == null) {
      base = transmissions;
    } else {
      final specs =
          globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
      if (specs != null && specs['transmissions'] != null) {
        final fromSpecs = (specs['transmissions'] as List<dynamic>)
            .map((e) => e.toString())
            .where((t) => !_isExcludedTransmissionFilter(t))
            .toList();
        base = ['Any', ...fromSpecs];
      } else {
        base = transmissions;
      }
    }
    return base
        .where((t) => t == 'Any' || !_isExcludedTransmissionFilter(t))
        .toList();
  }

  List<String> getAvailableFuelTypes() {
    if (selectedBrand == null ||
        selectedModel == null ||
        selectedTrim == null) {
      return fuelTypes;
    }

    final specs =
        globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['fuelTypes'] != null) {
      return ['Any', ...specs['fuelTypes']];
    }
    return fuelTypes;
  }

  List<String> getAvailableDriveTypes() {
    if (selectedBrand == null ||
        selectedModel == null ||
        selectedTrim == null) {
      return driveTypes;
    }

    final specs =
        globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['driveTypes'] != null) {
      return ['Any', ...specs['driveTypes']];
    }
    return driveTypes;
  }

  List<String> getAvailableCylinderCounts() {
    final mot = _catalogMotorFilterOptions();
    if (mot != null) {
      if (mot.cylinders.isNotEmpty) {
        return ['Any', ...mot.cylinders];
      }
      return const ['Any'];
    }

    if (selectedBrand != null &&
        selectedModel != null &&
        selectedTrim != null) {
      final specs =
          globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
      if (specs != null && specs['cylinderCounts'] != null) {
        return ['Any', ...specs['cylinderCounts']];
      }
    }
    return cylinderCounts;
  }

  List<String> getAvailableSeatings() {
    if (selectedBrand == null ||
        selectedModel == null ||
        selectedTrim == null) {
      return seatings;
    }

    final specs =
        globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['seatings'] != null) {
      return ['Any', ...specs['seatings']];
    }
    return seatings;
  }

  List<String> getAvailableColors() {
    if (selectedBrand == null ||
        selectedModel == null ||
        selectedTrim == null) {
      return colors;
    }

    final specs =
        globalVehicleSpecs[selectedBrand]?[selectedModel]?[selectedTrim];
    if (specs != null && specs['colors'] != null) {
      return ['Any', ...specs['colors']];
    }
    return colors;
  }

  // Helper method to get a valid drive type value for dropdown (dropdown uses '' for Any)
  String? _getValidDriveTypeValue() {
    if (selectedDriveType == null ||
        selectedDriveType == 'Any' ||
        selectedDriveType!.isEmpty) {
      return '';
    }

    final availableTypes = getAvailableDriveTypes();

    // First try exact match (excluding 'Any' which is represented as '' in dropdown items)
    if (availableTypes.contains(selectedDriveType) &&
        selectedDriveType != 'Any') {
      return selectedDriveType;
    }

    // Try case-insensitive match
    final lowerSelected = selectedDriveType!.toLowerCase();
    for (final type in availableTypes) {
      if (type != 'Any' && type.toLowerCase() == lowerSelected) {
        return type;
      }
    }

    return '';
  }

  String _getValidRegionSpecsValue() {
    final s = selectedRegionSpecs?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return '';
    return isValidCarRegionSpecCode(s) ? s : '';
  }

  // Helper method to get a valid fuel type value for dropdown (dropdown uses '' for Any)
  String? _getValidFuelTypeValue() {
    if (selectedFuelType == null ||
        selectedFuelType == 'Any' ||
        selectedFuelType!.isEmpty) {
      return '';
    }

    final availableTypes = getAvailableFuelTypes();

    // First try exact match (excluding 'Any' which is represented as '' in dropdown items)
    if (availableTypes.contains(selectedFuelType) &&
        selectedFuelType != 'Any') {
      return selectedFuelType;
    }

    // Try case-insensitive match
    final lowerSelected = selectedFuelType!.toLowerCase();
    for (final type in availableTypes) {
      if (type != 'Any' && type.toLowerCase() == lowerSelected) {
        return type;
      }
    }

    return '';
  }

  String _getValidCylinderCountValue() {
    if (selectedCylinderCount == null ||
        selectedCylinderCount == 'Any' ||
        selectedCylinderCount!.isEmpty) {
      return '';
    }
    final available = getAvailableCylinderCounts();
    if (available.contains(selectedCylinderCount) &&
        selectedCylinderCount != 'Any') {
      return selectedCylinderCount!;
    }
    final lower = selectedCylinderCount!.toLowerCase();
    for (final c in available) {
      if (c != 'Any' && c.toLowerCase() == lower) {
        return c;
      }
    }
    return '';
  }

  String _getValidEngineSizeValue() {
    if (selectedEngineSize == null ||
        selectedEngineSize == 'Any' ||
        selectedEngineSize!.isEmpty) {
      return '';
    }
    final available = getAvailableEngineSizes();
    if (available.contains(selectedEngineSize) && selectedEngineSize != 'Any') {
      return selectedEngineSize!;
    }
    final lower = selectedEngineSize!.toLowerCase();
    for (final e in available) {
      if (e != 'Any' && e.toLowerCase() == lower) {
        return e;
      }
    }
    return '';
  }

  // Helper method to check if there are any active filters
  bool _hasActiveFilters() {
    return selectedBrand != null ||
        selectedModel != null ||
        selectedTrim != null ||
        selectedMinPrice != null ||
        selectedMaxPrice != null ||
        selectedMinYear != null ||
        selectedMaxYear != null ||
        selectedMinMileage != null ||
        selectedMaxMileage != null ||
        selectedCondition != null ||
        selectedTransmission != null ||
        selectedFuelType != null ||
        selectedBodyType != null ||
        selectedColor != null ||
        selectedDriveType != null ||
        selectedRegionSpecs != null ||
        selectedCylinderCount != null ||
        selectedSeating != null ||
        selectedEngineSize != null ||
        selectedCity != null ||
        selectedPlateType != null ||
        selectedPlateCity != null ||
        selectedSortBy != null ||
        selectedTitleStatus != null ||
        selectedDamagedParts != null;
  }

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
