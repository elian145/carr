part of 'sell_flow.dart';
class SellStep2Page extends StatefulWidget {
  const SellStep2Page({super.key, this.specsHydrateToken = ''});

  /// When catalog/online/AI specs timestamps change, state re-reads [carData] (covers off-screen step 2).
  final String specsHydrateToken;

  @override
  State<SellStep2Page> createState() => _SellStep2PageState();
}

class _SellStep2PageState extends State<SellStep2Page> {
  final _formKey = GlobalKey<FormState>();
  static const String _draftKey = 'legacy_sell_draft_step2_v1';
  String? selectedMileage;
  String? selectedCondition;
  String? selectedTransmission;
  String? selectedFuelType;
  String? selectedBodyType;
  String? selectedColor;
  String? selectedDriveType;

  /// Lowercase code sent as `region_specs` (see [kCarRegionSpecCodes]).
  String? selectedRegionSpecs;
  String? selectedSeating;
  String? selectedEngineSize;
  String? selectedCylinderCount;
  String? selectedTitleStatus;
  String? selectedDamagedParts;
  String? selectedVin;
  bool errMileage = false;
  bool errCondition = false;
  bool errTransmission = false;
  bool errFuelType = false;
  bool errBodyType = false;
  bool errColor = false;
  bool errDrive = false;
  bool errRegionSpecs = false;
  bool errSeating = false;
  bool errEngineSize = false;
  bool errCylinderCount = false;
  bool errTitle = false;
  bool errDamagedParts = false;
  bool isMileageManualInput = false;
  bool isEngineSizeManualInput = false;

  /// Bumps when step 1 applies catalog/online specs so we re-hydrate when returning to step 2.
  int? _lastSpecsHydrateStamp;

  CarSpecIndex? _specIdx;
  CatalogSellFieldOptions? _catalogSellOpts;

  // Focus nodes for keyboard management
  final FocusNode _mileageFocusNode = FocusNode();
  final FocusNode _engineSizeFocusNode = FocusNode();

  // Controllers for manual inputs
  late TextEditingController _mileageController;
  late TextEditingController _engineSizeController;
  late TextEditingController _vinController;

  @override
  void initState() {
    super.initState();
    _mileageController = TextEditingController();
    _engineSizeController = TextEditingController();
    _vinController = TextEditingController();
    _resetStep2();
    _hydrateFromParentCarData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _hydrateFromParentCarData(force: true);
    });
    CarSpecIndex.load().then((idx) {
      if (!mounted) return;
      setState(() {
        _specIdx = idx;
        _refreshCatalogOptsFromParent();
      });
    });
  }

  @override
  void didUpdateWidget(covariant SellStep2Page oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.specsHydrateToken != oldWidget.specsHydrateToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _hydrateFromParentCarData(force: true);
      });
    }
  }

  CatalogSellFieldOptions? _computeCatalogSellOpts(
    Map<String, dynamic>? carData,
    CarSpecIndex? idx,
  ) {
    if (carData == null || idx == null) return null;
    final b = carData['brand']?.toString().trim() ?? '';
    final m = carData['model']?.toString().trim() ?? '';
    final y = int.tryParse(carData['year']?.toString().trim() ?? '');
    if (b.isEmpty || m.isEmpty || y == null) return null;
    if (!idx.hasCoverage(b, m)) return null;
    return idx.sellFieldOptionsUnion(
      b,
      m,
      CarSpecIndex.catalogAutofillModelOnly,
      y,
    );
  }

  void _refreshCatalogOptsFromParent() {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    _catalogSellOpts = _computeCatalogSellOpts(parent?.carData, _specIdx);
  }

  void _hydrateFromParentCarData({bool force = false}) {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    _refreshCatalogOptsFromParent();
    if (parent == null) return;

    final rawCatalog = parent.carData['_catalog_specs_applied'];
    final rawOnline = parent.carData['_online_specs_applied'];
    final catalogStamp = rawCatalog is int
        ? rawCatalog
        : int.tryParse(rawCatalog?.toString() ?? '');
    final onlineStamp = rawOnline is int
        ? rawOnline
        : int.tryParse(rawOnline?.toString() ?? '');
    int? stamp;
    for (final x in [catalogStamp, onlineStamp]) {
      if (x == null) continue;
      if (stamp == null || x > stamp) stamp = x;
    }

    if (!force) {
      if (stamp == null || stamp == _lastSpecsHydrateStamp) return;
    } else if (stamp == null) {
      // Force hydration from parent snapshot even without explicit stamp.
      // This covers first-time step open when values are already in carData.
    }

    _lastSpecsHydrateStamp = stamp ?? _lastSpecsHydrateStamp;
    final d = parent.carData;
    void take(String key, void Function(String v) apply) {
      final v = d[key]?.toString().trim();
      if (v != null && v.isNotEmpty) apply(v);
    }

    void takeScalarOrOnlineOpt(
      String scalarKey,
      String optKey,
      void Function(String v) apply,
    ) {
      final direct = d[scalarKey]?.toString().trim();
      if (direct != null && direct.isNotEmpty) {
        apply(direct);
        return;
      }
      final raw = d[optKey];
      if (raw is List && raw.isNotEmpty) {
        final s = raw.first.toString().trim();
        if (s.isNotEmpty) apply(s);
      }
    }

    setState(() {
      selectedMileage = d['mileage']?.toString();
      selectedCondition = d['condition']?.toString();
      takeScalarOrOnlineOpt(
        'transmission',
        '_online_opts_transmission',
        (v) => selectedTransmission = v,
      );
      takeScalarOrOnlineOpt(
        'fuel_type',
        '_online_opts_fuel',
        (v) => selectedFuelType = v,
      );
      takeScalarOrOnlineOpt(
        'body_type',
        '_online_opts_body',
        (v) => selectedBodyType = v,
      );
      takeScalarOrOnlineOpt(
        'drive_type',
        '_online_opts_drive',
        (v) => selectedDriveType = v,
      );
      take('region_specs', (v) {
        final c = v.trim().toLowerCase();
        if (isValidCarRegionSpecCode(c)) selectedRegionSpecs = c;
      });
      takeScalarOrOnlineOpt(
        'seating',
        '_online_opts_seating',
        (v) => selectedSeating = v,
      );
      selectedColor = d['color']?.toString();
      final rawTitle = d['title_status']?.toString().trim();
      if (rawTitle != null && rawTitle.isNotEmpty) {
        selectedTitleStatus = rawTitle;
      }
      selectedDamagedParts = d['damaged_parts']?.toString();
      final rawVin = d['vin']?.toString().trim();
      if (rawVin != null && rawVin.isNotEmpty) {
        selectedVin = rawVin;
        _vinController.text = rawVin;
      }
      takeScalarOrOnlineOpt(
        'cylinder_count',
        '_online_opts_cylinder',
        (v) => selectedCylinderCount = v,
      );
      String? es = d['engine_size']?.toString().trim();
      if (es == null || es.isEmpty) {
        final raw = d['_online_opts_engine_size'];
        if (raw is List && raw.isNotEmpty) {
          for (final c in raw) {
            final t = c.toString().trim();
            final lit = OnlineSpecVariant.parseLeadingEngineLiters(t);
            if (lit != null && lit > 0.001) {
              es = t;
              break;
            }
          }
        }
      }
      if (es != null && es.isNotEmpty) {
        final lit = OnlineSpecVariant.parseLeadingEngineLiters(es);
        if (lit == null || lit <= 0.001) {
          es = null;
        }
      }
      if (es != null && es.isNotEmpty) {
        // Prefer staying in picker mode by snapping to an available option
        // based on leading liters (preserves suffix labels like "T").
        final available = getAvailableEngineSizes()
            .where((e) => e != 'Any')
            .map((e) => e.trim())
            .toList();
        String? resolved = available.contains(es) ? es : null;
        final lit = OnlineSpecVariant.parseLeadingEngineLiters(es);
        if (resolved == null && lit != null) {
          for (final opt in available) {
            final oL = OnlineSpecVariant.parseLeadingEngineLiters(opt);
            if (oL != null && (oL - lit).abs() < 0.06) {
              resolved = opt;
              break;
            }
          }
        }

        if (resolved != null && resolved.isNotEmpty) {
          selectedEngineSize = resolved;
          isEngineSizeManualInput = false;
          _engineSizeController.text =
              (OnlineSpecVariant.parseLeadingEngineLiters(resolved)
                      ?.toStringAsFixed(1) ??
                  '');
        } else {
          // Unknown label; fall back to manual input.
          isEngineSizeManualInput = true;
          _engineSizeController.text =
              (OnlineSpecVariant.parseLeadingEngineLiters(es)
                      ?.toStringAsFixed(1) ??
                  es);
          selectedEngineSize = _engineSizeController.text.trim().isEmpty
              ? es
              : _engineSizeController.text.trim();
        }
      }
    });
  }

  @override
  void dispose() {
    if (!LegacySellDraftPrefs.suppressPersist) {
      unawaited(_saveDraft());
    }
    _mileageFocusNode.dispose();
    _engineSizeFocusNode.dispose();
    _mileageController.dispose();
    _engineSizeController.dispose();
    _vinController.dispose();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _draftKey,
        json.encode(<String, dynamic>{
          'selectedMileage': selectedMileage,
          'selectedCondition': selectedCondition,
          'selectedTransmission': selectedTransmission,
          'selectedFuelType': selectedFuelType,
          'selectedBodyType': selectedBodyType,
          'selectedColor': selectedColor,
          'selectedDriveType': selectedDriveType,
          'selectedRegionSpecs': selectedRegionSpecs,
          'selectedSeating': selectedSeating,
          'selectedEngineSize': selectedEngineSize,
          'selectedCylinderCount': selectedCylinderCount,
          'selectedTitleStatus': selectedTitleStatus,
          'selectedDamagedParts': selectedDamagedParts,
          'selectedVin': selectedVin,
          'errMileage': errMileage,
          'errCondition': errCondition,
          'errTransmission': errTransmission,
          'errFuelType': errFuelType,
          'errBodyType': errBodyType,
          'errColor': errColor,
          'errDrive': errDrive,
          'errRegionSpecs': errRegionSpecs,
          'errSeating': errSeating,
          'errEngineSize': errEngineSize,
          'errCylinderCount': errCylinderCount,
          'errTitle': errTitle,
          'errDamagedParts': errDamagedParts,
          'isMileageManualInput': isMileageManualInput,
          'isEngineSizeManualInput': isEngineSizeManualInput,
          'mileageControllerText': _mileageController.text,
          'engineSizeControllerText': _engineSizeController.text,
        }),
      );
    } catch (e, st) { logNonFatal(e, st); }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hydrateFromParentCarData();
  }

  void _resetStep2() {
    selectedMileage = null;
    selectedCondition = null;
    selectedTransmission = null;
    selectedFuelType = null;
    selectedBodyType = null;
    selectedColor = null;
    selectedDriveType = null;
    selectedRegionSpecs = null;
    selectedSeating = null;
    selectedEngineSize = null;
    selectedCylinderCount = null;
    selectedTitleStatus = null;
    selectedDamagedParts = null;
    selectedVin = null;
  }

  void _dismissKeyboard() {
    // Clear focus from mileage field
    _mileageFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  final List<String> conditions = ['New', 'Used'];
  final List<String> transmissions = ['Automatic', 'Manual'];
  final List<String> fuelTypes = [
    'Gasoline',
    'Diesel',
    'Electric',
    'Hybrid',
    'Plug-in Hybrid',
  ];
  final List<String> bodyTypes = [
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
    'Black',
    'White',
    'Silver',
    'Gray',
    'Red',
    'Blue',
    'Green',
    'Brown',
    'Gold',
    'Other',
  ];
  final List<String> driveTypes = ['FWD', 'RWD', 'AWD', '4WD'];
  final List<String> seatings = ['2', '4', '5', '6', '7', '8'];
  // Same engine size options as More Filters (0.5 to 16.0 step 0.1)
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
  final List<String> cylinderCounts = ['3', '4', '5', '6', '8', '10', '12'];
  final List<String> titleStatuses = ['Clean', 'Damaged'];

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

  Future<String?> _pickFromList(String title, List<String> options) async {
    return await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      pageBuilder: (context, a1, a2) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return Dialog(
              backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 420,
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: Color(0xFFFF6B00),
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    SizedBox(
                      height: 420,
                      child: ListView.separated(
                        itemCount: options.length,
                        separatorBuilder: (context, index) => SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final value = options[index];
                          final lowerTitle = title.toLowerCase();
                          String displayText = value;
                          final bool isNumeric = RegExp(
                            r'^[0-9]+(\.[0-9]+)?$',
                          ).hasMatch(value);
                          if (lowerTitle.contains('price')) {
                            displayText = _formatCurrencyGlobal(context, value);
                          } else if (lowerTitle.contains('mileage') &&
                              isNumeric) {
                            final nf = _decimalFormatterGlobal(context);
                            displayText =
                                '${_localizeDigitsGlobal(context, nf.format(num.tryParse(value) ?? 0))} ${AppLocalizations.of(context)!.unit_km}';
                          } else if (lowerTitle.contains('year') && isNumeric) {
                            displayText = _localizeDigitsGlobal(context, value);
                          } else if (lowerTitle.contains('seating') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} ${_trLegacyText(context, 'seats', ar: 'مقاعد', ku: 'دانیشتن')}';
                          } else if (lowerTitle.contains('cylinder') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} ${_trLegacyText(context, 'cylinders', ar: 'أسطوانات', ku: 'سیلەندەر')}';
                          } else if (lowerTitle.contains('region') &&
                              isValidCarRegionSpecCode(value)) {
                            displayText =
                                carRegionSpecDisplayLabelLocalized(context, value);
                          } else if (lowerTitle.contains('engine') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} L';
                          } else if (value == 'Any') {
                            displayText = AppLocalizations.of(
                              context,
                            )!.anyOption;
                          } else {
                            final translated = _translateValueGlobal(
                              context,
                              value,
                            );
                            if (translated != null) displayText = translated;
                          }
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(context, value),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.06),
                                    Colors.white.withValues(alpha: 0.02),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayText,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.white70,
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
      transitionDuration: Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF6B00).withValues(alpha: 0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFFF6B00).withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.settings, size: 48, color: Color(0xFFFF6B00)),
                  SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)!.carDetailsTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.carDetailsSubtitle,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Mileage (Modal or Manual Input)
            Row(
              children: [
                Expanded(
                  child: isMileageManualInput
                      ? TextFormField(
                          focusNode: _mileageFocusNode,
                          controller: _mileageController,
                          decoration: InputDecoration(
                            labelText:
                                '${AppLocalizations.of(context)!.mileageKmLabel} *',
                            hintText: AppLocalizations.of(
                              context,
                            )!.enterMileage,
                            filled: true,
                            fillColor: _sellFlowManualFieldFill(context),
                            labelStyle: _sellFlowManualFieldLabelStyle(context),
                            hintStyle: _sellFlowManualFieldHintStyle(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.red),
                            ),
                          ),
                          style: _sellFlowManualFieldTextStyle(context),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            setState(() {
                              selectedMileage = value.isEmpty ? null : value;
                            });
                            _syncStep2DraftToParent();
                          },
                          validator: (value) {
                            final l = AppLocalizations.of(context)!;
                            if (value == null || value.isEmpty) {
                              return l.pleaseEnterMileage;
                            }
                            final mileage = int.tryParse(value);
                            if (mileage == null) return l.invalidMileage;
                            if (mileage < 0) {
                              return l.mileageNegative;
                            }
                            return null;
                          },
                        )
                      : FormField<String>(
                          validator: (_) =>
                              (selectedMileage == null ||
                                  selectedMileage!.isEmpty)
                              ? AppLocalizations.of(
                                  context,
                                )!.pleaseSelectMileage
                              : null,
                          builder: (state) => GestureDetector(
                            onTap: () async {
                              final miles = [
                                ...[
                                  for (int m = 0; m <= 100000; m += 1000)
                                    m.toString(),
                                ],
                                ...[
                                  for (int m = 105000; m <= 300000; m += 5000)
                                    m.toString(),
                                ],
                              ];
                              final choice = await _pickFromList(
                                AppLocalizations.of(context)!.mileageKmLabel,
                                miles,
                              );
                              if (choice != null) {
                                setState(() => selectedMileage = choice);
                                _syncStep2DraftToParent();
                              }
                            },
                            child: buildFancySelector(
                              context,
                              icon: Icons.speed,
                              label:
                                  '${AppLocalizations.of(context)!.mileageKmLabel} *',
                              value: selectedMileage != null
                                  ? ('${_localizeDigitsGlobal(context, _decimalFormatterGlobal(context).format(int.tryParse(selectedMileage!) ?? 0))} ${AppLocalizations.of(context)!.unit_km}')
                                  : null,
                              isError:
                                  errMileage &&
                                  (selectedMileage == null ||
                                      selectedMileage!.isEmpty),
                            ),
                          ),
                        ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    if (isMileageManualInput) {
                      // If in manual input mode, confirm the mileage and dismiss keyboard
                      _mileageFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        isMileageManualInput = false;
                        // Ensure the selectedMileage is properly set
                        if (_mileageController.text.isNotEmpty) {
                          selectedMileage = _mileageController.text;
                        }
                      });
                      _syncStep2DraftToParent();
                    } else {
                      // If in dropdown mode, switch to manual input
                      setState(() {
                        isMileageManualInput = true;
                        // Clear the controller to start fresh
                        _mileageController.clear();
                        selectedMileage = null;
                      });
                      _syncStep2DraftToParent();
                    }
                  },
                  icon: Icon(
                    isMileageManualInput ? Icons.check : Icons.edit,
                    color: Color(0xFFFF6B00),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  tooltip: isMileageManualInput
                      ? AppLocalizations.of(context)!.confirmMileage
                      : AppLocalizations.of(context)!.typeManually,
                ),
              ],
            ),
            SizedBox(height: 16),

            // Condition (Modal)
            FormField<String>(
              validator: (_) => selectedCondition == null
                  ? AppLocalizations.of(context)!.pleaseSelectCondition
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.conditionLabel,
                    getAvailableConditions(),
                  );
                  if (choice != null) {
                    setState(() => selectedCondition = choice);
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.check_circle,
                  label: '${AppLocalizations.of(context)!.conditionLabel} *',
                  value: _translateValueGlobal(context, selectedCondition),
                  isError:
                      errCondition &&
                      (selectedCondition == null || selectedCondition!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Transmission (Modal)
            FormField<String>(
              validator: (_) => selectedTransmission == null
                  ? AppLocalizations.of(context)!.pleaseSelectTransmission
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.transmissionLabel,
                    getAvailableTransmissions(),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedTransmission = choice;
                      _syncStep2ToOnlineVariant({'tr'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.settings,
                  label: '${AppLocalizations.of(context)!.transmissionLabel} *',
                  value: _translateValueGlobal(context, selectedTransmission),
                  isError:
                      errTransmission &&
                      (selectedTransmission == null ||
                          selectedTransmission!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Fuel Type (Modal)
            FormField<String>(
              validator: (_) => selectedFuelType == null
                  ? AppLocalizations.of(context)!.pleaseSelectFuelType
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.fuelTypeLabel,
                    getAvailableFuelTypes(),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedFuelType = choice;
                      _syncStep2ToOnlineVariant({'fuel'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.local_gas_station,
                  label: '${AppLocalizations.of(context)!.fuelTypeLabel} *',
                  value: _translateValueGlobal(context, selectedFuelType),
                  isError:
                      errFuelType &&
                      (selectedFuelType == null || selectedFuelType!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Body Type (Modal - grid like search)
            FormField<String>(
              validator: (_) => selectedBodyType == null
                  ? AppLocalizations.of(context)!.pleaseSelectBodyType
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          width: 400,
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
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
                                      color: Color(0xFFFF6B00),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              SizedBox(
                                height: 300,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: BouncingScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        childAspectRatio: 0.82,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                      ),
                                  itemCount: getAvailableBodyTypes().length,
                                  itemBuilder: (context, index) {
                                    final bodyTypeName =
                                        getAvailableBodyTypes()[index];
                                    final asset = _getBodyTypeAsset(
                                      bodyTypeName,
                                    );
                                    final bool isSelected =
                                        (selectedBodyType ?? '') ==
                                        bodyTypeName;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () =>
                                          Navigator.pop(context, bodyTypeName),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xFFFF6B00)
                                                : Colors.white24,
                                            width: isSelected ? 2 : 1,
                                          ),
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(
                                                      0xFFFF6B00,
                                                    ).withValues(alpha: 0.35),
                                                    blurRadius: 14,
                                                    spreadRadius: 1,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ]
                                              : [
                                                  const BoxShadow(
                                                    color: Colors.black54,
                                                    blurRadius: 10,
                                                    spreadRadius: 0,
                                                    offset: Offset(0, 3),
                                                  ),
                                                ],
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 56,
                                              height: 56,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? const Color(0xFFFF6B00)
                                                      : Colors.white24,
                                                  width: isSelected ? 2 : 1,
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
                                            const SizedBox(height: 8),
                                            Text(
                                              bodyTypeName == 'Any'
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
                                                    ? Colors.white
                                                    : Colors.white70,
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
                  if (choice != null) {
                    setState(() {
                      selectedBodyType = choice;
                      _syncStep2ToOnlineVariant({'body'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.directions_car,
                  label: '${AppLocalizations.of(context)!.bodyTypeLabel} *',
                  value: selectedBodyType == null
                      ? _tapToSelectTextGlobal(context)
                      : (_translateValueGlobal(context, selectedBodyType) ??
                          selectedBodyType),
                  isError:
                      errBodyType &&
                      (selectedBodyType == null || selectedBodyType!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Color (Modal - swatches like search)
            FormField<String>(
              validator: (_) => selectedColor == null
                  ? AppLocalizations.of(context)!.pleaseSelectColor
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          width: 400,
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppLocalizations.of(context)!.selectColor,
                                    style: GoogleFonts.orbitron(
                                      color: Color(0xFFFF6B00),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              SizedBox(
                                height: 300,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: BouncingScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        childAspectRatio: 1.2,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                      ),
                                  itemCount: getAvailableColors().length,
                                  itemBuilder: (context, index) {
                                    final colorName =
                                        getAvailableColors()[index];
                                    final colorValue = _colorFromName(
                                      colorName,
                                    );
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () =>
                                          Navigator.pop(context, colorName),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.white24,
                                          ),
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: colorValue,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.white24,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              _translateValueGlobal(
                                                    context,
                                                    colorName,
                                                  ) ??
                                                  colorName,
                                              style: GoogleFonts.orbitron(
                                                fontSize: 12,
                                                color: Colors.white,
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
                  if (choice != null) setState(() => selectedColor = choice);
                  if (choice != null) _syncStep2DraftToParent();
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.palette,
                  label: '${AppLocalizations.of(context)!.colorLabel} *',
                  value: selectedColor == null
                      ? _tapToSelectTextGlobal(context)
                      : (_translateValueGlobal(context, selectedColor) ??
                          selectedColor),
                  isError:
                      errColor &&
                      (selectedColor == null || selectedColor!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Drive Type (Modal)
            FormField<String>(
              validator: (_) => selectedDriveType == null
                  ? AppLocalizations.of(context)!.pleaseSelectDriveType
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.driveType,
                    getAvailableDriveTypes(),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedDriveType = choice;
                      _syncStep2ToOnlineVariant({'drv'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.directions,
                  label: '${AppLocalizations.of(context)!.driveType} *',
                  value: _translateValueGlobal(context, selectedDriveType),
                  isError:
                      errDrive &&
                      (selectedDriveType == null || selectedDriveType!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            FormField<String>(
              validator: (_) =>
                  (selectedRegionSpecs == null ||
                      !isValidCarRegionSpecCode(selectedRegionSpecs))
                  ? AppLocalizations.of(context)!.pleaseSelectRegionSpecs
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.regionSpecsLabel,
                    List<String>.from(kCarRegionSpecCodes),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedRegionSpecs = choice.trim().toLowerCase();
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.public,
                  label: '${AppLocalizations.of(context)!.regionSpecsLabel} *',
                  value: selectedRegionSpecs == null
                      ? null
                      : carRegionSpecDisplayLabelLocalized(
                          context,
                          selectedRegionSpecs!,
                        ),
                  isError:
                      errRegionSpecs &&
                      (selectedRegionSpecs == null ||
                          !isValidCarRegionSpecCode(selectedRegionSpecs)),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Seating (Modal)
            FormField<String>(
              validator: (_) => selectedSeating == null
                  ? AppLocalizations.of(context)!.pleaseSelectSeating
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.seating,
                    getAvailableSeatings().where((s) => s != 'Any').toList(),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedSeating = choice;
                      _syncStep2ToOnlineVariant({'seat'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.people,
                  label: '${AppLocalizations.of(context)!.seating} *',
                  value: selectedSeating == null
                      ? null
                      : ('${_localizeDigitsGlobal(context, selectedSeating!)} ${_trLegacyText(context, 'seats', ar: 'مقاعد', ku: 'دانیشتن')}'),
                  isError:
                      errSeating &&
                      (selectedSeating == null || selectedSeating!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Engine Size (Modal or Manual Input)
            Row(
              children: [
                Expanded(
                  child: isEngineSizeManualInput
                      ? TextFormField(
                          focusNode: _engineSizeFocusNode,
                          controller: _engineSizeController,
                          decoration: InputDecoration(
                            labelText:
                                '${AppLocalizations.of(context)!.engineSizeL} *',
                            hintText: AppLocalizations.of(
                              context,
                            )!.pleaseSelectEngineSize,
                            filled: true,
                            fillColor: _sellFlowManualFieldFill(context),
                            labelStyle: _sellFlowManualFieldLabelStyle(context),
                            hintStyle: _sellFlowManualFieldHintStyle(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.red),
                            ),
                            errorText: () {
                              if (!errEngineSize) return null;
                              final raw = _engineSizeController.text.trim();
                              final l = AppLocalizations.of(context)!;
                              if (raw.isEmpty) return l.pleaseSelectEngineSize;
                              final size = double.tryParse(raw);
                              if (size == null || size <= 0) {
                                return l.pleaseSelectEngineSize;
                              }
                              return null;
                            }(),
                          ),
                          style: _sellFlowManualFieldTextStyle(context),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            services.FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedEngineSize = value.isEmpty
                                  ? null
                                  : value.trim();
                              if (errEngineSize) errEngineSize = false;
                            });
                            _syncStep2DraftToParent();
                          },
                          validator: (value) {
                            final l = AppLocalizations.of(context)!;
                            if (value == null || value.isEmpty) {
                              return l.pleaseSelectEngineSize;
                            }
                            final size = double.tryParse(value);
                            if (size == null) return l.pleaseSelectEngineSize;
                            if (size <= 0) {
                              return l.pleaseSelectEngineSize;
                            }
                            return null;
                          },
                        )
                      : FormField<String>(
                          validator: (_) =>
                              (selectedEngineSize == null ||
                                  selectedEngineSize!.isEmpty)
                              ? AppLocalizations.of(
                                  context,
                                )!.pleaseSelectEngineSize
                              : null,
                          builder: (state) => GestureDetector(
                            onTap: () async {
                              final choice = await _pickFromList(
                                AppLocalizations.of(context)!.engineSizeL,
                                getAvailableEngineSizes()
                                    .where((e) => e != 'Any')
                                    .toList(),
                              );
                              if (choice != null) {
                                setState(() {
                                  selectedEngineSize = choice.replaceAll(
                                    ' L',
                                    '',
                                  );
                                  if (errEngineSize) errEngineSize = false;
                                  _syncStep2ToOnlineVariant({'e'});
                                });
                                _syncStep2DraftToParent();
                              }
                            },
                            child: buildFancySelector(
                              context,
                              icon: Icons.engineering,
                              label:
                                  '${AppLocalizations.of(context)!.engineSizeL} *',
                              value: selectedEngineSize == null
                                  ? null
                                  : _engineSizeSellRowLabel(
                                      context,
                                      selectedEngineSize!,
                                    ),
                              isError:
                                  errEngineSize &&
                                  (selectedEngineSize == null ||
                                      selectedEngineSize!.trim().isEmpty),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    if (isEngineSizeManualInput) {
                      // Confirm manual engine size and dismiss keyboard
                      _engineSizeFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        isEngineSizeManualInput = false;
                        if (_engineSizeController.text.isNotEmpty) {
                          selectedEngineSize = _engineSizeController.text
                              .trim();
                          _syncStep2ToOnlineVariant({'e'});
                        }
                      });
                      _syncStep2DraftToParent();
                    } else {
                      // Switch from modal picker to manual input
                      setState(() {
                        isEngineSizeManualInput = true;
                        _engineSizeController.clear();
                        selectedEngineSize = null;
                      });
                      _syncStep2DraftToParent();
                    }
                  },
                  icon: Icon(
                    isEngineSizeManualInput ? Icons.check : Icons.edit,
                    color: const Color(0xFFFF6B00),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  tooltip: isEngineSizeManualInput
                      ? AppLocalizations.of(context)!.confirmYear
                      : AppLocalizations.of(context)!.typeManually,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cylinder Count (Modal)
            FormField<String>(
              validator: (_) =>
                  (selectedCylinderCount == null ||
                      selectedCylinderCount!.trim().isEmpty)
                  ? AppLocalizations.of(context)!.pleaseSelectCylinderCount
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.cylinderCount,
                    getAvailableCylinderCounts()
                        .where((c) => c != 'Any')
                        .toList(),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedCylinderCount = choice.replaceAll(
                        ' cylinders',
                        '',
                      );
                      if (errCylinderCount) errCylinderCount = false;
                      _syncStep2ToOnlineVariant({'c'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.settings_input_component,
                  label: '${AppLocalizations.of(context)!.cylinderCount} *',
                  value: selectedCylinderCount == null
                      ? null
                      : ('${_localizeDigitsGlobal(context, selectedCylinderCount!)} ${_trLegacyText(context, 'cylinders', ar: 'أسطوانات', ku: 'سیلەندەر')}'),
                  isError:
                      errCylinderCount &&
                      (selectedCylinderCount == null ||
                          selectedCylinderCount!.trim().isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Title Status (Modal)
            FormField<String>(
              validator: (_) => selectedTitleStatus == null
                  ? AppLocalizations.of(context)!.titleStatus
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.titleStatus,
                    titleStatuses,
                  );
                  if (choice != null) {
                    setState(() {
                      selectedTitleStatus = choice;
                      if (choice != 'Damaged') selectedDamagedParts = null;
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.description,
                  label: '${AppLocalizations.of(context)!.titleStatus} *',
                  value: _translateValueGlobal(context, selectedTitleStatus),
                  isError:
                      errTitle &&
                      (selectedTitleStatus == null ||
                          (selectedTitleStatus ?? '').isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Damaged Parts modal
            if ((selectedTitleStatus ?? '').toLowerCase() == 'damaged')
              FormField<String>(
                builder: (state) => GestureDetector(
                  onTap: () async {
                    final nums = List.generate(20, (i) => (i + 1).toString());
                    final choice = await _pickFromList(
                      AppLocalizations.of(context)!.damagedParts,
                      nums,
                    );
                    if (choice != null) {
                      setState(() => selectedDamagedParts = choice);
                    _syncStep2DraftToParent();
                    }
                  },
                  child: buildFancySelector(
                    context,
                    icon: Icons.warning,
                    label: AppLocalizations.of(context)!.damagedParts,
                    value: selectedDamagedParts == null
                        ? null
                        : _localizeDigitsGlobal(context, selectedDamagedParts!),
                    isError:
                        errDamagedParts &&
                        (selectedDamagedParts == null ||
                            selectedDamagedParts!.isEmpty),
                  ),
                ),
              ),
            SizedBox(height: 16),

            // VIN (optional)
            Container(
              decoration: BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color(0xFFFF6B00).withValues(alpha: 0.3)),
              ),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: _vinController,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  icon: Icon(Icons.pin_outlined, color: Color(0xFFFF6B00)),
                  labelText: _trLegacyText(
                    context,
                    'VIN (optional)',
                    ar: 'رقم الهيكل (اختياري)',
                    ku: 'ژمارەی شاسی (ئارەزوومەندانە)',
                  ),
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: 'e.g. 1HGBH41JXMN109186',
                  hintStyle: TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (value) {
                  selectedVin = value.trim().isEmpty ? null : value.trim();
                  _syncStep2DraftToParent();
                },
                validator: (v) {
                  final trimmed = (v ?? '').trim();
                  if (trimmed.isEmpty) return null;
                  if (trimmed.length != 17) {
                    return _trLegacyText(
                      context,
                      'VIN must be 17 characters',
                      ar: 'رقم الهيكل يجب أن يكون 17 حرفاً',
                      ku: 'ژمارەی شاسی دەبێت ١٧ پیت بێت',
                    );
                  }
                  return null;
                },
              ),
            ),
            SizedBox(height: 32),
            // Navigation Buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        final parentState = context
                            .findAncestorStateOfType<_SellCarPageState>();
                        if (parentState != null) {
                          parentState._goToPreviousStep();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Color(0xFFFF6B00)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.previousButton,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6B00),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        final List<String> missing = [];
                        if (selectedMileage == null ||
                            (selectedMileage ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.mileageLabel,
                          );
                        }
                        if (selectedCondition == null ||
                            (selectedCondition ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.conditionLabel,
                          );
                        }
                        if (selectedTransmission == null ||
                            (selectedTransmission ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.transmissionLabel,
                          );
                        }
                        if (selectedFuelType == null ||
                            (selectedFuelType ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.fuelTypeLabel,
                          );
                        }
                        if (selectedBodyType == null ||
                            (selectedBodyType ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.selectBodyType,
                          );
                        }
                        if (selectedColor == null ||
                            (selectedColor ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.selectColor,
                          );
                        }
                        if (selectedDriveType == null ||
                            (selectedDriveType ?? '').isEmpty) {
                          missing.add(AppLocalizations.of(context)!.driveType);
                        }
                        if (selectedRegionSpecs == null ||
                            !isValidCarRegionSpecCode(selectedRegionSpecs)) {
                          missing.add(
                            AppLocalizations.of(context)!.regionSpecsLabel,
                          );
                        }
                        if (selectedSeating == null ||
                            (selectedSeating ?? '').isEmpty) {
                          missing.add(AppLocalizations.of(context)!.seating);
                        }
                        final String engineForStep = isEngineSizeManualInput
                            ? _engineSizeController.text.trim()
                            : (selectedEngineSize ?? '').trim();
                        final double? engineLiters =
                            OnlineSpecVariant.parseLeadingEngineLiters(
                                  engineForStep,
                                ) ??
                                double.tryParse(engineForStep);
                        final bool engineOk =
                            engineForStep.isNotEmpty &&
                            engineLiters != null &&
                            engineLiters > 0;
                        if (!engineOk) {
                          missing.add(
                            AppLocalizations.of(context)!.engineSizeL,
                          );
                        }
                        if (selectedCylinderCount == null ||
                            selectedCylinderCount!.trim().isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.cylinderCount,
                          );
                        }
                        if (selectedTitleStatus == null ||
                            (selectedTitleStatus ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.titleStatus,
                          );
                        }
                        if ((selectedTitleStatus?.toLowerCase() == 'damaged') &&
                            (selectedDamagedParts == null ||
                                (selectedDamagedParts ?? '').isEmpty)) {
                          missing.add(
                            AppLocalizations.of(context)!.damagedParts,
                          );
                        }
                        if (missing.isNotEmpty) {
                          setState(() {
                            errMileage =
                                selectedMileage == null ||
                                (selectedMileage ?? '').isEmpty;
                            errCondition =
                                selectedCondition == null ||
                                (selectedCondition ?? '').isEmpty;
                            errTransmission =
                                selectedTransmission == null ||
                                (selectedTransmission ?? '').isEmpty;
                            errFuelType =
                                selectedFuelType == null ||
                                (selectedFuelType ?? '').isEmpty;
                            errBodyType =
                                selectedBodyType == null ||
                                (selectedBodyType ?? '').isEmpty;
                            errColor =
                                selectedColor == null ||
                                (selectedColor ?? '').isEmpty;
                            errDrive =
                                selectedDriveType == null ||
                                (selectedDriveType ?? '').isEmpty;
                            errRegionSpecs =
                                selectedRegionSpecs == null ||
                                !isValidCarRegionSpecCode(selectedRegionSpecs);
                            errSeating =
                                selectedSeating == null ||
                                (selectedSeating ?? '').isEmpty;
                            errEngineSize = !engineOk;
                            errCylinderCount =
                                selectedCylinderCount == null ||
                                selectedCylinderCount!.trim().isEmpty;
                            errTitle =
                                selectedTitleStatus == null ||
                                (selectedTitleStatus ?? '').isEmpty;
                            errDamagedParts =
                                (selectedTitleStatus?.toLowerCase() ==
                                    'damaged') &&
                                (selectedDamagedParts == null ||
                                    (selectedDamagedParts ?? '').isEmpty);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_pleaseFillRequiredGlobal(context)}: ${missing.join(', ')}',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        final parentState = context
                            .findAncestorStateOfType<_SellCarPageState>();
                        if (parentState != null) {
                          if (isEngineSizeManualInput) {
                            final te = _engineSizeController.text.trim();
                            if (te.isNotEmpty) selectedEngineSize = te;
                          }
                          parentState.carData['mileage'] = selectedMileage;
                          parentState.carData['condition'] = selectedCondition;
                          parentState.carData['transmission'] =
                              selectedTransmission;
                          parentState.carData['fuel_type'] = selectedFuelType;
                          parentState.carData['body_type'] = selectedBodyType;
                          parentState.carData['color'] = selectedColor;
                          parentState.carData['drive_type'] = selectedDriveType;
                          parentState.carData['region_specs'] =
                              selectedRegionSpecs?.trim().toLowerCase();
                          parentState.carData['seating'] = selectedSeating;
                          parentState.carData['engine_size'] =
                              selectedEngineSize;
                          parentState.carData['cylinder_count'] =
                              selectedCylinderCount;
                          parentState.carData['title_status'] =
                              selectedTitleStatus;
                          parentState.carData['damaged_parts'] =
                              selectedDamagedParts;
                          final vinText = _vinController.text.trim();
                          parentState.carData['vin'] =
                              vinText.isNotEmpty ? vinText : null;
                          setState(() {
                            errMileage = errCondition = errTransmission =
                                errFuelType = errBodyType = errColor =
                                    errDrive = errRegionSpecs = errSeating =
                                        errEngineSize = errCylinderCount =
                                            errTitle = errDamagedParts = false;
                          });
                          parentState._goToNextStep();
                          unawaited(parentState._saveSellDraftSnapshot());
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFFF6B00),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.nextStep,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Step 3: Pricing & Contact Information
