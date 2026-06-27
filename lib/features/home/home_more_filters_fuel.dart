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
                          TextFormField(
                            key: ValueKey(
                              'fuel_${_homeSelectedFuelTypes.join(',')}',
                            ),
                            readOnly: true,
                            style: TextStyle(
                              color:
                                  _homeSelectedFuelTypes.isNotEmpty
                                  ? style.onSurface
                                  : style.anyOrange,
                            ),
                            initialValue: _homeFuelTypeFilterLabel(context),
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
                              suffixIcon: const Icon(
                                Icons.local_gas_station,
                                color: Color(0xFFFF6B00),
                              ),
                            ),
                            onTap: () async {
                              final fuelTypes =
                                  await _showHomeMultiValuePickerDialog(
                                context,
                                title: AppLocalizations.of(
                                  context,
                                )!.fuelTypeLabel,
                                options: getAvailableFuelTypes(),
                                initialSelection: _homeSelectedFuelTypes,
                                labelForOption: (ctx, value) =>
                                    _translateValueGlobal(ctx, value) ??
                                    value,
                              );
                              if (fuelTypes == null) return;
                              setState(() {
                                _homeSetSelectedFuelTypes(fuelTypes);
                              });
                              setStateDialog(() {});
                            },
                          ),
      ];
}
