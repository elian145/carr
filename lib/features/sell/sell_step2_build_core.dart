part of 'sell_flow.dart';

mixin _SellStep2BuildCore on _SellStep2Pickers {
  List<Widget> _sellStep2BuildCoreSection() {
    return [
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
    ];
  }
}
