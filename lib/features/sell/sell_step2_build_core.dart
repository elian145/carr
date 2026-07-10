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
        tileWidth: 100,
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
