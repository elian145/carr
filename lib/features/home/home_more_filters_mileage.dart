part of 'home_flow.dart';

mixin _HomePageMoreFiltersMileageChips on _HomePageMoreFiltersMileageRange {
  List<Widget> _moreFiltersTitleConditionWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
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
      ];

  List<Widget> _moreFiltersTransmissionChipWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
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

  List<Widget> _moreFiltersMileageChipsWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
        ..._moreFiltersTitleConditionWidgets(
          context,
          setStateDialog,
          style,
        ),
        ..._moreFiltersTransmissionChipWidgets(
          context,
          setStateDialog,
          style,
        ),
      ];
}

mixin _HomePageMoreFiltersMileage on _HomePageMoreFiltersMileageChips {
  List<Widget> _moreFiltersMileageWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
        ..._moreFiltersMileageRangeWidgets(context, setStateDialog, style),
        ..._moreFiltersMileageChipsWidgets(context, setStateDialog, style),
      ];
}
