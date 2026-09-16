part of 'home_flow.dart';

mixin _HomePageFilterLogic on _HomePageFilterPersist {
  String? get _homeSelectedBrand => homeFilterDecodeSingle(selectedBrand);

  String? get _homeSingleSelectedBrand => _homeSelectedBrand;

  List<String> get _homeSelectedBodyTypes =>
      homeFilterDecodeList(selectedBodyType);

  void _homeSetSelectedBrand(String? brand) {
    if (brand == null ||
        brand.trim().isEmpty ||
        brand.trim().toLowerCase() == 'any') {
      selectedBrand = null;
    } else {
      selectedBrand = homeFilterDecodeSingle(brand) ?? brand.trim();
    }
    selectedModel = null;
    selectedTrim = null;
  }

  void _homeToggleBrand(String brand) {
    if (_homeSelectedBrand == brand) {
      _homeSetSelectedBrand(null);
    } else {
      _homeSetSelectedBrand(brand);
    }
  }

  void _homeSetSelectedBodyTypes(List<String> types) {
    selectedBodyType = homeFilterEncodeList(types);
  }

  void _homeToggleBodyType(String bodyType) {
    if (bodyType == 'Any') {
      _homeSetSelectedBodyTypes([]);
      return;
    }
    _homeSetSelectedBodyTypes(
      homeFilterToggleValue(_homeSelectedBodyTypes, bodyType),
    );
  }

  List<String> get _homeSelectedFuelTypes =>
      homeFilterDecodeList(selectedFuelType);

  List<String> get _homeSelectedDriveTypes =>
      homeFilterDecodeList(selectedDriveType);

  void _homeSetSelectedFuelTypes(List<String> types) {
    selectedFuelType = homeFilterEncodeList(types);
  }

  void _homeSetSelectedDriveTypes(List<String> types) {
    selectedDriveType = homeFilterEncodeList(types);
  }

  void _homeToggleFuelType(String fuelType) {
    if (fuelType == 'Any') {
      _homeSetSelectedFuelTypes([]);
      return;
    }
    _homeSetSelectedFuelTypes(
      homeFilterToggleValue(_homeSelectedFuelTypes, fuelType),
    );
  }

  void _homeToggleDriveType(String driveType) {
    if (driveType == 'Any') {
      _homeSetSelectedDriveTypes([]);
      return;
    }
    _homeSetSelectedDriveTypes(
      homeFilterToggleValue(_homeSelectedDriveTypes, driveType),
    );
  }

  bool _hasActiveFilters() => _homeFiltersSnapshot().hasActiveFilters;

  // Helper method to clear a specific filter
  void _clearFilter(String filterType) {
    setState(() {
      _applyHomeFiltersSnapshot(
        clearHomeFilterChip(_homeFiltersSnapshot(), filterType),
      );
      _syncHomeFilterTextControllersFromSelection();
    });
    unawaited(_persistFilters());
    onFilterChanged();
  }

  List<Widget> _buildActiveFilterChips() {
    return buildLocalizedHomeFilterChips(
      context,
      filters: _homeFiltersSnapshot(),
      onClear: _clearFilter,
    );
  }
}
