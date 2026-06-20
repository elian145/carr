part of '../sell_page.dart';

// Extensions on [_SellPageState] call [setState] legitimately.
// ignore_for_file: invalid_use_of_protected_member

extension SellPageCatalog on _SellPageState {
  void _refreshDatasetPicker() {
    final idx = _specIndex;
    final brand = _selectedBrand;
    final model = _selectedModel;

    int? newModelId = _datasetModelId;
    int? newYear = _catalogYear;

    if (idx == null ||
        brand == null ||
        model == null ||
        !idx.hasCoverage(brand, model)) {
      newModelId = null;
      newYear = null;
    } else {
      final bid = idx.datasetBrandId(brand);
      if (bid == null) {
        newModelId = null;
        newYear = null;
      } else {
        final variants = idx.variantsForAppModel(brand, model);
        if (variants.isEmpty) {
          newModelId = null;
          newYear = null;
        } else {
          final formYear = int.tryParse(_year.text.trim());
          final years = idx.yearsForCatalogStep(
            brand,
            model,
            CarSpecIndex.catalogAutofillModelOnly,
          );
          if (years.isEmpty) {
            newModelId = null;
            newYear = null;
          } else {
            int resolvedYear;
            if (formYear != null && years.contains(formYear)) {
              resolvedYear = formYear;
            } else if (newYear != null && years.contains(newYear)) {
              resolvedYear = newYear;
            } else {
              resolvedYear = years.first;
            }
            newYear = resolvedYear;
            final preferred = idx.suggestDatasetModelIdForFormYear(
              brand,
              model,
              CarSpecIndex.catalogAutofillModelOnly,
              resolvedYear,
            );
            var modelId = newModelId ?? 0;
            if (modelId == 0 || !variants.any((v) => v.id == modelId)) {
              modelId = preferred ?? variants.first.id;
            } else if (!idx.datasetVariantCoversYear(modelId, resolvedYear)) {
              modelId = preferred ?? modelId;
            }
            newModelId = modelId;
          }
        }
      }
    }

    setState(() {
      _datasetModelId = newModelId;
      _catalogYear = newYear;
    });
  }

  /// Fills constrained step-2 lists from bundled-catalog [OnlineSpecVariant] rows.
  void _applyConstrainedOptionsFromCatalogVariants(List<OnlineSpecVariant> vs) {
    if (vs.isEmpty) return;
    final tr = <String>{};
    final dr = <String>{};
    final body = <String>{};
    final engt = <String>{};
    final fuel = <String>{};
    final sizeLabels = <String>[];
    final seenSizes = <String>{};
    final cyl = <int>{};
    final seat = <int>{};
    final fe = <String>{};
    for (final v in vs) {
      if (v.transmission != null) tr.add(v.transmission!);
      if (v.drivetrain != null) dr.add(v.drivetrain!);
      if (v.bodyType != null) body.add(v.bodyType!);
      if (v.engineType != null) engt.add(v.engineType!);
      if (v.fuelType != null) fuel.add(v.fuelType!);
      if (v.engineSizeLiters != null && v.engineSizeLiters! > 0.001) {
        final lit = double.parse(v.engineSizeLiters!.toStringAsFixed(1));
        final label = '${lit.toStringAsFixed(1)}${v.displacementSuffix}';
        if (seenSizes.add(label)) sizeLabels.add(label);
      }
      if (v.cylinderCount != null && v.cylinderCount! > 0) {
        cyl.add(v.cylinderCount!);
      }
      if (v.seating != null && v.seating! > 0) seat.add(v.seating!);
      if (v.fuelEconomy != null && v.fuelEconomy!.trim().isNotEmpty) {
        fe.add(v.fuelEconomy!.trim());
      }
    }
    _transmissionOptions = tr.isNotEmpty ? (tr.toList()..sort()) : null;
    _drivetrainOptions = dr.isNotEmpty ? (dr.toList()..sort()) : null;
    _bodyTypeOptions = body.isNotEmpty ? (body.toList()..sort()) : null;
    _engineTypeOptions = engt.isNotEmpty ? (engt.toList()..sort()) : null;
    _fuelTypeOptions = fuel.isNotEmpty ? (fuel.toList()..sort()) : null;
    if (sizeLabels.isNotEmpty) {
      sizeLabels.sort((a, b) {
        final la = OnlineSpecVariant.parseLeadingEngineLiters(a) ?? 0;
        final lb = OnlineSpecVariant.parseLeadingEngineLiters(b) ?? 0;
        final c = la.compareTo(lb);
        if (c != 0) return c;
        return a.compareTo(b);
      });
      _engineSizeDisplayOptions = sizeLabels;
    } else {
      _engineSizeDisplayOptions = null;
    }
    _cylinderOptions = cyl.isNotEmpty ? (cyl.toList()..sort()) : null;
    _seatingOptions = seat.isNotEmpty ? (seat.toList()..sort()) : null;
    _fuelEconomyOptions = fe.isNotEmpty ? (fe.toList()..sort()) : null;
  }

  void _applyCatalogSpecs() {
    final idx = _specIndex;
    if (idx == null || _catalogYear == null) {
      return;
    }
    final brand = (_selectedBrand ?? '').trim();
    final model = (_selectedModel ?? '').trim();
    if (brand.isEmpty || model.isEmpty) return;

    final rep = idx.representativeForCatalogSell(
      brand,
      model,
      CarSpecIndex.catalogAutofillModelOnly,
      _catalogYear!,
    );
    CatalogSpecFields? fields = rep?.fields;
    if (fields == null) {
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loc?.invalidField ??
                'No specs for this year — pick another year or variant.',
          ),
        ),
      );
      return;
    }
    final specFields = fields;

    var catVs = (brand.isNotEmpty && model.isNotEmpty)
        ? idx.catalogSellSpecVariants(
            brand,
            model,
            CarSpecIndex.catalogAutofillModelOnly,
            _catalogYear!,
          )
        : <OnlineSpecVariant>[];
    if (catVs.isEmpty) {
      catVs = [
        OnlineSpecVariant(
          engineSizeLiters: specFields.engineSizeLiters,
          displacementSuffix: specFields.displacementSuffix,
          cylinderCount: specFields.cylinderCount,
          seating: specFields.seating,
          fuelEconomy: specFields.fuelEconomy,
          transmission: specFields.transmission,
          drivetrain: specFields.driveType,
          bodyType: specFields.bodyType,
          engineType: specFields.engineType,
          fuelType: specFields.fuelType,
        ),
      ];
    }

    setState(() {
      if (rep != null) {
        _datasetModelId = rep.datasetModelId;
      }
      _onlineSpecVariants = List<OnlineSpecVariant>.from(catVs);
      _applyConstrainedOptionsFromCatalogVariants(catVs);
      _engineType = specFields.engineType;
      _fuelType = specFields.fuelType;
      _transmission = specFields.transmission;
      _driveType = specFields.driveType;
      _bodyType = specFields.bodyType;
      _specDropdownKey++;
      _engineSizeCtl.text = specFields.engineSizeLiters != null
          ? '${specFields.engineSizeLiters!.toStringAsFixed(1)}${specFields.displacementSuffix}'
          : '';
      _cylinderCtl.text = specFields.cylinderCount != null
          ? '${specFields.cylinderCount}'
          : '';
      _fuelEconomyCtl.text = specFields.fuelEconomy ?? '';
      _seatingCtl.text = specFields.seating != null
          ? '${specFields.seating}'
          : '';
      _year.text = '${_catalogYear!}';
      _syncConstrainedSelectionsAfterCatalogApply();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _text(
            'Applied specs from catalog',
            ar: 'تم تطبيق المواصفات من الكتالوج',
            ku: 'تایبەتمەندییەکان لە کاتالۆگەوە جێبەجێ کران',
          ),
        ),
      ),
    );
    _scheduleDraftSave();
  }

  void _scheduleRefreshDataset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshDatasetPicker();
    });
  }

  void _onListingYearChanged() {
    _scheduleRefreshDataset();
    _scheduleDraftSave();
  }

}
