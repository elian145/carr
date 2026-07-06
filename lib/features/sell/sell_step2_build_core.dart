part of 'sell_flow.dart';

mixin _SellStep2BuildCore on _SellStep2Pickers {
  List<Widget> _sellStep2MileageSection() {
    final loc = AppLocalizations.of(context)!;
    final style = filterDialogStyle(context);
    final miles = [
      for (int m = 0; m <= 100000; m += 1000) m.toString(),
      for (int m = 105000; m <= 300000; m += 5000) m.toString(),
    ];

    String formatMileage(String value) {
      final parsed = int.tryParse(value) ?? 0;
      final nf = _decimalFormatterGlobal(context);
      return '${_localizeDigitsGlobal(context, nf.format(parsed))} ${loc.unit_km}';
    }

    return [
      FilterCard(
        isError: errMileage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionHeader(
              title: loc.mileageKmLabel,
              requiredField: true,
              valueSummary: selectedMileage == null
                  ? loc.tapToSelect
                  : formatMileage(selectedMileage!),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: isMileageManualInput
                      ? TextFormField(
                          focusNode: _mileageFocusNode,
                          controller: _mileageController,
                          decoration: filterFieldDecoration(
                            style,
                            loc.mileageKmLabel,
                            errorText: errMileage ? loc.pleaseSelectMileage : null,
                          ),
                          style: TextStyle(color: style.onSurface),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            setState(() {
                              selectedMileage = value.isEmpty ? null : value;
                            });
                            _syncStep2DraftToParent();
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return loc.pleaseEnterMileage;
                            }
                            final mileage = int.tryParse(value);
                            if (mileage == null) return loc.invalidMileage;
                            if (mileage < 0) return loc.mileageNegative;
                            return null;
                          },
                        )
                      : DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: selectedMileage != null &&
                                  miles.contains(selectedMileage)
                              ? selectedMileage
                              : null,
                          decoration: filterFieldDecoration(
                            style,
                            loc.mileageKmLabel,
                            errorText: errMileage ? loc.pleaseSelectMileage : null,
                          ),
                          items: miles.map((mile) {
                            return DropdownMenuItem<String>(
                              value: mile,
                              child: Text(formatMileage(mile)),
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
                            setState(() => selectedMileage = value);
                            _syncStep2DraftToParent();
                          },
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    if (isMileageManualInput) {
                      _mileageFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        isMileageManualInput = false;
                        if (_mileageController.text.isNotEmpty) {
                          selectedMileage = _mileageController.text;
                        }
                      });
                      _syncStep2DraftToParent();
                    } else {
                      setState(() {
                        isMileageManualInput = true;
                        _mileageController.clear();
                        selectedMileage = null;
                      });
                      _syncStep2DraftToParent();
                    }
                  },
                  icon: Icon(
                    isMileageManualInput ? Icons.check : Icons.edit,
                    color: kFilterAccentColor,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  tooltip: isMileageManualInput
                      ? loc.confirmMileage
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
            const Icon(Icons.settings, size: 48, color: kFilterAccentColor),
            const SizedBox(height: 12),
            Text(
              loc.carDetailsTitle,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.carDetailsSubtitle,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
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
      FilterIconCardSection(
        title: loc.fuelTypeLabel,
        options: getAvailableFuelTypes(),
        selected: selectedFuelType,
        requiredField: true,
        isError: errFuelType,
        scrollHorizontally: true,
        iconForOption: filterFuelTypeIcon,
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
