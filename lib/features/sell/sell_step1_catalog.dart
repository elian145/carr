part of 'sell_flow.dart';

mixin _SellStep1Catalog on _SellStep1Fields {
  void _hydrateFromParentCarData() {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final data = parent?.carData;
    if (data == null || data.isEmpty) return;
    setState(() {
      selectedBrand = data['brand']?.toString();
      selectedModel = data['model']?.toString();
      selectedTrim = data['trim']?.toString();
      selectedYear = data['year']?.toString();
      _dsModelId = int.tryParse(data['_catalog_model_id']?.toString() ?? '');
      _catYear = int.tryParse(data['_catalog_year']?.toString() ?? '');
      final yearText = data['year']?.toString() ?? '';
      _yearController.text = yearText;
    });
  }

  Future<void> _saveDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _SellStep1Fields._draftKey,
        json.encode(<String, dynamic>{
          'selectedBrand': selectedBrand,
          'selectedModel': selectedModel,
          'selectedTrim': selectedTrim,
          'selectedYear': selectedYear,
          'errBrand': errBrand,
          'errModel': errModel,
          'errTrim': errTrim,
          'errYear': errYear,
          'isYearManualInput': isYearManualInput,
          'dsModelId': _dsModelId,
          'catYear': _catYear,
          'yearControllerText': _yearController.text,
        }),
      );
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _resetSellFilters() async {
    selectedBrand = null;
    selectedModel = null;
    selectedTrim = null;
    selectedYear = null;
    setState(() {});
  }

  void _dismissKeyboard() {
    // Clear focus from year field
    _yearFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _schedDsRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshDsPicker();
    });
  }

  void _onYearTextForCatalog() {
    _schedDsRefresh();
  }

  void _resetDsPicker() {
    _dsModelId = null;
    _catYear = null;
  }

  void _refreshDsPicker() {
    final idx = _specIdx;
    final b = selectedBrand;
    final m = selectedModel;
    int? newId = _dsModelId;
    int? newY = _catYear;
    if (idx == null || b == null || m == null || !idx.hasCoverage(b, m)) {
      newId = null;
      newY = null;
    } else {
      final bid = idx.datasetBrandId(b);
      if (bid == null) {
        newId = null;
        newY = null;
      } else {
        final variants = idx.variantsForAppModel(b, m);
        if (variants.isEmpty) {
          newId = null;
          newY = null;
        } else {
          final formYear =
              int.tryParse(_yearController.text.trim()) ??
              int.tryParse((selectedYear ?? '').trim());
          final years = idx.yearsForCatalogStep(
            b,
            m,
            CarSpecIndex.catalogAutofillModelOnly,
          );
          if (years.isEmpty) {
            newId = null;
            newY = null;
          } else {
            int resolvedYear;
            if (formYear != null && years.contains(formYear)) {
              resolvedYear = formYear;
            } else if (newY != null && years.contains(newY)) {
              resolvedYear = newY;
            } else {
              resolvedYear = years.first;
            }
            newY = resolvedYear;
            final preferred = idx.suggestDatasetModelIdForFormYear(
              b,
              m,
              CarSpecIndex.catalogAutofillModelOnly,
              resolvedYear,
            );
            var mid = newId ?? 0;
            if (mid == 0 || !variants.any((v) => v.id == mid)) {
              mid = preferred ?? variants.first.id;
            } else if (!idx.datasetVariantCoversYear(mid, resolvedYear)) {
              mid = preferred ?? mid;
            }
            newId = mid;
          }
        }
      }
    }
    setState(() {
      _dsModelId = newId;
      _catYear = newY;
      _pruneYearOutsideCatalog();
    });
  }

  /// Catalog-backed years for the current brand + model, or null to use the default range.
  List<String>? _catalogYearStringsIfAny() {
    final idx = _specIdx;
    final b = selectedBrand;
    final m = selectedModel;
    if (idx == null || b == null || m == null) {
      return null;
    }
    if (!idx.hasCoverage(b, m)) return null;
    final ys = idx.yearsForCatalogStep(
      b,
      m,
      CarSpecIndex.catalogAutofillModelOnly,
    );
    if (ys.isEmpty) return null;
    return ys.map((e) => '$e').toList();
  }

  void _pruneYearOutsideCatalog() {
    if (isYearManualInput) return;
    final catalog = _catalogYearStringsIfAny();
    if (catalog == null) return;
    if (selectedYear != null && !catalog.contains(selectedYear)) {
      selectedYear = null;
    }
  }

  void _syncStep1DraftToParent() {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    if (parent == null) return;
    parent.carData['brand'] = selectedBrand;
    parent.carData['model'] = selectedModel;
    parent.carData['trim'] = selectedTrim;
    parent.carData['year'] = selectedYear;
    parent.setState(() {});
    unawaited(parent._saveSellDraftSnapshot());
  }

  void _applyCatalogSpecsToFlow() {
    final idx = _specIdx;
    if (idx == null || _catYear == null) return;
    final b = (selectedBrand ?? '').trim();
    final m = (selectedModel ?? '').trim();
    if (b.isEmpty || m.isEmpty) return;
    final rep = idx.representativeForCatalogSell(
      b,
      m,
      CarSpecIndex.catalogAutofillModelOnly,
      _catYear!,
    );
    final CatalogSpecFields? f = rep?.fields;
    if (f == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No spec row for this year — try another year or variant.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    if (parent == null) return;
    _clearOnlineSpecOptionsInCarData(parent.carData);
    final y = '${_catYear!}';
    setState(() {
      if (rep != null) {
        _dsModelId = rep.datasetModelId;
      }
      selectedYear = y;
      if (isYearManualInput) {
        _yearController.text = y;
      }
    });
    parent.carData['transmission'] = sellFlowTransmissionLabel(f.transmission);
    parent.carData['fuel_type'] = sellFlowFuelLabel(f.fuelType);
    parent.carData['engine_type'] = f.engineType;
    parent.carData['body_type'] = sellFlowBodyLabel(f.bodyType);
    parent.carData['drive_type'] = sellFlowDriveLabel(f.driveType);
    if (f.engineSizeLiters != null && f.engineSizeLiters! > 0) {
      // Keep suffix (T/D/TD) for display, while the API submit parses leading liters.
      parent.carData['engine_size'] =
          '${f.engineSizeLiters!.toStringAsFixed(1)}${f.displacementSuffix}';
    }
    if (f.cylinderCount != null && f.cylinderCount! > 0) {
      parent.carData['cylinder_count'] = '${f.cylinderCount}';
    }
    final seatStr = sellFlowNearestSeatingLabel(f.seating);
    if (seatStr != null) {
      parent.carData['seating'] = seatStr;
    }
    if (f.fuelEconomy != null && f.fuelEconomy!.trim().isNotEmpty) {
      parent.carData['fuel_economy'] = f.fuelEconomy!.trim();
    }
    final union = (b.isNotEmpty && m.isNotEmpty)
        ? idx.sellFieldOptionsUnion(
            b,
            m,
            CarSpecIndex.catalogAutofillModelOnly,
            _catYear!,
          )
        : null;
    var catVs = (b.isNotEmpty && m.isNotEmpty)
        ? idx.catalogSellSpecVariants(
            b,
            m,
            CarSpecIndex.catalogAutofillModelOnly,
            _catYear!,
          )
        : const <OnlineSpecVariant>[];
    if (catVs.isEmpty) {
      catVs = [_onlineSpecVariantFromCatalogFields(f)];
    }
    if (union != null) {
      _applyCatalogSellFieldUnionToCarData(parent.carData, union);
    } else {
      _applyCatalogSpecConstrainedOptionsToCarData(parent.carData, f);
    }
    if (catVs.isNotEmpty) {
      parent.carData[_kOnlineSpecVariantsKey] = catVs
          .map((e) => e.toJson())
          .toList();
    }
    parent.carData['_catalog_specs_applied'] =
        DateTime.now().millisecondsSinceEpoch;
    parent.setState(() {});
    unawaited(parent._saveSellDraftSnapshot());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _trLegacyText(
            context,
            'Specs applied — year set; step 2 fields pre-filled.',
            ar: 'تم تطبيق المواصفات — تم ضبط السنة وملء حقول الخطوة 2 مسبقا.',
            ku: 'سپێسەکان جێبەجێ کران — ساڵ دانرا و خانەکانی هەنگاو 2 پڕکرانەوە.',
          ),
        ),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  List<String> get brands => CarCatalog.brands;
  Map<String, List<String>> get models => CarCatalog.models;
  Map<String, Map<String, List<String>>> get trimsByBrandModel =>
      CarCatalog.trimsByBrandModel;

  List<String> get availableYears {
    final catalog = _catalogYearStringsIfAny();
    if (catalog != null) return catalog;
    final currentYear = DateTime.now().year;
    return List.generate(30, (index) => (currentYear - index).toString());
  }

  List<String> get availableTrims =>
      CarCatalog.trimsFor(selectedBrand, selectedModel);
}
