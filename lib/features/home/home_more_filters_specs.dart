part of 'home_flow.dart';

mixin _HomePageMoreFiltersSpecs on _HomePageMoreFiltersMid {
  List<Widget> _moreFiltersSpecsWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    return <Widget>[
                          // Drive Type Dropdown
                          DropdownButtonFormField<
                            String
                          >(
                            initialValue:
                                _getValidDriveTypeValue(),
                            decoration: InputDecoration(
                              labelText:
                                  AppLocalizations.of(
                                    context,
                                  )!.driveType,
                              filled: true,
                              fillColor:
                                  style.fieldFill,
                              labelStyle: TextStyle(
                                color:
                                    style.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.any,
                                  style: TextStyle(
                                    color:
                                        style.anyOrange,
                                  ),
                                ),
                              ),
                              ...getAvailableDriveTypes()
                                  .where(
                                    (d) =>
                                        d != 'Any',
                                  )
                                  .map(
                                    (
                                      d,
                                    ) => DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        _translateValueGlobal(
                                              context,
                                              d,
                                            ) ??
                                            d,
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (value) {
                              setState(
                                () =>
                                    selectedDriveType =
                                        value == ''
                                        ? null
                                        : value,
                              );
                              _persistFilters();
                            },
                          ),
                          SizedBox(height: 12),
                          DropdownButtonFormField<
                            String
                          >(
                            key: ValueKey(
                              'home_more_region_specs_$_moreFiltersDialogFieldGeneration',
                            ),
                            initialValue:
                                _getValidRegionSpecsValue(),
                            decoration: InputDecoration(
                              labelText:
                                  AppLocalizations.of(
                                    context,
                                  )!.regionSpecsLabel,
                              filled: true,
                              fillColor:
                                  style.fieldFill,
                              labelStyle: TextStyle(
                                color:
                                    style.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.any,
                                  style: TextStyle(
                                    color:
                                        style.anyOrange,
                                  ),
                                ),
                              ),
                              ...kCarRegionSpecCodes.map(
                                (
                                  code,
                                ) => DropdownMenuItem(
                                  value: code,
                                  child: Text(
                                    carRegionSpecDisplayLabelLocalized(
                                      context,
                                      code,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(
                                () => selectedRegionSpecs =
                                    value == null ||
                                        value
                                            .isEmpty
                                    ? null
                                    : value,
                              );
                              _persistFilters();
                            },
                          ),
                          SizedBox(height: 12),
                          // Cylinder Count Dropdown
                          DropdownButtonFormField<
                            String
                          >(
                            initialValue:
                                _getValidCylinderCountValue(),
                            decoration: InputDecoration(
                              labelText:
                                  AppLocalizations.of(
                                    context,
                                  )!.cylinderCount,
                              filled: true,
                              fillColor:
                                  style.fieldFill,
                              labelStyle: TextStyle(
                                color:
                                    style.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.any,
                                  style: TextStyle(
                                    color:
                                        style.anyOrange,
                                  ),
                                ),
                              ),
                              ...getAvailableCylinderCounts()
                                  .where(
                                    (c) =>
                                        c != 'Any',
                                  )
                                  .map(
                                    (
                                      c,
                                    ) => DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                        _localizeDigitsGlobal(
                                          context,
                                          c,
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedCylinderCount =
                                    value == ''
                                    ? null
                                    : value;
                                _applyMoreFiltersEngineSyncFromCylinder(
                                  selectedCylinderCount,
                                );
                              });
                              setStateDialog(() {});
                              _persistFilters();
                            },
                          ),
                          SizedBox(height: 12),
                          // Seating Dropdown
                          DropdownButtonFormField<
                            String
                          >(
                            initialValue:
                                selectedSeating ??
                                '',
                            decoration: InputDecoration(
                              labelText:
                                  AppLocalizations.of(
                                    context,
                                  )!.seating,
                              filled: true,
                              fillColor:
                                  style.fieldFill,
                              labelStyle: TextStyle(
                                color:
                                    style.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.any,
                                  style: TextStyle(
                                    color:
                                        style.anyOrange,
                                  ),
                                ),
                              ),
                              ...getAvailableSeatings()
                                  .where(
                                    (s) =>
                                        s != 'Any',
                                  )
                                  .map(
                                    (
                                      s,
                                    ) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        _localizeDigitsGlobal(
                                          context,
                                          s,
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (value) {
                              setState(
                                () =>
                                    selectedSeating =
                                        value == ''
                                        ? null
                                        : value,
                              );
                              _persistFilters();
                            },
                          ),
                          SizedBox(height: 12),
                          // Engine Size Dropdown / Manual input
                          Row(
                            children: [
                              Expanded(
                                child:
                                    isEngineSizeDropdown
                                    ? DropdownButtonFormField<
                                        String
                                      >(
                                        initialValue:
                                            _getValidEngineSizeValue(),
                                        decoration: InputDecoration(
                                          labelText: AppLocalizations.of(
                                            context,
                                          )!.engineSizeL,
                                          filled:
                                              true,
                                          fillColor:
                                              style.fieldFill,
                                          labelStyle:
                                              TextStyle(
                                                color:
                                                    style.onSurface,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(
                                                  12,
                                                ),
                                          ),
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value:
                                                '',
                                            child: Text(
                                              AppLocalizations.of(
                                                context,
                                              )!.any,
                                              style: TextStyle(
                                                color:
                                                    style.anyOrange,
                                              ),
                                            ),
                                          ),
                                          ...getAvailableEngineSizes()
                                              .where(
                                                (
                                                  e,
                                                ) =>
                                                    e !=
                                                    'Any',
                                              )
                                              .map(
                                                (
                                                  e,
                                                ) => DropdownMenuItem(
                                                  value: e,
                                                  child: Text(
                                                    '${_localizeDigitsGlobal(context, e)}${AppLocalizations.of(context)!.unit_liter_suffix}',
                                                  ),
                                                ),
                                              ),
                                        ],
                                        onChanged: (value) {
                                          setState(() {
                                            selectedEngineSize =
                                                value ==
                                                    ''
                                                ? null
                                                : value;
                                            _applyMoreFiltersCylinderSyncFromEngine(
                                              selectedEngineSize,
                                            );
                                          });
                                          setStateDialog(
                                            () {},
                                          );
                                          _persistFilters();
                                        },
                                      )
                                    : TextFormField(
                                        controller:
                                            _engineSizeController,
                                        decoration: InputDecoration(
                                          labelText: AppLocalizations.of(
                                            context,
                                          )!.engineSizeL,
                                          filled:
                                              true,
                                          fillColor:
                                              style.fieldFill,
                                          labelStyle:
                                              TextStyle(
                                                color:
                                                    style.onSurface,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(
                                                  12,
                                                ),
                                          ),
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal:
                                                  true,
                                            ),
                                        inputFormatters: [
                                          services
                                              .FilteringTextInputFormatter.allow(
                                            RegExp(
                                              r'[0-9.]',
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          setState(() {
                                            selectedEngineSize =
                                                value.isEmpty
                                                ? null
                                                : value;
                                            _applyMoreFiltersCylinderSyncFromEngine(
                                              selectedEngineSize,
                                            );
                                          });
                                          setStateDialog(
                                            () {},
                                          );
                                          _persistFilters();
                                        },
                                      ),
                              ),
                              const SizedBox(
                                width: 8,
                              ),
                              IconButton(
                                onPressed: () => setStateDialog(() {
                                  if (isEngineSizeDropdown) {
                                    _engineSizeController
                                            .text =
                                        selectedEngineSize ??
                                        '';
                                  }
                                  isEngineSizeDropdown =
                                      !isEngineSizeDropdown;
                                }),
                                icon: Icon(
                                  isEngineSizeDropdown
                                      ? Icons.edit
                                      : Icons.list,
                                  color:
                                      const Color(
                                        0xFFFF6B00,
                                      ),
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      style.fieldFill,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                          8,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          DropdownButtonFormField<
                            String
                          >(
                            initialValue:
                                selectedPlateType ??
                                '',
                            decoration: InputDecoration(
                              labelText: _trLegacyText(context, 'Plate type', ar: 'نوع اللوحة', ku: 'جۆری پڵەیت'),
                              filled: true,
                              fillColor:
                                  style.fieldFill,
                              labelStyle: TextStyle(
                                color:
                                    style.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.any,
                                  style: TextStyle(
                                    color:
                                        style.anyOrange,
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'private',
                                child: Text(
                                  _translatePlateTypeLegacy(
                                    context,
                                    'private',
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'temporary',
                                child: Text(
                                  _translatePlateTypeLegacy(
                                    context,
                                    'temporary',
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'commercial',
                                child: Text(
                                  _translatePlateTypeLegacy(
                                    context,
                                    'commercial',
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'taxi',
                                child: Text(
                                  _translatePlateTypeLegacy(
                                    context,
                                    'taxi',
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedPlateType =
                                    (value == null ||
                                            value
                                                .isEmpty)
                                    ? null
                                    : value;
                              });
                              _persistFilters();
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<
                            String
                          >(
                            initialValue:
                                selectedPlateCity ??
                                '',
                            decoration: InputDecoration(
                              labelText: _trLegacyText(context, 'Plate city', ar: 'مدينة اللوحة', ku: 'شاری پڵەیت'),
                              filled: true,
                              fillColor:
                                  style.fieldFill,
                              labelStyle: TextStyle(
                                color:
                                    style.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.any,
                                  style: TextStyle(
                                    color:
                                        style.anyOrange,
                                  ),
                                ),
                              ),
                              ...cities
                                  .where(
                                    (c) =>
                                        c.toLowerCase() !=
                                        'any',
                                  )
                                  .map(
                                    (c) =>
                                        DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                        _translateValueGlobal(
                                              context,
                                              c,
                                            ) ??
                                            c,
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedPlateCity =
                                    (value == null ||
                                            value
                                                .isEmpty)
                                    ? null
                                    : value;
                              });
                              _persistFilters();
                            },
                          ),
    ];
  }
}
