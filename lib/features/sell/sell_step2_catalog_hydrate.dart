part of 'sell_flow.dart';

mixin _SellStep2CatalogHydrate on _SellStep2CatalogOptions {
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

  Future<void> _saveDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _SellStep2Fields._draftKey,
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
}
