part of 'sell_flow.dart';

mixin _SellStep1Build on _SellStep1Pickers {
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
                  Icon(
                    Icons.directions_car,
                    size: 48,
                    color: Color(0xFFFF6B00),
                  ),
                  SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)!.basicInformationTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.basicInformationSubtitle,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Brand Selection (Modal)
            FormField<String>(
              validator: (_) => selectedBrand == null
                  ? AppLocalizations.of(context)!.pleaseSelectBrand
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickBrandModal();
                  if (choice != null) {
                    setState(() {
                      selectedBrand = choice;
                      selectedModel = null;
                      selectedTrim = null;
                      _resetDsPicker();
                      _pruneYearOutsideCatalog();
                    });
                    _schedDsRefresh();
                    _syncStep1DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  label: '${AppLocalizations.of(context)!.brandLabel} *',
                  value: selectedBrand != null
                      ? (CarNameTranslations.getLocalizedBrand(
                              context,
                              selectedBrand,
                            ).isNotEmpty
                            ? CarNameTranslations.getLocalizedBrand(
                                context,
                                selectedBrand,
                              )
                            : selectedBrand)
                      : selectedBrand,
                  isError:
                      errBrand &&
                      (selectedBrand == null || selectedBrand!.isEmpty),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B00).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: selectedBrand == null
                        ? Icon(Icons.business, color: const Color(0xFFFF6B00))
                        : Padding(
                            padding: const EdgeInsets.all(6),
                            child: CachedNetworkImage(
                              imageUrl:
                                  '${getApiBase()}/static/images/brands/${sellBrandSlug(selectedBrand!)}.png',
                              fit: BoxFit.contain,
                              errorWidget: (context, url, error) => Image.network(
                                '${getApiBase()}/static/images/brands/default.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Model (Modal)
            FormField<String>(
              validator: (_) => selectedModel == null
                  ? AppLocalizations.of(context)!.pleaseSelectModel
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  if (selectedBrand == null) return;
                  final options = models[selectedBrand!] ?? [];
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.modelLabel,
                    options,
                    contextBrand: selectedBrand,
                  );
                  if (choice != null) {
                    setState(() {
                      selectedModel = choice;
                      selectedTrim = null;
                      _resetDsPicker();
                      _pruneYearOutsideCatalog();
                    });
                    _schedDsRefresh();
                    _syncStep1DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.directions_car,
                  label: '${AppLocalizations.of(context)!.modelLabel} *',
                  value: selectedModel != null
                      ? (CarNameTranslations.getLocalizedModel(
                              context,
                              selectedBrand,
                              selectedModel,
                            ).isNotEmpty
                            ? CarNameTranslations.getLocalizedModel(
                                context,
                                selectedBrand,
                                selectedModel,
                              )
                            : selectedModel)
                      : (selectedBrand == null
                            ? AppLocalizations.of(context)!.selectBrandFirst
                            : ''),
                  isError:
                      errModel &&
                      (selectedModel == null || selectedModel!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Trim (Modal)
            FormField<String>(
              validator: (_) => selectedTrim == null
                  ? AppLocalizations.of(context)!.pleaseSelectTrim
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.trimLabel,
                    availableTrims,
                  );
                  if (choice != null) {
                    setState(() {
                      selectedTrim = choice;
                      _resetDsPicker();
                      _pruneYearOutsideCatalog();
                    });
                    _schedDsRefresh();
                    _syncStep1DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.settings,
                  label: '${AppLocalizations.of(context)!.trimLabel} *',
                  value: selectedTrim,
                  isError:
                      errTrim &&
                      (selectedTrim == null || selectedTrim!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            _buildTrimCatalogSection(),

            // Year (Modal or Manual Input)
            Row(
              children: [
                Expanded(
                  child: isYearManualInput
                      ? TextFormField(
                          focusNode: _yearFocusNode,
                          controller: _yearController,
                          decoration: InputDecoration(
                            labelText:
                                '${AppLocalizations.of(context)!.yearLabel} *',
                            hintText: AppLocalizations.of(
                              context,
                            )!.enterYearHint,
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
                              selectedYear = value.isEmpty ? null : value;
                            });
                          },
                          validator: (value) {
                            final l = AppLocalizations.of(context)!;
                            if (value == null || value.isEmpty) {
                              return l.pleaseEnterYear;
                            }
                            final year = int.tryParse(value);
                            if (year == null) return l.yearInvalid;
                            if (year < 1900 || year > DateTime.now().year + 1) {
                              return l.yearOutOfRange;
                            }
                            return null;
                          },
                        )
                      : FormField<String>(
                          validator: (_) => selectedYear == null
                              ? AppLocalizations.of(context)!.pleaseSelectYear
                              : null,
                          builder: (state) => GestureDetector(
                            onTap: () async {
                              final choice = await _pickFromList(
                                AppLocalizations.of(context)!.yearLabel,
                                availableYears,
                              );
                              if (choice != null) {
                                setState(() {
                                  selectedYear = choice;
                                });
                                _syncStep1DraftToParent();
                              }
                            },
                            child: buildFancySelector(
                              context,
                              icon: Icons.calendar_today,
                              label:
                                  '${AppLocalizations.of(context)!.yearLabel} *',
                              value: selectedYear != null
                                  ? _localizeDigitsGlobal(
                                      context,
                                      selectedYear!,
                                    )
                                  : null,
                              isError:
                                  errYear &&
                                  (selectedYear == null ||
                                      selectedYear!.isEmpty),
                            ),
                          ),
                        ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    if (isYearManualInput) {
                      // If in manual input mode, confirm the year and dismiss keyboard
                      _yearFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        isYearManualInput = false;
                        // Ensure the selectedYear is properly set
                        if (_yearController.text.isNotEmpty) {
                          selectedYear = _yearController.text;
                        }
                      });
                      _syncStep1DraftToParent();
                    } else {
                      // If in dropdown mode, switch to manual input
                      setState(() {
                        isYearManualInput = true;
                        // Clear the controller to start fresh
                        _yearController.clear();
                        selectedYear = null;
                      });
                      _syncStep1DraftToParent();
                    }
                  },
                  icon: Icon(
                    isYearManualInput ? Icons.check : Icons.edit,
                    color: Color(0xFFFF6B00),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  tooltip: isYearManualInput
                      ? AppLocalizations.of(context)!.confirmYear
                      : AppLocalizations.of(context)!.typeManually,
                ),
              ],
            ),
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
                  // Manual validation for required selectors (since we use custom tiles)
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

                  // Save data and navigate to next step
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
