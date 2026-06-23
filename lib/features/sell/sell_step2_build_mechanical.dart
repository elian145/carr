part of 'sell_flow.dart';

mixin _SellStep2BuildMechanical on _SellStep2BuildAppearance {
  List<Widget> _sellStep2BuildMechanicalSection() {
    return [
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
    ];
  }
}
