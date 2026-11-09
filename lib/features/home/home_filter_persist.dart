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
    _searchFiltersKeywordController.text = parsed.keyword ?? '';
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
    selectedSortBy = _localizedSortSelection(parsed.sortBy);
    // Restored dependent values must agree with the restored vehicle: keep valid
    // ones, drop only those the catalog rules out (no-op until the catalog loads;
    // the catalog-load hook re-runs it).
    syncDependentFiltersToVehicle();
  }

  void _applyHomeFiltersSnapshot(HomeFiltersSnapshot snap) {
    selectedBrand = homeFilterDecodeSingle(snap.brand);
    selectedModel = snap.model;
    selectedTrim = snap.trim;
    _searchFiltersKeywordController.text = snap.keyword ?? '';
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
    selectedSortBy = _localizedSortSelection(snap.sortByUi);
    syncDependentFiltersToVehicle();
  }

  /// Re-localizes a persisted sort label so chips/menus match the active language.
  String? _localizedSortSelection(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final api = convertSortToApiValue(context, raw);
    if (api == null) return null;
    if (!isKnownSortOption(raw) && api == raw) return raw;
    return localizeSortOption(context, raw);
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

  /// Clears in-memory feed cache + pagination so the next fetch cannot reuse
  /// unfiltered (or previously filtered) pages.
  void _resetHomeFeedForFilterChange() {
    _HomePageFields._homeFeedCache.clear();
    _HomePageFields._homeFeedCacheDefaultSort = null;
    _HomePageFields._homeFeedCacheFetchedAt = null;
    cars = [];
    _page = 1;
    _hasNext = true;
    _loadMoreFailed = false;
  }

  /// Restores [normalized] onto the live Home filter state, persists the
  /// session snapshot, drops stale feed rows, and starts a refresh.
  /// Used by Saved Searches via [HomeTabActions.onApplySavedSearchFilters].
  Future<bool> applySavedSearchFiltersAndRefresh(
    Map<String, dynamic> normalized,
  ) async {
    if (!mounted || widget.isSearchFiltersHost) return false;
    setState(() {
      applyFiltersFromSavedSearch(normalized);
      _resetHomeFeedForFilterChange();
    });
    await _persistFilters();
    if (!mounted) return false;
    // Cross-mixin scroll helper lives on fetch core; use the shell hook.
    HomeTabActions.scrollToTop();
    // Drop one-time prefs so a later cold path cannot re-apply / race.
    await SavedSearchHomeBridge.consumeOneTimeFilters();
    await SavedSearchHomeBridge.consumePendingFetch();
    if (!mounted) return false;
    fetchCars(bypassCache: true);
    return true;
  }

  /// Consumes one-time bridge prefs (if any) and applies them on Home.
  Future<bool> consumePendingSavedSearchFiltersAndRefresh() async {
    if (!mounted || widget.isSearchFiltersHost) return false;
    final oneTimeFilters = await SavedSearchHomeBridge.consumeOneTimeFilters();
    await SavedSearchHomeBridge.consumePendingFetch();
    if (oneTimeFilters == null) return false;
    if (!mounted) return false;
    setState(() {
      applyFiltersFromHomePersistMap(oneTimeFilters);
      _resetHomeFeedForFilterChange();
    });
    await _persistFilters();
    if (!mounted) return false;
    HomeTabActions.scrollToTop();
    fetchCars(bypassCache: true);
    return true;
  }

  Future<void> _restoreFilters() async {
    try {
      // Drop disk leftovers from older builds; filters are session-memory only.
      await _removeLegacyPersistedHomeFilters();
      final map = _HomeFilterSessionPersistence.snapshot;
      if (map == null || map.isEmpty) return;
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
      syncDependentFiltersToVehicle();
      _syncHomeFilterTextControllersFromSelection();
    });
  }

  Future<void> _persistFilters() async {
    if (widget.isSearchFiltersHost) return;
    try {
      if (!_homeFiltersSnapshot().hasActiveFilters) {
        _HomeFilterSessionPersistence.clear();
        await _removeLegacyPersistedHomeFilters();
        return;
      }
      final map = homeFilterHomePersistMap(_homeFiltersSnapshot());
      _HomeFilterSessionPersistence.save(map);
      // Keep SharedPreferences clean so a kill/relaunch cannot restore filters.
      await _removeLegacyPersistedHomeFilters();
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _removeLegacyPersistedHomeFilters() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_HomePageFields._filtersKey);
      await sp.remove(_HomePageFields._sellFiltersKey);
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _saveCurrentSearch({
    bool forceNotify = false,
    bool openSavedSearches = true,
    BuildContext? messengerContext,
  }) async {
    try {
      // F-34: saved searches are stored per account by SavedSearchService;
      // never touch the old global key from here.
      await SavedSearchService.upsertFromFilters(
        filters: _getCurrentFilterState(),
        name: _generateSearchName(),
        forceNotify: forceNotify,
      );
      if (!mounted) return;
      final snackContext = messengerContext ?? context;
      if (!snackContext.mounted) return;
      final messenger = ScaffoldMessenger.of(snackContext);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            forceNotify
                ? AppLocalizations.of(snackContext)!.youLlBeNotifiedWhenAMatchingCarIsListed
                : AppLocalizations.of(snackContext)!.saved,
          ),
          action: openSavedSearches
              ? null
              : SnackBarAction(
                  label: AppLocalizations.of(snackContext)!.view,
                  onPressed: () {
                    Navigator.pushNamed(snackContext, '/saved-searches');
                  },
                ),
        ),
      );
      if (openSavedSearches) {
        Navigator.pushNamed(context, '/saved-searches');
      }
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<bool> _prepareSavedSearchAction(BuildContext pageContext) async {
    if (!AuthService().isAuthenticated) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(pageContext)!.loginRequired),
          action: SnackBarAction(
            label: AppLocalizations.of(pageContext)!.logIn,
            onPressed: () => Navigator.pushNamed(pageContext, '/login'),
          ),
        ),
      );
      return false;
    }
    if (!_homeFiltersSnapshot().hasActiveFilters) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(pageContext)!.noFiltersApplied),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _saveSearchFromFiltersPage(BuildContext pageContext) async {
    if (!await _prepareSavedSearchAction(pageContext)) return;
    if (!pageContext.mounted) return;
    await _saveCurrentSearch(
      forceNotify: false,
      openSavedSearches: false,
      messengerContext: pageContext,
    );
  }

  Future<void> _enableSearchMatchAlerts(BuildContext pageContext) async {
    if (!await _prepareSavedSearchAction(pageContext)) return;
    if (!pageContext.mounted) return;
    await _saveCurrentSearch(
      forceNotify: true,
      openSavedSearches: false,
      messengerContext: pageContext,
    );
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
