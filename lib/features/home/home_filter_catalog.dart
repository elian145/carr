part of 'home_flow.dart';

mixin _HomePageFilterCatalog on _HomePageFetch {
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
    return engineSizes;
  }

  List<String> getAvailableConditions() => conditions;

  List<String> getAvailableBodyTypes() => bodyTypes;

  List<String> getAvailableTransmissions() => transmissions
      .where((t) => t == 'Any' || !_isExcludedTransmissionFilter(t))
      .toList();

  List<String> getAvailableFuelTypes() => fuelTypes;

  List<String> getAvailableDriveTypes() => driveTypes;

  List<String> getAvailableCylinderCounts() {
    final mot = _catalogMotorFilterOptions();
    if (mot != null) {
      if (mot.cylinders.isNotEmpty) {
        return ['Any', ...mot.cylinders];
      }
      return const ['Any'];
    }
    return cylinderCounts;
  }

  List<String> getAvailableSeatings() => seatings;

  List<String> getAvailableColors() => colors;

  // Helper method to get a valid drive type value for dropdown (dropdown uses '' for Any)
  String? _getValidDriveTypeValue() {
    return homeValidDropdownSelection(
      selected: selectedDriveType,
      available: getAvailableDriveTypes(),
    );
  }

  String _getValidRegionSpecsValue() {
    return homeFilterNormalizeRegionSpecs(selectedRegionSpecs) ?? '';
  }

  String? _getValidFuelTypeValue() {
    return homeValidDropdownSelection(
      selected: selectedFuelType,
      available: getAvailableFuelTypes(),
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
