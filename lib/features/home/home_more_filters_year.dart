part of 'home_flow.dart';

mixin _HomePageMoreFiltersYear on _HomePageMoreFiltersPrice {
  List<Widget> _moreFiltersYearWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    return <Widget>[
                          // Year Filter
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              AppLocalizations.of(
                                context,
                              )!.yearRange,
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
                                    isYearDropdown
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
                                                          selectedMinYear ??
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
                                                        ...List.generate(
                                                              127,
                                                              (
                                                                i,
                                                              ) =>
                                                                  (1900 +
                                                                          i)
                                                                      .toString(),
                                                            ).reversed
                                                            .where(
                                                              (
                                                                y,
                                                              ) {
                                                                if (selectedMaxYear ==
                                                                        null ||
                                                                    selectedMaxYear!.isEmpty) {
                                                                  return true;
                                                                }
                                                                final max = int.tryParse(
                                                                  selectedMaxYear!,
                                                                );
                                                                final val = int.tryParse(
                                                                  y,
                                                                );
                                                                return max ==
                                                                            null ||
                                                                        val ==
                                                                            null
                                                                    ? true
                                                                    : val <=
                                                                          max;
                                                              },
                                                            )
                                                            .map(
                                                              (
                                                                y,
                                                              ) => DropdownMenuItem(
                                                                value: y,
                                                                child: Text(
                                                                  _localizeDigitsGlobal(
                                                                    context,
                                                                    y,
                                                                  ),
                                                                  style: TextStyle(
                                                                    color: style.onSurface,
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
                                                                selectedMinYear =
                                                                    value?.isEmpty ==
                                                                        true
                                                                    ? null
                                                                    : value;
                                                                final min = int.tryParse(
                                                                  selectedMinYear ??
                                                                      '',
                                                                );
                                                                final max = int.tryParse(
                                                                  selectedMaxYear ??
                                                                      '',
                                                                );
                                                                if (min !=
                                                                        null &&
                                                                    max !=
                                                                        null &&
                                                                    min >
                                                                        max) {
                                                                  selectedMaxYear = selectedMinYear;
                                                                }
                                                                _afterHomeYearBoundsChanged();
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
                                                          selectedMaxYear ??
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
                                                        ...List.generate(
                                                              127,
                                                              (
                                                                i,
                                                              ) =>
                                                                  (1900 +
                                                                          i)
                                                                      .toString(),
                                                            ).reversed
                                                            .where(
                                                              (
                                                                y,
                                                              ) {
                                                                if (selectedMinYear ==
                                                                        null ||
                                                                    selectedMinYear!.isEmpty) {
                                                                  return true;
                                                                }
                                                                final min = int.tryParse(
                                                                  selectedMinYear!,
                                                                );
                                                                final val = int.tryParse(
                                                                  y,
                                                                );
                                                                return min ==
                                                                            null ||
                                                                        val ==
                                                                            null
                                                                    ? true
                                                                    : val >=
                                                                          min;
                                                              },
                                                            )
                                                            .map(
                                                              (
                                                                y,
                                                              ) => DropdownMenuItem(
                                                                value: y,
                                                                child: Text(
                                                                  _localizeDigitsGlobal(
                                                                    context,
                                                                    y,
                                                                  ),
                                                                  style: TextStyle(
                                                                    color: style.onSurface,
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
                                                                selectedMaxYear =
                                                                    value?.isEmpty ==
                                                                        true
                                                                    ? null
                                                                    : value;
                                                                final min = int.tryParse(
                                                                  selectedMinYear ??
                                                                      '',
                                                                );
                                                                final max = int.tryParse(
                                                                  selectedMaxYear ??
                                                                      '',
                                                                );
                                                                if (min !=
                                                                        null &&
                                                                    max !=
                                                                        null &&
                                                                    max <
                                                                        min) {
                                                                  selectedMinYear = selectedMaxYear;
                                                                }
                                                                _afterHomeYearBoundsChanged();
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
                                                  controller: _minYearController,
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
                                                            selectedMinYear = value.isEmpty
                                                                ? null
                                                                : value;
                                                            final min = int.tryParse(
                                                              selectedMinYear ??
                                                                  '',
                                                            );
                                                            final max = int.tryParse(
                                                              selectedMaxYear ??
                                                                  '',
                                                            );
                                                            if (min !=
                                                                    null &&
                                                                max !=
                                                                    null &&
                                                                min >
                                                                    max) {
                                                              selectedMaxYear = selectedMinYear;
                                                              _maxYearController.text =
                                                                  selectedMaxYear ??
                                                                  '';
                                                            }
                                                            _afterHomeYearBoundsChanged();
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
                                                  controller: _maxYearController,
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
                                                            selectedMaxYear = value.isEmpty
                                                                ? null
                                                                : value;
                                                            final min = int.tryParse(
                                                              selectedMinYear ??
                                                                  '',
                                                            );
                                                            final max = int.tryParse(
                                                              selectedMaxYear ??
                                                                  '',
                                                            );
                                                            if (min !=
                                                                    null &&
                                                                max !=
                                                                    null &&
                                                                max <
                                                                    min) {
                                                              selectedMinYear = selectedMaxYear;
                                                              _minYearController.text =
                                                                  selectedMinYear ??
                                                                  '';
                                                            }
                                                            _afterHomeYearBoundsChanged();
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
                                  if (isYearDropdown) {
                                    _minYearController
                                            .text =
                                        selectedMinYear ??
                                        '';
                                    _maxYearController
                                            .text =
                                        selectedMaxYear ??
                                        '';
                                  }
                                  isYearDropdown =
                                      !isYearDropdown;
                                }),
                                icon: Icon(
                                  isYearDropdown
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
