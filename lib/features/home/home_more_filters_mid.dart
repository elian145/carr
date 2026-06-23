part of 'home_flow.dart';

mixin _HomePageMoreFiltersMid on _HomePageMoreFiltersYear {
  List<Widget> _moreFiltersMidWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    return <Widget>[
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
                          SizedBox(
                            height:
                                style.fieldGap,
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              AppLocalizations.of(context)!.titleStatus,
                              style: TextStyle(
                                color: style.onSurface,
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
                                        ? style.anyOrange
                                        : Theme.of(context).colorScheme.primary,
                                    backgroundColor: style.fieldFill,
                                    labelStyle: TextStyle(
                                      color: (selectedTitleStatus ?? '') == entry.key
                                          ? Colors.white
                                          : style.onSurface,
                                      fontWeight: (selectedTitleStatus ?? '') == entry.key
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: (selectedTitleStatus ?? '') == entry.key
                                            ? Colors.transparent
                                            : style.onSurface.withValues(alpha: 0.2),
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
                                    style.fieldGap,
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
                                style.fieldGap,
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              AppLocalizations.of(context)!.conditionLabel,
                              style: TextStyle(
                                color: style.onSurface,
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
                                      ? style.anyOrange
                                      : Theme.of(context).colorScheme.primary,
                                  backgroundColor: style.fieldFill,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : style.onSurface,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isSelected
                                          ? Colors.transparent
                                          : style.onSurface.withValues(alpha: 0.2),
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
                                style.fieldGap,
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              AppLocalizations.of(context)!.transmissionLabel,
                              style: TextStyle(
                                color: style.onSurface,
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
                                        ? style.anyOrange
                                        : Theme.of(context).colorScheme.primary,
                                    backgroundColor: style.fieldFill,
                                    labelStyle: TextStyle(
                                      color: (selectedTransmission ?? 'Any') == t
                                          ? Colors.white
                                          : style.onSurface,
                                      fontWeight: (selectedTransmission ?? 'Any') == t
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: (selectedTransmission ?? 'Any') == t
                                            ? Colors.transparent
                                            : style.onSurface.withValues(alpha: 0.2),
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
                          SizedBox(
                            height:
                                style.fieldGap,
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
                                  ? style.onSurface
                                  : style.anyOrange,
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
                                style.fieldGap,
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
                                  ? style.onSurface
                                  : style.anyOrange,
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
    ];
  }
}
