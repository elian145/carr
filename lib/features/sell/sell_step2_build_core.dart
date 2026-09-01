part of 'sell_flow.dart';

mixin _SellStep2BuildCore on _SellStep2Pickers {
  Widget _mileageUnitOption({
    required String value,
    required String label,
  }) {
    final selected = selectedMileageUnit == value;
    return InkWell(
      onTap: () {
        setState(() => selectedMileageUnit = value);
        _syncStep2DraftToParent();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? kFilterAccentColor.withValues(alpha: 0.12)
              : Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? kFilterAccentColor : const Color(0xFFE0E0E5),
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? kFilterAccentColor : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  List<Widget> _sellStep2MileageSection() {
    final loc = AppLocalizations.of(context)!;
    final style = filterDialogStyle(context);

    String formatMileage(String value) {
      final parsed = int.tryParse(value) ?? 0;
      final nf = _decimalFormatterGlobal(context);
      final unit =
          selectedMileageUnit == 'miles' ? loc.unit_miles : loc.unit_km;
      return '${_localizeDigitsGlobal(context, nf.format(parsed))} $unit';
    }

    return [
      FilterCard(
        isError: errMileage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionHeader(
              title: loc.mileageLabel,
              requiredField: true,
              valueSummary: selectedMileage == null ||
                      selectedMileage!.trim().isEmpty
                  ? loc.enterMileage
                  : formatMileage(selectedMileage!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              focusNode: _mileageFocusNode,
              controller: _mileageController,
              decoration: filterFieldDecoration(
                style,
                loc.enterMileage,
                errorText: errMileage ? loc.pleaseEnterMileage : null,
              ),
              style: TextStyle(color: style.onSurface),
              keyboardType: TextInputType.number,
              inputFormatters: const [
                ThousandsSeparatorInputFormatter(),
              ],
              onChanged: (value) {
                final digits =
                    ThousandsSeparatorInputFormatter.digitsOnly(value);
                setState(() {
                  selectedMileage = digits.isEmpty ? null : digits;
                });
                _syncStep2DraftToParent();
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return loc.pleaseEnterMileage;
                }
                final mileage = int.tryParse(
                  ThousandsSeparatorInputFormatter.digitsOnly(value),
                );
                if (mileage == null) return loc.invalidMileage;
                if (mileage < 0) return loc.mileageNegative;
                return null;
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _mileageUnitOption(
                    value: 'km',
                    label: loc.unit_km,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _mileageUnitOption(
                    value: 'miles',
                    label: loc.unit_miles,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _sellStep2TitleStatusSection() {
    final loc = AppLocalizations.of(context)!;
    final style = filterDialogStyle(context);

    return [
      FilterIconCardSection(
        title: loc.titleStatus,
        options: titleStatuses,
        selected: selectedTitleStatus,
        requiredField: true,
        isError: errTitle,
        textOnly: true,
        labelForOption: _sellTitleStatusLabel,
        onSelected: (value) {
          setState(() {
            selectedTitleStatus = value;
            if ((value ?? '').toLowerCase() != 'damaged') {
              selectedDamagedParts = null;
            }
          });
          _syncStep2DraftToParent();
        },
        onClear: selectedTitleStatus != null
            ? () {
                setState(() => selectedTitleStatus = null);
                _syncStep2DraftToParent();
              }
            : null,
      ),
      if ((selectedTitleStatus ?? '').toLowerCase() == 'damaged')
        FilterCard(
          isError: errDamagedParts,
          child: FilterDropdownField(
            style: style,
            label: loc.damagedParts,
            value: selectedDamagedParts,
            errorText: errDamagedParts ? loc.damagedParts : null,
            items: List.generate(20, (i) => (i + 1).toString())
                .map(
                  (n) => DropdownMenuItem(
                    value: n,
                    child: Text(_localizeDigitsGlobal(context, n)),
                  ),
                )
                .toList(),
            hint: Text(
              loc.tapToSelect,
              style: TextStyle(
                color: style.anyOrange,
                fontWeight: FontWeight.w600,
              ),
            ),
            onChanged: (value) {
              setState(() => selectedDamagedParts = value);
              _syncStep2DraftToParent();
            },
          ),
        ),
    ];
  }

  String _sellTitleStatusLabel(BuildContext context, String status) {
    final loc = AppLocalizations.of(context)!;
    switch (status.toLowerCase()) {
      case 'clean':
        return loc.value_title_clean;
      case 'damaged':
        return loc.value_title_damaged;
      default:
        return _translateValueGlobal(context, status) ?? status;
    }
  }

  List<Widget> _sellStep2CylinderEngineSection() {
    final loc = AppLocalizations.of(context)!;
    final style = filterDialogStyle(context);

    return [
      FilterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterDropdownField(
              style: style,
              label: loc.cylinderCount,
              value: selectedCylinderCount != null &&
                      getAvailableCylinderCounts()
                          .where((c) => c != 'Any')
                          .contains(selectedCylinderCount)
                  ? selectedCylinderCount
                  : null,
              errorText:
                  errCylinderCount ? loc.pleaseSelectCylinderCount : null,
              items: getAvailableCylinderCounts()
                  .where((c) => c != 'Any')
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${_localizeDigitsGlobal(context, c)} ${AppLocalizations.of(context)!.labelCylinders}',
                      ),
                    ),
                  )
                  .toList(),
              hint: Text(
                loc.tapToSelect,
                style: TextStyle(
                  color: style.anyOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  selectedCylinderCount = value;
                  if (errCylinderCount) errCylinderCount = false;
                  _syncStep2ToOnlineVariant({'c'});
                });
                _syncStep2DraftToParent();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: isEngineSizeManualInput
                      ? TextFormField(
                          focusNode: _engineSizeFocusNode,
                          controller: _engineSizeController,
                          decoration: filterFieldDecoration(
                            style,
                            loc.engineSizeL,
                            errorText: errEngineSize
                                ? loc.pleaseSelectEngineSize
                                : null,
                          ),
                          style: TextStyle(color: style.onSurface),
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
                              selectedEngineSize =
                                  value.isEmpty ? null : value.trim();
                              if (errEngineSize) errEngineSize = false;
                            });
                            _syncStep2DraftToParent();
                          },
                        )
                      : FilterDropdownField(
                          style: style,
                          label: loc.engineSizeL,
                          value: selectedEngineSize != null &&
                                  getAvailableEngineSizes()
                                      .where((e) => e != 'Any')
                                      .contains(selectedEngineSize)
                              ? selectedEngineSize
                              : null,
                          errorText: errEngineSize
                              ? loc.pleaseSelectEngineSize
                              : null,
                          items: getAvailableEngineSizes()
                              .where((e) => e != 'Any')
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    _engineSizeSellRowLabel(context, e),
                                  ),
                                ),
                              )
                              .toList(),
                          hint: Text(
                            loc.tapToSelect,
                            style: TextStyle(
                              color: style.anyOrange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              selectedEngineSize = value;
                              if (errEngineSize) errEngineSize = false;
                              _syncStep2ToOnlineVariant({'e'});
                            });
                            _syncStep2DraftToParent();
                          },
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    if (isEngineSizeManualInput) {
                      _engineSizeFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        isEngineSizeManualInput = false;
                        if (_engineSizeController.text.isNotEmpty) {
                          selectedEngineSize = _engineSizeController.text.trim();
                          _syncStep2ToOnlineVariant({'e'});
                        }
                      });
                      _syncStep2DraftToParent();
                    } else {
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
                    color: kFilterAccentColor,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  tooltip: isEngineSizeManualInput
                      ? loc.confirmYear
                      : loc.typeManually,
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _sellStep2BuildCoreSection() {
    final loc = AppLocalizations.of(context)!;

    return [
      ..._sellStep2MileageSection(),
      FilterIconCardSection(
        title: loc.conditionLabel,
        options: getAvailableConditions(),
        selected: selectedCondition,
        requiredField: true,
        isError: errCondition,
        textOnly: true,
        onSelected: (value) {
          setState(() => selectedCondition = value);
          _syncStep2DraftToParent();
        },
        labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
        onClear: selectedCondition != null
            ? () {
                setState(() => selectedCondition = null);
                _syncStep2DraftToParent();
              }
            : null,
      ),
      ..._sellStep2CylinderEngineSection(),
      FilterIconCardSection(
        title: loc.transmissionLabel,
        options: getAvailableTransmissions(),
        selected: selectedTransmission,
        requiredField: true,
        isError: errTransmission,
        scrollHorizontally: true,
        tileWidth: 88,
        tileImageWidth: 76,
        tileImageHeight: 76,
        tileImageBorderRadius: 8,
        iconForOption: filterTransmissionIcon,
        imageAssetForOption: transmissionTypeImageAsset,
        labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
        onSelected: (value) {
          setState(() {
            selectedTransmission = value;
            _syncStep2ToOnlineVariant({'tr'});
          });
          _syncStep2DraftToParent();
        },
        onClear: selectedTransmission != null
            ? () {
                setState(() => selectedTransmission = null);
                _syncStep2DraftToParent();
              }
            : null,
      ),
      ..._sellStep2TitleStatusSection(),
      FilterIconCardSection(
        title: loc.fuelTypeLabel,
        options: getAvailableFuelTypes(),
        selected: selectedFuelType,
        requiredField: true,
        isError: errFuelType,
        scrollHorizontally: true,
        tileWidth: 80,
        tileImageWidth: 40,
        tileImageHeight: 40,
        tileImageBorderRadius: 6,
        compactImageTile: true,
        iconForOption: filterFuelTypeIcon,
        imageAssetForOption: fuelTypeImageAsset,
        labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
        onSelected: (value) {
          setState(() {
            selectedFuelType = value;
            _syncStep2ToOnlineVariant({'fuel'});
          });
          _syncStep2DraftToParent();
        },
        onClear: selectedFuelType != null
            ? () {
                setState(() => selectedFuelType = null);
                _syncStep2DraftToParent();
              }
            : null,
      ),
    ];
  }
}
