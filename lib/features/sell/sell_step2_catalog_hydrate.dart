part of 'sell_flow.dart';

mixin _SellStep2CatalogHydrate on _SellStep2CatalogOptions {
  CatalogSellFieldOptions? _computeCatalogSellOpts(
    Map<String, dynamic>? carData,
    CarSpecIndex? idx,
  ) {
    if (carData == null || idx == null) return null;
    final b = carData['brand']?.toString().trim() ?? '';
    final m = carData['model']?.toString().trim() ?? '';
    if (b.isEmpty || m.isEmpty) return null;
    // A model the spec dataset has no rows for has no "Apply specs" path at
    // all. The approved IQ overlay is coverage for the specific field it
    // supplies (engine sizes / cylinders); every other field, and any field IQ
    // has nothing for, keeps the full static option set (null -> defaults).
    if (!idx.hasCoverage(b, m)) {
      return idx.iqOnlyFieldOptions(b, m, CarSpecIndex.catalogAutofillModelOnly);
    }
    // Brand + model defines the options, always: before AND after "Apply specs".
    // Neither the listing year, the trim nor Apply is an input; Apply only
    // prefills selected values. ("availableOptions" vs "selectedValues".)
    return idx.sellFieldOptionsUnion(
      b,
      m,
      CarSpecIndex.catalogAutofillModelOnly,
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
      final mileageRaw = ThousandsSeparatorInputFormatter.digitsOnly(
        d['mileage']?.toString() ?? '',
      );
      selectedMileage = mileageRaw.isEmpty ? null : mileageRaw;
      selectedMileageUnit =
          d['mileage_unit']?.toString() == 'miles' ? 'miles' : 'km';
      final mileageText = ThousandsSeparatorInputFormatter.format(
        selectedMileage ?? '',
      );
      if (_mileageController.text != mileageText) {
        _mileageController.text = mileageText;
      }
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
      // Each is restored from its OWN stored value (never from "the first"
      // entry of a multi-value option list). The engine is never rewritten;
      // its trusted cylinder count is applied after this block.
      final cylDirect = d['cylinder_count']?.toString().trim();
      if (cylDirect != null && cylDirect.isNotEmpty) {
        selectedCylinderCount = cylDirect;
      } else {
        final raw = d['_online_opts_cylinder'];
        if (raw is List && raw.length == 1) {
          final s = raw.first.toString().trim();
          if (s.isNotEmpty) selectedCylinderCount = s;
        }
      }
      String? es = d['engine_size']?.toString().trim();
      if (es == null || es.isEmpty) {
        final raw = d['_online_opts_engine_size'];
        if (raw is List && raw.length == 1) {
          final t = raw.first.toString().trim();
          final lit = OnlineSpecVariant.parseLeadingEngineLiters(t);
          if (lit != null && lit > 0.001) es = t;
        }
      }
      if (es != null && es.isNotEmpty) {
        final lit = OnlineSpecVariant.parseLeadingEngineLiters(es);
        if (lit == null || lit <= 0.001) {
          es = null;
        }
      }
      if (es != null && es.isNotEmpty) {
        final available = getAvailableEngineSizes()
            .where((e) => e != 'Any')
            .map((e) => e.trim())
            .toList();
        final wasManual = d['_engine_size_manual'] == true;
        final onlineEngineList = _onlineMultiFromCarData(
              '_online_opts_engine_size',
            ) !=
            null;
        // The spec index is still loading and nothing narrows the list yet:
        // keep the stored pick untouched; it is re-checked once the index loads.
        final listPending = _specIdx == null && !onlineEngineList;
        final narrowing = _engineListIsNarrowed();
        String? resolved;
        if (!wasManual) {
          if (available.contains(es) || listPending) {
            resolved = es;
          } else if (!narrowing) {
            // Generic ladder only: snap a plain typed size to its ladder entry.
            final lit = OnlineSpecVariant.parseLeadingEngineLiters(es);
            if (lit != null) {
              for (final opt in available) {
                final oL = OnlineSpecVariant.parseLeadingEngineLiters(opt);
                if (oL != null && (oL - lit).abs() < 0.06) {
                  resolved = opt;
                  break;
                }
              }
            }
          } else {
            // The catalog narrowed the list and this pick is not in it any more
            // (year / trim change): clear ONLY the engine.
            selectedEngineSize = null;
            isEngineSizeManualInput = false;
            _engineSizeController.text = '';
            es = null;
          }
        }
        if (es == null) {
          // cleared above
        } else if (resolved != null && resolved.isNotEmpty) {
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
      // The restored engine keeps its exact label; its trusted cylinder count
      // (when the evidence is unique) is then recomputed and applied.
      _applyTrustedCylinderForSelectedEngine();
      _clearCylinderIfNotInOwnList();
    });
  }

  /// True when the engine list is the catalog / IQ list for this vehicle rather
  /// than the generic ladder (manual typing is then the only way past it).
  bool _engineListIsNarrowed() {
    if (_onlineMultiFromCarData('_online_opts_engine_size') != null) return true;
    return _specIdx != null && (_catalogSellOpts?.engineSizes.isNotEmpty ?? false);
  }

  bool _cylinderListIsNarrowed() {
    if (_onlineMultiFromCarData('_online_opts_cylinder') != null) return true;
    final o = _catalogSellOpts;
    return _specIdx != null &&
        o != null &&
        (o.cylinderCounts.isNotEmpty || o.iqCylinderCounts.isNotEmpty);
  }

  /// Clears the cylinder pick ONLY, and only when the narrowed cylinder list no
  /// longer offers it. Never touches or derives the engine.
  bool _clearCylinderIfNotInOwnList() {
    final c = selectedCylinderCount?.trim();
    if (c == null || c.isEmpty || !_cylinderListIsNarrowed()) return false;
    final avail = getAvailableCylinderCounts().where((e) => e != 'Any');
    if (avail.contains(c)) return false;
    selectedCylinderCount = null;
    return true;
  }

  /// Once the spec index (and so the real option lists) is available, drop a
  /// restored engine / cylinder that its OWN list no longer contains. Each field
  /// is checked independently: an invalid engine clears the engine only, an
  /// invalid cylinder clears the cylinder only.
  void _clearSelectionsOutsideOwnLists() {
    var changed = false;
    final es = selectedEngineSize?.trim();
    if (!isEngineSizeManualInput &&
        es != null &&
        es.isNotEmpty &&
        _engineListIsNarrowed()) {
      final avail = getAvailableEngineSizes().where((e) => e != 'Any');
      if (!avail.contains(es)) {
        selectedEngineSize = null;
        _engineSizeController.text = '';
        changed = true;
      }
    }
    if (_applyTrustedCylinderForSelectedEngine()) changed = true;
    if (_clearCylinderIfNotInOwnList()) changed = true;
    if (changed) _syncStep2DraftToParent();
  }

  Future<void> _saveDraft() async {
    try {
      if (LegacySellDraftPrefs.suppressPersist) return;
      final epoch = LegacySellDraftPrefs.persistEpoch;
      final sp = await SharedPreferences.getInstance();
      if (!LegacySellDraftPrefs.isCurrentPersistEpoch(epoch)) return;
      await sp.setString(
        _SellStep2Fields._draftKey,
        json.encode(<String, dynamic>{
          'selectedMileage': selectedMileage,
          'selectedMileageUnit': selectedMileageUnit,
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
          'isEngineSizeManualInput': isEngineSizeManualInput,
          'mileageControllerText': _mileageController.text,
          'engineSizeControllerText': _engineSizeController.text,
        }),
      );
    } catch (e, st) { logNonFatal(e, st); }
  }

  void _resetStep2() {
    selectedMileage = null;
    selectedMileageUnit = 'km';
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
}
