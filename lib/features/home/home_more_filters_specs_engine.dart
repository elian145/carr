part of 'home_flow.dart';

mixin _HomePageMoreFiltersSpecsEngine on _HomePageMoreFiltersSpecsDrive {
  List<Widget> _moreFiltersSpecsEngineWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style, {
    bool narrowMenu = false,
  }) {
    final loc = AppLocalizations.of(context)!;

    return [
      const SizedBox(height: 12),
      _moreFiltersDropdownField(
        context: context,
        style: style,
        label: loc.cylinderCount,
        value: _getValidCylinderCountValue(),
        narrowMenu: narrowMenu,
        items: [
          DropdownMenuItem(
            value: '',
            child: Text(loc.any, style: TextStyle(color: style.anyOrange)),
          ),
          ...getAvailableCylinderCounts()
              .where((c) => c != 'Any')
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(_localizeDigitsGlobal(context, c)),
                ),
              ),
        ],
        onChanged: (value) {
          setState(() {
            selectedCylinderCount = value == '' ? null : value;
            _applyMoreFiltersEngineSyncFromCylinder(selectedCylinderCount);
          });
          setStateDialog(() {});
          _persistFilters();
        },
      ),
      const SizedBox(height: 12),
      _moreFiltersDropdownField(
        context: context,
        style: style,
        label: loc.seating,
        value: selectedSeating ?? '',
        narrowMenu: narrowMenu,
        items: [
          DropdownMenuItem(
            value: '',
            child: Text(loc.any, style: TextStyle(color: style.anyOrange)),
          ),
          ...getAvailableSeatings()
              .where((s) => s != 'Any')
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(_localizeDigitsGlobal(context, s)),
                ),
              ),
        ],
        onChanged: (value) {
          setState(() => selectedSeating = value == '' ? null : value);
          _persistFilters();
        },
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: isEngineSizeDropdown
                ? _moreFiltersDropdownField(
                    context: context,
                    style: style,
                    label: loc.engineSizeL,
                    value: _getValidEngineSizeValue(),
                    narrowMenu: narrowMenu,
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(
                          loc.any,
                          style: TextStyle(color: style.anyOrange),
                        ),
                      ),
                      ...getAvailableEngineSizes()
                          .where((e) => e != 'Any')
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                '${_localizeDigitsGlobal(context, e)}${loc.unit_liter_suffix}',
                              ),
                            ),
                          ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedEngineSize = value == '' ? null : value;
                        _applyMoreFiltersCylinderSyncFromEngine(
                          selectedEngineSize,
                        );
                      });
                      setStateDialog(() {});
                      _persistFilters();
                    },
                  )
                : TextFormField(
                    controller: _engineSizeController,
                    decoration: _moreFiltersColorMatchedFieldDecoration(
                      style,
                      loc.engineSizeL,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      services.FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.]'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedEngineSize = value.isEmpty ? null : value;
                        _applyMoreFiltersCylinderSyncFromEngine(
                          selectedEngineSize,
                        );
                      });
                      setStateDialog(() {});
                      _persistFilters();
                    },
                  ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => setStateDialog(() {
              if (isEngineSizeDropdown) {
                _engineSizeController.text = selectedEngineSize ?? '';
              }
              isEngineSizeDropdown = !isEngineSizeDropdown;
            }),
            icon: Icon(
              isEngineSizeDropdown ? Icons.edit : Icons.list,
              color: const Color(0xFFFF6B00),
            ),
            style: IconButton.styleFrom(
              backgroundColor: style.fieldFill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    ];
  }
}
