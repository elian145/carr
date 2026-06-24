part of 'home_flow.dart';

mixin _HomePageMoreFiltersMileageRange on _HomePageMoreFiltersYear {
  List<Widget> _moreFiltersMileageRangeWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
                          // Mileage Filter
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              AppLocalizations.of(
                                context,
                              )!.mileageRangeLabel,
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
                                    isMileageDropdown
                                    ? Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child:
                                                    DropdownButtonFormField<
                                                      String
                                                    >(
                                                      initialValue:
                                                          (selectedMinMileage !=
                                                                  null &&
                                                              selectedMinMileage!.isNotEmpty)
                                                          ? selectedMinMileage
                                                          : '',
                                                      decoration: InputDecoration(
                                                        hintText: AppLocalizations.of(
                                                          context,
                                                        )!.minMileage,
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
                                                                int m = 0;
                                                                m <=
                                                                    100000;
                                                                m += 1000
                                                              )
                                                                m,
                                                              for (
                                                                int m = 105000;
                                                                m <=
                                                                    300000;
                                                                m += 5000
                                                              )
                                                                m,
                                                            ]
                                                            .where(
                                                              (
                                                                m,
                                                              ) {
                                                                if (selectedMaxMileage ==
                                                                        null ||
                                                                    selectedMaxMileage!.isEmpty) {
                                                                  return true;
                                                                }
                                                                final max = int.tryParse(
                                                                  selectedMaxMileage!,
                                                                );
                                                                return max ==
                                                                        null
                                                                    ? true
                                                                    : m <=
                                                                          max;
                                                              },
                                                            )
                                                            .map(
                                                              (
                                                                m,
                                                              ) => DropdownMenuItem(
                                                                value: m.toString(),
                                                                child: Text(
                                                                  _localizeDigitsGlobal(
                                                                    context,
                                                                    m.toString().replaceAllMapped(
                                                                      RegExp(
                                                                        r'(\d{1,3})(?=(\d{3})+(?!\d))',
                                                                      ),
                                                                      (
                                                                        mm,
                                                                      ) => '${mm[1]},',
                                                                    ),
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
                                                                selectedMinMileage =
                                                                    (value ==
                                                                            null ||
                                                                        value.isEmpty)
                                                                    ? null
                                                                    : value;
                                                                final min = int.tryParse(
                                                                  selectedMinMileage ??
                                                                      '',
                                                                );
                                                                final max = int.tryParse(
                                                                  selectedMaxMileage ??
                                                                      '',
                                                                );
                                                                if (min !=
                                                                        null &&
                                                                    max !=
                                                                        null &&
                                                                    min >
                                                                        max) {
                                                                  selectedMaxMileage = selectedMinMileage;
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
                                                      initialValue:
                                                          (selectedMaxMileage !=
                                                                  null &&
                                                              selectedMaxMileage!.isNotEmpty)
                                                          ? selectedMaxMileage
                                                          : '',
                                                      decoration: InputDecoration(
                                                        hintText: AppLocalizations.of(
                                                          context,
                                                        )!.maxMileage,
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
                                                                int m = 0;
                                                                m <=
                                                                    100000;
                                                                m += 1000
                                                              )
                                                                m,
                                                              for (
                                                                int m = 105000;
                                                                m <=
                                                                    300000;
                                                                m += 5000
                                                              )
                                                                m,
                                                            ]
                                                            .where(
                                                              (
                                                                m,
                                                              ) {
                                                                if (selectedMinMileage ==
                                                                        null ||
                                                                    selectedMinMileage!.isNotEmpty ==
                                                                        false) {
                                                                  return true;
                                                                }
                                                                final min = int.tryParse(
                                                                  selectedMinMileage!,
                                                                );
                                                                return min ==
                                                                        null
                                                                    ? true
                                                                    : m >=
                                                                          min;
                                                              },
                                                            )
                                                            .map(
                                                              (
                                                                m,
                                                              ) => DropdownMenuItem(
                                                                value: m.toString(),
                                                                child: Text(
                                                                  _localizeDigitsGlobal(
                                                                    context,
                                                                    m.toString().replaceAllMapped(
                                                                      RegExp(
                                                                        r'(\d{1,3})(?=(\d{3})+(?!\d))',
                                                                      ),
                                                                      (
                                                                        mm,
                                                                      ) => '${mm[1]},',
                                                                    ),
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
                                                                selectedMaxMileage =
                                                                    (value ==
                                                                            null ||
                                                                        value.isEmpty)
                                                                    ? null
                                                                    : value;
                                                                final min = int.tryParse(
                                                                  selectedMinMileage ??
                                                                      '',
                                                                );
                                                                final max = int.tryParse(
                                                                  selectedMaxMileage ??
                                                                      '',
                                                                );
                                                                if (min !=
                                                                        null &&
                                                                    max !=
                                                                        null &&
                                                                    max <
                                                                        min) {
                                                                  selectedMinMileage = selectedMaxMileage;
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
                                                  controller: _minMileageController,
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
                                                            selectedMinMileage = value.isEmpty
                                                                ? null
                                                                : value;
                                                            final min = int.tryParse(
                                                              selectedMinMileage ??
                                                                  '',
                                                            );
                                                            final max = int.tryParse(
                                                              selectedMaxMileage ??
                                                                  '',
                                                            );
                                                            if (min !=
                                                                    null &&
                                                                max !=
                                                                    null &&
                                                                min >
                                                                    max) {
                                                              selectedMaxMileage = selectedMinMileage;
                                                              _maxMileageController.text =
                                                                  selectedMaxMileage ??
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
                                                  controller: _maxMileageController,
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
                                                            selectedMaxMileage = value.isEmpty
                                                                ? null
                                                                : value;
                                                            final min = int.tryParse(
                                                              selectedMinMileage ??
                                                                  '',
                                                            );
                                                            final max = int.tryParse(
                                                              selectedMaxMileage ??
                                                                  '',
                                                            );
                                                            if (min !=
                                                                    null &&
                                                                max !=
                                                                    null &&
                                                                max <
                                                                    min) {
                                                              selectedMinMileage = selectedMaxMileage;
                                                              _minMileageController.text =
                                                                  selectedMinMileage ??
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
                                  if (isMileageDropdown) {
                                    _minMileageController
                                            .text =
                                        selectedMinMileage ??
                                        '';
                                    _maxMileageController
                                            .text =
                                        selectedMaxMileage ??
                                        '';
                                  }
                                  isMileageDropdown =
                                      !isMileageDropdown;
                                }),
                                icon: Icon(
                                  isMileageDropdown
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
      ];
}
