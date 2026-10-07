part of 'home_flow.dart';

mixin _HomePageFilterCatalog on _HomePageFetch {
  void _invalidateHomeCatalogFilterCaches() {
    _homeCatalogOptsCacheKey = null;
    _homeCatalogOptsCache = null;
    _homeFilterSpecVariantsCacheKey = null;
    _homeFilterSpecVariantsCache = null;
    _homeVehicleFieldOptionsCacheKey = null;
    _homeVehicleFieldOptionsCacheIdx = null;
    _homeVehicleFieldOptionsCache = null;
    _homeVehicleFieldOptionsCacheProvisional = false;
  }

  /// Spec rows for correlating engine ↔ cylinders in More Filters (cached per scope).
  List<OnlineSpecVariant> _homeMoreFiltersSpecVariants() {
    final singleBrand = homeFilterDecodeSingle(selectedBrand) ?? '';
    final m = selectedModel?.trim();
    if (singleBrand.isEmpty || m == null || m.isEmpty) return const [];
    final idx = _homeCarSpecIdx;
    if (idx == null) return const [];
    // Brand + model only: the trim never changes the rows.
    final key = 'sv|$singleBrand|\x1e|$m';
    if (_homeFilterSpecVariantsCacheKey == key &&
        _homeFilterSpecVariantsCache != null) {
      return _homeFilterSpecVariantsCache!;
    }
    final list = idx.homeFilterSpecVariantsUnion(
      singleBrand,
      m,
      CarSpecIndex.catalogAutofillModelOnly,
    );
    _homeFilterSpecVariantsCacheKey = key;
    _homeFilterSpecVariantsCache = list;
    return list;
  }

  /// The shared trusted resolver ([SellSpecReconciler], the same one Sell uses)
  /// over the CarNet rows scoped to the current Search vehicle (make + model +
  /// trim + year window). Null when the catalog cannot answer. The approved IQ
  /// model-level engine / cylinder lists only widen the AVAILABLE engine labels;
  /// they never create a relationship.
  SearchSpecReconciler? _homeLinkedSpecReconciler() {
    if (_homeVehicleResolutionDeferred) return null;
    final rows = _homeMoreFiltersSpecVariants();
    if (rows.isEmpty) return null;
    return SearchSpecReconciler(
      SellSpecReconciler(
        rows: rows,
        availableEngines: getAvailableEngineSizes(),
        fuelKeyOf: (v) {
          final f = (v.fuelType ?? v.engineType)?.trim();
          if (f == null || f.isEmpty) return null;
          return sellFlowFuelLabel(f).toLowerCase();
        },
      ),
    );
  }

  SearchSpecState _homeLinkedSpecState() {
    final eng = selectedEngineSize?.trim() ?? '';
    // A hand-typed engine is not a catalog label: never reconciled or replaced.
    final engineLabel =
        isEngineSizeDropdown && eng.isNotEmpty && eng.toLowerCase() != 'any'
            ? eng
            : null;
    final cyl = int.tryParse((selectedCylinderCount ?? '').trim());
    return SearchSpecState(
      engine: engineLabel,
      cylinders: cyl,
      fuels: [
        for (final f in homeFilterDecodeList(selectedFuelType))
          f.trim().toLowerCase(),
      ],
    );
  }

  /// Writes [next] into the filter state (plain assignments, no callbacks) and
  /// reports whether anything changed. Only values the current option lists
  /// offer are applied.
  bool _homeApplyLinkedSpecState(SearchSpecState cur, SearchSpecState next) {
    if (next == cur) return false;
    var changed = false;
    final e = next.engine;
    if (e != null && e != cur.engine && getAvailableEngineSizes().contains(e)) {
      selectedEngineSize = e;
      _engineSizeController.text = e;
      changed = true;
    }
    final c = next.cylinders;
    if (c != null &&
        c != cur.cylinders &&
        getAvailableCylinderCounts().contains('$c')) {
      selectedCylinderCount = '$c';
      changed = true;
    }
    if (next.fuels.join('|') != cur.fuels.join('|') && next.fuels.isNotEmpty) {
      final offered = getAvailableFuelTypes();
      final labels = <String>[
        for (final k in next.fuels)
          if (offered.contains(sellFlowFuelLabel(k))) sellFlowFuelLabel(k),
      ];
      if (labels.isNotEmpty) {
        selectedFuelType = homeFilterEncodeList(labels);
        changed = true;
      }
    }
    if (changed) _moreFiltersDialogFieldGeneration++;
    return changed;
  }

  /// One cheap, deterministic reconciliation pass after the user changed the
  /// engine, cylinders or fuel (a concrete value; picking `Any` never calls
  /// this). The changed field is preserved; see [SearchSpecReconciler].
  bool _homeReconcileLinkedSpecs(SellSpecField changed, {String? addedFuel}) {
    final r = _homeLinkedSpecReconciler();
    if (r == null) return false;
    final cur = _homeLinkedSpecState();
    final next = switch (changed) {
      SellSpecField.engine => r.afterEngine(cur),
      SellSpecField.cylinders => r.afterCylinders(cur),
      SellSpecField.fuel => r.afterFuel(cur, added: addedFuel?.toLowerCase()),
    };
    return _homeApplyLinkedSpecState(cur, next);
  }

  /// Restored / re-validated filters: keep compatible selections, let the stored
  /// engine pull a conflicting concrete cylinder / fuel to its trusted value.
  bool _homeRestoreLinkedSpecs() {
    if (_homeCarSpecIdx == null) return false;
    final cur = _homeLinkedSpecState();
    if (cur.engine == null) return false;
    final r = _homeLinkedSpecReconciler();
    if (r == null) return false;
    return _homeApplyLinkedSpecState(cur, r.afterRestore(cur));
  }

  /// The current Search vehicle selection (make / model / trim / year window).
  HomeVehicleContext _homeVehicleContext() {
    return HomeVehicleContext(
      brand: homeFilterDecodeSingle(selectedBrand),
      model: selectedModel,
      trim: selectedTrim,
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

  /// Engine-size catalog values: make + model only (trim and year never change
  /// them), i.e. the same answer as [_homeCatalogFieldOptions].
  CatalogSellFieldOptions? _homeEngineCatalogFieldOptions() =>
      _homeCatalogFieldOptions();

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
      // A catalog Brand + Model is selected, the index is loaded and no result
      // tap is pending: the catalog's answer (or silence) for engine/cylinder is
      // final. A model the CarNet catalog does not list at all (e.g. a stale
      // saved search) keeps the generic defaults and is never wiped.
      vehicleResolved: idx != null &&
          !_homeVehicleResolutionDeferred &&
          (CarCatalog.models[_homeVehicleContext().brand?.trim() ?? '']
                  ?.contains(_homeVehicleContext().model?.trim() ?? '') ??
              false),
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
    if (after == before) {
      // Nothing was ruled out: still let a stored concrete engine pull a
      // conflicting concrete cylinder / fuel to its trusted value.
      return _homeRestoreLinkedSpecs();
    }
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
    // Valid selections stay; a stored engine then reconciles its conflicting
    // concrete dependents (trusted evidence only).
    _homeRestoreLinkedSpecs();
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
