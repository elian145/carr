part of 'home_flow.dart';

mixin _HomePageMoreFiltersColor on _HomePageMoreFiltersBodyType {
  List<Widget> _moreFiltersColorWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style, {
    bool includeAnyOption = true,
    bool narrowMenu = false,
  }) {
    final fieldFontSize = 18.0;
    final swatchSize = narrowMenu ? 20.0 : 24.0;
    final colorOptions = includeAnyOption
        ? getAvailableColors()
        : getAvailableColors().where((c) => c != 'Any').toList();
    final hasColor =
        selectedColor != null &&
        selectedColor!.isNotEmpty &&
        selectedColor != 'Any';

    return [
      SizedBox(height: narrowMenu ? 12 : style.fieldGap),
      InputDecorator(
        decoration: filterDropdownFieldDecoration(
          style,
          AppLocalizations.of(context)!.colorLabel,
          compactLabel: narrowMenu,
        ),
        // Keep label floated so closed height matches cylinder/search dropdowns.
        isEmpty: false,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () async {
              final color = await showDialog<String>(
                context: context,
                builder: (dlgContext) {
                  final isLightPicker =
                      Theme.of(dlgContext).brightness == Brightness.light;
                  final pickerBg = isLightPicker
                      ? Colors.white
                      : (Colors.grey[900]?.withValues(alpha: 0.98) ??
                            Colors.grey.shade900);
                  final onPicker =
                      isLightPicker ? const Color(0xFF1A1A1A) : Colors.white;
                  final borderSubtle =
                      isLightPicker ? Colors.black26 : Colors.white24;
                  final cellFill = isLightPicker
                      ? Colors.grey.shade200
                      : Colors.black.withValues(alpha: 0.15);
                  return Dialog(
                    backgroundColor: pickerBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ResponsiveDialogBody(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.selectColor,
                                style: AppFonts.orbitron(
                                  color: AppColors.brandOrange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                              IconButton(
                                tooltip: AppLocalizations.of(dlgContext)!.close,
                                icon: Icon(Icons.close, color: onPicker),
                                onPressed: () => Navigator.pop(dlgContext),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: AppResponsive.dialogScrollHeight(
                              dlgContext,
                              preferred: 300,
                              headerFooterReserve: 100,
                            ),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const BouncingScrollPhysics(),
                              gridDelegate:
                                  AppResponsive.colorPickerGridDelegate(
                                    dlgContext,
                                  ),
                              itemCount: colorOptions.length,
                              itemBuilder: (context, index) {
                                final colorName = colorOptions[index];
                                final isAny = colorName == 'Any';
                                Color colorValue = Colors.grey;
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
                                  case 'grey':
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
                                    colorValue = const Color(0xFFF5F5DC);
                                    break;
                                  case 'gold':
                                    colorValue = const Color(0xFFFFD700);
                                    break;
                                  default:
                                    colorValue = Colors.grey;
                                }
                                final selected =
                                    (selectedColor == null && isAny) ||
                                    selectedColor == colorName;
                                final label = isAny
                                    ? AppLocalizations.of(context)!.any
                                    : (_translateValueGlobal(
                                            context,
                                            colorName,
                                          ) ??
                                          colorName);
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () =>
                                      Navigator.pop(dlgContext, colorName),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: cellFill,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.brandOrange
                                            : borderSubtle,
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isAny)
                                          Icon(
                                            Icons.block,
                                            color: AppColors.brandOrange,
                                            size: 28,
                                          )
                                        else
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: colorValue,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: borderSubtle,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        const SizedBox(height: 6),
                                        Text(
                                          label,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.25,
                                            color: onPicker,
                                            fontWeight: FontWeight.w600,
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
                  selectedColor = color == 'Any' ? null : color;
                });
                setStateDialog(() {});
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    hasColor
                        ? (_translateValueGlobal(context, selectedColor) ??
                              selectedColor!)
                        : (includeAnyOption
                              ? AppLocalizations.of(context)!.any
                              : ''),
                    style: TextStyle(
                      color: hasColor ? style.onSurface : style.anyOrange,
                      fontWeight: FontWeight.w600,
                      fontSize: fieldFontSize,
                      height: narrowMenu ? 1.2 : 1.35,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: swatchSize,
                  height: swatchSize,
                  decoration: BoxDecoration(
                    color: hasColor
                        ? homeFilterNamedColor(selectedColor!)
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: style.onSurface.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (!narrowMenu) const SizedBox(height: 12),
    ];
  }
}

mixin _HomePageMoreFiltersBodyColor on _HomePageMoreFiltersColor {
  List<Widget> _moreFiltersBodyColorWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
    ..._moreFiltersFuelWidgets(context, setStateDialog, style),
    ..._moreFiltersBodyTypeWidgets(context, setStateDialog, style),
    ..._moreFiltersColorWidgets(context, setStateDialog, style),
  ];
}
