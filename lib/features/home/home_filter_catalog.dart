part of 'home_flow.dart';

mixin _HomePageFilterCatalog on _HomePageFetch {
  void _invalidateHomeCatalogFilterCaches() {
    _homeCatalogOptsCacheKey = null;
    _homeCatalogOptsCache = null;
    _homeEngineCatalogOptsCacheKey = null;
    _homeEngineCatalogOptsCache = null;
    _homeFilterSpecVariantsCacheKey = null;
    _homeFilterSpecVariantsCache = null;
    _homeVehicleFieldOptionsCacheKey = null;
    _homeVehicleFieldOptionsCacheIdx = null;
    _homeVehicleFieldOptionsCache = null;
    _homeVehicleFieldOptionsCacheProvisional = false;
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
    syncDependentFiltersToVehicle();
  }

  /// Spec rows for correlating engine ↔ cylinders in More Filters (cached per scope).
  List<OnlineSpecVariant> _homeMoreFiltersSpecVariants() {
    final singleBrand = homeFilterDecodeSingle(selectedBrand) ?? '';
    final m = selectedModel?.trim();
    if (singleBrand.isEmpty || m == null || m.isEmpty) return const [];
    final idx = _homeCarSpecIdx;
    if (idx == null) return const [];
    final trimKey = selectedTrim?.trim() ?? '';
    final yb = _homeFilterYearBounds();
    final key =
        'sv|$singleBrand|\x1e|$m|\x1e|$trimKey|\x1e|${yb.minY ?? ''}|\x1e|${yb.maxY ?? ''}';
    if (_homeFilterSpecVariantsCacheKey == key &&
        _homeFilterSpecVariantsCache != null) {
      return _homeFilterSpecVariantsCache!;
    }
    final appTrim = trimKey.isEmpty
        ? CarSpecIndex.catalogAutofillModelOnly
        : trimKey;
    final list = idx.homeFilterSpecVariantsUnion(
      singleBrand,
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

  /// The current Search vehicle selection (make / model / trim / year window).
  HomeVehicleContext _homeVehicleContext() {
    final yb = _homeFilterYearBounds();
    return HomeVehicleContext(
      brand: homeFilterDecodeSingle(selectedBrand),
      model: selectedModel,
      trim: selectedTrim,
      minYear: yb.minY,
      maxYear: yb.maxY,
    );
  }

  /// Model-level catalog values (make + model + year window; trim ignored) from
  /// the same resolver and dependency depth Sell step 2 uses
  /// ([CarSpecIndex.sellFieldOptionsUnion] with `catalogAutofillModelOnly`).
  /// Drives cylinders, body, transmission, fuel, drive and seating. Null when the
  /// catalog cannot answer (no model / unknown model / no index).
  CatalogSellFieldOptions? _homeCatalogFieldOptions() {
    final idx = _homeCarSpecIdx;
    if (idx == null) return null;
    final ctx = _homeVehicleContext();
    final key = ctx.modelCacheKey;
    if (_homeCatalogOptsCacheKey == key) return _homeCatalogOptsCache;
    // A Search result tap is still being acknowledged: answer from defaults now
    // and let the post-frame resolution run the catalog scan.
    if (_homeVehicleResolutionDeferred) return null;
    final resolved = resolveHomeVehicleCatalogOptions(idx, ctx);
    _homeCatalogOptsCacheKey = key;
    _homeCatalogOptsCache = resolved;
    return resolved;
  }

  /// Trim-aware catalog values (make + model + trim + year window). Engine size
  /// only: Search's pre-existing trim narrowing for engines, which Sell lacks.
  CatalogSellFieldOptions? _homeEngineCatalogFieldOptions() {
    final idx = _homeCarSpecIdx;
    if (idx == null) return null;
    final ctx = _homeVehicleContext();
    // Without a trim the trim-aware resolution is identical to the model-level
    // one (see [resolveHomeVehicleEngineCatalogOptions]): reuse it instead of
    // scanning the catalog a second time.
    if ((ctx.trim?.trim() ?? '').isEmpty) return _homeCatalogFieldOptions();
    final key = ctx.engineCacheKey;
    if (_homeEngineCatalogOptsCacheKey == key) {
      return _homeEngineCatalogOptsCache;
    }
    if (_homeVehicleResolutionDeferred) return null;
    final resolved = resolveHomeVehicleEngineCatalogOptions(idx, ctx);
    _homeEngineCatalogOptsCacheKey = key;
    _homeEngineCatalogOptsCache = resolved;
    return resolved;
  }

  HomeVehicleFieldDefaults _homeVehicleFieldDefaults() =>
      HomeVehicleFieldDefaults(
        bodyTypes: bodyTypes,
        transmissions: transmissions
            .where((t) => t == 'Any' || !_isExcludedTransmissionFilter(t))
            .toList(growable: false),
        fuelTypes: fuelTypes,
        driveTypes: driveTypes,
        cylinderCounts: cylinderCounts
            .where((c) => !_isExcludedCylinderFilter(c))
            .toList(growable: false),
        seatings: seatings,
        // Lazy: listing every catalog engine size scans all spec rows, and is
        // only needed when the catalog has no engines for the selected vehicle.
        // While a result tap is being acknowledged never start that scan: use
        // the cached list (warmed in the background) or the static ladder.
        engineSizesProvider: () => _homeVehicleResolutionDeferred
            ? engineSizeFilterOptionsFromCatalogIfCached(_homeCarSpecIdx)
            : engineSizeFilterOptionsFromCatalog(_homeCarSpecIdx),
      );

  /// Per-field allowed values for the current vehicle (catalog-narrowed where the
  /// catalog has data for that field, defaults otherwise).
  ///
  /// Memoized per vehicle context + catalog instance: a single Search build
  /// asks for these from many sections and must not re-resolve each time.
  /// Answers given while a result tap is deferred are provisional and are
  /// replaced as soon as the deferred resolution has run.
  HomeVehicleFieldOptions _homeVehicleFieldOptions() {
    final idx = _homeCarSpecIdx;
    final key = _homeVehicleContext().engineCacheKey;
    final cached = _homeVehicleFieldOptionsCache;
    if (cached != null &&
        _homeVehicleFieldOptionsCacheKey == key &&
        identical(_homeVehicleFieldOptionsCacheIdx, idx) &&
        // A provisional (defaults-only) answer is only reusable while the
        // deferral that produced it is still pending.
        (!_homeVehicleFieldOptionsCacheProvisional ||
            _homeVehicleResolutionDeferred)) {
      return cached;
    }
    final resolved = HomeVehicleFieldOptions.resolve(
      catalog: _homeCatalogFieldOptions(),
      engineCatalog: _homeEngineCatalogFieldOptions(),
      defaults: _homeVehicleFieldDefaults(),
    );
    _homeVehicleFieldOptionsCacheKey = key;
    _homeVehicleFieldOptionsCacheIdx = idx;
    _homeVehicleFieldOptionsCache = resolved;
    _homeVehicleFieldOptionsCacheProvisional = _homeVehicleResolutionDeferred;
    return resolved;
  }

  /// Fills the full-catalog engine-size list in frame-sized slices so the first
  /// Search build / result tap never pays for the cold scan.
  void _prewarmHomeCatalogEngineSizes(CarSpecIndex? idx) {
    if (idx == null) return;
    unawaited(idx.prewarmAllCatalogEngineSizeLabels());
  }

  /// Applies a Search make/model/trim pick: [mutate] runs and the page repaints
  /// at once, so the selection is visible on the tap frame. The catalog work
  /// (model-aware option lists, cleanup of now-invalid dependent filters) runs
  /// right after that frame via [syncDependentFiltersToVehicle], then the page
  /// refreshes once more with the resolved lists.
  void _homeApplyVehicleSelection(
    BuildContext context,
    StateSetter setStateDialog,
    VoidCallback mutate,
  ) {
    _homeVehicleResolutionDeferred = true;
    setState(mutate);
    setStateDialog(() {});
    if (_homeVehicleResolutionScheduled) return;
    _homeVehicleResolutionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeVehicleResolutionScheduled = false;
      if (!mounted) {
        _homeVehicleResolutionDeferred = false;
        return;
      }
      setState(() {
        syncDependentFiltersToVehicle();
      });
      if (context.mounted) setStateDialog(() {});
    });
  }

  /// Re-validates every catalog-dependent filter against the current vehicle.
  ///
  /// Called whenever make / model / trim / year window change, after the catalog
  /// finishes loading, and after filters are restored (saved search, session,
  /// dialog revert). Only selections the catalog has ruled out are cleared;
  /// valid selections (and fields without catalog data) are kept untouched.
  /// Returns true if anything was cleared.
  bool syncDependentFiltersToVehicle() {
    _homeVehicleResolutionDeferred = false;
    final before = HomeVehicleDependentSelections(
      bodyType: selectedBodyType,
      transmission: selectedTransmission,
      fuelType: selectedFuelType,
      driveType: selectedDriveType,
      cylinderCount: selectedCylinderCount,
      seating: selectedSeating,
      engineSize: selectedEngineSize,
    );
    final after = sanitizeHomeVehicleDependentSelections(
      before,
      _homeVehicleFieldOptions(),
      pruneEngineSize: isEngineSizeDropdown,
    );
    if (after == before) return false;
    selectedBodyType = after.bodyType;
    selectedTransmission = after.transmission;
    selectedFuelType = after.fuelType;
    selectedDriveType = after.driveType;
    selectedCylinderCount = after.cylinderCount;
    selectedSeating = after.seating;
    if (after.engineSize != before.engineSize) {
      selectedEngineSize = after.engineSize;
      _engineSizeController.text = after.engineSize ?? '';
    }
    // Remount dropdowns so they drop stale internal state.
    _moreFiltersDialogFieldGeneration++;
    return true;
  }

  // Helper methods to get available options based on selected vehicle
  List<String> getAvailableEngineSizes() =>
      _homeVehicleFieldOptions().engineSizes;

  List<String> getAvailableConditions() => conditions;

  List<String> getAvailableBodyTypes() => _homeVehicleFieldOptions().bodyTypes;

  List<String> getAvailableTransmissions() =>
      _homeVehicleFieldOptions().transmissions;

  List<String> getAvailableFuelTypes() => _homeVehicleFieldOptions().fuelTypes;

  List<String> getAvailableDriveTypes() =>
      _homeVehicleFieldOptions().driveTypes;

  static const Set<String> _excludedCylinderFilterValues = {
    '7',
    '9',
    '11',
    '13',
    '14',
    '15',
    'cylinder',
  };

  bool _isExcludedCylinderFilter(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty || v == 'any') return false;
    return _excludedCylinderFilterValues.contains(v);
  }

  /// Model-aware like Sell: the catalog's known cylinder counts for the selected
  /// vehicle, or the full static ladder when the catalog has none for it.
  List<String> getAvailableCylinderCounts() =>
      _homeVehicleFieldOptions().cylinderCounts;

  List<String> getAvailableSeatings() => _homeVehicleFieldOptions().seatings;

  List<String> getAvailableColors() => colors;

  String _getValidSeatingValue() {
    return homeValidDropdownSelection(
      selected: selectedSeating,
      available: getAvailableSeatings(),
    );
  }

  String _getValidCylinderCountValue() {
    return homeValidDropdownSelection(
      selected: selectedCylinderCount,
      available: getAvailableCylinderCounts(),
    );
  }

  String _getValidEngineSizeValue() {
    return homeValidDropdownSelection(
      selected: selectedEngineSize,
      available: getAvailableEngineSizes(),
    );
  }

  // Helper method to check if there are any active filters
}
