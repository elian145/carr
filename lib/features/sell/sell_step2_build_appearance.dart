part of 'sell_flow.dart';

mixin _SellStep2BuildAppearance on _SellStep2BuildCore {
  List<Widget> _sellStep2BuildAppearanceSection() {
    return [
            // Body Type (Modal - grid like search)
            FormField<String>(
              validator: (_) => selectedBodyType == null
                  ? AppLocalizations.of(context)!.pleaseSelectBodyType
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          width: 400,
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
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
                                      color: Color(0xFFFF6B00),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              SizedBox(
                                height: 300,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: BouncingScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        childAspectRatio: 0.82,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                      ),
                                  itemCount: getAvailableBodyTypes().length,
                                  itemBuilder: (context, index) {
                                    final bodyTypeName =
                                        getAvailableBodyTypes()[index];
                                    final asset = _getBodyTypeAsset(
                                      bodyTypeName,
                                    );
                                    final bool isSelected =
                                        (selectedBodyType ?? '') ==
                                        bodyTypeName;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () =>
                                          Navigator.pop(context, bodyTypeName),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xFFFF6B00)
                                                : Colors.white24,
                                            width: isSelected ? 2 : 1,
                                          ),
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(
                                                      0xFFFF6B00,
                                                    ).withValues(alpha: 0.35),
                                                    blurRadius: 14,
                                                    spreadRadius: 1,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ]
                                              : [
                                                  const BoxShadow(
                                                    color: Colors.black54,
                                                    blurRadius: 10,
                                                    spreadRadius: 0,
                                                    offset: Offset(0, 3),
                                                  ),
                                                ],
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 56,
                                              height: 56,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? const Color(0xFFFF6B00)
                                                      : Colors.white24,
                                                  width: isSelected ? 2 : 1,
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
                                            const SizedBox(height: 8),
                                            Text(
                                              bodyTypeName == 'Any'
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
                                                    ? Colors.white
                                                    : Colors.white70,
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
                  if (choice != null) {
                    setState(() {
                      selectedBodyType = choice;
                      _syncStep2ToOnlineVariant({'body'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.directions_car,
                  label: '${AppLocalizations.of(context)!.bodyTypeLabel} *',
                  value: selectedBodyType == null
                      ? _tapToSelectTextGlobal(context)
                      : (_translateValueGlobal(context, selectedBodyType) ??
                          selectedBodyType),
                  isError:
                      errBodyType &&
                      (selectedBodyType == null || selectedBodyType!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Color (Modal - swatches like search)
            FormField<String>(
              validator: (_) => selectedColor == null
                  ? AppLocalizations.of(context)!.pleaseSelectColor
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          width: 400,
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppLocalizations.of(context)!.selectColor,
                                    style: GoogleFonts.orbitron(
                                      color: Color(0xFFFF6B00),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              SizedBox(
                                height: 300,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: BouncingScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        childAspectRatio: 1.2,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                      ),
                                  itemCount: getAvailableColors().length,
                                  itemBuilder: (context, index) {
                                    final colorName =
                                        getAvailableColors()[index];
                                    final colorValue = _colorFromName(
                                      colorName,
                                    );
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () =>
                                          Navigator.pop(context, colorName),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.white24,
                                          ),
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: colorValue,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.white24,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              _translateValueGlobal(
                                                    context,
                                                    colorName,
                                                  ) ??
                                                  colorName,
                                              style: GoogleFonts.orbitron(
                                                fontSize: 12,
                                                color: Colors.white,
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
                  if (choice != null) setState(() => selectedColor = choice);
                  if (choice != null) _syncStep2DraftToParent();
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.palette,
                  label: '${AppLocalizations.of(context)!.colorLabel} *',
                  value: selectedColor == null
                      ? _tapToSelectTextGlobal(context)
                      : (_translateValueGlobal(context, selectedColor) ??
                          selectedColor),
                  isError:
                      errColor &&
                      (selectedColor == null || selectedColor!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),
    ];
  }
}
