part of 'sell_flow.dart';

mixin _SellStep2BuildMechanical on _SellStep2BuildAppearance {
  List<Widget> _sellStep2SpecsDropdownSection() {
    final loc = AppLocalizations.of(context)!;
    final style = filterDialogStyle(context);

    return [
      FilterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionHeader(
              title: _trLegacyText(
                context,
                'Specifications',
                ar: 'المواصفات',
                ku: 'سپێسەکان',
              ),
              valueSummary: '',
            ),
            const SizedBox(height: 12),
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
                        '${_localizeDigitsGlobal(context, c)} ${_trLegacyText(context, 'cylinders', ar: 'أسطوانات', ku: 'سیلەندەر')}',
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
            FilterDropdownField(
              style: style,
              label: loc.seating,
              value: selectedSeating != null &&
                      getAvailableSeatings()
                          .where((s) => s != 'Any')
                          .contains(selectedSeating)
                  ? selectedSeating
                  : null,
              errorText: errSeating ? loc.pleaseSelectSeating : null,
              items: getAvailableSeatings()
                  .where((s) => s != 'Any')
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                        '${_localizeDigitsGlobal(context, s)} ${_trLegacyText(context, 'seats', ar: 'مقاعد', ku: 'دانیشتن')}',
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
                setState(() => selectedSeating = value);
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

  List<Widget> _sellStep2BuildMechanicalSection() {
    final loc = AppLocalizations.of(context)!;
    final style = filterDialogStyle(context);

    return [
      FilterIconCardSection(
        title: loc.driveType,
        options: getAvailableDriveTypes(),
        selected: selectedDriveType,
        requiredField: true,
        isError: errDrive,
        scrollHorizontally: true,
        tileWidth: 88,
        tileImageWidth: 76,
        tileImageHeight: 76,
        tileImageBorderRadius: 8,
        iconForOption: filterDriveTypeIcon,
        imageAssetForOption: driveTypeImageAsset,
        labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
        onSelected: (value) {
          setState(() {
            selectedDriveType = value;
            _syncStep2ToOnlineVariant({'drv'});
          });
          _syncStep2DraftToParent();
        },
        onClear: selectedDriveType != null
            ? () {
                setState(() => selectedDriveType = null);
                _syncStep2DraftToParent();
              }
            : null,
      ),
      FilterIconCardSection(
        title: loc.regionSpecsLabel,
        options: List<String>.from(kCarRegionSpecCodes),
        selected: selectedRegionSpecs,
        requiredField: true,
        isError: errRegionSpecs,
        scrollHorizontally: true,
        tileWidth: 80,
        tileImageWidth: 40,
        tileImageHeight: 28,
        tileImageFit: BoxFit.cover,
        tileImageBorderRadius: 4,
        iconForOption: filterRegionSpecIcon,
        imageAssetForOption: regionSpecFlagAsset,
        labelForOption: (ctx, o) => carRegionSpecDisplayLabelLocalized(ctx, o),
        onSelected: (value) {
          setState(() => selectedRegionSpecs = value?.trim().toLowerCase());
          _syncStep2DraftToParent();
        },
        onClear: selectedRegionSpecs != null
            ? () {
                setState(() => selectedRegionSpecs = null);
                _syncStep2DraftToParent();
              }
            : null,
      ),
      ..._sellStep2SpecsDropdownSection(),
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
      FilterCard(
        child: TextFormField(
          controller: _vinController,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(color: filterDialogStyle(context).onSurface),
          decoration: filterFieldDecoration(
            style,
            _trLegacyText(
              context,
              'VIN (optional)',
              ar: 'رقم الهيكل (اختياري)',
              ku: 'ژمارەی شاسی (ئارەزوومەندانە)',
            ),
          ).copyWith(
            hintText: 'e.g. 1HGBH41JXMN109186',
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
    ];
  }
}
