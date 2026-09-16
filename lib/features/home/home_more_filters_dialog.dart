part of 'home_flow.dart';

mixin _HomePageMoreFiltersDialog on _HomePageMoreFiltersSpecsEngine {
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

  void _cancelSearchFiltersPage(Map<String, dynamic> snapshot) {
    _restoreSearchFiltersPageSnapshot(snapshot);
    unawaited(_persistFilters());
  }
}
