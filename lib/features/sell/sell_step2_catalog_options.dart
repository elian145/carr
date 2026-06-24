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
    final o = _catalogSellOpts;
    if (o == null || o.bodyTypes.isEmpty) return bodyTypes;
    final f = bodyTypes.where((e) => o.bodyTypes.contains(e)).toList();
    return f.isEmpty ? bodyTypes : f;
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
    final o = _catalogSellOpts;
    if (o == null || o.transmissions.isEmpty) return transmissions;
    final f = transmissions.where((e) => o.transmissions.contains(e)).toList();
    return f.isEmpty ? transmissions : f;
  }

  List<String> getAvailableFuelTypes() {
    final online = _onlineMultiFromCarData('_online_opts_fuel');
    if (online != null) return online;
    final o = _catalogSellOpts;
    if (o == null || o.fuelTypes.isEmpty) return fuelTypes;
    final f = fuelTypes.where((e) => o.fuelTypes.contains(e)).toList();
    return f.isEmpty ? fuelTypes : f;
  }

  List<String> getAvailableDriveTypes() {
    final online = _onlineMultiFromCarData('_online_opts_drive');
    if (online != null) return online;
    final o = _catalogSellOpts;
    if (o == null || o.driveTypes.isEmpty) return driveTypes;
    final f = driveTypes.where((e) => o.driveTypes.contains(e)).toList();
    return f.isEmpty ? driveTypes : f;
  }

  List<String> getAvailableSeatings() {
    final online = _onlineMultiFromCarData('_online_opts_seating');
    if (online != null) return online;
    final o = _catalogSellOpts;
    if (o == null || o.seatings.isEmpty) return seatings;
    final f = seatings.where((e) => o.seatings.contains(e)).toList();
    return f.isEmpty ? seatings : f;
  }

  List<String> getAvailableEngineSizes() {
    final onlineRaw = _onlineMultiFromCarData('_online_opts_engine_size');
    if (onlineRaw != null) {
      final online = onlineRaw.map((e) => e.toString().trim()).where((s) {
        final x = OnlineSpecVariant.parseLeadingEngineLiters(s);
        return x != null && x > 0.001;
      }).toList();
      if (online.isEmpty) {
        // Bad API data (e.g. 0.0 L) — use full list like no-online.
      } else if (online.length == 1) {
        return online;
      } else {
        return <String>['Any', ...online];
      }
    }
    final o = _catalogSellOpts;
    if (o == null || o.engineSizes.isEmpty) return engineSizes;
    final f = engineSizes
        .where((e) => e == 'Any' || o.engineSizes.contains(e))
        .toList();
    final concrete = f.where((e) => e != 'Any').toList();
    if (concrete.length == 1) {
      return concrete;
    }
    if (f.length <= 1) {
      return engineSizes;
    }
    return f;
  }

  List<String> getAvailableCylinderCounts() {
    final online = _onlineMultiFromCarData('_online_opts_cylinder');
    if (online != null) return online;
    final o = _catalogSellOpts;
    if (o == null || o.cylinderCounts.isEmpty) return cylinderCounts;
    final f = cylinderCounts
        .where((e) => o.cylinderCounts.contains(e))
        .toList();
    return f.isEmpty ? cylinderCounts : f;
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
      default:
        return 'fwd';
    }
  }

  String? _sellStep2BodyLabelToApi(String? label) {
    if (label == null) return null;
    const apis = ['sedan', 'suv', 'hatchback', 'coupe', 'pickup', 'van'];
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

  void _applyOnlineVariantToSellStep2(OnlineSpecVariant v) {
    if (v.engineSizeLiters != null && !isEngineSizeManualInput) {
      // Keep suffix (T/D/TD) for display; submit parses leading liters.
      selectedEngineSize =
          '${v.engineSizeLiters!.toStringAsFixed(1)}${v.displacementSuffix}';
    }
    if (v.cylinderCount != null) {
      selectedCylinderCount = '${v.cylinderCount}';
    }
    if (v.transmission != null) {
      selectedTransmission = sellFlowTransmissionLabel(v.transmission!);
    }
    if (v.drivetrain != null) {
      selectedDriveType = sellFlowDriveLabel(v.drivetrain!);
    }
    if (v.bodyType != null) {
      selectedBodyType = sellFlowBodyLabel(v.bodyType!);
    }
    final fuelApi = v.fuelType ?? v.engineType;
    if (fuelApi != null) {
      selectedFuelType = sellFlowFuelLabel(fuelApi);
    }
    if (v.seating != null) {
      selectedSeating =
          sellFlowNearestSeatingLabel(v.seating) ?? '${v.seating}';
    }
  }

  /// When [carData] has multiple catalog spec variants, align fields to one matching row.
  void _syncStep2ToOnlineVariant(Set<String> anchors) {
    final vs = _onlineSpecVariantsFromParent();
    if (vs == null) return;
    final eng = isEngineSizeManualInput
        ? null
        : OnlineSpecVariant.parseLeadingEngineLiters(selectedEngineSize ?? '');
    final m = OnlineSpecVariant.matchBestAnchored(
      vs,
      anchors,
      engineLiters: eng,
      cylinders: int.tryParse((selectedCylinderCount ?? '').trim()),
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
    if (m != null) _applyOnlineVariantToSellStep2(m);
  }

  void _syncStep2DraftToParent() {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    parentState.carData['mileage'] = selectedMileage;
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
    parentState.carData['cylinder_count'] = selectedCylinderCount;
    parentState.carData['title_status'] = selectedTitleStatus;
    parentState.carData['damaged_parts'] = selectedDamagedParts;
    final vinText = _vinController.text.trim();
    selectedVin = vinText.isNotEmpty ? vinText : null;
    parentState.carData['vin'] = selectedVin;
    unawaited(parentState._saveSellDraftSnapshot());
  }

  Color _colorFromName(String colorName) {
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
        return const Color(0xFFF5F5DC);
      case 'gold':
        return const Color(0xFFFFD700);
      default:
        return Colors.grey;
    }
  }
}
