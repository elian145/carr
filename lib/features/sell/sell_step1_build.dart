part of 'sell_flow.dart';

mixin _SellStep1Build on _SellStep1Pickers {
  Widget _sellStep1YearSection() {
    final loc = AppLocalizations.of(context)!;
    final style = filterDialogStyle(context);

    return FilterCard(
      isError: errYear,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterSectionHeader(
            title: loc.yearLabel,
            requiredField: true,
            valueSummary: selectedYear == null
                ? loc.tapToSelect
                : _localizeDigitsGlobal(context, selectedYear!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: isYearManualInput
                    ? TextFormField(
                        focusNode: _yearFocusNode,
                        controller: _yearController,
                        decoration: filterFieldDecoration(
                          style,
                          loc.yearLabel,
                          errorText: errYear ? loc.pleaseSelectYear : null,
                        ),
                        style: TextStyle(color: style.onSurface),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          setState(() {
                            selectedYear = value.isEmpty ? null : value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return loc.pleaseEnterYear;
                          }
                          final year = int.tryParse(value);
                          if (year == null) return loc.yearInvalid;
                          if (year < 1900 || year > DateTime.now().year + 1) {
                            return loc.yearOutOfRange;
                          }
                          return null;
                        },
                      )
                    : DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: selectedYear != null &&
                                availableYears.contains(selectedYear)
                            ? selectedYear
                            : null,
                        decoration: filterFieldDecoration(
                          style,
                          loc.yearLabel,
                          errorText: errYear ? loc.pleaseSelectYear : null,
                        ),
                        items: availableYears.map((year) {
                          return DropdownMenuItem<String>(
                            value: year,
                            child: Text(
                              _localizeDigitsGlobal(context, year),
                            ),
                          );
                        }).toList(),
                        hint: Text(
                          loc.tapToSelect,
                          style: TextStyle(
                            color: style.anyOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() => selectedYear = value);
                          _syncStep1DraftToParent();
                        },
                      ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  if (isYearManualInput) {
                    _yearFocusNode.unfocus();
                    FocusScope.of(context).unfocus();
                    setState(() {
                      isYearManualInput = false;
                      if (_yearController.text.isNotEmpty) {
                        selectedYear = _yearController.text;
                      }
                    });
                    _syncStep1DraftToParent();
                  } else {
                    setState(() {
                      isYearManualInput = true;
                      _yearController.clear();
                      selectedYear = null;
                    });
                    _syncStep1DraftToParent();
                  }
                },
                icon: Icon(
                  isYearManualInput ? Icons.check : Icons.edit,
                  color: kFilterAccentColor,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                tooltip: isYearManualInput
                    ? loc.confirmYear
                    : loc.typeManually,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kFilterAccentColor.withValues(alpha: 0.1),
                    Colors.white,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: kFilterAccentColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.directions_car,
                    size: 48,
                    color: kFilterAccentColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)!.basicInformationTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.basicInformationSubtitle,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            MakeModelKeywordSearch(
              brands: brands,
              models: models,
              controller: _makeModelSearchController,
              focusNode: _makeModelSearchFocusNode,
              onBrandSelected: (brand) {
                setState(() {
                  selectedBrand = brand;
                  selectedModel = null;
                  selectedTrim = null;
                  isModelManualInput = false;
                  isTrimManualInput = false;
                  _modelManualController.clear();
                  _trimManualController.clear();
                  errBrand = false;
                  _resetDsPicker();
                  _pruneYearOutsideCatalog();
                });
                _schedDsRefresh();
                _syncStep1DraftToParent();
              },
              onModelSelected: (brand, model) {
                setState(() {
                  selectedBrand = brand;
                  selectedModel = model;
                  selectedTrim = null;
                  isModelManualInput = false;
                  isTrimManualInput = false;
                  _modelManualController.clear();
                  _trimManualController.clear();
                  errBrand = false;
                  errModel = false;
                  _resetDsPicker();
                  _pruneYearOutsideCatalog();
                });
                _schedDsRefresh();
                _syncStep1DraftToParent();
              },
            ),
            const SizedBox(height: 14),
            FilterMakeSection(
              brands: brands,
              selectedBrand: selectedBrand,
              onBrandSelected: (brand) {
                setState(() {
                  selectedBrand = brand;
                  selectedModel = null;
                  selectedTrim = null;
                  isModelManualInput = false;
                  isTrimManualInput = false;
                  _modelManualController.clear();
                  _trimManualController.clear();
                  _resetDsPicker();
                  _pruneYearOutsideCatalog();
                });
                _schedDsRefresh();
                _syncStep1DraftToParent();
              },
              brandsExpanded: brandsExpanded,
              onToggleBrandsExpanded: () {
                setState(() => brandsExpanded = !brandsExpanded);
              },
              models: models,
              selectedModel: selectedModel,
              onModelSelected: (model) {
                setState(() {
                  selectedModel = model;
                  selectedTrim = null;
                  isTrimManualInput = false;
                  _trimManualController.clear();
                  if (!isModelManualInput) {
                    _modelManualController.clear();
                  }
                  _resetDsPicker();
                  _pruneYearOutsideCatalog();
                });
                _schedDsRefresh();
                _syncStep1DraftToParent();
              },
              trimList: availableTrims,
              selectedTrim: selectedTrim,
              onTrimSelected: (trim) {
                setState(() {
                  selectedTrim = trim;
                  if (!isTrimManualInput) {
                    _trimManualController.clear();
                  }
                  _resetDsPicker();
                  _pruneYearOutsideCatalog();
                });
                _schedDsRefresh();
                _syncStep1DraftToParent();
              },
              allowCustomModel: true,
              allowCustomTrim: true,
              isModelManualInput: isModelManualInput,
              isTrimManualInput: isTrimManualInput,
              modelManualController: _modelManualController,
              trimManualController: _trimManualController,
              onToggleModelManual: () {
                setState(() {
                  if (isModelManualInput) {
                    final typed = _modelManualController.text.trim();
                    final list = selectedBrand != null
                        ? (models[selectedBrand!] ?? const <String>[])
                        : const <String>[];
                    selectedModel =
                        typed.isNotEmpty && list.contains(typed) ? typed : null;
                    selectedTrim = null;
                    isTrimManualInput = false;
                    _trimManualController.clear();
                    isModelManualInput = false;
                    _modelManualController.clear();
                    _resetDsPicker();
                  } else {
                    isModelManualInput = true;
                    _modelManualController.clear();
                    selectedModel = null;
                    selectedTrim = null;
                    isTrimManualInput = false;
                    _trimManualController.clear();
                    _resetDsPicker();
                  }
                });
                _schedDsRefresh();
                _syncStep1DraftToParent();
              },
              onToggleTrimManual: () {
                setState(() {
                  if (isTrimManualInput) {
                    final typed = _trimManualController.text.trim();
                    selectedTrim = typed.isNotEmpty &&
                            availableTrims.contains(typed)
                        ? typed
                        : null;
                    isTrimManualInput = false;
                    _trimManualController.clear();
                  } else {
                    isTrimManualInput = true;
                    _trimManualController.clear();
                    selectedTrim = null;
                  }
                });
                _syncStep1DraftToParent();
              },
              brandError: errBrand,
              modelError: errModel,
              trimError: errTrim,
            ),
            _buildTrimCatalogSection(),
            _sellStep1YearSection(),
            const SizedBox(height: 32),
            buildSellWizardNavRow(
              context,
              onPrevious: () {
                final parentState = context
                    .findAncestorStateOfType<_SellCarPageState>();
                if (parentState == null) return;
                parentState.carData['brand'] = selectedBrand;
                parentState.carData['model'] = selectedModel;
                parentState.carData['trim'] = selectedTrim;
                parentState.carData['year'] = selectedYear;
                unawaited(parentState._saveSellDraftSnapshot());
                parentState._goToPreviousStep();
              },
              onNext: () {
                final List<String> missing = [];
                if (selectedBrand == null || (selectedBrand ?? '').isEmpty) {
                  missing.add(AppLocalizations.of(context)!.brandLabel);
                }
                if (selectedModel == null || (selectedModel ?? '').isEmpty) {
                  missing.add(AppLocalizations.of(context)!.modelLabel);
                }
                if (selectedTrim == null || (selectedTrim ?? '').isEmpty) {
                  missing.add(AppLocalizations.of(context)!.trimLabel);
                }
                if (selectedYear == null || (selectedYear ?? '').isEmpty) {
                  missing.add(AppLocalizations.of(context)!.yearLabel);
                }

                if (missing.isNotEmpty) {
                  setState(() {
                    errBrand =
                        selectedBrand == null ||
                        (selectedBrand ?? '').isEmpty;
                    errModel =
                        selectedModel == null ||
                        (selectedModel ?? '').isEmpty;
                    errTrim =
                        selectedTrim == null || (selectedTrim ?? '').isEmpty;
                    errYear =
                        selectedYear == null || (selectedYear ?? '').isEmpty;
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
                  parentState.carData['brand'] = selectedBrand;
                  parentState.carData['model'] = selectedModel;
                  parentState.carData['trim'] = selectedTrim;
                  parentState.carData['year'] = selectedYear;
                  setState(() {
                    errBrand = errModel = errTrim = errYear = false;
                  });
                  parentState._goToNextStep();
                  unawaited(parentState._saveSellDraftSnapshot());
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
