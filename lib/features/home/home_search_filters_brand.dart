part of 'home_flow.dart';

mixin _HomePageSearchFiltersBrand on _HomePageSearchFiltersCards {
  Widget _searchBrandLogoCircle(String brand, {double size = 52}) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      child: BrandLogoImage(
        brand: brand,
        placeholderSize: 20,
        errorIconSize: 22,
        errorIconColor: _searchAccent,
      ),
    );
  }

  List<String> _searchFeaturedBrands() {
    const featured = [
      'Toyota',
      'Honda',
      'Ford',
      'Chevrolet',
      'BMW',
    ];
    final picked = featured.where(homeBrands.contains).toList();
    if (picked.length >= 4) return picked.take(5).toList();
    final extras = homeBrands
        .where((b) => !picked.contains(b))
        .take(5 - picked.length);
    return [...picked, ...extras];
  }

  List<String> _searchCollapsedBrands() {
    final featured = _searchFeaturedBrands();
    final selected = _homeSelectedBrand;
    if (selected == null || selected.isEmpty) return featured;
    final rest = featured.where((b) => b != selected).toList();
    return [selected, ...rest];
  }

  static const double _searchBrandRowHeight = 92;
  static const double _searchBrandTileWidth = 72;
  static const double _searchBrandGridSpacing = 10;
  static const int _searchBrandExpandedVisibleRows = 4;

  int _searchBrandGridCrossAxisCount(double maxWidth) {
    return ((maxWidth + _searchBrandGridSpacing) /
            (_searchBrandTileWidth + _searchBrandGridSpacing))
        .floor()
        .clamp(3, 8);
  }

  Widget _searchBrandActionTile({
    required BuildContext context,
    required Color labelColor,
    required bool isLight,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: _searchBrandTileWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLight
                    ? Colors.white
                    : Colors.black.withValues(alpha: 0.2),
                border: Border.all(
                  color: const Color(0xFFE0E0E5),
                ),
              ),
              child: Icon(
                icon,
                color: _searchAccent,
              ),
            ),
            const SizedBox(height: 8),
            AppResponsive.fittedLabel(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBrandTile({
    required BuildContext context,
    required String brand,
    required bool selected,
    required Color labelColor,
    required VoidCallback onTap,
  }) {
    final display = CarNameTranslations.getLocalizedBrand(
              context,
              brand,
            ).isNotEmpty
        ? CarNameTranslations.getLocalizedBrand(context, brand)
        : brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: _searchBrandTileWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _searchAccent : const Color(0xFFE0E0E5),
                  width: selected ? 2 : 1,
                ),
              ),
              child: _searchBrandLogoCircle(brand),
            ),
            const SizedBox(height: 8),
            AppResponsive.fittedLabel(
              display,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? _searchAccent : labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchMakeSection(
    BuildContext context,
    StateSetter setStateDialog, {
    required bool brandsExpanded,
    required VoidCallback onToggleBrandsExpanded,
  }) {
    final loc = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final labelColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final collapsedBrands = _searchCollapsedBrands();
    final hasBrand = _homeSelectedBrand != null;
    final hasModel =
        _homeSingleSelectedBrand != null &&
        selectedModel != null &&
        selectedModel!.trim().isNotEmpty;
    final trimList = hasBrand && hasModel
        ? (trimsByBrandModel[_homeSingleSelectedBrand!]?[selectedModel!] ??
            const <String>[])
        : const <String>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _searchCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _searchSectionHeader(
              context,
              title: loc.brandLabel,
              valueSummary: _searchBrandLabel(context),
              onSummaryTap: () {
                  setState(() {
                    _homeSetSelectedBrand(null);
                    clearFiltersOnVehicleChange();
                  });
                  setStateDialog(() {});
                },
            ),
            const SizedBox(height: 14),
            if (brandsExpanded)
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount =
                      _searchBrandGridCrossAxisCount(constraints.maxWidth);
                  final expandedHeight = _searchBrandRowHeight *
                          _searchBrandExpandedVisibleRows +
                      _searchBrandGridSpacing *
                          (_searchBrandExpandedVisibleRows - 1);
                  return SizedBox(
                    height: expandedHeight,
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: _searchBrandGridSpacing,
                        crossAxisSpacing: _searchBrandGridSpacing,
                        mainAxisExtent: _searchBrandRowHeight,
                      ),
                      itemCount: homeBrands.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _searchBrandActionTile(
                            context: context,
                            labelColor: labelColor,
                            isLight: isLight,
                            icon: Icons.expand_less,
                            label: _trLegacyText(
                              context,
                              'Less',
                              ar: 'أقل',
                              ku: 'کەمتر',
                            ),
                            onTap: onToggleBrandsExpanded,
                          );
                        }
                        final brand = homeBrands[index - 1];
                        final selected = _homeSelectedBrand == brand;
                        return _searchBrandTile(
                          context: context,
                          brand: brand,
                          selected: selected,
                          labelColor: labelColor,
                          onTap: () {
                            setState(() {
                              _homeToggleBrand(brand);
                              clearFiltersOnVehicleChange();
                            });
                            setStateDialog(() {});
                          },
                        );
                      },
                    ),
                  );
                },
              )
            else
              SizedBox(
                height: _searchBrandRowHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: collapsedBrands.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: _searchBrandGridSpacing),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _searchBrandActionTile(
                        context: context,
                        labelColor: labelColor,
                        isLight: isLight,
                        icon: Icons.more_horiz,
                        label: _trLegacyText(
                          context,
                          'More',
                          ar: 'المزيد',
                          ku: 'زیاتر',
                        ),
                        onTap: onToggleBrandsExpanded,
                      );
                    }
                    final brand = collapsedBrands[index - 1];
                    final selected = _homeSelectedBrand == brand;
                    return _searchBrandTile(
                      context: context,
                      brand: brand,
                      selected: selected,
                      labelColor: labelColor,
                      onTap: () {
                        setState(() {
                          _homeToggleBrand(brand);
                          clearFiltersOnVehicleChange();
                        });
                        setStateDialog(() {});
                      },
                    );
                  },
                ),
              ),
            if (hasBrand && _homeSingleSelectedBrand != null) ...[
              const SizedBox(height: 16),
              _searchSectionHeader(
                context,
                title: loc.modelLabel,
                valueSummary: _searchModelLabel(context),
                onSummaryTap: () {
                  setState(() {
                    selectedModel = null;
                    selectedTrim = null;
                    clearFiltersOnVehicleChange();
                  });
                  setStateDialog(() {});
                },
              ),
              const SizedBox(height: 12),
              _searchModelField(context, setStateDialog),
            ],
            if (hasBrand && hasModel && trimList.isNotEmpty) ...[
              const SizedBox(height: 16),
              _searchSectionHeader(
                context,
                title: loc.trimLabel,
                valueSummary: _searchTrimLabel(context),
                onSummaryTap: () {
                  setState(() {
                    selectedTrim = null;
                    clearFiltersOnVehicleChange();
                  });
                  setStateDialog(() {});
                },
              ),
              const SizedBox(height: 12),
              _searchTrimField(context, setStateDialog, trimList),
            ],
          ],
        ),
      ),
    );
  }

  IconData _searchDriveTypeIcon(String drive) {
    switch (drive) {
      case 'FWD':
        return Icons.arrow_circle_up_outlined;
      case 'RWD':
        return Icons.arrow_circle_down_outlined;
      case 'AWD':
        return Icons.sync_alt_rounded;
      default:
        return Icons.grid_view_rounded;
    }
  }

  IconData _searchFuelTypeIcon(String fuel) {
    switch (fuel) {
      case 'Electric':
        return Icons.electric_bolt_outlined;
      case 'Hybrid':
      case 'Plug-in Hybrid':
        return Icons.energy_savings_leaf_outlined;
      case 'Diesel':
        return Icons.local_gas_station_outlined;
      default:
        return Icons.local_gas_station_outlined;
    }
  }

  IconData _searchTransmissionIcon(String transmission) {
    switch (transmission) {
      case 'Manual':
        return Icons.pan_tool_alt_outlined;
      default:
        return Icons.settings_outlined;
    }
  }

  IconData _searchRegionSpecIcon(String code) {
    switch (code) {
      case 'us':
        return Icons.flag_outlined;
      case 'gcc':
        return Icons.mosque_outlined;
      case 'iraq':
        return Icons.location_city_outlined;
      case 'canada':
        return Icons.map_outlined;
      case 'eu':
        return Icons.euro_outlined;
      case 'cn':
        return Icons.language_outlined;
      case 'korea':
        return Icons.star_outline;
      case 'ru':
        return Icons.ac_unit_outlined;
      case 'iran':
        return Icons.public_outlined;
      default:
        return Icons.grid_view_rounded;
    }
  }

  IconData _searchPlateTypeIcon(String plateType) {
    switch (plateType) {
      case 'private':
        return Icons.directions_car_outlined;
      case 'temporary':
        return Icons.schedule_outlined;
      case 'commercial':
        return Icons.local_shipping_outlined;
      case 'taxi':
        return Icons.local_taxi_outlined;
      default:
        return Icons.grid_view_rounded;
    }
  }

  IconData _searchPlateCityIcon(String city) {
    return Icons.location_on_outlined;
  }

  String _searchPlateCityLabel(BuildContext context, String city) {
    return _translateValueGlobal(context, city) ?? city;
  }

  String _searchTitleStatusLabel(BuildContext context, String status) {
    final loc = AppLocalizations.of(context)!;
    switch (status) {
      case 'clean':
        return loc.value_title_clean;
      case 'damaged':
        return loc.value_title_damaged;
      default:
        return status;
    }
  }

  Widget _searchModelField(
    BuildContext context,
    StateSetter setStateDialog,
  ) {
    final brand = _homeSingleSelectedBrand;
    if (brand == null || brand.isEmpty) return const SizedBox.shrink();
    final modelList = models[brand] ?? const <String>[];
    if (modelList.isEmpty) return const SizedBox.shrink();

    final currentModel =
        selectedModel != null && modelList.contains(selectedModel)
            ? selectedModel
            : null;

    final loc = AppLocalizations.of(context)!;
    return FilterDropdownField(
      style: _searchMoreFiltersStyle(context),
      label: loc.modelLabel,
      value: currentModel,
      narrowMenu: false,
      items: modelList.map(
        (model) {
          final display =
              CarNameTranslations.getLocalizedModel(context, brand, model)
                      .isNotEmpty
                  ? CarNameTranslations.getLocalizedModel(context, brand, model)
                  : model;
          return DropdownMenuItem<String>(
            value: model,
            child: Text(display, overflow: TextOverflow.ellipsis),
          );
        },
      ).toList(),
      hint: Text(
        loc.tapToSelect,
        style: TextStyle(
          color: _searchAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
      onChanged: (value) {
        setState(() {
          selectedModel = value;
          selectedTrim = null;
          clearFiltersOnVehicleChange();
        });
        setStateDialog(() {});
      },
    );
  }

  Widget _searchTrimField(
    BuildContext context,
    StateSetter setStateDialog,
    List<String> trimList,
  ) {
    final currentTrim = selectedTrim != null && trimList.contains(selectedTrim)
        ? selectedTrim
        : null;

    final loc = AppLocalizations.of(context)!;
    return FilterDropdownField(
      style: _searchMoreFiltersStyle(context),
      label: loc.trimLabel,
      value: currentTrim,
      narrowMenu: false,
      items: trimList
          .map(
            (trim) => DropdownMenuItem<String>(
              value: trim,
              child: Text(trim, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      hint: Text(
        loc.tapToSelect,
        style: TextStyle(
          color: _searchAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
      onChanged: (value) {
        setState(() {
          selectedTrim = value;
          clearFiltersOnVehicleChange();
        });
        setStateDialog(() {});
      },
    );
  }
}
