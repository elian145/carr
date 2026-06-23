part of 'home_flow.dart';

mixin _HomePageMoreFiltersDialog on _HomePageFilterBar {
  Future<void> _showMoreFiltersDialog(BuildContext context) async {
  // Sync manual-entry controllers to current selections
  // (do this once when opening the dialog, not during typing).
  _minPriceController.text =
      selectedMinPrice ?? '';
  _maxPriceController.text =
      selectedMaxPrice ?? '';
  _minYearController.text =
      selectedMinYear ?? '';
  _maxYearController.text =
      selectedMaxYear ?? '';
  _minMileageController.text =
      selectedMinMileage ?? '';
  _maxMileageController.text =
      selectedMaxMileage ?? '';
  _engineSizeController.text =
      selectedEngineSize ?? '';
  final moreFiltersSnapshot =
      _moreFiltersDialogSnapshot();
  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          final isLightMoreFilters =
              Theme.of(context).brightness ==
              Brightness.light;
          final moreFiltersBg =
              isLightMoreFilters
              ? Colors.white
              : (Colors.grey[900]
                        ?.withValues(alpha: 0.98) ??
                    Colors.grey.shade900);
          final moreFiltersOnSurface =
              isLightMoreFilters
              ? const Color(0xFF1A1A1A)
              : Colors.white;
          final moreFiltersMuted =
              isLightMoreFilters
              ? const Color(0xFF757575)
              : Colors.white70;
          final moreFiltersAnyOrange =
              const Color(0xFFFF6B00);
          final moreFiltersFieldFill =
              isLightMoreFilters
              ? Colors.grey.shade200
              : Colors.black.withValues(alpha: 0.2);
          const double moreFiltersFieldGap =
              18;
          return AlertDialog(
            backgroundColor: moreFiltersBg,
            surfaceTintColor:
                Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(20),
            ),
            title: Text(
              AppLocalizations.of(
                context,
              )!.moreFilters,
              style: GoogleFonts.orbitron(
                color: Color(0xFFFF6B00),
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: KeyedSubtree(
                key: ValueKey<int>(
                  _moreFiltersDialogFieldGeneration,
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    // Price Filter
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        AppLocalizations.of(
                          context,
                        )!.priceRange,
                        style: TextStyle(
                          color:
                              moreFiltersOnSurface,
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
                                                  fillColor: moreFiltersFieldFill,
                                                  hintStyle: TextStyle(
                                                    color: moreFiltersAnyOrange,
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
                                                        color: moreFiltersAnyOrange,
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
                                                  fillColor: moreFiltersFieldFill,
                                                  hintStyle: TextStyle(
                                                    color: moreFiltersAnyOrange,
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
                                                        color: moreFiltersAnyOrange,
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
                                              fillColor: moreFiltersFieldFill,
                                              hintStyle: TextStyle(
                                                color: moreFiltersAnyOrange,
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
                                              fillColor: moreFiltersFieldFill,
                                              hintStyle: TextStyle(
                                                color: moreFiltersAnyOrange,
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
                                moreFiltersFieldFill,
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
                          moreFiltersFieldGap,
                    ),
                    // Year Filter
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        AppLocalizations.of(
                          context,
                        )!.yearRange,
                        style: TextStyle(
                          color:
                              moreFiltersOnSurface,
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
                                                  fillColor: moreFiltersFieldFill,
                                                  hintStyle: TextStyle(
                                                    color: moreFiltersAnyOrange,
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
                                                        color: moreFiltersAnyOrange,
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
                                                              color: moreFiltersOnSurface,
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
                                                  fillColor: moreFiltersFieldFill,
                                                  hintStyle: TextStyle(
                                                    color: moreFiltersAnyOrange,
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
                                                        color: moreFiltersAnyOrange,
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
                                                              color: moreFiltersOnSurface,
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
                                              fillColor: moreFiltersFieldFill,
                                              hintStyle: TextStyle(
                                                color: moreFiltersAnyOrange,
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
                                              fillColor: moreFiltersFieldFill,
                                              hintStyle: TextStyle(
                                                color: moreFiltersAnyOrange,
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
                                moreFiltersFieldFill,
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
                          moreFiltersFieldGap,
                    ),
                    // Mileage Filter
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        AppLocalizations.of(
                          context,
                        )!.mileageRangeLabel,
                        style: TextStyle(
                          color:
                              moreFiltersOnSurface,
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
                                                  fillColor: moreFiltersFieldFill,
                                                  hintStyle: TextStyle(
                                                    color: moreFiltersAnyOrange,
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
                                                        color: moreFiltersAnyOrange,
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
                                                  fillColor: moreFiltersFieldFill,
                                                  hintStyle: TextStyle(
                                                    color: moreFiltersAnyOrange,
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
                                                        color: moreFiltersAnyOrange,
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
                                              fillColor: moreFiltersFieldFill,
                                              hintStyle: TextStyle(
                                                color: moreFiltersAnyOrange,
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
                                              fillColor: moreFiltersFieldFill,
                                              hintStyle: TextStyle(
                                                color: moreFiltersAnyOrange,
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
                                moreFiltersFieldFill,
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
                          moreFiltersFieldGap,
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        AppLocalizations.of(context)!.titleStatus,
                        style: TextStyle(
                          color: moreFiltersOnSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in <String, String>{
                            '': AppLocalizations.of(context)!.any,
                            'clean': AppLocalizations.of(context)!.value_title_clean,
                            'damaged': AppLocalizations.of(context)!.value_title_damaged,
                          }.entries)
                            ChoiceChip(
                              label: Text(entry.value),
                              selected: (selectedTitleStatus ?? '') == entry.key,
                              selectedColor: entry.key == ''
                                  ? moreFiltersAnyOrange
                                  : Theme.of(context).colorScheme.primary,
                              backgroundColor: moreFiltersFieldFill,
                              labelStyle: TextStyle(
                                color: (selectedTitleStatus ?? '') == entry.key
                                    ? Colors.white
                                    : moreFiltersOnSurface,
                                fontWeight: (selectedTitleStatus ?? '') == entry.key
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: (selectedTitleStatus ?? '') == entry.key
                                      ? Colors.transparent
                                      : moreFiltersOnSurface.withValues(alpha: 0.2),
                                ),
                              ),
                              onSelected: (_) {
                                setState(() {
                                  selectedTitleStatus = entry.key == '' ? null : entry.key;
                                  if (selectedTitleStatus != 'damaged') {
                                    selectedDamagedParts = null;
                                  }
                                });
                                setStateDialog(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                    if (selectedTitleStatus ==
                        'damaged')
                      ...[
                        SizedBox(
                          height:
                              moreFiltersFieldGap,
                        ),
                        DropdownButtonFormField<
                          String
                        >(
                          initialValue:
                              selectedDamagedParts ??
                              '',
                          decoration: InputDecoration(
                            labelText:
                                AppLocalizations.of(
                                  context,
                                )!.damagedParts,
                            filled: true,
                            fillColor:
                                moreFiltersFieldFill,
                            labelStyle: TextStyle(
                              color:
                                  moreFiltersOnSurface,
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
                                      moreFiltersAnyOrange,
                                ),
                              ),
                            ),
                            ...List.generate(
                              15,
                              (i) => (i + 1)
                                  .toString(),
                            ).map(
                              (
                                p,
                              ) => DropdownMenuItem(
                                value: p,
                                child: Text(
                                  '${_localizeDigitsGlobal(context, p)} ${AppLocalizations.of(context)!.damagedParts}',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(
                              () =>
                                  selectedDamagedParts =
                                      value ==
                                          ''
                                      ? null
                                      : value,
                            );
                            setStateDialog(
                              () {},
                            );
                          },
                        ),
                      ],
                    SizedBox(
                      height:
                          moreFiltersFieldGap,
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        AppLocalizations.of(context)!.conditionLabel,
                        style: TextStyle(
                          color: moreFiltersOnSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: conditions.map((c) {
                          final isSelected = (selectedCondition ?? 'Any') == c;
                          return ChoiceChip(
                            label: Text(
                              _translateValueGlobal(context, c) ?? c,
                            ),
                            selected: isSelected,
                            selectedColor: c == 'Any'
                                ? moreFiltersAnyOrange
                                : Theme.of(context).colorScheme.primary,
                            backgroundColor: moreFiltersFieldFill,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : moreFiltersOnSurface,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.transparent
                                    : moreFiltersOnSurface.withValues(alpha: 0.2),
                              ),
                            ),
                            onSelected: (_) {
                              setState(() {
                                selectedCondition = c == 'Any' ? 'Any' : c;
                              });
                              setStateDialog(() {});
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    SizedBox(
                      height:
                          moreFiltersFieldGap,
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        AppLocalizations.of(context)!.transmissionLabel,
                        style: TextStyle(
                          color: moreFiltersOnSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in ['Any', ...getAvailableTransmissions().where((t) => t != 'Any')])
                            ChoiceChip(
                              label: Text(
                                t == 'Any'
                                    ? AppLocalizations.of(context)!.any
                                    : _translateValueGlobal(context, t) ?? t,
                              ),
                              selected: (selectedTransmission ?? 'Any') == t,
                              selectedColor: t == 'Any'
                                  ? moreFiltersAnyOrange
                                  : Theme.of(context).colorScheme.primary,
                              backgroundColor: moreFiltersFieldFill,
                              labelStyle: TextStyle(
                                color: (selectedTransmission ?? 'Any') == t
                                    ? Colors.white
                                    : moreFiltersOnSurface,
                                fontWeight: (selectedTransmission ?? 'Any') == t
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: (selectedTransmission ?? 'Any') == t
                                      ? Colors.transparent
                                      : moreFiltersOnSurface.withValues(alpha: 0.2),
                                ),
                              ),
                              onSelected: (_) {
                                setState(() {
                                  selectedTransmission = t == 'Any' ? 'Any' : t;
                                });
                                setStateDialog(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height:
                          moreFiltersFieldGap,
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
                            moreFiltersFieldFill,
                        labelStyle: TextStyle(
                          color:
                              moreFiltersOnSurface,
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
                                  moreFiltersAnyOrange,
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
                    SizedBox(
                      height:
                          moreFiltersFieldGap,
                    ),
                    TextFormField(
                      key: ValueKey(
                        'bodyType_${selectedBodyType ?? 'any'}',
                      ),
                      readOnly: true,
                      style: TextStyle(
                        color:
                            (selectedBodyType !=
                                    null &&
                                selectedBodyType!
                                    .isNotEmpty)
                            ? moreFiltersOnSurface
                            : moreFiltersAnyOrange,
                      ),
                      initialValue:
                          (selectedBodyType ??
                          AppLocalizations.of(
                            context,
                          )!.any),
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(
                              context,
                            )!.bodyTypeLabel,
                        filled: true,
                        fillColor:
                            moreFiltersFieldFill,
                        labelStyle: TextStyle(
                          color:
                              moreFiltersOnSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(
                                12,
                              ),
                        ),
                        suffixIcon: Container(
                          margin:
                              EdgeInsets.all(
                                8,
                              ),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape
                                .circle,
                            color:
                                Colors.white,
                            border: Border.all(
                              color: Color(
                                0xFFFF6B00,
                              ),
                              width: 2,
                            ),
                          ),
                          child: Padding(
                            padding:
                                EdgeInsets.all(
                                  6,
                                ),
                            child: ClipOval(
                              child: FittedBox(
                                fit: BoxFit
                                    .contain,
                                child:
                                    (selectedBodyType !=
                                            null &&
                                        selectedBodyType!
                                            .isNotEmpty)
                                    ? _buildBodyTypeImage(
                                        _getBodyTypeAsset(
                                          selectedBodyType!,
                                        ),
                                      )
                                    : Icon(
                                        _getBodyTypeIcon(
                                          'car',
                                        ),
                                        color:
                                            Colors.black,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      onTap: () async {
                        final bodyType = await showDialog<String>(
                          context: context,
                          builder: (dlgContext) {
                            final isLightPicker =
                                Theme.of(
                                  dlgContext,
                                ).brightness ==
                                Brightness
                                    .light;
                            final pickerBg =
                                isLightPicker
                                ? Colors.white
                                : (Colors.grey[900]
                                          ?.withValues(alpha: 
                                            0.98,
                                          ) ??
                                      Colors
                                          .grey
                                          .shade900);
                            final onPicker =
                                isLightPicker
                                ? const Color(
                                    0xFF1A1A1A,
                                  )
                                : Colors
                                      .white;
                            final onPickerMuted =
                                isLightPicker
                                ? const Color(
                                    0xFF616161,
                                  )
                                : Colors
                                      .white70;
                            final borderSubtle =
                                isLightPicker
                                ? Colors
                                      .black26
                                : Colors
                                      .white24;
                            final shadowIdle =
                                isLightPicker
                                ? Colors
                                      .black12
                                : Colors
                                      .black54;
                            return Dialog(
                              backgroundColor:
                                  pickerBg,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      20,
                                    ),
                              ),
                              child: Container(
                                width: 400,
                                padding:
                                    EdgeInsets.all(
                                      20,
                                    ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  mainAxisSize:
                                      MainAxisSize
                                          .min,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.selectBodyType,
                                          style: GoogleFonts.orbitron(
                                            color: Color(
                                              0xFFFF6B00,
                                            ),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.close,
                                            color: onPicker,
                                          ),
                                          onPressed: () => Navigator.pop(
                                            dlgContext,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(
                                      height:
                                          10,
                                    ),
                                    SizedBox(
                                      height:
                                          300,
                                      child: GridView.builder(
                                        shrinkWrap:
                                            true,
                                        physics:
                                            BouncingScrollPhysics(),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount:
                                              3,
                                          childAspectRatio:
                                              0.82,
                                          crossAxisSpacing:
                                              12,
                                          mainAxisSpacing:
                                              12,
                                        ),
                                        itemCount:
                                            getAvailableBodyTypes().length,
                                        itemBuilder:
                                            (
                                              context,
                                              index,
                                            ) {
                                              final bodyTypeName = getAvailableBodyTypes()[index];
                                              final asset = _getBodyTypeAsset(
                                                bodyTypeName,
                                              );
                                              final bool
                                              isSelected =
                                                  (selectedBodyType ??
                                                      AppLocalizations.of(
                                                        context,
                                                      )!.any) ==
                                                  bodyTypeName;
                                              return InkWell(
                                                borderRadius: BorderRadius.circular(
                                                  12,
                                                ),
                                                onTap: () => Navigator.pop(
                                                  dlgContext,
                                                  bodyTypeName,
                                                ),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.transparent,
                                                    borderRadius: BorderRadius.circular(
                                                      12,
                                                    ),
                                                    border: Border.all(
                                                      color: isSelected
                                                          ? const Color(
                                                              0xFFFF6B00,
                                                            )
                                                          : borderSubtle,
                                                      width: isSelected
                                                          ? 2
                                                          : 1,
                                                    ),
                                                    boxShadow: isSelected
                                                        ? [
                                                            BoxShadow(
                                                              color:
                                                                  const Color(
                                                                    0xFFFF6B00,
                                                                  ).withValues(alpha: 
                                                                    0.35,
                                                                  ),
                                                              blurRadius: 14,
                                                              spreadRadius: 1,
                                                              offset: const Offset(
                                                                0,
                                                                4,
                                                              ),
                                                            ),
                                                          ]
                                                        : [
                                                            BoxShadow(
                                                              color: shadowIdle,
                                                              blurRadius: 10,
                                                              spreadRadius: 0,
                                                              offset: const Offset(
                                                                0,
                                                                3,
                                                              ),
                                                            ),
                                                          ],
                                                  ),
                                                  padding: EdgeInsets.all(
                                                    8,
                                                  ),
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Container(
                                                        width: 56,
                                                        height: 56,
                                                        decoration: BoxDecoration(
                                                          shape: BoxShape.circle,
                                                          color: Colors.white,
                                                          border: Border.all(
                                                            color: isSelected
                                                                ? const Color(
                                                                    0xFFFF6B00,
                                                                  )
                                                                : borderSubtle,
                                                            width: isSelected
                                                                ? 2
                                                                : 1,
                                                          ),
                                                        ),
                                                        child: Padding(
                                                          padding: const EdgeInsets.all(
                                                            8,
                                                          ),
                                                          child: FittedBox(
                                                            fit: BoxFit.contain,
                                                            child: _buildBodyTypeImage(
                                                              asset,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 8,
                                                      ),
                                                      Text(
                                                        bodyTypeName ==
                                                                'Any'
                                                            ? AppLocalizations.of(
                                                                context,
                                                              )!.anyOption
                                                            : (_translateValueGlobal(
                                                                    context,
                                                                    bodyTypeName,
                                                                  ) ??
                                                                  bodyTypeName),
                                                        style: GoogleFonts.orbitron(
                                                          fontSize: 12,
                                                          color: isSelected
                                                              ? const Color(
                                                                  0xFFFF6B00,
                                                                )
                                                              : onPickerMuted,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                        textAlign: TextAlign.center,
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                        if (bodyType !=
                            null) {
                          setState(() {
                            selectedBodyType =
                                bodyType ==
                                    'Any'
                                ? null
                                : bodyType;
                          });
                          setStateDialog(
                            () {},
                          );
                        }
                      },
                    ),
                    SizedBox(
                      height:
                          moreFiltersFieldGap,
                    ),
                    TextFormField(
                      key: ValueKey(
                        'color_${selectedColor ?? 'any'}',
                      ),
                      readOnly: true,
                      style: TextStyle(
                        color:
                            (selectedColor !=
                                    null &&
                                selectedColor!
                                    .isNotEmpty)
                            ? moreFiltersOnSurface
                            : moreFiltersAnyOrange,
                      ),
                      initialValue:
                          (_translateValueGlobal(
                            context,
                            selectedColor,
                          ) ??
                          selectedColor ??
                          AppLocalizations.of(
                            context,
                          )!.any),
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(
                              context,
                            )!.colorLabel,
                        filled: true,
                        fillColor:
                            moreFiltersFieldFill,
                        labelStyle: TextStyle(
                          color:
                              moreFiltersOnSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(
                                12,
                              ),
                        ),
                        suffixIcon: Container(
                          width: 24,
                          height: 24,
                          margin:
                              EdgeInsets.all(
                                8,
                              ),
                          decoration: BoxDecoration(
                            color:
                                selectedColor !=
                                    null
                                ? _getColorValue(
                                    selectedColor!,
                                  )
                                : Colors.grey,
                            borderRadius:
                                BorderRadius.circular(
                                  6,
                                ),
                            border: Border.all(
                              color: Colors
                                  .white24,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      onTap: () async {
                        final color = await showDialog<String>(
                          context: context,
                          builder: (dlgContext) {
                            final isLightPicker =
                                Theme.of(
                                  dlgContext,
                                ).brightness ==
                                Brightness
                                    .light;
                            final pickerBg =
                                isLightPicker
                                ? Colors.white
                                : (Colors.grey[900]
                                          ?.withValues(alpha: 
                                            0.98,
                                          ) ??
                                      Colors
                                          .grey
                                          .shade900);
                            final onPicker =
                                isLightPicker
                                ? const Color(
                                    0xFF1A1A1A,
                                  )
                                : Colors
                                      .white;
                            final borderSubtle =
                                isLightPicker
                                ? Colors
                                      .black26
                                : Colors
                                      .white24;
                            final cellFill =
                                isLightPicker
                                ? Colors
                                      .grey
                                      .shade200
                                : Colors.black
                                      .withValues(alpha: 
                                        0.15,
                                      );
                            return Dialog(
                              backgroundColor:
                                  pickerBg,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                      20,
                                    ),
                              ),
                              child: Container(
                                width: 400,
                                padding:
                                    EdgeInsets.all(
                                      20,
                                    ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  mainAxisSize:
                                      MainAxisSize
                                          .min,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.selectColor,
                                          style: GoogleFonts.orbitron(
                                            color: Color(
                                              0xFFFF6B00,
                                            ),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.close,
                                            color: onPicker,
                                          ),
                                          onPressed: () => Navigator.pop(
                                            dlgContext,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(
                                      height:
                                          10,
                                    ),
                                    SizedBox(
                                      height:
                                          300,
                                      child: GridView.builder(
                                        shrinkWrap:
                                            true,
                                        physics:
                                            BouncingScrollPhysics(),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount:
                                              3,
                                          childAspectRatio:
                                              1.2,
                                          crossAxisSpacing:
                                              10,
                                          mainAxisSpacing:
                                              10,
                                        ),
                                        itemCount:
                                            getAvailableColors().length,
                                        itemBuilder:
                                            (
                                              context,
                                              index,
                                            ) {
                                              final colorName = getAvailableColors()[index];
                                              Color
                                              colorValue = Colors.grey;
                                              switch (colorName.toLowerCase()) {
                                                case 'black':
                                                  colorValue = Colors.black;
                                                  break;
                                                case 'white':
                                                  colorValue = Colors.white;
                                                  break;
                                                case 'silver':
                                                  colorValue = Colors.grey[300]!;
                                                  break;
                                                case 'gray':
                                                  colorValue = Colors.grey[600]!;
                                                  break;
                                                case 'red':
                                                  colorValue = Colors.red;
                                                  break;
                                                case 'blue':
                                                  colorValue = Colors.blue;
                                                  break;
                                                case 'green':
                                                  colorValue = Colors.green;
                                                  break;
                                                case 'yellow':
                                                  colorValue = Colors.yellow;
                                                  break;
                                                case 'orange':
                                                  colorValue = Colors.orange;
                                                  break;
                                                case 'purple':
                                                  colorValue = Colors.purple;
                                                  break;
                                                case 'brown':
                                                  colorValue = Colors.brown;
                                                  break;
                                                case 'beige':
                                                  colorValue = Color(
                                                    0xFFF5F5DC,
                                                  );
                                                  break;
                                                case 'gold':
                                                  colorValue = Color(
                                                    0xFFFFD700,
                                                  );
                                                  break;
                                                default:
                                                  colorValue = Colors.grey;
                                              }
                                              return InkWell(
                                                borderRadius: BorderRadius.circular(
                                                  12,
                                                ),
                                                onTap: () => Navigator.pop(
                                                  dlgContext,
                                                  colorName,
                                                ),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: cellFill,
                                                    borderRadius: BorderRadius.circular(
                                                      12,
                                                    ),
                                                    border: Border.all(
                                                      color: borderSubtle,
                                                    ),
                                                  ),
                                                  padding: EdgeInsets.all(
                                                    8,
                                                  ),
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Container(
                                                        width: 40,
                                                        height: 40,
                                                        decoration: BoxDecoration(
                                                          color: colorValue,
                                                          borderRadius: BorderRadius.circular(
                                                            8,
                                                          ),
                                                          border: Border.all(
                                                            color: borderSubtle,
                                                            width: 2,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height: 8,
                                                      ),
                                                      Text(
                                                        _translateValueGlobal(
                                                              context,
                                                              colorName,
                                                            ) ??
                                                            colorName,
                                                        style: GoogleFonts.orbitron(
                                                          fontSize: 12,
                                                          color: onPicker,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                        textAlign: TextAlign.center,
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                        if (color != null) {
                          setState(() {
                            selectedColor =
                                color == 'Any'
                                ? null
                                : color;
                          });
                          setStateDialog(
                            () {},
                          );
                        }
                      },
                    ),
                    SizedBox(height: 12),
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
                            moreFiltersFieldFill,
                        labelStyle: TextStyle(
                          color:
                              moreFiltersOnSurface,
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
                                  moreFiltersAnyOrange,
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
                            moreFiltersFieldFill,
                        labelStyle: TextStyle(
                          color:
                              moreFiltersOnSurface,
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
                                  moreFiltersAnyOrange,
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
                            moreFiltersFieldFill,
                        labelStyle: TextStyle(
                          color:
                              moreFiltersOnSurface,
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
                                  moreFiltersAnyOrange,
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
                            moreFiltersFieldFill,
                        labelStyle: TextStyle(
                          color:
                              moreFiltersOnSurface,
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
                                  moreFiltersAnyOrange,
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
                                        moreFiltersFieldFill,
                                    labelStyle:
                                        TextStyle(
                                          color:
                                              moreFiltersOnSurface,
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
                                              moreFiltersAnyOrange,
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
                                        moreFiltersFieldFill,
                                    labelStyle:
                                        TextStyle(
                                          color:
                                              moreFiltersOnSurface,
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
                                moreFiltersFieldFill,
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
                            moreFiltersFieldFill,
                        labelStyle: TextStyle(
                          color:
                              moreFiltersOnSurface,
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
                                  moreFiltersAnyOrange,
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
                            moreFiltersFieldFill,
                        labelStyle: TextStyle(
                          color:
                              moreFiltersOnSurface,
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
                                  moreFiltersAnyOrange,
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
                  ],
                ),
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: Row(
                  textDirection:
                      ui.TextDirection.ltr,
                  children: [
                    TextButton(
                      onPressed: () async {
                        await _resetFiltersFromMoreFiltersDialog(
                          () =>
                              setStateDialog(
                                () {},
                              ),
                        );
                      },
                      child: Text(
                        AppLocalizations.of(
                          context,
                        )!.resetButton,
                        style: TextStyle(
                          color:
                              moreFiltersMuted,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _restoreMoreFiltersDialogSnapshot(
                          moreFiltersSnapshot,
                        );
                        unawaited(
                          _persistFilters(),
                        );
                        Navigator.pop(
                          context,
                        );
                      },
                      child: Text(
                        _cancelTextGlobal(
                          context,
                        ),
                        style: TextStyle(
                          color:
                              moreFiltersMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Color(
                                0xFFFF6B00,
                              ),
                          foregroundColor:
                              Colors.white,
                        ),
                        onPressed: () {
                          unawaited(
                            _persistFilters(),
                          );
                          onFilterChanged();
                          Navigator.pop(
                            context,
                          );
                        },
                        child: Text(
                          AppLocalizations.of(
                            context,
                          )!.applyFilters,
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
  }
}
