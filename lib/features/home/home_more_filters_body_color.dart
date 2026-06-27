part of 'home_flow.dart';

mixin _HomePageMoreFiltersColor on _HomePageMoreFiltersBodyType {
  List<Widget> _moreFiltersColorWidgets(
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
                                      ? homeFilterNamedColor(
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
                                    child: ResponsiveDialogBody(
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
                                                AppResponsive.dialogScrollHeight(
                                              dlgContext,
                                              preferred: 300,
                                              headerFooterReserve: 100,
                                            ),
                                            child: GridView.builder(
                                              shrinkWrap:
                                                  true,
                                              physics:
                                                  BouncingScrollPhysics(),
                                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount:
                                                    AppResponsive.bodyTypeGridCrossAxisCount(
                                                  dlgContext,
                                                ),
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
