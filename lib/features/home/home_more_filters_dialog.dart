part of 'home_flow.dart';

mixin _HomePageMoreFiltersDialog on _HomePageMoreFiltersSpecs {
  void _syncMoreFiltersControllers() {
    _minPriceController.text = selectedMinPrice ?? '';
    _maxPriceController.text = selectedMaxPrice ?? '';
    _minYearController.text = selectedMinYear ?? '';
    _maxYearController.text = selectedMaxYear ?? '';
    _minMileageController.text = selectedMinMileage ?? '';
    _maxMileageController.text = selectedMaxMileage ?? '';
    _engineSizeController.text = selectedEngineSize ?? '';
  }

  MoreFiltersDialogStyle _moreFiltersStyle(BuildContext context) {
    final isLightMoreFilters = Theme.of(context).brightness == Brightness.light;
    return MoreFiltersDialogStyle(
      onSurface: isLightMoreFilters ? const Color(0xFF1A1A1A) : Colors.white,
      muted: isLightMoreFilters ? const Color(0xFF757575) : Colors.white70,
      anyOrange: AppColors.brandOrange,
      fieldFill: isLightMoreFilters
          ? Colors.grey.shade200
          : Colors.black.withValues(alpha: 0.2),
      menuFill: isLightMoreFilters
          ? Colors.white
          : const Color(0xFF2A2A2E),
    );
  }

  List<Widget> _moreFiltersAdvancedWidgets(
    BuildContext context,
    StateSetter setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    return [
      ..._moreFiltersPriceWidgets(context, setStateDialog, style),
      ..._moreFiltersYearWidgets(context, setStateDialog, style),
      ..._moreFiltersMileageRangeWidgets(context, setStateDialog, style),
      ..._moreFiltersTitleConditionWidgets(context, setStateDialog, style),
      ..._moreFiltersSpecsEngineWidgets(
        context,
        setStateDialog,
        style,
        includeSeating: false,
      ),
      ..._moreFiltersTransmissionChipWidgets(context, setStateDialog, style),
      ..._moreFiltersBodyColorWidgets(context, setStateDialog, style),
      ..._moreFiltersSpecsWidgets(context, setStateDialog, style),
    ];
  }

  Map<String, dynamic> _searchFiltersPageSnapshot() {
    return {
      ..._moreFiltersDialogSnapshot(),
      'brand': selectedBrand,
      'model': selectedModel,
      'trim': selectedTrim,
    };
  }

  void _restoreSearchFiltersPageSnapshot(Map<String, dynamic> snap) {
    setState(() {
      selectedBrand = _filterStr(snap['brand']);
      selectedModel = _filterStr(snap['model']);
      selectedTrim = _filterStr(snap['trim']);
    });
    _restoreMoreFiltersDialogSnapshot(snap);
  }

  Future<void> _resetSearchFiltersPage(VoidCallback refreshDialog) async {
    setState(() {
      _resetAllFiltersInMemory();
      _moreFiltersDialogFieldGeneration++;
      isPriceDropdown = true;
      isYearDropdown = true;
      isMileageDropdown = true;
      isEngineSizeDropdown = true;
      _minPriceController.clear();
      _maxPriceController.clear();
      _minYearController.clear();
      _maxYearController.clear();
      _minMileageController.clear();
      _maxMileageController.clear();
      _engineSizeController.clear();
      _searchFiltersKeywordController.clear();
      _searchFiltersKeywordFocusNode.unfocus();
    });
    refreshDialog();
    await _persistFilters();
    onFilterChanged();
  }

  Widget _moreFiltersActionBar(
    BuildContext context,
    StateSetter setStateDialog,
    MoreFiltersDialogStyle style,
    Map<String, dynamic> moreFiltersSnapshot, {
    required VoidCallback onClose,
    required void Function(Map<String, dynamic> snapshot) onCancel,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OverflowBar(
        alignment: MainAxisAlignment.end,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        overflowSpacing: 8,
        textDirection: ui.TextDirection.ltr,
        children: [
          TextButton(
            onPressed: () async {
              await _resetFiltersFromMoreFiltersDialog(
                () => setStateDialog(() {}),
              );
            },
            child: Text(
              AppLocalizations.of(context)!.resetButton,
              style: TextStyle(color: style.muted),
            ),
          ),
          TextButton(
            onPressed: () {
              onCancel(moreFiltersSnapshot);
              unawaited(_persistFilters());
              onClose();
            },
            child: Text(
              _cancelTextGlobal(context),
              style: TextStyle(color: style.muted),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: AppResponsive.isCompactPhone(context) ? 120 : 150,
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandOrange,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                unawaited(_persistFilters());
                onFilterChanged();
                onClose();
              },
              child: Text(
                AppLocalizations.of(context)!.applyFilters,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _cancelMoreFilters(Map<String, dynamic> moreFiltersSnapshot) {
    _restoreMoreFiltersDialogSnapshot(moreFiltersSnapshot);
    unawaited(_persistFilters());
  }

  void _cancelSearchFiltersPage(Map<String, dynamic> snapshot) {
    _restoreSearchFiltersPageSnapshot(snapshot);
    unawaited(_persistFilters());
  }

  Future<void> _showMoreFiltersDialog(BuildContext context) async {
    _syncMoreFiltersControllers();
    final moreFiltersSnapshot = _moreFiltersDialogSnapshot();
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final style = _moreFiltersStyle(context);
            final isLightMoreFilters =
                Theme.of(context).brightness == Brightness.light;
            final moreFiltersBg = isLightMoreFilters
                ? Colors.white
                : (Colors.grey[900]?.withValues(alpha: 0.98) ??
                      Colors.grey.shade900);
            return AlertDialog(
              backgroundColor: moreFiltersBg,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                AppLocalizations.of(context)!.moreFilters,
                style: AppFonts.orbitron(
                  color: AppColors.brandOrange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: AppResponsive.dialogWidth(context, preferred: 420),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: AppResponsive.dialogMaxHeight(
                      context,
                      fraction: 0.72,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: KeyedSubtree(
                      key: ValueKey<int>(_moreFiltersDialogFieldGeneration),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _moreFiltersAdvancedWidgets(
                          context,
                          setStateDialog,
                          style,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                _moreFiltersActionBar(
                  context,
                  setStateDialog,
                  style,
                  moreFiltersSnapshot,
                  onClose: () => Navigator.pop(context),
                  onCancel: _cancelMoreFilters,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
