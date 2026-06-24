part of 'home_flow.dart';

mixin _HomePageMoreFiltersBodyType on _HomePageMoreFiltersFuel {
  List<Widget> _moreFiltersBodyTypeWidgets(
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
                                              homeFilterBodyTypeIcon(
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
      ];
}
