part of 'home_flow.dart';

mixin _HomePageMoreFiltersSpecsDrive on _HomePageMoreFiltersMid {
  List<Widget> _moreFiltersSpecsDriveWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
                          // Drive Type multi-select
                          TextFormField(
                            key: ValueKey(
                              'drive_${_homeSelectedDriveTypes.join(',')}',
                            ),
                            readOnly: true,
                            style: TextStyle(
                              color:
                                  _homeSelectedDriveTypes.isNotEmpty
                                  ? style.onSurface
                                  : style.anyOrange,
                            ),
                            initialValue: _homeDriveTypeFilterLabel(context),
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
                              suffixIcon: const Icon(
                                Icons.settings,
                                color: Color(0xFFFF6B00),
                              ),
                            ),
                            onTap: () async {
                              final driveTypes =
                                  await _showHomeMultiValuePickerDialog(
                                context,
                                title: AppLocalizations.of(
                                  context,
                                )!.driveType,
                                options: getAvailableDriveTypes(),
                                initialSelection: _homeSelectedDriveTypes,
                                labelForOption: (ctx, value) =>
                                    _translateValueGlobal(ctx, value) ??
                                    value,
                              );
                              if (driveTypes == null) return;
                              setState(() {
                                _homeSetSelectedDriveTypes(driveTypes);
                              });
                              setStateDialog(() {});
                              _persistFilters();
                            },
                          ),
      ];

  List<Widget> _moreFiltersRegionSpecsWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
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
      ];
}
