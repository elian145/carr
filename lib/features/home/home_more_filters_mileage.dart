part of 'home_flow.dart';

mixin _HomePageMoreFiltersMileage on _HomePageMoreFiltersYear {
  List<Widget> _moreFiltersMileageWidgets(
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
    ];
  }
}
