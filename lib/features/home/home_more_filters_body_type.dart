part of 'home_flow.dart';

mixin _HomePageMoreFiltersBodyType on _HomePageMoreFiltersFuel {
  Future<List<String>?> _showHomeBodyTypeMultiPickerDialog(
    BuildContext context, {
    required List<String> initialSelection,
  }) {
    final options =
        getAvailableBodyTypes().where((t) => t != 'Any').toList();
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        final selected = Set<String>.from(initialSelection);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void toggle(String bodyTypeName) {
              setDialogState(() {
                if (selected.contains(bodyTypeName)) {
                  selected.remove(bodyTypeName);
                } else {
                  selected.add(bodyTypeName);
                }
              });
            }

            final isLightPicker =
                Theme.of(dialogContext).brightness == Brightness.light;
            final pickerBg = isLightPicker
                ? Colors.white
                : (Colors.grey[900]?.withValues(alpha: 0.98) ??
                    Colors.grey.shade900);
            final onPicker =
                isLightPicker ? const Color(0xFF1A1A1A) : Colors.white;
            final onPickerMuted =
                isLightPicker ? const Color(0xFF616161) : Colors.white70;
            final borderSubtle =
                isLightPicker ? Colors.black26 : Colors.white24;
            final shadowIdle =
                isLightPicker ? Colors.black12 : Colors.black54;

            return Dialog(
              backgroundColor: pickerBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ResponsiveDialogBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.selectBodyType,
                            style: GoogleFonts.orbitron(
                              color: const Color(0xFFFF6B00),
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, <String>[]),
                          child: Text(AppLocalizations.of(context)!.any),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: onPicker),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                    if (selected.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _trLegacyText(
                            context,
                            '${selected.length} selected',
                            ar: '${selected.length} محدد',
                            ku: '${selected.length} هەڵبژێردراو',
                          ),
                          style: TextStyle(color: onPickerMuted, fontSize: 13),
                        ),
                      ),
                    SizedBox(
                      height: AppResponsive.dialogScrollHeight(
                        context,
                        preferred: 300,
                        headerFooterReserve: 160,
                      ),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              AppResponsive.bodyTypeGridCrossAxisCount(context),
                          childAspectRatio: 0.82,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final bodyTypeName = options[index];
                          final asset = _getBodyTypeAsset(bodyTypeName);
                          final isSelected = selected.contains(bodyTypeName);
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => toggle(bodyTypeName),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFFF6B00)
                                      : borderSubtle,
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFFF6B00)
                                              .withValues(alpha: 0.35),
                                          blurRadius: 14,
                                          spreadRadius: 1,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: shadowIdle,
                                          blurRadius: 10,
                                          spreadRadius: 0,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                              ),
                              padding: const EdgeInsets.all(8),
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
                                            ? const Color(0xFFFF6B00)
                                            : borderSubtle,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        child: _buildBodyTypeImage(asset),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _translateValueGlobal(
                                          context,
                                          bodyTypeName,
                                        ) ??
                                        bodyTypeName,
                                    style: GoogleFonts.orbitron(
                                      fontSize: 12,
                                      color: isSelected
                                          ? const Color(0xFFFF6B00)
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
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          selected.toList(),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                        ),
                        child: Text(
                          _trLegacyText(
                            context,
                            'Apply',
                            ar: 'تطبيق',
                            ku: 'جێبەجێکردن',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

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
                              'bodyType_${_homeSelectedBodyTypes.join(',')}',
                            ),
                            readOnly: true,
                            style: TextStyle(
                              color:
                                  _homeSelectedBodyTypes.isNotEmpty
                                  ? style.onSurface
                                  : style.anyOrange,
                            ),
                            initialValue: _homeBodyTypeFilterLabel(context),
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
                                          _homeSelectedBodyTypes.length == 1
                                          ? _buildBodyTypeImage(
                                              _getBodyTypeAsset(
                                                _homeSelectedBodyTypes.first,
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
                              final bodyTypes =
                                  await _showHomeBodyTypeMultiPickerDialog(
                                context,
                                initialSelection: _homeSelectedBodyTypes,
                              );
                              if (bodyTypes == null) return;
                              setState(() {
                                _homeSetSelectedBodyTypes(bodyTypes);
                              });
                              setStateDialog(() {});
                            },
                          ),
      ];
}

