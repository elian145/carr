part of 'main_legacy.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

/// Empty listings: shows only the message. When a non-default sort is already
/// selected, still runs a one-time auto-fetch (no extra controls on this screen).
class _HomeEmptyListMessage extends StatefulWidget {
  final String? selectedSortBy;
  final VoidCallback onAutoFetch;

  const _HomeEmptyListMessage({
    required this.selectedSortBy,
    required this.onAutoFetch,
  });

  @override
  State<_HomeEmptyListMessage> createState() => _HomeEmptyListMessageState();
}

class _HomeEmptyListMessageState extends State<_HomeEmptyListMessage> {
  bool _didAutoFetch = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectedSortBy != null && widget.selectedSortBy!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_didAutoFetch && mounted) {
          _didAutoFetch = true;
          widget.onAutoFetch();
        }
      });
    }
  }

  @override
  void didUpdateWidget(_HomeEmptyListMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSortBy != null &&
        widget.selectedSortBy != oldWidget.selectedSortBy &&
        !_didAutoFetch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_didAutoFetch && mounted) {
          _didAutoFetch = true;
          widget.onAutoFetch();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        AppLocalizations.of(context)!.noCarsFound,
        style: TextStyle(color: Colors.white70),
      ),
    );
  }
}

class _HomePageState extends State<HomePage> {
  // Keep a lightweight in-memory feed snapshot across route replacement.
  static List<Map<String, dynamic>> _homeFeedCache = <Map<String, dynamic>>[];
  static int _homeFeedCachePage = 1;
  static bool _homeFeedCacheHasNext = true;
  static bool _homeDeleteHandlerRegistered = false;

  List<Map<String, dynamic>> cars = [];
  bool isLoading = true;
  bool hasLoadedOnce = false;
  String? loadErrorMessage;

  // Filter variables
  String? selectedBrand;
  String? selectedModel;
  String? selectedTrim;
  String? selectedMinPrice;
  String? selectedMaxPrice;
  String? selectedMinYear;
  String? selectedMaxYear;
  String? selectedMinMileage;
  String? selectedMaxMileage;
  String? selectedCondition;
  String? selectedTransmission;
  String? selectedFuelType;
  String? selectedBodyType;
  String? selectedColor;
  String? selectedDriveType;

  /// Lowercase API code: us, gcc, iraq, … (see [kCarRegionSpecCodes]).
  String? selectedRegionSpecs;
  String? selectedCylinderCount;
  String? selectedSeating;
  String? selectedEngineSize;
  String? selectedCity;
  String? selectedPlateType;
  String? selectedPlateCity;
  String? selectedTitleStatus;
  String? selectedDamagedParts;
  String? contactPhone;
  String? selectedSortBy;

  // Toggle states for unified filters
  bool isPriceDropdown = true;
  bool isYearDropdown = true;
  bool isMileageDropdown = true;
  bool isEngineSizeDropdown = true;
  static const String _filtersKey = 'home_filters_v1';
  static const String _sellFiltersKey = 'sell_filters_v1';
  static const String _savedSearchesKey = 'saved_searches_v1';

  // Listings layout
  int listingColumns = 2;
  // Infinite scroll state (offset restored via [_HomeFeedScrollPersistence] after tab switches)
  late final ScrollController _homeScrollController;
  /// Target scroll offset to apply after listings finish loading (initial offset is lost while `isLoading`).
  double? _pendingHomeScrollRestore;
  int _homeScrollRestoreScheduleGen = 0;
  /// Last known pixels (updated in scroll listener); [dispose] often runs after the viewport dropped [ScrollPosition] clients.
  double _lastHomeScrollPixels = 0;
  /// Hides the feed until [_restoreHomeScrollWork] jumps to the saved offset (avoids a flash of the top).
  bool _obscureHomeBodyUntilScrollRestored = false;
  int _homeCarouselResetSeed = 0;
  int _page = 1;
  bool _hasNext = true;
  bool _isLoadingMore = false;

  // Bottom bar tab selection for inline pages (payments, chat, saved, etc.)
  int? _selectedBottomTabIndex;

  /// When the list is empty but a non-default sort is set, auto-fetch once
  /// (no sort/apply UI on the empty state).
  bool _autoFetchedForEmptyWithSort = false;

  // Toggle state for inline engine size picker on the sell page.
  bool isInlineEngineSizeDropdown = true;

  /// Bumped when More Filters form fields are reset so dropdowns remount
  /// (`initialValue` is otherwise ignored after the first build).
  int _moreFiltersDialogFieldGeneration = 0;

  /// Bundled spec DB for model-aware engine / cylinder pick lists in More Filters.
  CarSpecIndex? _homeCarSpecIdx;
  String? _homeMotorOptsCacheKey;
  ({List<String> engines, List<String> cylinders})? _homeMotorOptsCache;
  String? _homeFilterSpecVariantsCacheKey;
  List<OnlineSpecVariant>? _homeFilterSpecVariantsCache;

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
      final raw = sp.getString(_filtersKey);
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
    } catch (_) {}
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
      await sp.setString(_filtersKey, json.encode(map));
    } catch (_) {}
  }

  Future<void> _clearPersistedFilters() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_filtersKey);
      await sp.remove(_sellFiltersKey);
      await sp.remove(_savedSearchesKey);
      // Clear known caches
      await sp.remove('cache_favorites');
      // Attempt to clear dynamic cache_home_* and cache_car_* keys by scanning
      final allKeys = sp.getKeys();
      for (final k in allKeys) {
        if (k.startsWith('cache_home_') || k.startsWith('cache_car_')) {
          await sp.remove(k);
        }
      }
    } catch (_) {}
  }

  Future<void> _clearFiltersOnly() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_filtersKey);
      await sp.remove(_sellFiltersKey);
      await sp.remove(_savedSearchesKey);
      // Don't clear cached car data to improve reliability
    } catch (_) {}
  }

  Future<void> _saveCurrentSearch() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final List<dynamic> raw = json.decode(
        sp.getString(_savedSearchesKey) ?? '[]',
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

      await sp.setString(_savedSearchesKey, json.encode(deduped));
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
    } catch (_) {}
  }

  // Intentionally disabled: auto-saving on every filter change created many duplicates.
  Future<void> _autoSaveSearch() async {}

  // Check if current filters have meaningful values
  bool _hasMeaningfulFilters() {
    return (selectedBrand?.isNotEmpty == true) ||
        (selectedModel?.isNotEmpty == true) ||
        (selectedCity?.isNotEmpty == true) ||
        (selectedMinPrice?.isNotEmpty == true) ||
        (selectedMaxPrice?.isNotEmpty == true) ||
        (selectedMinYear?.isNotEmpty == true) ||
        (selectedMaxYear?.isNotEmpty == true) ||
        (selectedMinMileage?.isNotEmpty == true) ||
        (selectedMaxMileage?.isNotEmpty == true) ||
        (selectedCondition?.isNotEmpty == true && selectedCondition != 'Any') ||
        (selectedTransmission?.isNotEmpty == true &&
            selectedTransmission != 'Any') ||
        (selectedFuelType?.isNotEmpty == true && selectedFuelType != 'Any') ||
        (selectedBodyType?.isNotEmpty == true && selectedBodyType != 'Any') ||
        (selectedColor?.isNotEmpty == true && selectedColor != 'Any') ||
        (selectedDriveType?.isNotEmpty == true && selectedDriveType != 'Any') ||
        (selectedRegionSpecs?.isNotEmpty == true &&
            isValidCarRegionSpecCode(selectedRegionSpecs)) ||
        (selectedCylinderCount?.isNotEmpty == true &&
            selectedCylinderCount != 'Any') ||
        (selectedSeating?.isNotEmpty == true && selectedSeating != 'Any') ||
        (selectedTitleStatus?.isNotEmpty == true);
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

  // Check if two filter maps are equal
  bool _areFiltersEqual(
    Map<String, dynamic> filters1,
    Map<String, dynamic> filters2,
  ) {
    if (filters1.length != filters2.length) return false;
    for (String key in filters1.keys) {
      if (filters1[key] != filters2[key]) return false;
    }
    return true;
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

  // Static options
  List<String> get homeBrands => CarCatalog.brands;
  Map<String, List<String>> get models => CarCatalog.models;
  Map<String, Map<String, List<String>>> get trimsByBrandModel =>
      CarCatalog.trimsByBrandModel;

  final List<String> trims = [
    'Base',
    'Sport',
    'Luxury',
    'Premium',
    'Limited',
    'Platinum',
    'Signature',
    'Touring',
    'SE',
    'LE',
    'XLE',
    'XSE',
  ];
  final List<String> conditions = ['Any', 'New', 'Used'];
  // Same options as sell page (with 'Any' for filter)
  final List<String> transmissions = ['Any', 'Automatic', 'Manual'];
  final List<String> fuelTypes = [
    'Any',
    'Gasoline',
    'Diesel',
    'Electric',
    'Hybrid',
    'Plug-in Hybrid',
  ];
  // Same options as sell page (with 'Any' for filter); keep fixed list so More Filters matches sell page
  List<String> bodyTypes = [
    'Any',
    'Sedan',
    'SUV',
    'Hatchback',
    'Coupe',
    'Convertible',
    'Wagon',
    'Pickup',
    'Van',
    'Minivan',
  ];
  final List<String> colors = [
    'Any',
    'Black',
    'White',
    'Silver',
    'Gray',
    'Red',
    'Blue',
    'Green',
    'Yellow',
    'Orange',
    'Purple',
    'Brown',
    'Beige',
    'Gold',
  ];
  final List<String> driveTypes = ['Any', 'FWD', 'RWD', 'AWD', '4WD'];
  final List<String> cylinderCounts = [
    'Any',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
  ];
  final List<String> seatings = [
    'Any',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
    '17',
    '18',
    '19',
    '20',
    '21',
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
    '28',
    '29',
    '30',
    '31',
    '32',
    '33',
    '34',
    '35',
    '36',
    '37',
    '38',
    '39',
    '40',
    '41',
    '42',
    '43',
    '44',
    '45',
    '46',
    '47',
    '48',
    '49',
    '50',
  ];
  final List<String> engineSizes = [
    'Any',
    '0.5',
    '0.6',
    '0.7',
    '0.8',
    '0.9',
    '1.0',
    '1.1',
    '1.2',
    '1.3',
    '1.4',
    '1.5',
    '1.6',
    '1.7',
    '1.8',
    '1.9',
    '2.0',
    '2.1',
    '2.2',
    '2.3',
    '2.4',
    '2.5',
    '2.6',
    '2.7',
    '2.8',
    '2.9',
    '3.0',
    '3.1',
    '3.2',
    '3.3',
    '3.4',
    '3.5',
    '3.6',
    '3.7',
    '3.8',
    '3.9',
    '4.0',
    '4.1',
    '4.2',
    '4.3',
    '4.4',
    '4.5',
    '4.6',
    '4.7',
    '4.8',
    '4.9',
    '5.0',
    '5.1',
    '5.2',
    '5.3',
    '5.4',
    '5.5',
    '5.6',
    '5.7',
    '5.8',
    '5.9',
    '6.0',
    '6.1',
    '6.2',
    '6.3',
    '6.4',
    '6.5',
    '6.6',
    '6.7',
    '6.8',
    '6.9',
    '7.0',
    '7.1',
    '7.2',
    '7.3',
    '7.4',
    '7.5',
    '7.6',
    '7.7',
    '7.8',
    '7.9',
    '8.0',
    '8.1',
    '8.2',
    '8.3',
    '8.4',
    '8.5',
    '8.6',
    '8.7',
    '8.8',
    '8.9',
    '9.0',
    '9.1',
    '9.2',
    '9.3',
    '9.4',
    '9.5',
    '9.6',
    '9.7',
    '9.8',
    '9.9',
    '10.0',
    '10.1',
    '10.2',
    '10.3',
    '10.4',
    '10.5',
    '10.6',
    '10.7',
    '10.8',
    '10.9',
    '11.0',
    '11.1',
    '11.2',
    '11.3',
    '11.4',
    '11.5',
    '11.6',
    '11.7',
    '11.8',
    '11.9',
    '12.0',
    '12.1',
    '12.2',
    '12.3',
    '12.4',
    '12.5',
    '12.6',
    '12.7',
    '12.8',
    '12.9',
    '13.0',
    '13.1',
    '13.2',
    '13.3',
    '13.4',
    '13.5',
    '13.6',
    '13.7',
    '13.8',
    '13.9',
    '14.0',
    '14.1',
    '14.2',
    '14.3',
    '14.4',
    '14.5',
    '14.6',
    '14.7',
    '14.8',
    '14.9',
    '15.0',
    '15.1',
    '15.2',
    '15.3',
    '15.4',
    '15.5',
    '15.6',
    '15.7',
    '15.8',
    '15.9',
    '16.0',
  ];
  final List<String> cities = [
    'Any',
    'Baghdad',
    'Basra',
    'Erbil',
    'Najaf',
    'Karbala',
    'Kirkuk',
    'Mosul',
    'Sulaymaniyah',
    'Dohuk',
    'Anbar',
    'Halabja',
    'Diyala',
    'Diyarbakir',
    'Maysan',
    'Muthanna',
    'Dhi Qar',
    'Salaheldeen',
  ];
  List<String> getLocalizedSortOptions(BuildContext context) => [
    AppLocalizations.of(context)!.defaultSort,
    AppLocalizations.of(context)!.sort_newest,
    AppLocalizations.of(context)!.sort_price_low_high,
    AppLocalizations.of(context)!.sort_price_high_low,
    AppLocalizations.of(context)!.sort_year_newest,
    AppLocalizations.of(context)!.sort_year_oldest,
    AppLocalizations.of(context)!.sort_mileage_low_high,
    AppLocalizations.of(context)!.sort_mileage_high_low,
  ];

  bool useCustomMinPrice = false;
  bool useCustomMaxPrice = false;
  bool useCustomMinMileage = false;
  bool useCustomMaxMileage = false;

  // Controllers for manual (non-dropdown) filter inputs in the "More Filters" dialog.
  // These avoid creating new controllers on every rebuild (which can cause churn/leaks).
  late final TextEditingController _minPriceController;
  late final TextEditingController _maxPriceController;
  late final TextEditingController _minYearController;
  late final TextEditingController _maxYearController;
  late final TextEditingController _minMileageController;
  late final TextEditingController _maxMileageController;
  late final TextEditingController _engineSizeController;

  @override
  void initState() {
    super.initState();
    final seededOffset = _HomeFeedScrollPersistence.initialOffset;
    _homeScrollController = ScrollController(
      initialScrollOffset: seededOffset > 0 ? seededOffset : 0,
    );
    _primePendingHomeScrollRestoreFromPersistence();
    // Do not obscure the home body while restoring scroll; in route-replacement
    // flows this can get stuck and appear as a blank page.
    _obscureHomeBodyUntilScrollRestored = false;
    _minPriceController = TextEditingController();
    _maxPriceController = TextEditingController();
    _minYearController = TextEditingController();
    _maxYearController = TextEditingController();
    _minMileageController = TextEditingController();
    _maxMileageController = TextEditingController();
    _engineSizeController = TextEditingController();
    if (_homeFeedCache.isNotEmpty) {
      cars = _homeFeedCache
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: true);
      isLoading = false;
      hasLoadedOnce = true;
      _page = _homeFeedCachePage;
      _hasNext = _homeFeedCacheHasNext;
    }
    // Restore last chosen layout (grid vs list) across pages.
    ListingLayoutPrefs.load().then((cols) {
      if (!mounted) return;
      setState(() {
        listingColumns = cols;
      });
    });
    _loadBodyTypesFromAssets();
    CarSpecIndex.loadWithResult().then((r) {
      if (!mounted) return;
      setState(() {
        _homeCarSpecIdx = r.index;
        _invalidateHomeCatalogFilterCaches();
        _pruneHomeMotorFilterSelectionsIfInvalid();
      });
    });
    if (!_homeDeleteHandlerRegistered) {
      _homeDeleteHandlerRegistered = true;
      ListingEvents.addDeleteHandler(_purgeDeletedFromHomeFeedCache);
    }
    ListingEvents.deletedListingId.addListener(_onHomeListingDeleted);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Avoid network calls during `flutter test` runs.
      // `FLUTTER_TEST` isn't reliably set as a compile-time define for all builds,
      // so we also check the runtime environment variable.
      if (_kFlutterTest || Platform.environment.containsKey('FLUTTER_TEST')) {
        return;
      }
      await _restoreFilters();
      if (!mounted) return;
      final oneTimeFilters = await _consumeOneTimeSavedSearchFilters();
      final pendingSavedSearch = await _consumePendingSavedSearchFetch();
      if (oneTimeFilters != null) {
        setState(() {
          applyFiltersFromHomePersistMap(oneTimeFilters);
        });
      }
      if (pendingSavedSearch || oneTimeFilters != null) {
        _homeFeedCache.clear();
        if (mounted) {
          setState(() {
            cars = [];
            _page = 1;
            _hasNext = true;
          });
        }
        fetchCars(bypassCache: true);
      } else if (cars.isEmpty) {
        // If we already rehydrated listings from memory (tab return), do not run an
        // immediate fetchCars(): the first-page API response would replace a deep
        // scroll's many rows with ~20 items, collapse maxScrollExtent, and wipe the
        // saved offset. User can pull-to-refresh or change filters to refetch.
        fetchCars();
      }
      // Kick restoration once the first frame is mounted, instead of waiting
      // for user interaction/layout changes.
      _scheduleHomeScrollRestoreAfterListReady();
    });
    // Hook up infinite scroll
    _homeScrollController.addListener(() {
      try {
        final pos = _homeScrollController.position;
        _lastHomeScrollPixels = pos.pixels.clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        // Never persist while loading overlay replaces the feed (short extent).
        if (isLoading || _isLoadingMore) return;
        // Persist continuously, but don't let temporary clamped restore values
        // overwrite a higher pending target that we still need to reach.
        final pending = _pendingHomeScrollRestore;
        final snapshot = (pending != null && pending > _lastHomeScrollPixels)
            ? pending
            : _lastHomeScrollPixels;
        _HomeFeedScrollPersistence.savePixels(snapshot);
        if (_hasNext &&
            !_isLoadingMore &&
            pos.pixels >= (pos.maxScrollExtent - 400)) {
          _loadMore();
        }
      } catch (_) {}
    });
  }

  /// Runs on delete even when [HomePage] is disposed (tab uses route replacement).
  static void _purgeDeletedFromHomeFeedCache(String id) {
    _homeFeedCache.removeWhere((c) => listingMatchesId(c, id));
  }

  void _onHomeListingDeleted() {
    final id = ListingEvents.deletedListingId.value;
    if (id == null || id.isEmpty || !mounted) return;
    setState(() {
      cars.removeWhere((c) => listingMatchesId(c, id));
    });
  }

  void dispose() {
    ListingEvents.deletedListingId.removeListener(_onHomeListingDeleted);
    _sortDebounceTimer?.cancel();
    unawaited(_persistFilters());
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _minYearController.dispose();
    _maxYearController.dispose();
    _minMileageController.dispose();
    _maxMileageController.dispose();
    _engineSizeController.dispose();
    try {
      _homeScrollRestoreScheduleGen++;
      // Prefer live controller position; on tab replacement the viewport is often
      // gone already (`!hasClients`), so fall back to [_lastHomeScrollPixels] / pending.
      var best = _lastHomeScrollPixels;
      try {
        if (_homeScrollController.hasClients) {
          final pos = _homeScrollController.position;
          best = pos.pixels.clamp(
            pos.minScrollExtent,
            pos.maxScrollExtent,
          );
        }
      } catch (_) {}
      if (best <= 0 && _pendingHomeScrollRestore != null) {
        best = _pendingHomeScrollRestore!;
      }
      _HomeFeedScrollPersistence.savePixels(best);
      _homeFeedCache = cars
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: true);
      _homeFeedCachePage = _page;
      _homeFeedCacheHasNext = _hasNext;
      _homeScrollController.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _persistCurrentHomeOffsetNow() {
    try {
      if (_homeScrollController.hasClients) {
        final pos = _homeScrollController.position;
        final y = pos.pixels.clamp(pos.minScrollExtent, pos.maxScrollExtent);
        _lastHomeScrollPixels = y;
        _pendingHomeScrollRestore = y;
        _HomeFeedScrollPersistence.savePixels(y);
        return;
      }
    } catch (_) {}
    _pendingHomeScrollRestore = _lastHomeScrollPixels;
    _HomeFeedScrollPersistence.savePixels(_lastHomeScrollPixels);
  }

  void _primePendingHomeScrollRestoreFromPersistence() {
    final y = _HomeFeedScrollPersistence.initialOffset;
    if (y > 0) _pendingHomeScrollRestore = y;
  }

  Future<void> _nextLayoutFrame() async {
    final c = Completer<void>();
    // Force a frame so awaiting this helper never depends on user input.
    SchedulerBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  void _scheduleHomeScrollRestoreAfterListReady() {
    final target = _pendingHomeScrollRestore;
    if (target == null || target <= 0) return;

    final gen = ++_homeScrollRestoreScheduleGen;
    // Ensure a frame is produced even when nothing else is animating.
    SchedulerBinding.instance.scheduleFrame();
    unawaited(_restoreHomeScrollWork(gen, target));
  }

  /// Loads extra pages without waiting on scroll physics, then jumps once — faster than
  /// nudging scroll each frame to trigger [_loadMore].
  Future<void> _restoreHomeScrollWork(int gen, double target) async {
    const slack = 12.0;
    const maxPrefetchPages = 40;

    try {
      for (var i = 0; i < 240 && mounted; i++) {
        if (gen != _homeScrollRestoreScheduleGen) return;
        await _nextLayoutFrame();
        if (!isLoading &&
            _homeScrollController.hasClients &&
            _homeScrollController.position.hasContentDimensions) {
          break;
        }
      }
      if (!mounted || gen != _homeScrollRestoreScheduleGen) return;

      for (var p = 0; p < maxPrefetchPages && mounted; p++) {
        if (gen != _homeScrollRestoreScheduleGen) return;
        if (!_homeScrollController.hasClients) return;
        final pos = _homeScrollController.position;
        if (!pos.hasContentDimensions) {
          await _nextLayoutFrame();
          continue;
        }
        if (pos.maxScrollExtent >= target - slack) break;
        if (!_hasNext) break;
        await _loadMore();
        await _nextLayoutFrame();
      }

      if (!mounted || gen != _homeScrollRestoreScheduleGen) return;
      await _nextLayoutFrame();
      if (!mounted || gen != _homeScrollRestoreScheduleGen) return;
      if (!_homeScrollController.hasClients) {
        SchedulerBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || gen != _homeScrollRestoreScheduleGen) return;
          _scheduleHomeScrollRestoreAfterListReady();
        });
        return;
      }
      final pos = _homeScrollController.position;
      if (!pos.hasContentDimensions) {
        SchedulerBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || gen != _homeScrollRestoreScheduleGen) return;
          _scheduleHomeScrollRestoreAfterListReady();
        });
        return;
      }
      final desired = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((pos.pixels - desired).abs() > 0.5) {
        _homeScrollController.jumpTo(desired);
      }
      // Do not clear pending target until we actually reach it (or data loading
      // has fully settled and no further growth is possible).
      final reachedTarget = (desired - target).abs() <= slack;
      final settling =
          isLoading || _isLoadingMore || (_hasNext && pos.maxScrollExtent < target - slack);
      if (!reachedTarget && settling) {
        SchedulerBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || gen != _homeScrollRestoreScheduleGen) return;
          _scheduleHomeScrollRestoreAfterListReady();
        });
        return;
      }
      _pendingHomeScrollRestore = null;
    } finally {
      if (mounted && gen == _homeScrollRestoreScheduleGen) {
        setState(() {
          _obscureHomeBodyUntilScrollRestored = false;
        });
      }
    }
  }

  Future<void> _loadBodyTypesFromAssets() async {
    try {
      final String manifestJson = await services.rootBundle.loadString(
        'AssetManifest.json',
      );
      final Map<String, dynamic> manifestMap = json.decode(manifestJson);
      final Iterable<String> allAssets = manifestMap.keys.cast<String>();

      // Accept both SVG (clean) and PNG variants from both folders
      final List<String> btAssets = allAssets
          .where(
            (p) =>
                (p.startsWith('assets/body_types_clean/') &&
                    (p.endsWith('.svg') || p.endsWith('.png'))) ||
                (p.startsWith('assets/body_types_png/') && p.endsWith('.png')),
          )
          .toList();

      // Build normalized label -> canonical svg path map
      final Map<String, String> labelToSvg = {};
      for (final String path in btAssets) {
        // Extract base filename without extension
        final String fileName = path.split('/').last; // e.g., sedan.svg
        final String base = fileName
            .replaceAll('.svg', '')
            .replaceAll('.png', '');
        if (base.toLowerCase() == 'default') {
          continue; // skip default placeholder
        }

        // Build a user-friendly label (title case, even if file uses underscores)
        final String label = base
            .replaceAll('_', ' ')
            .split(' ')
            .map(
              (w) => w.isEmpty
                  ? w
                  : (w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '')),
            )
            .join(' ');

        // Prefer clean SVG if available for same label, otherwise use PNG
        if (!labelToSvg.containsKey(label)) {
          labelToSvg[label] = path;
        } else {
          final String existing = labelToSvg[label]!;
          final bool existingIsSvg = existing.toLowerCase().endsWith('.svg');
          final bool incomingIsSvg = path.toLowerCase().endsWith('.svg');
          if (!existingIsSvg && incomingIsSvg) {
            labelToSvg[label] = path;
          }
        }
      }

      if (mounted) {
        setState(() {
          final List<String> labels = labelToSvg.keys.toList()..sort();
          globalBodyTypes = ['Any', ...labels];
          // Keep bodyTypes as sell-page list so More Filters options stay aligned
          globalBodyTypeAssetMap = labelToSvg;
        });
      }
    } catch (_) {
      // If anything fails, keep the existing static fallback already present in code
    }
  }

  Future<void> fetchCars({
    bool bypassCache = false,
    bool isRetry = false,
  }) async {
    _debugLog(
      'ðŸš€ fetchCars called with bypassCache: $bypassCache, isRetry: $isRetry',
    );
    // Analytics tracking for search fetch
    // Only show full-screen loading when there is no feed yet. If we already have
    // listings (e.g. memory rehydrate after tab switch), isLoading would replace the
    // grid with SliverFillRemaining, collapse scroll extent, and the scroll listener
    // would persist a tiny clamped offset — wiping the user's deep scroll position.
    if (mounted) {
      setState(() {
        if (cars.isEmpty) {
          isLoading = true;
        }
        loadErrorMessage = null;
      });
    }
    Map<String, String> filters = _buildFilters();
    // Reset pagination
    _page = 1;
    _hasNext = true;
    filters['page'] = _page.toString();
    filters['per_page'] = '20';

    String query = Uri(queryParameters: filters).query;
    final url = Uri.parse(
      '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
    );

    // Debug: Print the URL being called
    _debugLog('ðŸ” Fetching cars from: $url');
    _debugLog('ðŸ” Applied filters: $filters');
    _debugLog('ðŸ” Sort parameter: ${filters['sort_by']}');

    // Offline-first cache (skip cache if bypassCache is true)
    final sp = await SharedPreferences.getInstance();
    final cacheKey = 'cache_home_${query.hashCode}';
    String? cached;
    if (!bypassCache) {
      // Use cached data to improve reliability and reduce API dependency
      cached = sp.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        _debugLog('ðŸ“¦ Using cached data for key: $cacheKey');
        try {
          final decoded = json.decode(cached);
          List<dynamic> listSource;
          if (decoded is List) {
            listSource = decoded;
          } else if (decoded is Map && decoded['cars'] is List) {
            listSource = decoded['cars'] as List;
          } else {
            listSource = const [];
          }
          final List<Map<String, dynamic>> parsed = listSource
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
              .cast<Map<String, dynamic>>();
          if (mounted) {
            setState(() {
              cars = _applyDamagedPartsExactFilter(parsed);
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
              if (parsed.isNotEmpty) _autoFetchedForEmptyWithSort = false;
            });
            _scheduleHomeScrollRestoreAfterListReady();
          }
        } catch (_) {}
      }
    } else {
      _debugLog('ðŸš« Bypassing cache for key: $cacheKey');
    }

    try {
      // Use longer timeout for sorting requests and add connection headers
      final timeout = filters.containsKey('sort_by')
          ? Duration(seconds: 30)
          : Duration(seconds: 15);
      final response = await http
          .get(
            url,
            headers: {
              'Connection': 'keep-alive',
              'Accept': 'application/json',
              'User-Agent': 'CARZO-Mobile/1.0',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          )
          .timeout(timeout);

      _debugLog('ðŸ“¡ Response status: ${response.statusCode}');
      _debugLog('ðŸ“¡ Response body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> listSource;
        if (decoded is List) {
          listSource = decoded;
        } else if (decoded is Map && decoded['cars'] is List) {
          listSource = decoded['cars'] as List;
          try {
            final pg = (decoded['pagination'] as Map?);
            if (pg != null && pg['has_next'] is bool) {
              _hasNext = pg['has_next'] as bool;
            }
          } catch (_) {}
        } else {
          listSource = const [];
        }
        final List<Map<String, dynamic>> parsed = listSource
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
            .cast<Map<String, dynamic>>();

        _debugLog('ðŸ“Š Parsed ${parsed.length} cars from response');

        if (mounted) {
          setState(() {
            cars = _applyDamagedPartsExactFilter(parsed);
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage =
                null; // Clear any previous error message on success
            if (parsed.isNotEmpty) _autoFetchedForEmptyWithSort = false;
          });
          _homeFeedCache = cars
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: true);
          _homeFeedCachePage = _page;
          _homeFeedCacheHasNext = _hasNext;
        }
        // Save fresh cache
        unawaited(sp.setString(cacheKey, response.body));
        _debugLog('âœ… Found ${parsed.length} cars with applied filters');
        _page = 2; // next page to request
        // Reset retry count on success
        _fetchRetryCount = 0;
      } else {
        _debugLog('âŒ Server error: ${response.statusCode}');
        _debugLog('âŒ Response body: ${response.body}');
        await _handleFetchError(
          bypassCache,
          cached,
          'Server ${response.statusCode}',
          isRetry: isRetry,
        );
      }
    } catch (e) {
      _debugLog('âŒ Network error: $e');
      await _handleFetchError(
        bypassCache,
        cached,
        'Network error',
        isRetry: isRetry,
      );
    }
    if (mounted) {
      _scheduleHomeScrollRestoreAfterListReady();
    }
  }

  Future<void> _handleFetchError(
    bool bypassCache,
    String? cached,
    String errorMessage, {
    bool isRetry = false,
  }) async {
    // Don't show error immediately - try fallback strategies first
    _debugLog('ðŸ”„ Handling fetch error: $errorMessage, isRetry: $isRetry');

    // First, attempt the alternative endpoint /api/cars (server returns { cars: [...], pagination: {...} })
    try {
      final ok = await _fetchFromApiCars(includeSort: true);
      if (ok) return; // Success via /api/cars; stop handling error
    } catch (_) {}

    // If sorting failed and we have a sort parameter, try without sorting first
    if (selectedSortBy != null && selectedSortBy!.isNotEmpty && !isRetry) {
      _debugLog('ðŸ”„ Sorting failed, trying without sort parameter');
      try {
        await _fetchWithoutSort();
        return; // Success, don't show error
      } catch (e) {
        _debugLog('âŒ Fallback without sort also failed: $e');
      }
    }

    // Auto-retry logic for network errors
    if (_fetchRetryCount < _maxRetries &&
        errorMessage == 'Network error' &&
        !isRetry) {
      _fetchRetryCount++;
      _debugLog(
        'ðŸ”„ Auto-retrying fetch (attempt $_fetchRetryCount/$_maxRetries)',
      );
      await Future.delayed(Duration(seconds: 1)); // Shorter delay for better UX
      if (mounted) {
        try {
          await fetchCars(bypassCache: bypassCache, isRetry: true);
          return; // Success, don't show error
        } catch (e) {
          _debugLog('âŒ Auto-retry failed: $e');
        }
      }
    }

    // Only show error if all fallback strategies failed
    if (mounted) {
      setState(() {
        isLoading = false;
        hasLoadedOnce = true;
        // Only show error if bypassing cache OR no cached data is available
        if (bypassCache || cached == null) {
          final base = getApiBase();
          loadErrorMessage =
              '$errorMessage. Check server at $base and same Wi‑Fi.';
        } else {
          loadErrorMessage = null; // Clear error when using cached data
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasNext) return;
    _isLoadingMore = true;
    try {
      final Map<String, String> filters = _buildFilters();
      filters['page'] = _page.toString();
      filters['per_page'] = '20';
      final query = Uri(queryParameters: filters).query;
      final url = Uri.parse(
        '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
      );
      final resp = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        List<dynamic> listSource;
        if (decoded is Map && decoded['cars'] is List) {
          listSource = decoded['cars'] as List;
          try {
            final pg = (decoded['pagination'] as Map?);
            if (pg != null && pg['has_next'] is bool) {
              _hasNext = pg['has_next'] as bool;
            }
          } catch (_) {}
        } else if (decoded is List) {
          listSource = decoded;
        } else {
          listSource = const [];
        }
        final List<Map<String, dynamic>> more = listSource
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
            .cast<Map<String, dynamic>>();
        if (mounted && more.isNotEmpty) {
          setState(() {
            cars.addAll(_applyDamagedPartsExactFilter(more));
          });
          _homeFeedCache = cars
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: true);
          _homeFeedCachePage = _page;
          _homeFeedCacheHasNext = _hasNext;
        }
        _page += 1;
      }
    } catch (_) {}
    _isLoadingMore = false;
  }

  void _scrollHomeToTopAndResetCardImages() {
    _homeScrollRestoreScheduleGen++;
    _pendingHomeScrollRestore = null;
    _lastHomeScrollPixels = 0;
    _HomeFeedScrollPersistence.markTop();
    if (_homeScrollController.hasClients) {
      _homeScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) {
      setState(() {
        _obscureHomeBodyUntilScrollRestored = false;
        _homeCarouselResetSeed++;
      });
    }
  }

  // Fallback fetch using /api/cars which wraps results in { cars: [...], pagination: { has_next: bool } }
  Future<bool> _fetchFromApiCars({bool includeSort = true}) async {
    try {
      Map<String, String> filters = _buildFilters(includeSort: includeSort);
      final query = Uri(queryParameters: filters).query;
      final url = Uri.parse(
        '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
      );
      final resp = await http
          .get(
            url,
            headers: {
              'Accept': 'application/json',
              'Connection': 'close',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        if (decoded is Map && decoded['cars'] is List) {
          final List<Map<String, dynamic>> parsed =
              List<Map<String, dynamic>>.from(
                (decoded['cars'] as List).whereType<Map>().map(
                  (e) => e.map((k, v) => MapEntry(k.toString(), v)),
                ),
              );
          if (mounted) {
            setState(() {
              cars = _applyDamagedPartsExactFilter(parsed);
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
            });
          }
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _fetchWithAlternativeHeaders(String sortValue) async {
    try {
      _debugLog(
        'ðŸ”„ Attempting fetch with alternative headers for sort: $sortValue',
      );
      Map<String, String> filters = _buildFilters();

      String query = Uri(queryParameters: filters).query;
      final url = Uri.parse(
        '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
      );

      _debugLog('ðŸ” Alternative fetch URL: $url');

      final response = await http
          .get(
            url,
            headers: {
              'Connection': 'close',
              'Accept': 'application/json',
              'User-Agent': 'CARZO-Mobile/1.0',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          )
          .timeout(Duration(seconds: 25));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> listSource;
        if (decoded is List) {
          listSource = decoded;
        } else if (decoded is Map && decoded['cars'] is List) {
          listSource = decoded['cars'] as List;
        } else {
          listSource = const [];
        }
        final List<Map<String, dynamic>> parsed = listSource
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
            .cast<Map<String, dynamic>>();

        if (mounted) {
          setState(() {
            cars = _applyDamagedPartsExactFilter(parsed);
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage = null;
          });
        }

        _debugLog(
          'âœ… Alternative fetch successful: ${parsed.length} cars loaded',
        );
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      _debugLog('âŒ Alternative fetch error: $e');
      rethrow;
    }
  }

  Future<void> _fetchWithoutSort() async {
    try {
      _debugLog('ðŸ”„ Attempting fetch without sort parameter');
      Map<String, String> filters = _buildFilters(includeSort: false);

      String query = Uri(queryParameters: filters).query;
      final url = Uri.parse(
        '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
      );

      _debugLog('ðŸ” Fallback URL: $url');

      final response = await http.get(url).timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> listSource;
        if (decoded is List) {
          listSource = decoded;
        } else if (decoded is Map && decoded['cars'] is List) {
          listSource = decoded['cars'] as List;
        } else {
          listSource = const [];
        }
        final List<Map<String, dynamic>> parsed = listSource
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
            .cast<Map<String, dynamic>>();

        if (mounted) {
          setState(() {
            cars = _applyDamagedPartsExactFilter(parsed);
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage = null;
          });
        }

        _debugLog(
          'âœ… Fallback fetch successful: ${parsed.length} cars loaded',
        );

        // Show a message that sorting was disabled
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sorting temporarily disabled due to server issue'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        _debugLog('âŒ Fallback fetch failed: ${response.statusCode}');
        if (mounted) {
          setState(() {
            loadErrorMessage = 'Server error: ${response.statusCode}';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      _debugLog('âŒ Fallback fetch error: $e');
      if (mounted) {
        setState(() {
          loadErrorMessage = 'Network error';
          isLoading = false;
        });
      }
    }
  }

  void onFilterChanged() {
    // Analytics tracking for filters applied
    fetchCars();
    // Auto-save search after applying filters
    unawaited(_autoSaveSearch());
  }

  List<Map<String, dynamic>> _applyDamagedPartsExactFilter(
    List<Map<String, dynamic>> input,
  ) {
    if (selectedTitleStatus != 'damaged') return input;
    final targetParts = int.tryParse(selectedDamagedParts ?? '');
    if (targetParts == null) return input;

    return input.where((car) {
      final titleStatus = (car['title_status']?.toString() ?? '')
          .trim()
          .toLowerCase();
      if (titleStatus != 'damaged') return false;
      final parts = int.tryParse(car['damaged_parts']?.toString() ?? '');
      return parts == targetParts;
    }).toList();
  }

  Timer? _sortDebounceTimer;
  int _fetchRetryCount = 0;
  static const int _maxRetries = 3;

  Map<String, String> _buildFilters({bool includeSort = true}) {
    Map<String, String> filters = {};

    // Brand and Model filters
    if (selectedBrand != null && selectedBrand!.isNotEmpty) {
      filters['brand'] = selectedBrand!;
    }
    if (selectedModel != null && selectedModel!.isNotEmpty) {
      filters['model'] = selectedModel!;
    }
    if (selectedTrim != null && selectedTrim!.isNotEmpty) {
      filters['trim'] = selectedTrim!;
    }

    // Price filters - apply individually, not requiring both
    if (selectedMinPrice != null && selectedMinPrice!.isNotEmpty) {
      filters['min_price'] = selectedMinPrice!;
    }
    if (selectedMaxPrice != null && selectedMaxPrice!.isNotEmpty) {
      filters['max_price'] = selectedMaxPrice!;
    }

    // Year filters - apply individually, not requiring both
    if (selectedMinYear != null && selectedMinYear!.isNotEmpty) {
      filters['min_year'] = selectedMinYear!;
    }
    if (selectedMaxYear != null && selectedMaxYear!.isNotEmpty) {
      filters['max_year'] = selectedMaxYear!;
    }

    // Mileage filters - apply individually, not requiring both
    if (selectedMinMileage != null && selectedMinMileage!.isNotEmpty) {
      filters['min_mileage'] = selectedMinMileage!;
    }
    if (selectedMaxMileage != null && selectedMaxMileage!.isNotEmpty) {
      filters['max_mileage'] = selectedMaxMileage!;
    }

    // Vehicle condition and specifications
    if (selectedCondition != null &&
        selectedCondition!.isNotEmpty &&
        selectedCondition != 'Any') {
      filters['condition'] = selectedCondition!.toLowerCase();
    }
    if (selectedTransmission != null &&
        selectedTransmission!.isNotEmpty &&
        selectedTransmission != 'Any') {
      filters['transmission'] = selectedTransmission!.toLowerCase();
    }
    if (selectedFuelType != null &&
        selectedFuelType!.isNotEmpty &&
        selectedFuelType != 'Any') {
      filters['fuel_type'] = selectedFuelType!.toLowerCase();
    }
    if (selectedBodyType != null &&
        selectedBodyType!.isNotEmpty &&
        selectedBodyType != 'Any') {
      filters['body_type'] = selectedBodyType!.toLowerCase();
    }
    if (selectedColor != null &&
        selectedColor!.isNotEmpty &&
        selectedColor != 'Any') {
      filters['color'] = selectedColor!.toLowerCase();
    }
    if (selectedDriveType != null &&
        selectedDriveType!.isNotEmpty &&
        selectedDriveType != 'Any') {
      filters['drive_type'] = selectedDriveType!.toLowerCase();
    }
    if (selectedRegionSpecs != null &&
        selectedRegionSpecs!.isNotEmpty &&
        isValidCarRegionSpecCode(selectedRegionSpecs)) {
      filters['region_specs'] = selectedRegionSpecs!.trim().toLowerCase();
    }
    if (selectedCylinderCount != null &&
        selectedCylinderCount!.isNotEmpty &&
        selectedCylinderCount != 'Any') {
      filters['cylinder_count'] = selectedCylinderCount!;
    }
    if (selectedSeating != null &&
        selectedSeating!.isNotEmpty &&
        selectedSeating != 'Any') {
      filters['seating'] = selectedSeating!;
    }
    if (selectedEngineSize != null &&
        selectedEngineSize!.isNotEmpty &&
        selectedEngineSize != 'Any') {
      filters['engine_size'] = selectedEngineSize!;
    }

    // Location and other filters
    if (selectedCity != null && selectedCity!.isNotEmpty) {
      filters['city'] = selectedCity!;
    }
    if (selectedPlateType != null &&
        selectedPlateType!.isNotEmpty &&
        selectedPlateType != 'Any') {
      filters['plate_type'] = selectedPlateType!.toLowerCase();
    }
    if (selectedPlateCity != null &&
        selectedPlateCity!.isNotEmpty &&
        selectedPlateCity != 'Any') {
      filters['plate_city'] = selectedPlateCity!;
    }

    // Only include sort if requested and valid
    if (includeSort) {
      final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
      if (apiSortValue != null && apiSortValue.isNotEmpty) {
        filters['sort_by'] = apiSortValue;
      }
    }

    // Title status and damaged parts
    if (selectedTitleStatus != null && selectedTitleStatus!.isNotEmpty) {
      filters['title_status'] = selectedTitleStatus!;
      if (selectedTitleStatus == 'damaged' &&
          selectedDamagedParts != null &&
          selectedDamagedParts!.isNotEmpty) {
        filters['damaged_parts'] = selectedDamagedParts!;
      }
    }

    return filters;
  }

  void onSortChanged() async {
    _debugLog('ðŸ”„ Sort changed to: $selectedSortBy');
    // Analytics tracking for sort changed

    // Cancel any pending sort operation
    _sortDebounceTimer?.cancel();

    // Immediate response - no debounce for better UX
    if (!mounted) return;

    // Reset retry count when sorting changes
    _fetchRetryCount = 0;

    // Clear any previous error messages but do NOT set isLoading = true so we
    // keep showing the current list until the sorted result arrives (avoids
    // flashing empty state when only sort changed).
    if (mounted) {
      setState(() {
        loadErrorMessage = null;
      });
    }

    // Clear cache for current filters
    try {
      final sp = await SharedPreferences.getInstance();
      final currentFilters = _buildFilters();
      final query = Uri(queryParameters: currentFilters).query;
      final cacheKey = 'cache_home_${query.hashCode}';
      await sp.remove(cacheKey);
      _debugLog('ðŸ—‘ï¸ Cleared cache for current filters: $cacheKey');
    } catch (e) {
      _debugLog('âŒ Error clearing cache: $e');
    }

    // Try the sort operation immediately
    await _performSortWithFallback();
  }

  Future<void> _performSortWithFallback() async {
    // Validate sort parameter before attempting
    final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
    _debugLog(
      'ðŸ”„ Sort parameter validation: $selectedSortBy -> $apiSortValue',
    );

    if (apiSortValue == null || apiSortValue.isEmpty) {
      _debugLog('âš ï¸ Invalid sort parameter, skipping sort');
      await fetchCars(bypassCache: true);
      return;
    }

    // Try multiple strategies in sequence
    List<Future<void> Function()> strategies = [
      () => _tryDirectSort(apiSortValue),
      () => _tryAlternativeSort(apiSortValue),
      () => _trySimpleSort(apiSortValue),
      () => _tryConnectionReset(apiSortValue),
      () => _tryWithoutSort(),
    ];

    for (int i = 0; i < strategies.length; i++) {
      try {
        _debugLog('ðŸ”„ Trying strategy ${i + 1}/${strategies.length}');
        await strategies[i]();
        _debugLog('âœ… Strategy ${i + 1} successful');
        return;
      } catch (e) {
        _debugLog('âŒ Strategy ${i + 1} failed: $e');
        if (i < strategies.length - 1) {
          await Future.delayed(Duration(milliseconds: 200));
        }
      }
    }

    // If all strategies fail, show error
    if (mounted) {
      setState(() {
        loadErrorMessage = 'Failed to load listings';
        isLoading = false;
      });
    }
  }

  Future<void> _tryDirectSort(String apiSortValue) async {
    _debugLog('ðŸ”„ Direct sort attempt with: $apiSortValue');

    // Try up to 5 times with increasing delays and different approaches
    for (int attempt = 1; attempt <= 5; attempt++) {
      try {
        // Use different timeout and connection settings based on attempt
        final timeout = Duration(seconds: 10 + (attempt * 5));
        _debugLog('ðŸ”„ Attempt $attempt with ${timeout.inSeconds}s timeout');

        Map<String, String> filters = _buildFilters();
        String query = Uri(queryParameters: filters).query;
        final url = Uri.parse(
          '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
        );

        final response = await http
            .get(
              url,
              headers: {
                'Accept': 'application/json',
                'User-Agent': 'CARZO-Mobile/1.0',
                'Connection': attempt % 2 == 0 ? 'close' : 'keep-alive',
                'Cache-Control': 'no-cache',
              },
            )
            .timeout(timeout);

        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          final List<dynamic> listSource = decoded is List
              ? decoded
              : (decoded is Map && decoded['cars'] is List)
              ? decoded['cars'] as List
              : <dynamic>[];
          final List<Map<String, dynamic>> parsed = listSource
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
              .cast<Map<String, dynamic>>();

          if (mounted) {
            setState(() {
              if (parsed.isNotEmpty) {
                cars = _applyDamagedPartsExactFilter(parsed);
              } else if (cars.isEmpty) {
                cars = _applyDamagedPartsExactFilter(parsed);
              }
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
            });
          }

          // Save to cache
          final sp = await SharedPreferences.getInstance();
          final cacheKey = 'cache_home_${query.hashCode}';
          unawaited(sp.setString(cacheKey, response.body));

          unawaited(_autoSaveSearch());
          _debugLog('âœ… Direct sort successful on attempt $attempt');
          return;
        } else {
          throw Exception('Server error: ${response.statusCode}');
        }
      } catch (e) {
        _debugLog('âŒ Direct sort attempt $attempt failed: $e');
        if (attempt < 5) {
          await Future.delayed(Duration(milliseconds: 200 * attempt));
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> _tryAlternativeSort(String apiSortValue) async {
    _debugLog('ðŸ”„ Alternative sort attempt with: $apiSortValue');

    // Try with different connection approaches
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        Map<String, String> filters = _buildFilters();
        String query = Uri(queryParameters: filters).query;
        final url = Uri.parse(
          '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
        );

        final response = await http
            .get(
              url,
              headers: {
                'Accept': 'application/json',
                'User-Agent': 'CARZO-Mobile/1.0',
                'Connection': 'close',
                'Cache-Control': 'no-cache',
                'Pragma': 'no-cache',
                'If-None-Match': '*',
              },
            )
            .timeout(Duration(seconds: 15));

        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          final List<dynamic> listSource = decoded is List
              ? decoded
              : (decoded is Map && decoded['cars'] is List)
              ? decoded['cars'] as List
              : <dynamic>[];
          final List<Map<String, dynamic>> parsed = listSource
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
              .cast<Map<String, dynamic>>();

          if (mounted) {
            setState(() {
              if (parsed.isNotEmpty) {
                cars = _applyDamagedPartsExactFilter(parsed);
              } else if (cars.isEmpty) {
                cars = _applyDamagedPartsExactFilter(parsed);
              }
              isLoading = false;
              hasLoadedOnce = true;
              loadErrorMessage = null;
            });
          }

          unawaited(_autoSaveSearch());
          _debugLog('âœ… Alternative sort successful on attempt $attempt');
          return;
        } else {
          throw Exception('Server error: ${response.statusCode}');
        }
      } catch (e) {
        _debugLog('âŒ Alternative sort attempt $attempt failed: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 300));
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> _trySimpleSort(String apiSortValue) async {
    _debugLog('ðŸ”„ Simple sort attempt with: $apiSortValue');
    // Try with minimal headers and shorter timeout
    Map<String, String> filters = _buildFilters();
    String query = Uri(queryParameters: filters).query;
    final url = Uri.parse(
      '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
    );

    final response = await http
        .get(url, headers: {'Accept': 'application/json'})
        .timeout(Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final List<dynamic> listSource = decoded is List
          ? decoded
          : (decoded is Map && decoded['cars'] is List)
          ? decoded['cars'] as List
          : <dynamic>[];
      final List<Map<String, dynamic>> parsed = listSource
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList()
          .cast<Map<String, dynamic>>();

      if (mounted) {
        setState(() {
          if (parsed.isNotEmpty) {
            cars = _applyDamagedPartsExactFilter(parsed);
          } else if (cars.isEmpty) {
            cars = _applyDamagedPartsExactFilter(parsed);
          }
          isLoading = false;
          hasLoadedOnce = true;
          loadErrorMessage = null;
        });
      }
      unawaited(_autoSaveSearch());
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  Future<void> _tryConnectionReset(String apiSortValue) async {
    _debugLog('ðŸ”„ Connection reset attempt with: $apiSortValue');

    // Wait a bit longer and try with a completely fresh approach
    await Future.delayed(Duration(milliseconds: 1000));

    try {
      Map<String, String> filters = _buildFilters();
      String query = Uri(queryParameters: filters).query;
      final url = Uri.parse(
        '${getApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
      );

      // Try with a very simple request
      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<dynamic> listSource = decoded is List
            ? decoded
            : (decoded is Map && decoded['cars'] is List)
            ? decoded['cars'] as List
            : <dynamic>[];
        final List<Map<String, dynamic>> parsed = listSource
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
            .cast<Map<String, dynamic>>();

        if (mounted) {
          setState(() {
            if (parsed.isNotEmpty) {
              cars = _applyDamagedPartsExactFilter(parsed);
            } else if (cars.isEmpty) {
              cars = _applyDamagedPartsExactFilter(parsed);
            }
            isLoading = false;
            hasLoadedOnce = true;
            loadErrorMessage = null;
          });
        }

        unawaited(_autoSaveSearch());
        _debugLog('âœ… Connection reset successful');
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      _debugLog('âŒ Connection reset failed: $e');
      rethrow;
    }
  }

  Future<void> _tryWithoutSort() async {
    _debugLog('ðŸ”„ Fallback: trying without sort');
    try {
      await _fetchWithoutSort();
      // If we get here, try client-side sorting as a last resort
      await _tryClientSideSort();
    } catch (e) {
      _debugLog('âŒ Fallback also failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sorting temporarily unavailable'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _tryClientSideSort() async {
    _debugLog('ðŸ”„ Attempting client-side sort');
    final apiSortValue = _convertSortToApiValue(context, selectedSortBy);
    if (apiSortValue == null || selectedSortBy == null) return;

    List<Map<String, dynamic>> sortedCars = List.from(cars);

    try {
      switch (apiSortValue) {
        case 'price_asc':
          sortedCars.sort((a, b) {
            final priceA = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
            final priceB = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
            return priceA.compareTo(priceB);
          });
          break;
        case 'price_desc':
          sortedCars.sort((a, b) {
            final priceA = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
            final priceB = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
            return priceB.compareTo(priceA);
          });
          break;
        case 'year_desc':
          sortedCars.sort((a, b) {
            final yearA = int.tryParse(a['year']?.toString() ?? '0') ?? 0;
            final yearB = int.tryParse(b['year']?.toString() ?? '0') ?? 0;
            return yearB.compareTo(yearA);
          });
          break;
        case 'year_asc':
          sortedCars.sort((a, b) {
            final yearA = int.tryParse(a['year']?.toString() ?? '0') ?? 0;
            final yearB = int.tryParse(b['year']?.toString() ?? '0') ?? 0;
            return yearA.compareTo(yearB);
          });
          break;
        case 'mileage_asc':
          sortedCars.sort((a, b) {
            final mileageA = int.tryParse(a['mileage']?.toString() ?? '0') ?? 0;
            final mileageB = int.tryParse(b['mileage']?.toString() ?? '0') ?? 0;
            return mileageA.compareTo(mileageB);
          });
          break;
        case 'mileage_desc':
          sortedCars.sort((a, b) {
            final mileageA = int.tryParse(a['mileage']?.toString() ?? '0') ?? 0;
            final mileageB = int.tryParse(b['mileage']?.toString() ?? '0') ?? 0;
            return mileageB.compareTo(mileageA);
          });
          break;
        case 'newest':
          sortedCars.sort((a, b) {
            final dateA =
                DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                DateTime(1970);
            final dateB =
                DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                DateTime(1970);
            return dateB.compareTo(dateA);
          });
          break;
      }

      if (mounted) {
        setState(() {
          cars = sortedCars;
          isLoading = false;
          loadErrorMessage = null;
        });
      }

      _debugLog('âœ… Client-side sort successful');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sorted locally (server unavailable)'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      _debugLog('âŒ Client-side sort failed: $e');
      rethrow;
    }
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
        selectedDriveType!.isEmpty)
      return '';

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

  // Helper method to get a valid transmission value for dropdown (dropdown uses '' for Any)
  String? _getValidTransmissionValue() {
    if (selectedTransmission == null ||
        selectedTransmission == 'Any' ||
        selectedTransmission!.isEmpty)
      return '';

    final availableTypes = getAvailableTransmissions();

    // First try exact match (excluding 'Any' which is represented as '' in dropdown items)
    if (availableTypes.contains(selectedTransmission) &&
        selectedTransmission != 'Any') {
      return selectedTransmission;
    }

    // Try case-insensitive match
    final lowerSelected = selectedTransmission!.toLowerCase();
    for (final type in availableTypes) {
      if (type != 'Any' && type.toLowerCase() == lowerSelected) {
        return type;
      }
    }

    return '';
  }

  // Helper method to get a valid fuel type value for dropdown (dropdown uses '' for Any)
  String? _getValidFuelTypeValue() {
    if (selectedFuelType == null ||
        selectedFuelType == 'Any' ||
        selectedFuelType!.isEmpty)
      return '';

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
    return GestureDetector(
      onTap: () => _clearFilter(filterType),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.appTitle,
          style: TextStyle(fontSize: 18),
        ),
        titleSpacing: NavigationToolbar.kMiddleSpacing,
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              end: NavigationToolbar.kMiddleSpacing,
            ),
            child: OutlinedButton.icon(
              onPressed: () {
                // Same as leaving Home via bottom nav: keep scroll offset for return.
                _persistCurrentHomeOffsetNow();
                // Match former bottom-nav Sell: shell swap + SellEntryRouterPage
                // (draft gate / resume / start fresh), not a raw SellCarPage push.
                _switchMainTabNoAnimation(context, '/sell');
              },
              icon: Icon(Icons.add, color: Colors.white),
              label: Text(
                AppLocalizations.of(context)!.sellButton,
                style: TextStyle(color: Colors.white),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white70),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
      // Pull-to-refresh is already provided inside the main content via internal scrollables
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 0,
        onTap: (idx) {
          if (idx != 0) {
            // Persist exact offset before route replacement to avoid stale restores.
            _persistCurrentHomeOffsetNow();
          }
          switch (idx) {
            case 0:
              _scrollHomeToTopAndResetCardImages();
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              _switchMainTabNoAnimation(context, '/profile');
              break;
          }
        },
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 0.0),
              child: CustomScrollView(
                controller: _homeScrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 8.0,
                      ),
                      child: Card(
                        elevation: 12,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        color: Color.alphaBlend(
                          Colors.white.withOpacity(0.06),
                          AppThemes.darkHomeShellBackground,
                        ),
                        surfaceTintColor: Colors.transparent,
                        shadowColor: Colors.black54,
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Builder(
                                builder: (context) {
                                  final loc = AppLocalizations.of(context)!;
                                  const allKey = '__all_cities__';
                                  final isAll = (selectedCity == null ||
                                      selectedCity!.trim().isEmpty ||
                                      selectedCity == 'Any');
                                  final display = isAll
                                      ? loc.allCities
                                      : (_translateValueGlobal(
                                              context, selectedCity) ??
                                          selectedCity!);

                                  Widget cityIconLabel() {
                                    return FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: Row(
                                        // Keep icon+text visually consistent in RTL/LTR.
                                        textDirection: ui.TextDirection.ltr,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.location_city,
                                            size: 16,
                                            color: Color(0xFFFF6B00),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            display,
                                            maxLines: 1,
                                            softWrap: false,
                                            overflow: TextOverflow.visible,
                                            style: GoogleFonts.orbitron(
                                              fontSize: 14,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  return LayoutBuilder(
                                    builder: (context, c) {
                                      final maxW = c.maxWidth;
                                      final cityMaxW = (maxW * 0.46)
                                          .clamp(140.0, 240.0);
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () =>
                                                  _showSearchDialog(context),
                                              child: Align(
                                                // RTL: pins to the right; LTR: pins to the left.
                                                alignment: AlignmentDirectional.centerStart,
                                                child: Row(
                                                  // Keep icon+text visually consistent in RTL/LTR.
                                                  textDirection: ui.TextDirection.ltr,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.search,
                                                      color: Color(0xFFFF6B00),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Flexible(
                                                      child: Text(
                                                        loc.homeSearchHeading,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: GoogleFonts.orbitron(
                                                          color: const Color(
                                                            0xFFFF6B00,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 20,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: cityMaxW,
                                            ),
                                            child: SizedBox(
                                              height: 34,
                                              child: Align(
                                                alignment: AlignmentDirectional
                                                    .centerEnd,
                                                child: PopupMenuButton<String>(
                                                  tooltip: '',
                                                  position:
                                                      PopupMenuPosition.under,
                                                  offset: const Offset(0, 6),
                                                  color: Colors.grey[900]
                                                      ?.withOpacity(0.98),
                                                  splashRadius: 18,
                                                  onSelected: (value) {
                                                    setState(() {
                                                      selectedCity =
                                                          value == allKey
                                                              ? null
                                                              : value;
                                                    });
                                                    onFilterChanged();
                                                  },
                                                  itemBuilder: (context) => [
                                                    PopupMenuItem<String>(
                                                      value: allKey,
                                                      child: Text(
                                                        loc.allCities,
                                                        style: GoogleFonts
                                                            .orbitron(
                                                          fontSize: 14,
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    ...cities
                                                        .where(
                                                          (x) => x != 'Any',
                                                        )
                                                        .map(
                                                          (c) =>
                                                              PopupMenuItem<
                                                                  String>(
                                                            value: c,
                                                            child: Text(
                                                              (_translateValueGlobal(
                                                                      context, c) ??
                                                                  c),
                                                              style: GoogleFonts
                                                                  .orbitron(
                                                                fontSize: 14,
                                                                color:
                                                                    Colors.white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                  ],
                                                  child: Padding(
                                                    padding: const EdgeInsetsDirectional
                                                        .only(
                                                      start: 0,
                                                      top: 6,
                                                      bottom: 6,
                                                      end: 8,
                                                    ),
                                                    child: cityIconLabel(),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                              SizedBox(height: 16),
                              Row(
                                children: [
                                  // Brand selector styled like a form field for symmetry
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final brand = await showDialog<String>(
                                          context: context,
                                          builder: (context) {
                                            return Dialog(
                                              backgroundColor: Colors.grey[900]
                                                  ?.withOpacity(0.98),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Container(
                                                width: 400,
                                                padding: EdgeInsets.all(20),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.selectBrand,
                                                          style:
                                                              GoogleFonts.orbitron(
                                                                color: Color(
                                                                  0xFFFF6B00,
                                                                ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 20,
                                                              ),
                                                        ),
                                                        IconButton(
                                                          icon: Icon(
                                                            Icons.close,
                                                            color: Colors.white,
                                                          ),
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 10),
                                                    SizedBox(
                                                      height: 380,
                                                      child: GridView.builder(
                                                        shrinkWrap: true,
                                                        physics:
                                                            BouncingScrollPhysics(),
                                                        gridDelegate:
                                                            SliverGridDelegateWithFixedCrossAxisCount(
                                                              crossAxisCount: 4,
                                                              childAspectRatio:
                                                                  0.85,
                                                              crossAxisSpacing:
                                                                  10,
                                                              mainAxisSpacing:
                                                                  10,
                                                            ),
                                                        itemCount:
                                                            homeBrands.length,
                                                        itemBuilder: (context, index) {
                                                          final brand =
                                                              homeBrands[index];
                                                          final logoFile =
                                                              brandLogoFilenames[brand] ??
                                                              brand
                                                                  .toLowerCase()
                                                                  .replaceAll(
                                                                    ' ',
                                                                    '-',
                                                                  )
                                                                  .replaceAll(
                                                                    'Ã©',
                                                                    'e',
                                                                  )
                                                                  .replaceAll(
                                                                    'Ã¶',
                                                                    'o',
                                                                  );
                                                          final logoUrl =
                                                              '${getApiBase()}/static/images/brands/$logoFile.png';
                                                          return InkWell(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                            onTap: () =>
                                                                Navigator.pop(
                                                                  context,
                                                                  brand,
                                                                ),
                                                            child: Container(
                                                              decoration: BoxDecoration(
                                                                color: Colors
                                                                    .black
                                                                    .withOpacity(
                                                                      0.15,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      12,
                                                                    ),
                                                                border: Border.all(
                                                                  color: Colors
                                                                      .white24,
                                                                ),
                                                              ),
                                                              padding:
                                                                  EdgeInsets.all(
                                                                    6,
                                                                  ),
                                                              child: Column(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Container(
                                                                    width: 32,
                                                                    height: 32,
                                                                    padding:
                                                                        EdgeInsets.all(
                                                                          4,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors
                                                                          .white,
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            8,
                                                                          ),
                                                                    ),
                                                                    child: CachedNetworkImage(
                                                                      imageUrl:
                                                                          logoUrl,
                                                                      placeholder:
                                                                          (
                                                                            context,
                                                                            url,
                                                                          ) => SizedBox(
                                                                            width:
                                                                                24,
                                                                            height:
                                                                                24,
                                                                            child: CircularProgressIndicator(
                                                                              strokeWidth: 2,
                                                                            ),
                                                                          ),
                                                                      errorWidget:
                                                                          (
                                                                            context,
                                                                            url,
                                                                            error,
                                                                          ) => Icon(
                                                                            Icons.directions_car,
                                                                            size:
                                                                                22,
                                                                            color: Color(
                                                                              0xFFFF6B00,
                                                                            ),
                                                                          ),
                                                                      fit: BoxFit
                                                                          .contain,
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    height: 4,
                                                                  ),
                                                                  Text(
                                                                    CarNameTranslations.getLocalizedBrand(
                                                                          context,
                                                                          brand,
                                                                        ).isNotEmpty
                                                                        ? CarNameTranslations.getLocalizedBrand(
                                                                            context,
                                                                            brand,
                                                                          )
                                                                        : brand,
                                                                    style: GoogleFonts.orbitron(
                                                                      fontSize:
                                                                          10,
                                                                      color: Colors
                                                                          .white,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                    ),
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    maxLines: 1,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                        if (brand != null) {
                                          setState(() {
                                            selectedBrand = brand;
                                            selectedModel = null;
                                            selectedTrim = null;
                                            clearFiltersOnVehicleChange();
                                          });
                                          onFilterChanged();
                                        }
                                      },
                                      child: InputDecorator(
                                        decoration: InputDecoration(
                                          labelText: AppLocalizations.of(
                                            context,
                                          )!.brandLabel,
                                          labelStyle: GoogleFonts.orbitron(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          filled: true,
                                          fillColor: Colors.black.withOpacity(
                                            0.15,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 12,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            if (selectedBrand != null &&
                                                selectedBrand!.isNotEmpty)
                                              Container(
                                                width: 24,
                                                height: 24,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                padding: EdgeInsets.all(2),
                                                child: CachedNetworkImage(
                                                  imageUrl:
                                                      '${getApiBase()}/static/images/brands/${brandLogoFilenames[selectedBrand] ?? selectedBrand!.toLowerCase().replaceAll(' ', '-')}.png',
                                                  placeholder: (context, url) =>
                                                      SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      ),
                                                  errorWidget:
                                                      (
                                                        context,
                                                        url,
                                                        error,
                                                      ) => Icon(
                                                        Icons.directions_car,
                                                        size: 16,
                                                        color: Color(
                                                          0xFFFF6B00,
                                                        ),
                                                      ),
                                                  fit: BoxFit.contain,
                                                ),
                                              )
                                            else
                                              Icon(
                                                Icons.directions_car,
                                                size: 20,
                                                color: Color(0xFFFF6B00),
                                              ),
                                            SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                selectedBrand == null ||
                                                        selectedBrand!.isEmpty
                                                    ? AppLocalizations.of(
                                                        context,
                                                      )!.any
                                                    : (CarNameTranslations.getLocalizedBrand(
                                                            context,
                                                            selectedBrand,
                                                          ).isNotEmpty
                                                          ? CarNameTranslations.getLocalizedBrand(
                                                              context,
                                                              selectedBrand,
                                                            )
                                                          : selectedBrand!),
                                                style: GoogleFonts.orbitron(
                                                  fontSize: 14,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                softWrap: false,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  // Model Dropdown
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isDense: true,
                                      isExpanded: true,
                                      style: GoogleFonts.orbitron(
                                        fontSize: 14,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      initialValue:
                                          selectedModel != null &&
                                              (selectedModel!.isEmpty ||
                                                  (selectedBrand != null &&
                                                      models[selectedBrand] !=
                                                          null &&
                                                      models[selectedBrand]!
                                                          .contains(
                                                            selectedModel,
                                                          )))
                                          ? selectedModel
                                          : null,
                                      decoration: InputDecoration(
                                        labelText: AppLocalizations.of(
                                          context,
                                        )!.modelLabel,
                                        labelStyle: GoogleFonts.orbitron(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        filled: true,
                                        fillColor: Colors.black.withOpacity(
                                          0.15,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 6,
                                        ),
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                          value: '',
                                          child: Text(
                                            AppLocalizations.of(context)!.any,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.orbitron(
                                              color: Colors.grey,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (selectedBrand != null &&
                                            models[selectedBrand!] != null)
                                          ...models[selectedBrand!]!.map(
                                            (m) => DropdownMenuItem(
                                              value: m,
                                              child: Text(
                                                CarNameTranslations.getLocalizedModel(
                                                      context,
                                                      selectedBrand,
                                                      m,
                                                    ).isNotEmpty
                                                    ? CarNameTranslations.getLocalizedModel(
                                                        context,
                                                        selectedBrand,
                                                        m,
                                                      )
                                                    : m,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.orbitron(
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                      onChanged: (value) {
                                        setState(() {
                                          selectedModel = value == ''
                                              ? null
                                              : value;
                                          selectedTrim = null;
                                          clearFiltersOnVehicleChange();
                                        });
                                        onFilterChanged();
                                      },
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  // Trim Dropdown
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isDense: true,
                                      isExpanded: true,
                                      style: GoogleFonts.orbitron(
                                        fontSize: 14,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      initialValue:
                                          selectedTrim != null &&
                                              (selectedTrim!.isEmpty ||
                                                  (selectedBrand != null &&
                                                      selectedModel != null &&
                                                      trimsByBrandModel[selectedBrand] !=
                                                          null &&
                                                      trimsByBrandModel[selectedBrand]![selectedModel] !=
                                                          null &&
                                                      trimsByBrandModel[selectedBrand]![selectedModel]!
                                                          .contains(selectedTrim)))
                                          ? selectedTrim
                                          : null,
                                      decoration: InputDecoration(
                                        labelText:
                                            AppLocalizations.of(context)!.trimLabel,
                                        labelStyle: GoogleFonts.orbitron(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        filled: true,
                                        fillColor: Colors.black.withOpacity(0.15),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 6,
                                        ),
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                          value: '',
                                          child: Text(
                                            AppLocalizations.of(context)!.any,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.orbitron(
                                              color: Colors.grey,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (selectedBrand != null &&
                                            selectedModel != null &&
                                            trimsByBrandModel[selectedBrand] != null &&
                                            trimsByBrandModel[selectedBrand]![selectedModel] !=
                                                null)
                                          ...trimsByBrandModel[selectedBrand]![selectedModel]!
                                              .map(
                                                (t) => DropdownMenuItem(
                                                  value: t,
                                                  child: Text(
                                                    t,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.orbitron(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                      ],
                                      onChanged: (value) {
                                        setState(() {
                                          selectedTrim = value == '' ? null : value;
                                          clearFiltersOnVehicleChange();
                                        });
                                        onFilterChanged();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              // Active Filters Display
                              if (_hasActiveFilters())
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.filter_list,
                                                color: Color(0xFFFF6B00),
                                                size: 16,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                AppLocalizations.of(
                                                  context,
                                                )!.activeFilters,
                                                style: GoogleFonts.orbitron(
                                                  fontSize: 12,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              GestureDetector(
                                                onTap: _clearAllFilters,
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red
                                                        .withOpacity(0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.red,
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.clear,
                                                        color: Colors.red,
                                                        size: 12,
                                                      ),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        AppLocalizations.of(
                                                          context,
                                                        )!.clearFilters,
                                                        style:
                                                            GoogleFonts.orbitron(
                                                              fontSize: 10,
                                                              color: Colors.red,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              GestureDetector(
                                                onTap: _saveCurrentSearch,
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Color(
                                                      0xFFFF6B00,
                                                    ).withOpacity(0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: Color(0xFFFF6B00),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .bookmark_add_outlined,
                                                        color: Color(
                                                          0xFFFF6B00,
                                                        ),
                                                        size: 12,
                                                      ),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        AppLocalizations.of(
                                                          context,
                                                        )!.save,
                                                        style:
                                                            GoogleFonts.orbitron(
                                                              fontSize: 10,
                                                              color: Color(
                                                                0xFFFF6B00,
                                                              ),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          ..._buildActiveFilterChips(),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                height: 36,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFFFF6B00),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 0,
                                    ),
                                    minimumSize: Size(0, 32),
                                  ),
                                  icon: Icon(Icons.tune, size: 18),
                                  label: Text(
                                    AppLocalizations.of(context)!.moreFilters,
                                    style: GoogleFonts.orbitron(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () async {
                                    // Sync manual-entry controllers to current selections
                                    // (do this once when opening the dialog, not during typing).
                                    _minPriceController.text =
                                        selectedMinPrice ?? '';
                                    _maxPriceController.text =
                                        selectedMaxPrice ?? '';
                                    _minYearController.text =
                                        selectedMinYear ?? '';
                                    _maxYearController.text =
                                        selectedMaxYear ?? '';
                                    _minMileageController.text =
                                        selectedMinMileage ?? '';
                                    _maxMileageController.text =
                                        selectedMaxMileage ?? '';
                                    _engineSizeController.text =
                                        selectedEngineSize ?? '';
                                    final moreFiltersSnapshot =
                                        _moreFiltersDialogSnapshot();
                                    await showDialog(
                                      context: context,
                                      builder: (context) {
                                        return StatefulBuilder(
                                          builder: (context, setStateDialog) {
                                            final isLightMoreFilters =
                                                Theme.of(context).brightness ==
                                                Brightness.light;
                                            final moreFiltersBg =
                                                isLightMoreFilters
                                                ? Colors.white
                                                : (Colors.grey[900]
                                                          ?.withOpacity(0.98) ??
                                                      Colors.grey.shade900);
                                            final moreFiltersOnSurface =
                                                isLightMoreFilters
                                                ? const Color(0xFF1A1A1A)
                                                : Colors.white;
                                            final moreFiltersMuted =
                                                isLightMoreFilters
                                                ? const Color(0xFF757575)
                                                : Colors.white70;
                                            final moreFiltersAnyOrange =
                                                const Color(0xFFFF6B00);
                                            final moreFiltersFieldFill =
                                                isLightMoreFilters
                                                ? Colors.grey.shade200
                                                : Colors.black.withOpacity(0.2);
                                            const double moreFiltersFieldGap =
                                                18;
                                            return AlertDialog(
                                              backgroundColor: moreFiltersBg,
                                              surfaceTintColor:
                                                  Colors.transparent,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              title: Text(
                                                AppLocalizations.of(
                                                  context,
                                                )!.moreFilters,
                                                style: GoogleFonts.orbitron(
                                                  color: Color(0xFFFF6B00),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              content: SingleChildScrollView(
                                                child: KeyedSubtree(
                                                  key: ValueKey<int>(
                                                    _moreFiltersDialogFieldGeneration,
                                                  ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      // Price Filter
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.priceRange,
                                                          style: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 18,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(height: 12),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                isPriceDropdown
                                                                ? Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  isExpanded: true,
                                                                                  initialValue:
                                                                                      selectedMinPrice ??
                                                                                      '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.any,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...[
                                                                                          for (
                                                                                            int p = 500;
                                                                                            p <=
                                                                                                300000;
                                                                                            p += 500
                                                                                          )
                                                                                            p,
                                                                                          for (
                                                                                            int p = 310000;
                                                                                            p <=
                                                                                                2000000;
                                                                                            p += 10000
                                                                                          )
                                                                                            p,
                                                                                        ]
                                                                                        .where(
                                                                                          (
                                                                                            p,
                                                                                          ) {
                                                                                            if (selectedMaxPrice ==
                                                                                                    null ||
                                                                                                selectedMaxPrice!.isEmpty) {
                                                                                              return true;
                                                                                            }
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxPrice!,
                                                                                            );
                                                                                            return max ==
                                                                                                    null
                                                                                                ? true
                                                                                                : p <=
                                                                                                      max;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            p,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: p.toString(),
                                                                                            child: Text(
                                                                                              _formatCurrencyGlobal(
                                                                                                context,
                                                                                                p,
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMinPrice =
                                                                                                value?.isEmpty ==
                                                                                                    true
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinPrice ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxPrice ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                min >
                                                                                                    max) {
                                                                                              selectedMaxPrice = selectedMinPrice;
                                                                                            }
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  isExpanded: true,
                                                                                  initialValue:
                                                                                      selectedMaxPrice ??
                                                                                      '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.any,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...[
                                                                                          for (
                                                                                            int p = 500;
                                                                                            p <=
                                                                                                300000;
                                                                                            p += 500
                                                                                          )
                                                                                            p,
                                                                                          for (
                                                                                            int p = 310000;
                                                                                            p <=
                                                                                                2000000;
                                                                                            p += 10000
                                                                                          )
                                                                                            p,
                                                                                        ]
                                                                                        .where(
                                                                                          (
                                                                                            p,
                                                                                          ) {
                                                                                            if (selectedMinPrice ==
                                                                                                    null ||
                                                                                                selectedMinPrice!.isEmpty) {
                                                                                              return true;
                                                                                            }
                                                                                            final min = int.tryParse(
                                                                                              selectedMinPrice!,
                                                                                            );
                                                                                            return min ==
                                                                                                    null
                                                                                                ? true
                                                                                                : p >=
                                                                                                      min;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            p,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: p.toString(),
                                                                                            child: Text(
                                                                                              _formatCurrencyGlobal(
                                                                                                context,
                                                                                                p,
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMaxPrice =
                                                                                                value?.isEmpty ==
                                                                                                    true
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinPrice ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxPrice ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                max <
                                                                                                    min) {
                                                                                              selectedMinPrice = selectedMaxPrice;
                                                                                            }
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  )
                                                                : Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _minPriceController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMinPrice = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinPrice ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxPrice ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            min >
                                                                                                max) {
                                                                                          selectedMaxPrice = selectedMinPrice;
                                                                                          _maxPriceController.text =
                                                                                              selectedMaxPrice ??
                                                                                              '';
                                                                                        }
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _maxPriceController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMaxPrice = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinPrice ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxPrice ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            max <
                                                                                                min) {
                                                                                          selectedMinPrice = selectedMaxPrice;
                                                                                          _minPriceController.text =
                                                                                              selectedMinPrice ??
                                                                                              '';
                                                                                        }
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  ),
                                                          ),
                                                          SizedBox(width: 8),
                                                          IconButton(
                                                            onPressed: () => setStateDialog(() {
                                                              if (isPriceDropdown) {
                                                                _minPriceController
                                                                        .text =
                                                                    selectedMinPrice ??
                                                                    '';
                                                                _maxPriceController
                                                                        .text =
                                                                    selectedMaxPrice ??
                                                                    '';
                                                              }
                                                              isPriceDropdown =
                                                                  !isPriceDropdown;
                                                            }),
                                                            icon: Icon(
                                                              isPriceDropdown
                                                                  ? Icons.edit
                                                                  : Icons.list,
                                                              color: Color(
                                                                0xFFFF6B00,
                                                              ),
                                                            ),
                                                            style: IconButton.styleFrom(
                                                              backgroundColor:
                                                                  moreFiltersFieldFill,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      // Year Filter
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.yearRange,
                                                          style: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 18,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(height: 12),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                isYearDropdown
                                                                ? Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  initialValue:
                                                                                      selectedMinYear ??
                                                                                      '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.any,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...List.generate(
                                                                                          127,
                                                                                          (
                                                                                            i,
                                                                                          ) =>
                                                                                              (1900 +
                                                                                                      i)
                                                                                                  .toString(),
                                                                                        ).reversed
                                                                                        .where(
                                                                                          (
                                                                                            y,
                                                                                          ) {
                                                                                            if (selectedMaxYear ==
                                                                                                    null ||
                                                                                                selectedMaxYear!.isEmpty) {
                                                                                              return true;
                                                                                            }
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxYear!,
                                                                                            );
                                                                                            final val = int.tryParse(
                                                                                              y,
                                                                                            );
                                                                                            return max ==
                                                                                                        null ||
                                                                                                    val ==
                                                                                                        null
                                                                                                ? true
                                                                                                : val <=
                                                                                                      max;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            y,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: y,
                                                                                            child: Text(
                                                                                              _localizeDigitsGlobal(
                                                                                                context,
                                                                                                y,
                                                                                              ),
                                                                                              style: TextStyle(
                                                                                                color: moreFiltersOnSurface,
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMinYear =
                                                                                                value?.isEmpty ==
                                                                                                    true
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinYear ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxYear ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                min >
                                                                                                    max) {
                                                                                              selectedMaxYear = selectedMinYear;
                                                                                            }
                                                                                            _afterHomeYearBoundsChanged();
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  initialValue:
                                                                                      selectedMaxYear ??
                                                                                      '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.any,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...List.generate(
                                                                                          127,
                                                                                          (
                                                                                            i,
                                                                                          ) =>
                                                                                              (1900 +
                                                                                                      i)
                                                                                                  .toString(),
                                                                                        ).reversed
                                                                                        .where(
                                                                                          (
                                                                                            y,
                                                                                          ) {
                                                                                            if (selectedMinYear ==
                                                                                                    null ||
                                                                                                selectedMinYear!.isEmpty) {
                                                                                              return true;
                                                                                            }
                                                                                            final min = int.tryParse(
                                                                                              selectedMinYear!,
                                                                                            );
                                                                                            final val = int.tryParse(
                                                                                              y,
                                                                                            );
                                                                                            return min ==
                                                                                                        null ||
                                                                                                    val ==
                                                                                                        null
                                                                                                ? true
                                                                                                : val >=
                                                                                                      min;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            y,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: y,
                                                                                            child: Text(
                                                                                              _localizeDigitsGlobal(
                                                                                                context,
                                                                                                y,
                                                                                              ),
                                                                                              style: TextStyle(
                                                                                                color: moreFiltersOnSurface,
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMaxYear =
                                                                                                value?.isEmpty ==
                                                                                                    true
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinYear ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxYear ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                max <
                                                                                                    min) {
                                                                                              selectedMinYear = selectedMaxYear;
                                                                                            }
                                                                                            _afterHomeYearBoundsChanged();
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  )
                                                                : Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _minYearController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMinYear = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinYear ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxYear ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            min >
                                                                                                max) {
                                                                                          selectedMaxYear = selectedMinYear;
                                                                                          _maxYearController.text =
                                                                                              selectedMaxYear ??
                                                                                              '';
                                                                                        }
                                                                                        _afterHomeYearBoundsChanged();
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _maxYearController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMaxYear = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinYear ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxYear ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            max <
                                                                                                min) {
                                                                                          selectedMinYear = selectedMaxYear;
                                                                                          _minYearController.text =
                                                                                              selectedMinYear ??
                                                                                              '';
                                                                                        }
                                                                                        _afterHomeYearBoundsChanged();
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  ),
                                                          ),
                                                          SizedBox(width: 8),
                                                          IconButton(
                                                            onPressed: () => setStateDialog(() {
                                                              if (isYearDropdown) {
                                                                _minYearController
                                                                        .text =
                                                                    selectedMinYear ??
                                                                    '';
                                                                _maxYearController
                                                                        .text =
                                                                    selectedMaxYear ??
                                                                    '';
                                                              }
                                                              isYearDropdown =
                                                                  !isYearDropdown;
                                                            }),
                                                            icon: Icon(
                                                              isYearDropdown
                                                                  ? Icons.edit
                                                                  : Icons.list,
                                                              color: Color(
                                                                0xFFFF6B00,
                                                              ),
                                                            ),
                                                            style: IconButton.styleFrom(
                                                              backgroundColor:
                                                                  moreFiltersFieldFill,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      // Mileage Filter
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.mileageRangeLabel,
                                                          style: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 18,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(height: 12),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                isMileageDropdown
                                                                ? Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  initialValue:
                                                                                      (selectedMinMileage !=
                                                                                              null &&
                                                                                          selectedMinMileage!.isNotEmpty)
                                                                                      ? selectedMinMileage
                                                                                      : '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.minMileage,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...[
                                                                                          for (
                                                                                            int m = 0;
                                                                                            m <=
                                                                                                100000;
                                                                                            m += 1000
                                                                                          )
                                                                                            m,
                                                                                          for (
                                                                                            int m = 105000;
                                                                                            m <=
                                                                                                300000;
                                                                                            m += 5000
                                                                                          )
                                                                                            m,
                                                                                        ]
                                                                                        .where(
                                                                                          (
                                                                                            m,
                                                                                          ) {
                                                                                            if (selectedMaxMileage ==
                                                                                                    null ||
                                                                                                selectedMaxMileage!.isEmpty) {
                                                                                              return true;
                                                                                            }
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxMileage!,
                                                                                            );
                                                                                            return max ==
                                                                                                    null
                                                                                                ? true
                                                                                                : m <=
                                                                                                      max;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            m,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: m.toString(),
                                                                                            child: Text(
                                                                                              _localizeDigitsGlobal(
                                                                                                context,
                                                                                                m.toString().replaceAllMapped(
                                                                                                  RegExp(
                                                                                                    r'(\d{1,3})(?=(\d{3})+(?!\d))',
                                                                                                  ),
                                                                                                  (
                                                                                                    mm,
                                                                                                  ) => '${mm[1]},',
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMinMileage =
                                                                                                (value ==
                                                                                                        null ||
                                                                                                    value.isEmpty)
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinMileage ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxMileage ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                min >
                                                                                                    max) {
                                                                                              selectedMaxMileage = selectedMinMileage;
                                                                                            }
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  initialValue:
                                                                                      (selectedMaxMileage !=
                                                                                              null &&
                                                                                          selectedMaxMileage!.isNotEmpty)
                                                                                      ? selectedMaxMileage
                                                                                      : '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.maxMileage,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...[
                                                                                          for (
                                                                                            int m = 0;
                                                                                            m <=
                                                                                                100000;
                                                                                            m += 1000
                                                                                          )
                                                                                            m,
                                                                                          for (
                                                                                            int m = 105000;
                                                                                            m <=
                                                                                                300000;
                                                                                            m += 5000
                                                                                          )
                                                                                            m,
                                                                                        ]
                                                                                        .where(
                                                                                          (
                                                                                            m,
                                                                                          ) {
                                                                                            if (selectedMinMileage ==
                                                                                                    null ||
                                                                                                selectedMinMileage!.isNotEmpty ==
                                                                                                    false) {
                                                                                              return true;
                                                                                            }
                                                                                            final min = int.tryParse(
                                                                                              selectedMinMileage!,
                                                                                            );
                                                                                            return min ==
                                                                                                    null
                                                                                                ? true
                                                                                                : m >=
                                                                                                      min;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            m,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: m.toString(),
                                                                                            child: Text(
                                                                                              _localizeDigitsGlobal(
                                                                                                context,
                                                                                                m.toString().replaceAllMapped(
                                                                                                  RegExp(
                                                                                                    r'(\d{1,3})(?=(\d{3})+(?!\d))',
                                                                                                  ),
                                                                                                  (
                                                                                                    mm,
                                                                                                  ) => '${mm[1]},',
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMaxMileage =
                                                                                                (value ==
                                                                                                        null ||
                                                                                                    value.isEmpty)
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinMileage ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxMileage ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                max <
                                                                                                    min) {
                                                                                              selectedMinMileage = selectedMaxMileage;
                                                                                            }
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  )
                                                                : Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _minMileageController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMinMileage = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinMileage ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxMileage ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            min >
                                                                                                max) {
                                                                                          selectedMaxMileage = selectedMinMileage;
                                                                                          _maxMileageController.text =
                                                                                              selectedMaxMileage ??
                                                                                              '';
                                                                                        }
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _maxMileageController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMaxMileage = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinMileage ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxMileage ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            max <
                                                                                                min) {
                                                                                          selectedMinMileage = selectedMaxMileage;
                                                                                          _minMileageController.text =
                                                                                              selectedMinMileage ??
                                                                                              '';
                                                                                        }
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  ),
                                                          ),
                                                          SizedBox(width: 8),
                                                          IconButton(
                                                            onPressed: () => setStateDialog(() {
                                                              if (isMileageDropdown) {
                                                                _minMileageController
                                                                        .text =
                                                                    selectedMinMileage ??
                                                                    '';
                                                                _maxMileageController
                                                                        .text =
                                                                    selectedMaxMileage ??
                                                                    '';
                                                              }
                                                              isMileageDropdown =
                                                                  !isMileageDropdown;
                                                            }),
                                                            icon: Icon(
                                                              isMileageDropdown
                                                                  ? Icons.edit
                                                                  : Icons.list,
                                                              color: Color(
                                                                0xFFFF6B00,
                                                              ),
                                                            ),
                                                            style: IconButton.styleFrom(
                                                              backgroundColor:
                                                                  moreFiltersFieldFill,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(context)!.titleStatus,
                                                          style: TextStyle(
                                                            color: moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: [
                                                            for (final entry in <String, String>{
                                                              '': AppLocalizations.of(context)!.any,
                                                              'clean': AppLocalizations.of(context)!.value_title_clean,
                                                              'damaged': AppLocalizations.of(context)!.value_title_damaged,
                                                            }.entries)
                                                              ChoiceChip(
                                                                label: Text(entry.value),
                                                                selected: (selectedTitleStatus ?? '') == entry.key,
                                                                selectedColor: entry.key == ''
                                                                    ? moreFiltersAnyOrange
                                                                    : Theme.of(context).colorScheme.primary,
                                                                backgroundColor: moreFiltersFieldFill,
                                                                labelStyle: TextStyle(
                                                                  color: (selectedTitleStatus ?? '') == entry.key
                                                                      ? Colors.white
                                                                      : moreFiltersOnSurface,
                                                                  fontWeight: (selectedTitleStatus ?? '') == entry.key
                                                                      ? FontWeight.bold
                                                                      : FontWeight.normal,
                                                                ),
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius: BorderRadius.circular(12),
                                                                  side: BorderSide(
                                                                    color: (selectedTitleStatus ?? '') == entry.key
                                                                        ? Colors.transparent
                                                                        : moreFiltersOnSurface.withOpacity(0.2),
                                                                  ),
                                                                ),
                                                                onSelected: (_) {
                                                                  setState(() {
                                                                    selectedTitleStatus = entry.key == '' ? null : entry.key;
                                                                    if (selectedTitleStatus != 'damaged') {
                                                                      selectedDamagedParts = null;
                                                                    }
                                                                  });
                                                                  setStateDialog(() {});
                                                                },
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                      if (selectedTitleStatus ==
                                                          'damaged')
                                                        ...[
                                                          SizedBox(
                                                            height:
                                                                moreFiltersFieldGap,
                                                          ),
                                                          DropdownButtonFormField<
                                                            String
                                                          >(
                                                            initialValue:
                                                                selectedDamagedParts ??
                                                                '',
                                                            decoration: InputDecoration(
                                                              labelText:
                                                                  AppLocalizations.of(
                                                                    context,
                                                                  )!.damagedParts,
                                                              filled: true,
                                                              fillColor:
                                                                  moreFiltersFieldFill,
                                                              labelStyle: TextStyle(
                                                                color:
                                                                    moreFiltersOnSurface,
                                                                fontSize: 18,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                              border: OutlineInputBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      12,
                                                                    ),
                                                              ),
                                                            ),
                                                            items: [
                                                              DropdownMenuItem(
                                                                value: '',
                                                                child: Text(
                                                                  AppLocalizations.of(
                                                                    context,
                                                                  )!.any,
                                                                  style: TextStyle(
                                                                    color:
                                                                        moreFiltersAnyOrange,
                                                                  ),
                                                                ),
                                                              ),
                                                              ...List.generate(
                                                                15,
                                                                (i) => (i + 1)
                                                                    .toString(),
                                                              ).map(
                                                                (
                                                                  p,
                                                                ) => DropdownMenuItem(
                                                                  value: p,
                                                                  child: Text(
                                                                    '${_localizeDigitsGlobal(context, p)} ${AppLocalizations.of(context)!.damagedParts}',
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                            onChanged: (value) {
                                                              setState(
                                                                () =>
                                                                    selectedDamagedParts =
                                                                        value ==
                                                                            ''
                                                                        ? null
                                                                        : value,
                                                              );
                                                              setStateDialog(
                                                                () {},
                                                              );
                                                            },
                                                          ),
                                                        ],
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(context)!.conditionLabel,
                                                          style: TextStyle(
                                                            color: moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: conditions.map((c) {
                                                            final isSelected = (selectedCondition ?? 'Any') == c;
                                                            return ChoiceChip(
                                                              label: Text(
                                                                _translateValueGlobal(context, c) ?? c,
                                                              ),
                                                              selected: isSelected,
                                                              selectedColor: c == 'Any'
                                                                  ? moreFiltersAnyOrange
                                                                  : Theme.of(context).colorScheme.primary,
                                                              backgroundColor: moreFiltersFieldFill,
                                                              labelStyle: TextStyle(
                                                                color: isSelected
                                                                    ? Colors.white
                                                                    : moreFiltersOnSurface,
                                                                fontWeight: isSelected
                                                                    ? FontWeight.bold
                                                                    : FontWeight.normal,
                                                              ),
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(12),
                                                                side: BorderSide(
                                                                  color: isSelected
                                                                      ? Colors.transparent
                                                                      : moreFiltersOnSurface.withOpacity(0.2),
                                                                ),
                                                              ),
                                                              onSelected: (_) {
                                                                setState(() {
                                                                  selectedCondition = c == 'Any' ? 'Any' : c;
                                                                });
                                                                setStateDialog(() {});
                                                              },
                                                            );
                                                          }).toList(),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(context)!.transmissionLabel,
                                                          style: TextStyle(
                                                            color: moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: [
                                                            for (final t in ['Any', ...getAvailableTransmissions().where((t) => t != 'Any')])
                                                              ChoiceChip(
                                                                label: Text(
                                                                  t == 'Any'
                                                                      ? AppLocalizations.of(context)!.any
                                                                      : _translateValueGlobal(context, t) ?? t,
                                                                ),
                                                                selected: (selectedTransmission ?? 'Any') == t,
                                                                selectedColor: t == 'Any'
                                                                    ? moreFiltersAnyOrange
                                                                    : Theme.of(context).colorScheme.primary,
                                                                backgroundColor: moreFiltersFieldFill,
                                                                labelStyle: TextStyle(
                                                                  color: (selectedTransmission ?? 'Any') == t
                                                                      ? Colors.white
                                                                      : moreFiltersOnSurface,
                                                                  fontWeight: (selectedTransmission ?? 'Any') == t
                                                                      ? FontWeight.bold
                                                                      : FontWeight.normal,
                                                                ),
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius: BorderRadius.circular(12),
                                                                  side: BorderSide(
                                                                    color: (selectedTransmission ?? 'Any') == t
                                                                        ? Colors.transparent
                                                                        : moreFiltersOnSurface.withOpacity(0.2),
                                                                  ),
                                                                ),
                                                                onSelected: (_) {
                                                                  setState(() {
                                                                    selectedTransmission = t == 'Any' ? 'Any' : t;
                                                                  });
                                                                  setStateDialog(() {});
                                                                },
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            _getValidFuelTypeValue(),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.fuelTypeLabel,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...getAvailableFuelTypes()
                                                              .where(
                                                                (f) =>
                                                                    f != 'Any',
                                                              )
                                                              .map(
                                                                (
                                                                  f,
                                                                ) => DropdownMenuItem(
                                                                  value: f,
                                                                  child: Text(
                                                                    _translateValueGlobal(
                                                                          context,
                                                                          f,
                                                                        ) ??
                                                                        f,
                                                                  ),
                                                                ),
                                                              ),
                                                        ],
                                                        onChanged: (value) =>
                                                            setState(
                                                              () =>
                                                                  selectedFuelType =
                                                                      value ==
                                                                          ''
                                                                      ? 'Any'
                                                                      : value,
                                                            ),
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      TextFormField(
                                                        key: ValueKey(
                                                          'bodyType_${selectedBodyType ?? 'any'}',
                                                        ),
                                                        readOnly: true,
                                                        style: TextStyle(
                                                          color:
                                                              (selectedBodyType !=
                                                                      null &&
                                                                  selectedBodyType!
                                                                      .isNotEmpty)
                                                              ? moreFiltersOnSurface
                                                              : moreFiltersAnyOrange,
                                                        ),
                                                        initialValue:
                                                            (selectedBodyType ??
                                                            AppLocalizations.of(
                                                              context,
                                                            )!.any),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.bodyTypeLabel,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          suffixIcon: Container(
                                                            margin:
                                                                EdgeInsets.all(
                                                                  8,
                                                                ),
                                                            width: 44,
                                                            height: 44,
                                                            decoration: BoxDecoration(
                                                              shape: BoxShape
                                                                  .circle,
                                                              color:
                                                                  Colors.white,
                                                              border: Border.all(
                                                                color: Color(
                                                                  0xFFFF6B00,
                                                                ),
                                                                width: 2,
                                                              ),
                                                            ),
                                                            child: Padding(
                                                              padding:
                                                                  EdgeInsets.all(
                                                                    6,
                                                                  ),
                                                              child: ClipOval(
                                                                child: FittedBox(
                                                                  fit: BoxFit
                                                                      .contain,
                                                                  child:
                                                                      (selectedBodyType !=
                                                                              null &&
                                                                          selectedBodyType!
                                                                              .isNotEmpty)
                                                                      ? _buildBodyTypeImage(
                                                                          _getBodyTypeAsset(
                                                                            selectedBodyType!,
                                                                          ),
                                                                        )
                                                                      : Icon(
                                                                          _getBodyTypeIcon(
                                                                            'car',
                                                                          ),
                                                                          color:
                                                                              Colors.black,
                                                                        ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        onTap: () async {
                                                          final bodyType = await showDialog<String>(
                                                            context: context,
                                                            builder: (dlgContext) {
                                                              final isLightPicker =
                                                                  Theme.of(
                                                                    dlgContext,
                                                                  ).brightness ==
                                                                  Brightness
                                                                      .light;
                                                              final pickerBg =
                                                                  isLightPicker
                                                                  ? Colors.white
                                                                  : (Colors.grey[900]
                                                                            ?.withOpacity(
                                                                              0.98,
                                                                            ) ??
                                                                        Colors
                                                                            .grey
                                                                            .shade900);
                                                              final onPicker =
                                                                  isLightPicker
                                                                  ? const Color(
                                                                      0xFF1A1A1A,
                                                                    )
                                                                  : Colors
                                                                        .white;
                                                              final onPickerMuted =
                                                                  isLightPicker
                                                                  ? const Color(
                                                                      0xFF616161,
                                                                    )
                                                                  : Colors
                                                                        .white70;
                                                              final borderSubtle =
                                                                  isLightPicker
                                                                  ? Colors
                                                                        .black26
                                                                  : Colors
                                                                        .white24;
                                                              final shadowIdle =
                                                                  isLightPicker
                                                                  ? Colors
                                                                        .black12
                                                                  : Colors
                                                                        .black54;
                                                              return Dialog(
                                                                backgroundColor:
                                                                    pickerBg,
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        20,
                                                                      ),
                                                                ),
                                                                child: Container(
                                                                  width: 400,
                                                                  padding:
                                                                      EdgeInsets.all(
                                                                        20,
                                                                      ),
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Row(
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.spaceBetween,
                                                                        children: [
                                                                          Text(
                                                                            AppLocalizations.of(
                                                                              context,
                                                                            )!.selectBodyType,
                                                                            style: GoogleFonts.orbitron(
                                                                              color: Color(
                                                                                0xFFFF6B00,
                                                                              ),
                                                                              fontWeight: FontWeight.bold,
                                                                              fontSize: 20,
                                                                            ),
                                                                          ),
                                                                          IconButton(
                                                                            icon: Icon(
                                                                              Icons.close,
                                                                              color: onPicker,
                                                                            ),
                                                                            onPressed: () => Navigator.pop(
                                                                              dlgContext,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      SizedBox(
                                                                        height:
                                                                            10,
                                                                      ),
                                                                      SizedBox(
                                                                        height:
                                                                            300,
                                                                        child: GridView.builder(
                                                                          shrinkWrap:
                                                                              true,
                                                                          physics:
                                                                              BouncingScrollPhysics(),
                                                                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                                            crossAxisCount:
                                                                                3,
                                                                            childAspectRatio:
                                                                                0.82,
                                                                            crossAxisSpacing:
                                                                                12,
                                                                            mainAxisSpacing:
                                                                                12,
                                                                          ),
                                                                          itemCount:
                                                                              getAvailableBodyTypes().length,
                                                                          itemBuilder:
                                                                              (
                                                                                context,
                                                                                index,
                                                                              ) {
                                                                                final bodyTypeName = getAvailableBodyTypes()[index];
                                                                                final asset = _getBodyTypeAsset(
                                                                                  bodyTypeName,
                                                                                );
                                                                                final bool
                                                                                isSelected =
                                                                                    (selectedBodyType ??
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any) ==
                                                                                    bodyTypeName;
                                                                                return InkWell(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                  onTap: () => Navigator.pop(
                                                                                    dlgContext,
                                                                                    bodyTypeName,
                                                                                  ),
                                                                                  child: Container(
                                                                                    decoration: BoxDecoration(
                                                                                      color: Colors.transparent,
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                      border: Border.all(
                                                                                        color: isSelected
                                                                                            ? const Color(
                                                                                                0xFFFF6B00,
                                                                                              )
                                                                                            : borderSubtle,
                                                                                        width: isSelected
                                                                                            ? 2
                                                                                            : 1,
                                                                                      ),
                                                                                      boxShadow: isSelected
                                                                                          ? [
                                                                                              BoxShadow(
                                                                                                color:
                                                                                                    const Color(
                                                                                                      0xFFFF6B00,
                                                                                                    ).withOpacity(
                                                                                                      0.35,
                                                                                                    ),
                                                                                                blurRadius: 14,
                                                                                                spreadRadius: 1,
                                                                                                offset: const Offset(
                                                                                                  0,
                                                                                                  4,
                                                                                                ),
                                                                                              ),
                                                                                            ]
                                                                                          : [
                                                                                              BoxShadow(
                                                                                                color: shadowIdle,
                                                                                                blurRadius: 10,
                                                                                                spreadRadius: 0,
                                                                                                offset: const Offset(
                                                                                                  0,
                                                                                                  3,
                                                                                                ),
                                                                                              ),
                                                                                            ],
                                                                                    ),
                                                                                    padding: EdgeInsets.all(
                                                                                      8,
                                                                                    ),
                                                                                    child: Column(
                                                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                                                      children: [
                                                                                        Container(
                                                                                          width: 56,
                                                                                          height: 56,
                                                                                          decoration: BoxDecoration(
                                                                                            shape: BoxShape.circle,
                                                                                            color: Colors.white,
                                                                                            border: Border.all(
                                                                                              color: isSelected
                                                                                                  ? const Color(
                                                                                                      0xFFFF6B00,
                                                                                                    )
                                                                                                  : borderSubtle,
                                                                                              width: isSelected
                                                                                                  ? 2
                                                                                                  : 1,
                                                                                            ),
                                                                                          ),
                                                                                          child: Padding(
                                                                                            padding: const EdgeInsets.all(
                                                                                              8,
                                                                                            ),
                                                                                            child: FittedBox(
                                                                                              fit: BoxFit.contain,
                                                                                              child: _buildBodyTypeImage(
                                                                                                asset,
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                        const SizedBox(
                                                                                          height: 8,
                                                                                        ),
                                                                                        Text(
                                                                                          bodyTypeName ==
                                                                                                  'Any'
                                                                                              ? AppLocalizations.of(
                                                                                                  context,
                                                                                                )!.anyOption
                                                                                              : (_translateValueGlobal(
                                                                                                      context,
                                                                                                      bodyTypeName,
                                                                                                    ) ??
                                                                                                    bodyTypeName),
                                                                                          style: GoogleFonts.orbitron(
                                                                                            fontSize: 12,
                                                                                            color: isSelected
                                                                                                ? const Color(
                                                                                                    0xFFFF6B00,
                                                                                                  )
                                                                                                : onPickerMuted,
                                                                                            fontWeight: FontWeight.bold,
                                                                                          ),
                                                                                          textAlign: TextAlign.center,
                                                                                          overflow: TextOverflow.ellipsis,
                                                                                          maxLines: 1,
                                                                                        ),
                                                                                      ],
                                                                                    ),
                                                                                  ),
                                                                                );
                                                                              },
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          );
                                                          if (bodyType !=
                                                              null) {
                                                            setState(() {
                                                              selectedBodyType =
                                                                  bodyType ==
                                                                      'Any'
                                                                  ? null
                                                                  : bodyType;
                                                            });
                                                            setStateDialog(
                                                              () {},
                                                            );
                                                          }
                                                        },
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      TextFormField(
                                                        key: ValueKey(
                                                          'color_${selectedColor ?? 'any'}',
                                                        ),
                                                        readOnly: true,
                                                        style: TextStyle(
                                                          color:
                                                              (selectedColor !=
                                                                      null &&
                                                                  selectedColor!
                                                                      .isNotEmpty)
                                                              ? moreFiltersOnSurface
                                                              : moreFiltersAnyOrange,
                                                        ),
                                                        initialValue:
                                                            (_translateValueGlobal(
                                                              context,
                                                              selectedColor,
                                                            ) ??
                                                            selectedColor ??
                                                            AppLocalizations.of(
                                                              context,
                                                            )!.any),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.colorLabel,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          suffixIcon: Container(
                                                            width: 24,
                                                            height: 24,
                                                            margin:
                                                                EdgeInsets.all(
                                                                  8,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  selectedColor !=
                                                                      null
                                                                  ? _getColorValue(
                                                                      selectedColor!,
                                                                    )
                                                                  : Colors.grey,
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                              border: Border.all(
                                                                color: Colors
                                                                    .white24,
                                                                width: 2,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        onTap: () async {
                                                          final color = await showDialog<String>(
                                                            context: context,
                                                            builder: (dlgContext) {
                                                              final isLightPicker =
                                                                  Theme.of(
                                                                    dlgContext,
                                                                  ).brightness ==
                                                                  Brightness
                                                                      .light;
                                                              final pickerBg =
                                                                  isLightPicker
                                                                  ? Colors.white
                                                                  : (Colors.grey[900]
                                                                            ?.withOpacity(
                                                                              0.98,
                                                                            ) ??
                                                                        Colors
                                                                            .grey
                                                                            .shade900);
                                                              final onPicker =
                                                                  isLightPicker
                                                                  ? const Color(
                                                                      0xFF1A1A1A,
                                                                    )
                                                                  : Colors
                                                                        .white;
                                                              final borderSubtle =
                                                                  isLightPicker
                                                                  ? Colors
                                                                        .black26
                                                                  : Colors
                                                                        .white24;
                                                              final cellFill =
                                                                  isLightPicker
                                                                  ? Colors
                                                                        .grey
                                                                        .shade200
                                                                  : Colors.black
                                                                        .withOpacity(
                                                                          0.15,
                                                                        );
                                                              return Dialog(
                                                                backgroundColor:
                                                                    pickerBg,
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        20,
                                                                      ),
                                                                ),
                                                                child: Container(
                                                                  width: 400,
                                                                  padding:
                                                                      EdgeInsets.all(
                                                                        20,
                                                                      ),
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Row(
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.spaceBetween,
                                                                        children: [
                                                                          Text(
                                                                            AppLocalizations.of(
                                                                              context,
                                                                            )!.selectColor,
                                                                            style: GoogleFonts.orbitron(
                                                                              color: Color(
                                                                                0xFFFF6B00,
                                                                              ),
                                                                              fontWeight: FontWeight.bold,
                                                                              fontSize: 20,
                                                                            ),
                                                                          ),
                                                                          IconButton(
                                                                            icon: Icon(
                                                                              Icons.close,
                                                                              color: onPicker,
                                                                            ),
                                                                            onPressed: () => Navigator.pop(
                                                                              dlgContext,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      SizedBox(
                                                                        height:
                                                                            10,
                                                                      ),
                                                                      SizedBox(
                                                                        height:
                                                                            300,
                                                                        child: GridView.builder(
                                                                          shrinkWrap:
                                                                              true,
                                                                          physics:
                                                                              BouncingScrollPhysics(),
                                                                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                                            crossAxisCount:
                                                                                3,
                                                                            childAspectRatio:
                                                                                1.2,
                                                                            crossAxisSpacing:
                                                                                10,
                                                                            mainAxisSpacing:
                                                                                10,
                                                                          ),
                                                                          itemCount:
                                                                              getAvailableColors().length,
                                                                          itemBuilder:
                                                                              (
                                                                                context,
                                                                                index,
                                                                              ) {
                                                                                final colorName = getAvailableColors()[index];
                                                                                Color
                                                                                colorValue = Colors.grey;
                                                                                switch (colorName.toLowerCase()) {
                                                                                  case 'black':
                                                                                    colorValue = Colors.black;
                                                                                    break;
                                                                                  case 'white':
                                                                                    colorValue = Colors.white;
                                                                                    break;
                                                                                  case 'silver':
                                                                                    colorValue = Colors.grey[300]!;
                                                                                    break;
                                                                                  case 'gray':
                                                                                    colorValue = Colors.grey[600]!;
                                                                                    break;
                                                                                  case 'red':
                                                                                    colorValue = Colors.red;
                                                                                    break;
                                                                                  case 'blue':
                                                                                    colorValue = Colors.blue;
                                                                                    break;
                                                                                  case 'green':
                                                                                    colorValue = Colors.green;
                                                                                    break;
                                                                                  case 'yellow':
                                                                                    colorValue = Colors.yellow;
                                                                                    break;
                                                                                  case 'orange':
                                                                                    colorValue = Colors.orange;
                                                                                    break;
                                                                                  case 'purple':
                                                                                    colorValue = Colors.purple;
                                                                                    break;
                                                                                  case 'brown':
                                                                                    colorValue = Colors.brown;
                                                                                    break;
                                                                                  case 'beige':
                                                                                    colorValue = Color(
                                                                                      0xFFF5F5DC,
                                                                                    );
                                                                                    break;
                                                                                  case 'gold':
                                                                                    colorValue = Color(
                                                                                      0xFFFFD700,
                                                                                    );
                                                                                    break;
                                                                                  default:
                                                                                    colorValue = Colors.grey;
                                                                                }
                                                                                return InkWell(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                  onTap: () => Navigator.pop(
                                                                                    dlgContext,
                                                                                    colorName,
                                                                                  ),
                                                                                  child: Container(
                                                                                    decoration: BoxDecoration(
                                                                                      color: cellFill,
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                      border: Border.all(
                                                                                        color: borderSubtle,
                                                                                      ),
                                                                                    ),
                                                                                    padding: EdgeInsets.all(
                                                                                      8,
                                                                                    ),
                                                                                    child: Column(
                                                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                                                      children: [
                                                                                        Container(
                                                                                          width: 40,
                                                                                          height: 40,
                                                                                          decoration: BoxDecoration(
                                                                                            color: colorValue,
                                                                                            borderRadius: BorderRadius.circular(
                                                                                              8,
                                                                                            ),
                                                                                            border: Border.all(
                                                                                              color: borderSubtle,
                                                                                              width: 2,
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                        SizedBox(
                                                                                          height: 8,
                                                                                        ),
                                                                                        Text(
                                                                                          _translateValueGlobal(
                                                                                                context,
                                                                                                colorName,
                                                                                              ) ??
                                                                                              colorName,
                                                                                          style: GoogleFonts.orbitron(
                                                                                            fontSize: 12,
                                                                                            color: onPicker,
                                                                                            fontWeight: FontWeight.bold,
                                                                                          ),
                                                                                          textAlign: TextAlign.center,
                                                                                          overflow: TextOverflow.ellipsis,
                                                                                          maxLines: 1,
                                                                                        ),
                                                                                      ],
                                                                                    ),
                                                                                  ),
                                                                                );
                                                                              },
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          );
                                                          if (color != null) {
                                                            setState(() {
                                                              selectedColor =
                                                                  color == 'Any'
                                                                  ? null
                                                                  : color;
                                                            });
                                                            setStateDialog(
                                                              () {},
                                                            );
                                                          }
                                                        },
                                                      ),
                                                      SizedBox(height: 12),
                                                      // Drive Type Dropdown
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            _getValidDriveTypeValue(),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.driveType,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...getAvailableDriveTypes()
                                                              .where(
                                                                (d) =>
                                                                    d != 'Any',
                                                              )
                                                              .map(
                                                                (
                                                                  d,
                                                                ) => DropdownMenuItem(
                                                                  value: d,
                                                                  child: Text(
                                                                    _translateValueGlobal(
                                                                          context,
                                                                          d,
                                                                        ) ??
                                                                        d,
                                                                  ),
                                                                ),
                                                              ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(
                                                            () =>
                                                                selectedDriveType =
                                                                    value == ''
                                                                    ? null
                                                                    : value,
                                                          );
                                                          _persistFilters();
                                                        },
                                                      ),
                                                      SizedBox(height: 12),
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        key: ValueKey(
                                                          'home_more_region_specs_${_moreFiltersDialogFieldGeneration}',
                                                        ),
                                                        initialValue:
                                                            _getValidRegionSpecsValue(),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.regionSpecsLabel,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...kCarRegionSpecCodes.map(
                                                            (
                                                              code,
                                                            ) => DropdownMenuItem(
                                                              value: code,
                                                              child: Text(
                                                                carRegionSpecDisplayLabelLocalized(
                                                                  context,
                                                                  code,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(
                                                            () => selectedRegionSpecs =
                                                                value == null ||
                                                                    value
                                                                        .isEmpty
                                                                ? null
                                                                : value,
                                                          );
                                                          _persistFilters();
                                                        },
                                                      ),
                                                      SizedBox(height: 12),
                                                      // Cylinder Count Dropdown
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            _getValidCylinderCountValue(),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.cylinderCount,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...getAvailableCylinderCounts()
                                                              .where(
                                                                (c) =>
                                                                    c != 'Any',
                                                              )
                                                              .map(
                                                                (
                                                                  c,
                                                                ) => DropdownMenuItem(
                                                                  value: c,
                                                                  child: Text(
                                                                    _localizeDigitsGlobal(
                                                                      context,
                                                                      c,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(() {
                                                            selectedCylinderCount =
                                                                value == ''
                                                                ? null
                                                                : value;
                                                            _applyMoreFiltersEngineSyncFromCylinder(
                                                              selectedCylinderCount,
                                                            );
                                                          });
                                                          setStateDialog(() {});
                                                          _persistFilters();
                                                        },
                                                      ),
                                                      SizedBox(height: 12),
                                                      // Seating Dropdown
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            selectedSeating ??
                                                            '',
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.seating,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...getAvailableSeatings()
                                                              .where(
                                                                (s) =>
                                                                    s != 'Any',
                                                              )
                                                              .map(
                                                                (
                                                                  s,
                                                                ) => DropdownMenuItem(
                                                                  value: s,
                                                                  child: Text(
                                                                    _localizeDigitsGlobal(
                                                                      context,
                                                                      s,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(
                                                            () =>
                                                                selectedSeating =
                                                                    value == ''
                                                                    ? null
                                                                    : value,
                                                          );
                                                          _persistFilters();
                                                        },
                                                      ),
                                                      SizedBox(height: 12),
                                                      // Engine Size Dropdown / Manual input
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                isEngineSizeDropdown
                                                                ? DropdownButtonFormField<
                                                                    String
                                                                  >(
                                                                    initialValue:
                                                                        _getValidEngineSizeValue(),
                                                                    decoration: InputDecoration(
                                                                      labelText: AppLocalizations.of(
                                                                        context,
                                                                      )!.engineSizeL,
                                                                      filled:
                                                                          true,
                                                                      fillColor:
                                                                          moreFiltersFieldFill,
                                                                      labelStyle:
                                                                          TextStyle(
                                                                            color:
                                                                                moreFiltersOnSurface,
                                                                            fontSize: 18,
                                                                            fontWeight: FontWeight.bold,
                                                                          ),
                                                                      border: OutlineInputBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              12,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    items: [
                                                                      DropdownMenuItem(
                                                                        value:
                                                                            '',
                                                                        child: Text(
                                                                          AppLocalizations.of(
                                                                            context,
                                                                          )!.any,
                                                                          style: TextStyle(
                                                                            color:
                                                                                moreFiltersAnyOrange,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      ...getAvailableEngineSizes()
                                                                          .where(
                                                                            (
                                                                              e,
                                                                            ) =>
                                                                                e !=
                                                                                'Any',
                                                                          )
                                                                          .map(
                                                                            (
                                                                              e,
                                                                            ) => DropdownMenuItem(
                                                                              value: e,
                                                                              child: Text(
                                                                                '${_localizeDigitsGlobal(context, e)}${AppLocalizations.of(context)!.unit_liter_suffix}',
                                                                              ),
                                                                            ),
                                                                          ),
                                                                    ],
                                                                    onChanged: (value) {
                                                                      setState(() {
                                                                        selectedEngineSize =
                                                                            value ==
                                                                                ''
                                                                            ? null
                                                                            : value;
                                                                        _applyMoreFiltersCylinderSyncFromEngine(
                                                                          selectedEngineSize,
                                                                        );
                                                                      });
                                                                      setStateDialog(
                                                                        () {},
                                                                      );
                                                                      _persistFilters();
                                                                    },
                                                                  )
                                                                : TextFormField(
                                                                    controller:
                                                                        _engineSizeController,
                                                                    decoration: InputDecoration(
                                                                      labelText: AppLocalizations.of(
                                                                        context,
                                                                      )!.engineSizeL,
                                                                      filled:
                                                                          true,
                                                                      fillColor:
                                                                          moreFiltersFieldFill,
                                                                      labelStyle:
                                                                          TextStyle(
                                                                            color:
                                                                                moreFiltersOnSurface,
                                                                            fontSize: 18,
                                                                            fontWeight: FontWeight.bold,
                                                                          ),
                                                                      border: OutlineInputBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              12,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    keyboardType:
                                                                        const TextInputType.numberWithOptions(
                                                                          decimal:
                                                                              true,
                                                                        ),
                                                                    inputFormatters: [
                                                                      services
                                                                          .FilteringTextInputFormatter.allow(
                                                                        RegExp(
                                                                          r'[0-9.]',
                                                                        ),
                                                                      ),
                                                                    ],
                                                                    onChanged: (value) {
                                                                      setState(() {
                                                                        selectedEngineSize =
                                                                            value.isEmpty
                                                                            ? null
                                                                            : value;
                                                                        _applyMoreFiltersCylinderSyncFromEngine(
                                                                          selectedEngineSize,
                                                                        );
                                                                      });
                                                                      setStateDialog(
                                                                        () {},
                                                                      );
                                                                      _persistFilters();
                                                                    },
                                                                  ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          IconButton(
                                                            onPressed: () => setStateDialog(() {
                                                              if (isEngineSizeDropdown) {
                                                                _engineSizeController
                                                                        .text =
                                                                    selectedEngineSize ??
                                                                    '';
                                                              }
                                                              isEngineSizeDropdown =
                                                                  !isEngineSizeDropdown;
                                                            }),
                                                            icon: Icon(
                                                              isEngineSizeDropdown
                                                                  ? Icons.edit
                                                                  : Icons.list,
                                                              color:
                                                                  const Color(
                                                                    0xFFFF6B00,
                                                                  ),
                                                            ),
                                                            style: IconButton.styleFrom(
                                                              backgroundColor:
                                                                  moreFiltersFieldFill,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      SizedBox(height: 12),
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            selectedPlateType ??
                                                            '',
                                                        decoration: InputDecoration(
                                                          labelText: _trLegacyText(context, 'Plate type', ar: 'نوع اللوحة', ku: 'جۆری پڵەیت'),
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          DropdownMenuItem(
                                                            value: 'private',
                                                            child: Text(
                                                              _translatePlateTypeLegacy(
                                                                context,
                                                                'private',
                                                              ),
                                                            ),
                                                          ),
                                                          DropdownMenuItem(
                                                            value: 'temporary',
                                                            child: Text(
                                                              _translatePlateTypeLegacy(
                                                                context,
                                                                'temporary',
                                                              ),
                                                            ),
                                                          ),
                                                          DropdownMenuItem(
                                                            value: 'commercial',
                                                            child: Text(
                                                              _translatePlateTypeLegacy(
                                                                context,
                                                                'commercial',
                                                              ),
                                                            ),
                                                          ),
                                                          DropdownMenuItem(
                                                            value: 'taxi',
                                                            child: Text(
                                                              _translatePlateTypeLegacy(
                                                                context,
                                                                'taxi',
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(() {
                                                            selectedPlateType =
                                                                (value == null ||
                                                                        value
                                                                            .isEmpty)
                                                                ? null
                                                                : value;
                                                          });
                                                          _persistFilters();
                                                        },
                                                      ),
                                                      const SizedBox(height: 12),
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            selectedPlateCity ??
                                                            '',
                                                        decoration: InputDecoration(
                                                          labelText: _trLegacyText(context, 'Plate city', ar: 'مدينة اللوحة', ku: 'شاری پڵەیت'),
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...cities
                                                              .where(
                                                                (c) =>
                                                                    c.toLowerCase() !=
                                                                    'any',
                                                              )
                                                              .map(
                                                                (c) =>
                                                                    DropdownMenuItem(
                                                                  value: c,
                                                                  child: Text(
                                                                    _translateValueGlobal(
                                                                          context,
                                                                          c,
                                                                        ) ??
                                                                        c,
                                                                  ),
                                                                ),
                                                              ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(() {
                                                            selectedPlateCity =
                                                                (value == null ||
                                                                        value
                                                                            .isEmpty)
                                                                ? null
                                                                : value;
                                                          });
                                                          _persistFilters();
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              actions: [
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: Row(
                                                    textDirection:
                                                        ui.TextDirection.ltr,
                                                    children: [
                                                      TextButton(
                                                        onPressed: () async {
                                                          await _resetFiltersFromMoreFiltersDialog(
                                                            () =>
                                                                setStateDialog(
                                                                  () {},
                                                                ),
                                                          );
                                                        },
                                                        child: Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.resetButton,
                                                          style: TextStyle(
                                                            color:
                                                                moreFiltersMuted,
                                                          ),
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: () {
                                                          _restoreMoreFiltersDialogSnapshot(
                                                            moreFiltersSnapshot,
                                                          );
                                                          unawaited(
                                                            _persistFilters(),
                                                          );
                                                          Navigator.pop(
                                                            context,
                                                          );
                                                        },
                                                        child: Text(
                                                          _cancelTextGlobal(
                                                            context,
                                                          ),
                                                          style: TextStyle(
                                                            color:
                                                                moreFiltersMuted,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: ElevatedButton(
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                Color(
                                                                  0xFFFF6B00,
                                                                ),
                                                            foregroundColor:
                                                                Colors.white,
                                                          ),
                                                          onPressed: () {
                                                            unawaited(
                                                              _persistFilters(),
                                                            );
                                                            onFilterChanged();
                                                            Navigator.pop(
                                                              context,
                                                            );
                                                          },
                                                          child: Text(
                                                            AppLocalizations.of(
                                                              context,
                                                            )!.applyFilters,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ), // SliverToBoxAdapter
                  if (isLoading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFFF6B00),
                              ),
                            ),
                            SizedBox(height: 16),
                            Text(
                              selectedSortBy != null
                                  ? 'Sorting listings...'
                                  : 'Loading listings...',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (loadErrorMessage != null && cars.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _couldNotLoadListingsTextGlobal(context),
                              style: TextStyle(color: Colors.white70),
                            ),
                            SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () {
                                    _fetchRetryCount = 0;
                                    fetchCars(bypassCache: true);
                                  },
                                  child: Text(
                                    AppLocalizations.of(context)!.retryAction,
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () => onFilterChanged(),
                                  child: Text(
                                    AppLocalizations.of(context)!.clearFilters,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (cars.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _HomeEmptyListMessage(
                        selectedSortBy: selectedSortBy,
                        onAutoFetch: () {
                          if (!_autoFetchedForEmptyWithSort &&
                              selectedSortBy != null &&
                              selectedSortBy!.isNotEmpty) {
                            _autoFetchedForEmptyWithSort = true;
                            onFilterChanged();
                          }
                        },
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            PopupMenuButton<String>(
                              tooltip: AppLocalizations.of(context)!.sortBy,
                              icon: Icon(Icons.sort, size: 20),
                              onSelected: (value) {
                                setState(
                                  () => selectedSortBy = value == ''
                                      ? null
                                      : value,
                                );
                                _persistFilters();
                                onSortChanged();
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: '',
                                  child: Text(
                                    AppLocalizations.of(context)!.defaultSort,
                                  ),
                                ),
                                ...getLocalizedSortOptions(context)
                                    .skip(1)
                                    .map(
                                      (s) => PopupMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    ),
                              ],
                            ),
                            ToggleButtons(
                              isSelected: [
                                listingColumns == 1,
                                listingColumns == 2,
                                listingColumns == 3,
                              ],
                              onPressed: (index) {
                                setState(() {
                                  listingColumns = index == 0 ? 1 : (index == 1 ? 2 : 3);
                                });
                                ListingLayoutPrefs.setColumns(listingColumns);
                              },
                              children: const [
                                Icon(Icons.view_agenda),
                                Icon(Icons.grid_view),
                                Icon(Icons.swipe_vertical),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (loadErrorMessage != null && cars.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          margin: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.offline_bolt,
                                color: Colors.orange,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Showing cached results',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: fetchCars,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size(0, 0),
                                ),
                                child: Text(
                                  'Refresh',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        listingColumns == 1 ? 4 : 8,
                        8,
                        listingColumns == 1 ? 4 : 8,
                        8 + MediaQuery.of(context).padding.bottom + 92,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: listingColumns == 1 ? 1 : 2,
                          // Slightly taller cells than 0.65 so listing cards (image + content) don’t overflow
                          // One column: horizontal row — wider vs tall to match strip layout.
                          // One column: horizontal card. Larger ratio => shorter cell height
                          // so the text column is not left with a tall empty band under the last row.
                          childAspectRatio: listingColumns == 1
                              ? 2.78
                              : (Platform.isIOS ? 0.66 : 0.61),
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          if (index >= cars.length) {
                            return Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          final car = cars[index];
                          if (listingColumns == 3) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  '/tiktok_scroll',
                                  arguments: {
                                    'cars': cars,
                                    'initialIndex': index,
                                  },
                                );
                              },
                              child: AbsorbPointer(
                                child: buildGlobalCarCard(
                                  context,
                                  car,
                                  listLayout: false,
                                  carouselResetSeed: _homeCarouselResetSeed,
                                ),
                              ),
                            );
                          }
                          return buildGlobalCarCard(
                            context,
                            car,
                            listLayout: listingColumns == 1,
                            carouselResetSeed: _homeCarouselResetSeed,
                          );
                        }, childCount: cars.length + (_hasNext ? 1 : 0)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Intentionally avoid full-screen obscuring overlay while scroll restores.
          ],
        ),
      ),
      floatingActionButton: null,
    );
  }

  Widget _buildCardImageCarousel(BuildContext context, Map car) {
    final List<String> urls = () {
      final List<String> u = [];
      final String primary = (car['image_url'] ?? '').toString();
      final List<dynamic> imgs = (car['images'] is List)
          ? (car['images'] as List)
          : const [];
      if (primary.isNotEmpty) {
        u.add(_buildFullImageUrl(primary));
      }
      for (final dynamic it in imgs) {
        if (it is Map &&
            (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
          continue;
        }
        String s;
        if (it is Map) {
          s = (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
              .toString();
        } else {
          s = it.toString();
        }
        if (s.isNotEmpty) {
          final full = _buildFullImageUrl(s);
          if (!u.contains(full)) u.add(full);
        }
      }
      if (u.isEmpty && imgs.isNotEmpty) {
        dynamic first;
        for (final dynamic e in imgs) {
          if (e is Map &&
              (e['kind'] ?? '').toString().toLowerCase() == 'damage') {
            continue;
          }
          first = e;
          break;
        }
        if (first != null) {
          final String s = first is Map
              ? (first['image_url'] ??
                        first['url'] ??
                        first['path'] ??
                        first['src'] ??
                        '')
                    .toString()
              : first.toString();
          if (s.isNotEmpty) u.add(_buildFullImageUrl(s));
        }
      }
      return u;
    }();

    if (urls.isEmpty) {
      return Container(
        color: Colors.grey[900],
        width: double.infinity,
        child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
      );
    }

    int currentIndex = 0;

    return StatefulBuilder(
      builder: (context, setState) {
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/car_detail',
                  arguments: {'carId': car['id']},
                );
              },
              child: PageView.builder(
                onPageChanged: (i) => setState(() => currentIndex = i),
                itemCount: urls.length,
                itemBuilder: (context, i) {
                  final url = urls[i];
                  return _listingNetworkImage(
                    url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                  );
                },
              ),
            ),
            if (urls.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(urls.length, (i) {
                        final active = i == currentIndex;
                        return AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          margin: EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 8 : 6,
                          height: active ? 8 : 6,
                          decoration: BoxDecoration(
                            color: active ? Colors.white : Colors.white70,
                            shape: BoxShape.circle,
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Helper methods for unified filter functionality
  String? _getPriceRangeValue() {
    return selectedMinPrice ?? '';
  }

  String _formatPrice(String raw) {
    try {
      final num? value = num.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (value == null) return _localizeDigitsGlobal(context, raw);
      final locale = Localizations.localeOf(context).toLanguageTag();
      final formatter = _decimalFormatterGlobal(context);
      return _localizeDigitsGlobal(context, formatter.format(value));
    } catch (_) {
      return _localizeDigitsGlobal(context, raw);
    }
  }

  void _updatePriceFilter(String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        selectedMinPrice = null;
        selectedMaxPrice = null;
      } else {
        selectedMinPrice = value;
        selectedMaxPrice = null;
      }
    });
  }

  String? _getYearRangeValue() {
    return selectedMinYear ?? '';
  }

  void _updateYearFilter(String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        selectedMinYear = null;
        selectedMaxYear = null;
      } else {
        selectedMinYear = value;
        selectedMaxYear = null;
      }
    });
  }

  String? _getMileageRangeValue() {
    return selectedMinMileage ?? '';
  }

  void _updateMileageFilter(String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        selectedMinMileage = null;
        selectedMaxMileage = null;
      } else {
        selectedMinMileage = value;
        selectedMaxMileage = null;
      }
    });
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

  // Helper function to get an emoji for a given body type
  String _getBodyTypeEmoji(String bodyType) {
    switch (bodyType.toLowerCase()) {
      case 'sedan':
        return 'ðŸš—';
      case 'suv':
        return 'ðŸš™';
      case 'hatchback':
        return 'ðŸš—';
      case 'coupe':
        return 'ðŸŽï¸';
      case 'wagon':
        return 'ðŸš™';
      case 'pickup':
        return 'ðŸ›»';
      case 'van':
        return 'ðŸš';
      case 'minivan':
        return 'ðŸš';
      case 'motorcycle':
        return 'ðŸï¸';
      case 'utv':
        return 'ðŸšœ';
      case 'atv':
        return 'ðŸŽï¸';
      default:
        return 'ðŸš˜';
    }
  }

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _SearchDialog(
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

const String _homePendingSavedSearchFetchKey = 'home_pending_saved_search_fetch_v1';
const String _homeOneTimeFiltersKey = 'home_apply_filters_once_v1';

Future<void> _markPendingSavedSearchFetch() async {
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_homePendingSavedSearchFetchKey, true);
  } catch (_) {}
}

Future<bool> _consumePendingSavedSearchFetch() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final pending = sp.getBool(_homePendingSavedSearchFetchKey) ?? false;
    if (pending) {
      await sp.remove(_homePendingSavedSearchFetchKey);
    }
    return pending;
  } catch (_) {
    return false;
  }
}

Future<Map<String, dynamic>?> _consumeOneTimeSavedSearchFilters() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_homeOneTimeFiltersKey);
    if (raw == null || raw.isEmpty) return null;
    await sp.remove(_homeOneTimeFiltersKey);
    final decoded = json.decode(raw);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

/// One-time saved-search apply (not restored on next app launch).
Future<void> persistSavedSearchFiltersForHome(
  Map<String, dynamic> filters,
) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final map = <String, dynamic>{
      'brand': filters['brand'],
      'model': filters['model'],
      'trim': filters['trim'],
      'price_min': filters['min_price'] ?? filters['price_min'],
      'price_max': filters['max_price'] ?? filters['price_max'],
      'year_min': filters['min_year'] ?? filters['year_min'],
      'year_max': filters['max_year'] ?? filters['year_max'],
      'min_mileage': filters['min_mileage'],
      'max_mileage': filters['max_mileage'],
      'condition': filters['condition'],
      'transmission': filters['transmission'],
      'fuel_type': filters['fuel_type'],
      'body_type': filters['body_type'],
      'color': filters['color'],
      'drive_type': filters['drive_type'],
      'region_specs': filters['region_specs'],
      'cylinders': filters['cylinder_count'] ?? filters['cylinders'],
      'seating': filters['seating'],
      'engine_size': filters['engine_size'],
      'city': filters['city'],
      'plate_type': filters['plate_type'],
      'plate_city': filters['plate_city'],
      'title_status': filters['title_status'],
      'damaged_parts': filters['damaged_parts'],
      'sort_by': filters['sort_by'],
    };
    map.removeWhere((_, v) => v == null || v.toString().trim().isEmpty);
    await sp.remove('home_filters_v1');
    await sp.setString(_homeOneTimeFiltersKey, json.encode(map));
    await _markPendingSavedSearchFetch();
  } catch (_) {}
}
