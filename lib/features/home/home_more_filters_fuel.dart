part of 'home_flow.dart';

mixin _HomePageMoreFiltersFuel on _HomePageMoreFiltersMileage {
  List<Widget> _moreFiltersFuelWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
                          SizedBox(
                            height:
                                style.fieldGap,
                          ),
                          DropdownButtonFormField<
                            String
                          >(
                            initialValue:
                                _getValidFuelTypeValue(),
                            decoration: InputDecoration(
                              labelText:
                                  AppLocalizations.of(
                                    context,
                                  )!.fuelTypeLabel,
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
                              ...getAvailableFuelTypes()
                                  .where(
                                    (f) =>
                                        f != 'Any',
                                  )
                                  .map(
                                    (
                                      f,
                                    ) => DropdownMenuItem(
                                      value: f,
                                      child: Text(
                                        _translateValueGlobal(
                                              context,
                                              f,
                                            ) ??
                                            f,
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (value) =>
                                setState(
                                  () =>
                                      selectedFuelType =
                                          value ==
                                              ''
                                          ? 'Any'
                                          : value,
                                ),
                          ),
      ];
}
