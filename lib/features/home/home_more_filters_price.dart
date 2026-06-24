part of 'home_flow.dart';

mixin _HomePageMoreFiltersPrice on _HomePageMoreFiltersVehicle {
  List<Widget> _moreFiltersPriceWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    return <Widget>[
                          // Price Filter
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              AppLocalizations.of(
                                context,
                              )!.priceRange,
                              style: TextStyle(
                                color:
                                    style.onSurface,
                                fontWeight:
                                    FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child:
                                    isPriceDropdown
                                    ? Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child:
                                                    DropdownButtonFormField<
                                                      String
                                                    >(
                                                      isExpanded: true,
                                                      initialValue:
                                                          selectedMinPrice ??
                                                          '',
                                                      decoration: InputDecoration(
                                                        hintText: AppLocalizations.of(
                                                          context,
                                                        )!.any,
                                                        filled: true,
                                                        fillColor: style.fieldFill,
                                                        hintStyle: TextStyle(
                                                          color: style.anyOrange,
                                                        ),
                                                        border: OutlineInputBorder(
                                                          borderRadius: BorderRadius.circular(
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
                                                              color: style.anyOrange,
                                                            ),
                                                          ),
                                                        ),
                                                        ...[
                                                              for (
                                                                int p = 500;
                                                                p <=
                                                                    300000;
                                                                p += 500
                                                              )
                                                                p,
                                                              for (
                                                                int p = 310000;
                                                                p <=
                                                                    2000000;
                                                                p += 10000
                                                              )
                                                                p,
                                                            ]
                                                            .where(
                                                              (
                                                                p,
                                                              ) {
                                                                if (selectedMaxPrice ==
                                                                        null ||
                                                                    selectedMaxPrice!.isEmpty) {
                                                                  return true;
                                                                }
                                                                final max = int.tryParse(
                                                                  selectedMaxPrice!,
                                                                );
                                                                return max ==
                                                                        null
                                                                    ? true
                                                                    : p <=
                                                                          max;
                                                              },
                                                            )
                                                            .map(
                                                              (
                                                                p,
                                                              ) => DropdownMenuItem(
                                                                value: p.toString(),
                                                                child: Text(
                                                                  _formatCurrencyGlobal(
                                                                    context,
                                                                    p,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                      ],
                                                      onChanged:
                                                          (
                                                            value,
                                                          ) {
                                                            setState(
                                                              () {
                                                                selectedMinPrice =
                                                                    value?.isEmpty ==
                                                                        true
                                                                    ? null
                                                                    : value;
                                                                final min = int.tryParse(
                                                                  selectedMinPrice ??
                                                                      '',
                                                                );
                                                                final max = int.tryParse(
                                                                  selectedMaxPrice ??
                                                                      '',
                                                                );
                                                                if (min !=
                                                                        null &&
                                                                    max !=
                                                                        null &&
                                                                    min >
                                                                        max) {
                                                                  selectedMaxPrice = selectedMinPrice;
                                                                }
                                                              },
                                                            );
                                                            setStateDialog(
                                                              () {},
                                                            );
                                                          },
                                                    ),
                                              ),
                                              SizedBox(
                                                width:
                                                    8,
                                              ),
                                              Expanded(
                                                child:
                                                    DropdownButtonFormField<
                                                      String
                                                    >(
                                                      isExpanded: true,
                                                      initialValue:
                                                          selectedMaxPrice ??
                                                          '',
                                                      decoration: InputDecoration(
                                                        hintText: AppLocalizations.of(
                                                          context,
                                                        )!.any,
                                                        filled: true,
                                                        fillColor: style.fieldFill,
                                                        hintStyle: TextStyle(
                                                          color: style.anyOrange,
                                                        ),
                                                        border: OutlineInputBorder(
                                                          borderRadius: BorderRadius.circular(
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
                                                              color: style.anyOrange,
                                                            ),
                                                          ),
                                                        ),
                                                        ...[
                                                              for (
                                                                int p = 500;
                                                                p <=
                                                                    300000;
                                                                p += 500
                                                              )
                                                                p,
                                                              for (
                                                                int p = 310000;
                                                                p <=
                                                                    2000000;
                                                                p += 10000
                                                              )
                                                                p,
                                                            ]
                                                            .where(
                                                              (
                                                                p,
                                                              ) {
                                                                if (selectedMinPrice ==
                                                                        null ||
                                                                    selectedMinPrice!.isEmpty) {
                                                                  return true;
                                                                }
                                                                final min = int.tryParse(
                                                                  selectedMinPrice!,
                                                                );
                                                                return min ==
                                                                        null
                                                                    ? true
                                                                    : p >=
                                                                          min;
                                                              },
                                                            )
                                                            .map(
                                                              (
                                                                p,
                                                              ) => DropdownMenuItem(
                                                                value: p.toString(),
                                                                child: Text(
                                                                  _formatCurrencyGlobal(
                                                                    context,
                                                                    p,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                      ],
                                                      onChanged:
                                                          (
                                                            value,
                                                          ) {
                                                            setState(
                                                              () {
                                                                selectedMaxPrice =
                                                                    value?.isEmpty ==
                                                                        true
                                                                    ? null
                                                                    : value;
                                                                final min = int.tryParse(
                                                                  selectedMinPrice ??
                                                                      '',
                                                                );
                                                                final max = int.tryParse(
                                                                  selectedMaxPrice ??
                                                                      '',
                                                                );
                                                                if (min !=
                                                                        null &&
                                                                    max !=
                                                                        null &&
                                                                    max <
                                                                        min) {
                                                                  selectedMinPrice = selectedMaxPrice;
                                                                }
                                                              },
                                                            );
                                                            setStateDialog(
                                                              () {},
                                                            );
                                                          },
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      )
                                    : Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextFormField(
                                                  controller: _minPriceController,
                                                  decoration: InputDecoration(
                                                    hintText: AppLocalizations.of(
                                                      context,
                                                    )!.any,
                                                    filled: true,
                                                    fillColor: style.fieldFill,
                                                    hintStyle: TextStyle(
                                                      color: style.anyOrange,
                                                    ),
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(
                                                        12,
                                                      ),
                                                    ),
                                                  ),
                                                  keyboardType: TextInputType.number,
                                                  onChanged:
                                                      (
                                                        value,
                                                      ) {
                                                        setState(
                                                          () {
                                                            selectedMinPrice = value.isEmpty
                                                                ? null
                                                                : value;
                                                            final min = int.tryParse(
                                                              selectedMinPrice ??
                                                                  '',
                                                            );
                                                            final max = int.tryParse(
                                                              selectedMaxPrice ??
                                                                  '',
                                                            );
                                                            if (min !=
                                                                    null &&
                                                                max !=
                                                                    null &&
                                                                min >
                                                                    max) {
                                                              selectedMaxPrice = selectedMinPrice;
                                                              _maxPriceController.text =
                                                                  selectedMaxPrice ??
                                                                  '';
                                                            }
                                                          },
                                                        );
                                                        setStateDialog(
                                                          () {},
                                                        );
                                                      },
                                                ),
                                              ),
                                              SizedBox(
                                                width:
                                                    8,
                                              ),
                                              Expanded(
                                                child: TextFormField(
                                                  controller: _maxPriceController,
                                                  decoration: InputDecoration(
                                                    hintText: AppLocalizations.of(
                                                      context,
                                                    )!.any,
                                                    filled: true,
                                                    fillColor: style.fieldFill,
                                                    hintStyle: TextStyle(
                                                      color: style.anyOrange,
                                                    ),
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(
                                                        12,
                                                      ),
                                                    ),
                                                  ),
                                                  keyboardType: TextInputType.number,
                                                  onChanged:
                                                      (
                                                        value,
                                                      ) {
                                                        setState(
                                                          () {
                                                            selectedMaxPrice = value.isEmpty
                                                                ? null
                                                                : value;
                                                            final min = int.tryParse(
                                                              selectedMinPrice ??
                                                                  '',
                                                            );
                                                            final max = int.tryParse(
                                                              selectedMaxPrice ??
                                                                  '',
                                                            );
                                                            if (min !=
                                                                    null &&
                                                                max !=
                                                                    null &&
                                                                max <
                                                                    min) {
                                                              selectedMinPrice = selectedMaxPrice;
                                                              _minPriceController.text =
                                                                  selectedMinPrice ??
                                                                  '';
                                                            }
                                                          },
                                                        );
                                                        setStateDialog(
                                                          () {},
                                                        );
                                                      },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                              ),
                              SizedBox(width: 8),
                              IconButton(
                                onPressed: () => setStateDialog(() {
                                  if (isPriceDropdown) {
                                    _minPriceController
                                            .text =
                                        selectedMinPrice ??
                                        '';
                                    _maxPriceController
                                            .text =
                                        selectedMaxPrice ??
                                        '';
                                  }
                                  isPriceDropdown =
                                      !isPriceDropdown;
                                }),
                                icon: Icon(
                                  isPriceDropdown
                                      ? Icons.edit
                                      : Icons.list,
                                  color: Color(
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
                          SizedBox(
                            height:
                                style.fieldGap,
                          ),
    ];
  }
}
