part of 'home_flow.dart';

mixin _HomePageMoreFiltersSpecsPlate on _HomePageMoreFiltersSpecsEngine {
  List<Widget> _moreFiltersSpecsPlateWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
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

mixin _HomePageMoreFiltersSpecs on _HomePageMoreFiltersSpecsPlate {
  List<Widget> _moreFiltersSpecsWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
        ..._moreFiltersSpecsDriveWidgets(context, setStateDialog, style),
        ..._moreFiltersSpecsEngineWidgets(context, setStateDialog, style),
        ..._moreFiltersSpecsPlateWidgets(context, setStateDialog, style),
      ];
}
