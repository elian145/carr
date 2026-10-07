part of 'sell_flow.dart';

mixin _SellStep2CatalogOptions on _SellStep2Fields {
  List<String>? _onlineMultiFromCarData(String key) {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final raw = parent?.carData[key];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return null;
  }

  // Helpers to mirror search page availability with simple defaults
  List<String> getAvailableBodyTypes() {
    final online = _onlineMultiFromCarData('_online_opts_body');
    if (online != null) return online;
    return narrowOptionsToCatalog(bodyTypes, _catalogSellOpts?.bodyTypes);
  }

  List<String> getAvailableColors() {
    return colors;
  }

  // Availability helpers aligned with More Filters (simple pass-throughs here)
  List<String> getAvailableConditions() {
    return conditions;
  }

  List<String> getAvailableTransmissions() {
    final online = _onlineMultiFromCarData('_online_opts_transmission');
    if (online != null) return online;
    return narrowOptionsToCatalog(
      transmissions,
      _catalogSellOpts?.transmissions,
    );
  }

  List<String> getAvailableFuelTypes() {
    final online = _onlineMultiFromCarData('_online_opts_fuel');
    if (online != null) return online;
    return narrowOptionsToCatalog(fuelTypes, _catalogSellOpts?.fuelTypes);
  }

  List<String> getAvailableDriveTypes() {
    final online = _onlineMultiFromCarData('_online_opts_drive');
    if (online != null) return online;
    return narrowOptionsToCatalog(driveTypes, _catalogSellOpts?.driveTypes);
  }

  List<String> getAvailableSeatings() {
    final online = _onlineMultiFromCarData('_online_opts_seating');
    if (online != null) return online;
    return narrowOptionsToCatalog(seatings, _catalogSellOpts?.seatings);
  }

  List<String> getAvailableEngineSizes() {
    final onlineRaw = _onlineMultiFromCarData('_online_opts_engine_size');
    if (onlineRaw != null) {
      final online = onlineRaw.map((e) => e.toString().trim()).where((s) {
        final x = OnlineSpecVariant.parseLeadingEngineLiters(s);
        return x != null && x > 0.001;
      }).toList();
      if (online.isEmpty) {
        // Bad API data (e.g. 0.0 L) — use full catalog list like no-online.
      } else if (online.length == 1) {
        return online;
      } else {
        return <String>['Any', ...online];
      }
    }
    final o = _catalogSellOpts;
    if (o != null && o.engineSizes.isNotEmpty) {
      final catalog = sortCatalogEngineSizeLabels(o.engineSizes);
      if (catalog.length == 1) return catalog;
      return <String>['Any', ...catalog];
    }
    return engineSizeFilterOptionsFromCatalog(_specIdx);
  }

  List<String> getAvailableCylinderCounts() {
    final online = _onlineMultiFromCarData('_online_opts_cylinder');
    if (online != null) return online;
    // The generic ladder stays 3-12; counts the approved IQ overlay explicitly
    // supplied for this model (e.g. 2 or 16) are offered even outside it.
    return narrowCylinderOptionsToCatalog(
      cylinderCounts,
      _catalogSellOpts?.cylinderCounts,
      _catalogSellOpts?.iqCylinderCounts,
    );
  }

  List<OnlineSpecVariant>? _onlineSpecVariantsFromParent() {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final raw = parent?.carData[_kOnlineSpecVariantsKey];
    if (raw is! List || raw.isEmpty) return null;
    final out = <OnlineSpecVariant>[];
    for (final e in raw) {
      if (e is Map) {
        out.add(OnlineSpecVariant.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out.isEmpty ? null : out;
  }

  String? _sellStep2TransmissionLabelToApi(String? label) {
    if (label == null) return null;
    return label.toLowerCase().contains('manual') ? 'manual' : 'automatic';
  }

  String? _sellStep2DriveLabelToApi(String? label) {
    if (label == null) return null;
    switch (label.toUpperCase()) {
      case 'RWD':
        return 'rwd';
      case 'AWD':
        return 'awd';
      case '4WD':
        return '4wd';
      case 'FWD':
        return 'fwd';
      default:
        // Unknown label: no drivetrain evidence (never silently FWD).
        return null;
    }
  }

  String? _sellStep2BodyLabelToApi(String? label) {
    if (label == null) return null;
    const apis = [
      'sedan',
      'suv',
      'hatchback',
      'coupe',
      'pickup',
      'wagon',
      'convertible',
      'minivan',
      'van',
    ];
    for (final a in apis) {
      if (sellFlowBodyLabel(a) == label) return a;
    }
    return null;
  }

  String? _sellStep2FuelApiForMatch(
    List<OnlineSpecVariant> vs,
    String? displayLabel,
  ) {
    if (displayLabel == null || displayLabel.isEmpty) return null;
    for (final v in vs) {
      final f = v.fuelType ?? v.engineType;
      if (f != null && sellFlowFuelLabel(f) == displayLabel) return f;
    }
    switch (displayLabel) {
      case 'Diesel':
        return 'diesel';
      case 'Electric':
        return 'electric';
      case 'Hybrid':
        return 'hybrid';
      case 'Plug-in Hybrid':
        return 'plug-in hybrid';
      default:
        return 'gasoline';
    }
  }

  int? _sellStep2CurrentSeatingInt() {
    final s = selectedSeating?.trim();
    if (s == null || s.isEmpty) return null;
    return int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));
  }

  String? _sellStep2FuelKeyOfRow(OnlineSpecVariant v) {
    final f = (v.fuelType ?? v.engineType)?.trim();
    if (f == null || f.isEmpty) return null;
    return sellFlowFuelLabel(f).toLowerCase();
  }

  /// ONE deterministic reconciliation pass for the linked engine / cylinders /
  /// fuel fields after the user changed [changed] (see [SellSpecReconciler]).
  ///
  /// Relationships come only from the CarNet rows scoped to the selected
  /// vehicle + year (`_online_spec_variants`); the approved IQ model-level lists
  /// only widen the available options and never create a combination. The field
  /// the user just changed is kept, other fields stay while compatible, and the
  /// engine label is never rewritten except to another AVAILABLE label when the
  /// user changed cylinders / fuel and the current engine contradicts it. It
  /// writes plain state only (no callbacks), so it cannot loop.
  bool _reconcileSellSpecs(SellSpecField changed) {
    final rows = _onlineSpecVariantsFromParent();
    if (rows == null) return false;
    // A hand-typed engine is not a catalog label: never moved by the resolver.
    if (isEngineSizeManualInput && changed != SellSpecField.engine) {
      return false;
    }
    final available = getAvailableEngineSizes().where((e) => e != 'Any');
    final fuelLabel = selectedFuelType?.trim();
    final cur = SellSpecSelection(
      engine: (selectedEngineSize ?? '').trim().isEmpty
          ? null
          : selectedEngineSize!.trim(),
      cylinders: int.tryParse((selectedCylinderCount ?? '').trim()),
      fuel: fuelLabel == null || fuelLabel.isEmpty
          ? null
          : fuelLabel.toLowerCase(),
    );
    final next = SellSpecReconciler(
      rows: rows,
      availableEngines: available,
      fuelKeyOf: _sellStep2FuelKeyOfRow,
    ).reconcile(cur, changed);
    var changedAny = false;
    if (next.engine != cur.engine &&
        next.engine != null &&
        changed != SellSpecField.engine &&
        available.contains(next.engine)) {
      selectedEngineSize = next.engine;
      changedAny = true;
    }
    if (next.cylinders != cur.cylinders && next.cylinders != null) {
      final s = '${next.cylinders}';
      if (changed != SellSpecField.cylinders &&
          getAvailableCylinderCounts().contains(s)) {
        selectedCylinderCount = s;
        changedAny = true;
      }
    }
    if (next.fuel != cur.fuel && next.fuel != null) {
      final label = sellFlowFuelLabel(next.fuel!);
      if (changed != SellSpecField.fuel &&
          getAvailableFuelTypes().contains(label)) {
        selectedFuelType = label;
        changedAny = true;
      }
    }
    return changedAny;
  }

  /// Engine selected / restored: keeps the exact label and applies its trusted
  /// cylinder count and fuel (see [_reconcileSellSpecs]).
  bool _applyTrustedCylinderForSelectedEngine() {
    if (isEngineSizeManualInput) return false;
    return _reconcileSellSpecs(SellSpecField.engine);
  }

  /// A matched catalog row may fill the remaining spec fields (transmission,
  /// drivetrain, body, seating, and fuel only while unset), but it NEVER writes
  /// [selectedEngineSize] or [selectedCylinderCount] (those are owned by
  /// [_reconcileSellSpecs]). Unknown row values leave the field untouched.
  void _applyOnlineVariantToSellStep2(
    OnlineSpecVariant v,
    List<OnlineSpecVariant> scope,
  ) {
    if (v.transmission != null) {
      selectedTransmission = sellFlowTransmissionLabel(v.transmission!);
    }
    final driveLabel = sellFlowDriveLabel(v.drivetrain);
    if (driveLabel != null) selectedDriveType = driveLabel;
    final bodyLabel = sellFlowBodyLabel(v.bodyType);
    if (bodyLabel != null) selectedBodyType = bodyLabel;
    // Fuel is reconciled by [_reconcileSellSpecs]; a row only fills it when the
    // user has not chosen one (never overrides a chosen / reconciled fuel).
    // Only UNIQUE trusted evidence may fill it: every row in [scope] must agree
    // on one fuel (a plug-in hybrid labelled "Electric" never counts as a pure
    // electric, see [SellSpecReconciler.fuelKeysOfRows]).
    final fuelApi = v.fuelType ?? v.engineType;
    if (fuelApi != null && (selectedFuelType ?? '').isEmpty) {
      final keys = SellSpecReconciler.fuelKeysOfRows(
        scope,
        _sellStep2FuelKeyOfRow,
      );
      if (keys.length == 1 && keys.first == _sellStep2FuelKeyOfRow(v)) {
        selectedFuelType = sellFlowFuelLabel(fuelApi);
      }
    }
    if (v.seating != null) {
      selectedSeating =
          sellFlowNearestSeatingLabel(v.seating) ?? '${v.seating}';
    }
  }

  /// When [carData] has multiple catalog spec variants, align fields to one matching row.
  String? _onlineVariantEngineLabel(OnlineSpecVariant v) {
    final l = v.engineSizeLiters;
    if (l == null || l <= 0.001) return null;
    return '${l.toStringAsFixed(1)}${v.displacementSuffix}';
  }

  void _syncStep2ToOnlineVariant(Set<String> anchors) {
    final allVariants = _onlineSpecVariantsFromParent();
    if (allVariants == null) return;
    // Only a pick that is an exact CarNet row value may steer a row match. An
    // IQ-only engine ("3.0 T") or cylinder count has no CarNet row behind it, so
    // it must not borrow the row of a different engine (e.g. the plain 3.0).
    final engineLabel = (selectedEngineSize ?? '').trim();
    final engineIsRow = !isEngineSizeManualInput &&
        engineLabel.isNotEmpty &&
        allVariants.any((v) => _onlineVariantEngineLabel(v) == engineLabel);
    final cylInt = int.tryParse((selectedCylinderCount ?? '').trim());
    final cylIsRow =
        cylInt != null && allVariants.any((v) => v.cylinderCount == cylInt);
    if (anchors.contains('e') && !engineIsRow) return;
    if (anchors.contains('c') && !cylIsRow) return;
    final vs = anchors.contains('e')
        ? allVariants
            .where((v) => _onlineVariantEngineLabel(v) == engineLabel)
            .toList()
        : allVariants;
    final eng = engineIsRow
        ? OnlineSpecVariant.parseLeadingEngineLiters(engineLabel)
        : null;
    final m = OnlineSpecVariant.matchBestAnchored(
      vs,
      anchors,
      engineLiters: eng,
      cylinders: cylIsRow ? cylInt : null,
      transmission: _sellStep2TransmissionLabelToApi(selectedTransmission),
      drivetrain: _sellStep2DriveLabelToApi(selectedDriveType),
      bodyType: _sellStep2BodyLabelToApi(selectedBodyType),
      fuelType: _sellStep2FuelApiForMatch(vs, selectedFuelType),
      seating: _sellStep2CurrentSeatingInt(),
      currentTransmission: _sellStep2TransmissionLabelToApi(
        selectedTransmission,
      ),
      currentDrivetrain: _sellStep2DriveLabelToApi(selectedDriveType),
      currentSeating: _sellStep2CurrentSeatingInt(),
    );
    if (m != null) _applyOnlineVariantToSellStep2(m, vs);
  }

  void _syncStep2DraftToParent() {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    parentState.carData['mileage'] = selectedMileage;
    parentState.carData['mileage_unit'] = selectedMileageUnit;
    parentState.carData['condition'] = selectedCondition;
    parentState.carData['transmission'] = selectedTransmission;
    parentState.carData['fuel_type'] = selectedFuelType;
    parentState.carData['body_type'] = selectedBodyType;
    parentState.carData['color'] = selectedColor;
    parentState.carData['drive_type'] = selectedDriveType;
    parentState.carData['region_specs'] =
        selectedRegionSpecs?.trim().toLowerCase();
    parentState.carData['seating'] = selectedSeating;
    parentState.carData['engine_size'] = selectedEngineSize;
    // So a restored draft can tell a hand-typed size from a picker choice.
    parentState.carData['_engine_size_manual'] = isEngineSizeManualInput;
    parentState.carData['cylinder_count'] = selectedCylinderCount;
    parentState.carData['title_status'] = selectedTitleStatus;
    parentState.carData['damaged_parts'] = selectedDamagedParts;
    final vinText = _vinController.text.trim();
    selectedVin = vinText.isNotEmpty ? vinText : null;
    parentState.carData['vin'] = selectedVin;
    unawaited(parentState._saveSellDraftSnapshot());
  }
}
