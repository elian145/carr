part of 'home_flow.dart';

mixin _HomePageMoreFiltersSpecsDrive on _HomePageMoreFiltersMid {
  List<Widget> _moreFiltersSpecsDriveWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
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
