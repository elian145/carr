part of 'sell_flow.dart';

class SellStep2Page extends StatefulWidget {
  const SellStep2Page({super.key, this.specsHydrateToken = ''});

  /// When catalog/online/AI specs timestamps change, state re-reads [carData] (covers off-screen step 2).
  final String specsHydrateToken;

  @override
  State<SellStep2Page> createState() => _SellStep2PageState();
}

class _SellStep2PageState extends _SellStep2Fields with _SellStep2Logic {
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hydrateFromParentCarData();
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
