part of 'home_flow.dart';

mixin _HomePageSearchFiltersPageUi on _HomePageMoreFiltersDialog {
  static const Color _searchAccent = Color(0xFFFF6B00);

  MoreFiltersDialogStyle _searchMoreFiltersStyle(BuildContext context) {
    final base = _moreFiltersStyle(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return MoreFiltersDialogStyle(
      onSurface: base.onSurface,
      muted: base.muted,
      anyOrange: base.anyOrange,
      fieldFill: isLight ? Colors.white : base.fieldFill,
      menuFill: base.menuFill,
      fieldGap: 12,
    );
  }

  Widget _searchNumericRangeCard({
    required BuildContext context,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _searchCard(
        context,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _searchAllFilterSections(
    BuildContext context,
    StateSetter setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    final loc = AppLocalizations.of(context)!;

    return KeyedSubtree(
      key: ValueKey<int>(_moreFiltersDialogFieldGeneration),
      child: Column(
        children: [
          _searchNumericRangeCard(
            context: context,
            children: _moreFiltersPriceWidgets(
              context,
              setStateDialog,
              style,
            ),
          ),
          _searchNumericRangeCard(
            context: context,
            children: _moreFiltersYearWidgets(
              context,
              setStateDialog,
              style,
            ),
          ),
          _searchNumericRangeCard(
            context: context,
            children: _moreFiltersMileageRangeWidgets(
              context,
              setStateDialog,
              style,
            ),
          ),
          _searchMultiIconCardSection(
            context,
            setStateDialog,
            title: loc.fuelTypeLabel,
            options: fuelTypes,
            selectedValues: _homeSelectedFuelTypes,
            onToggle: _homeToggleFuelType,
            onClear: () => _homeSetSelectedFuelTypes([]),
            iconForOption: _searchFuelTypeIcon,
            imageAssetForOption: fuelTypeImageAsset,
            labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
            scrollHorizontally: true,
            tileWidth: 100,
            tileImageWidth: 44,
            tileImageHeight: 44,
            tileImageBorderRadius: 8,
          ),
          _searchMultiIconCardSection(
            context,
            setStateDialog,
            title: loc.bodyTypeLabel,
            options: bodyTypes,
            selectedValues: _homeSelectedBodyTypes,
            onToggle: _homeToggleBodyType,
            onClear: () => _homeSetSelectedBodyTypes([]),
            imageAssetForOption: body_type_assets.bodyTypeImageAsset,
            labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
            scrollHorizontally: true,
            tileWidth: 100,
            tileImageWidth: 52,
            tileImageHeight: 40,
            tileImageBorderRadius: 8,
          ),
          _searchMultiIconCardSection(
            context,
            setStateDialog,
            title: loc.driveType,
            options: driveTypes,
            selectedValues: _homeSelectedDriveTypes,
            onToggle: _homeToggleDriveType,
            onClear: () => _homeSetSelectedDriveTypes([]),
            iconForOption: _searchDriveTypeIcon,
            imageAssetForOption: driveTypeImageAsset,
            labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
            scrollHorizontally: true,
            tileWidth: 88,
            tileImageWidth: 48,
            tileImageHeight: 48,
            tileImageBorderRadius: 8,
          ),
          _searchIconCardSection(
            context,
            setStateDialog,
            title: loc.transmissionLabel,
            options: transmissions,
            selected: selectedTransmission,
            onSelected: (v) => selectedTransmission = v ?? 'Any',
            iconForOption: _searchTransmissionIcon,
            imageAssetForOption: transmissionTypeImageAsset,
            labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
            scrollHorizontally: true,
            tileWidth: 88,
            tileImageWidth: 48,
            tileImageHeight: 48,
            tileImageFit: BoxFit.contain,
            tileImageBorderRadius: 8,
          ),
          _searchNumericRangeCard(
            context: context,
            children: _moreFiltersColorWidgets(
              context,
              setStateDialog,
              style,
            ),
          ),
          _searchIconCardSection(
            context,
            setStateDialog,
            title: loc.titleStatus,
            options: const ['clean', 'damaged'],
            selected: selectedTitleStatus,
            onSelected: (v) {
              selectedTitleStatus = v;
              if (v != 'damaged') {
                selectedDamagedParts = null;
              }
            },
            labelForOption: _searchTitleStatusLabel,
            textOnly: true,
          ),
          if (selectedTitleStatus == 'damaged')
            _searchNumericRangeCard(
              context: context,
              children: [
                _searchDamagedPartsField(context, setStateDialog, style),
              ],
            ),
          _searchIconCardSection(
            context,
            setStateDialog,
            title: loc.conditionLabel,
            options: const ['New', 'Used'],
            selected: selectedCondition,
            onSelected: (v) => selectedCondition = v ?? 'Any',
            labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
            textOnly: true,
          ),
          _searchIconCardSection(
            context,
            setStateDialog,
            title: loc.regionSpecsLabel,
            options: kCarRegionSpecCodes,
            selected: selectedRegionSpecs,
            onSelected: (v) => selectedRegionSpecs = v,
            iconForOption: _searchRegionSpecIcon,
            imageAssetForOption: regionSpecFlagAsset,
            labelForOption: (ctx, o) =>
                carRegionSpecDisplayLabelLocalized(ctx, o),
            scrollHorizontally: true,
            tileWidth: 80,
            tileImageWidth: 40,
            tileImageHeight: 28,
            tileImageFit: BoxFit.cover,
            tileImageBorderRadius: 4,
          ),
          _searchIconCardSection(
            context,
            setStateDialog,
            title: _trLegacyText(
              context,
              'Plate type',
              ar: 'نوع اللوحة',
              ku: 'جۆری پڵەیت',
            ),
            options: const [
              'private',
              'temporary',
              'commercial',
              'taxi',
            ],
            selected: selectedPlateType,
            onSelected: (v) => selectedPlateType = v,
            iconForOption: _searchPlateTypeIcon,
            imageAssetForOption: plateTypeImageAsset,
            labelForOption: (ctx, o) => _translatePlateTypeLegacy(ctx, o),
            scrollHorizontally: true,
            tileWidth: 148,
            tileImageWidth: 132,
            tileImageHeight: 40,
            compactImageTile: true,
          ),
          _searchIconCardSection(
            context,
            setStateDialog,
            title: _trLegacyText(
              context,
              'Plate city',
              ar: 'مدينة اللوحة',
              ku: 'شاری پڵەیت',
            ),
            options: kPlateCityFilterOptions,
            selected: selectedPlateCity,
            onSelected: (v) => selectedPlateCity = v,
            iconForOption: _searchPlateCityIcon,
            imageAssetForOption: plateCityImageAsset,
            labelForOption: _searchPlateCityLabel,
            scrollHorizontally: true,
            tileWidth: 148,
            tileImageWidth: 132,
            tileImageHeight: 40,
            compactImageTile: true,
          ),
          _searchNumericRangeCard(
            context: context,
            children: _moreFiltersSpecsDropdownWidgets(
              context,
              setStateDialog,
              style,
            ),
          ),
        ],
      ),
    );
  }

  String _searchBrandLabel(BuildContext context) {
    final brand = _homeSelectedBrand;
    if (brand == null) return '';
    final localized = CarNameTranslations.getLocalizedBrand(context, brand);
    return localized.isNotEmpty ? localized : brand;
  }

  String _searchModelLabel(BuildContext context) {
    if (selectedModel == null || selectedModel!.isEmpty) return '';
    final localized = CarNameTranslations.getLocalizedModel(
      context,
      _homeSingleSelectedBrand,
      selectedModel,
    );
    return localized.isNotEmpty ? localized : selectedModel!;
  }

  String _searchTrimLabel(BuildContext context) {
    if (selectedTrim == null || selectedTrim!.isEmpty) return '';
    return selectedTrim!;
  }

  String _searchShowCarsLabel(BuildContext context) {
    return _trLegacyText(
      context,
      'Show Cars',
      ar: 'عرض السيارات',
      ku: 'نیشاندانی ئۆتۆمبێلەکان',
    );
  }

  BoxDecoration _searchCardDecoration(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxDecoration(
      color: isLight ? const Color(0xFFF7F7F9) : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isLight ? const Color(0xFFE8E8ED) : Colors.white12,
      ),
    );
  }

  Widget _searchCard(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: _searchCardDecoration(context),
      child: child,
    );
  }

  Widget _searchSectionHeader(
    BuildContext context, {
    required String title,
    required String valueSummary,
    VoidCallback? onSummaryTap,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final titleColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final summaryColor = isLight ? const Color(0xFF8E8E93) : Colors.white70;
    final summaryStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: summaryColor,
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: titleColor,
            ),
          ),
        ),
        InkWell(
          onTap: onSummaryTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  valueSummary,
                  style: summaryStyle,
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: summaryColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

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

  Widget _searchDamagedPartsField(
    BuildContext context,
    StateSetter setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    final loc = AppLocalizations.of(context)!;
    final current =
        selectedDamagedParts != null && selectedDamagedParts!.isNotEmpty
            ? selectedDamagedParts
            : null;

    return FilterDropdownField(
      style: style,
      label: loc.damagedParts,
      value: current,
      narrowMenu: true,
      items: List.generate(
        15,
        (i) => (i + 1).toString(),
      ).map(
        (p) => DropdownMenuItem(
          value: p,
          child: Text(
            '${localizeDigits(context, p)} ${loc.damagedParts}',
          ),
        ),
      ).toList(),
      hint: Text(
        loc.tapToSelect,
        style: TextStyle(
          color: style.anyOrange,
          fontWeight: FontWeight.w600,
        ),
      ),
      onChanged: (value) {
        setState(() {
          selectedDamagedParts = value == null || value.isEmpty ? null : value;
        });
        setStateDialog(() {});
      },
    );
  }

  String _searchOptionSummary(
    BuildContext context,
    String? selected, {
    String Function(BuildContext, String)? labelForOption,
  }) {
    if (selected == null || selected.isEmpty || selected == 'Any') {
      return '';
    }
    return labelForOption?.call(context, selected) ??
        _translateValueGlobal(context, selected) ??
        selected;
  }

  double _searchIconTileHeight({
    required bool textOnly,
    double? imageHeight,
    bool compactImageTile = false,
  }) {
    if (textOnly) return 52;
    final slotHeight = imageHeight ?? 26;
    // Tile uses symmetric vertical padding; selected state adds a 2px border.
    final verticalPadding = compactImageTile
        ? 16.0
        : (slotHeight > 80 ? 16.0 : 20.0);
    const gap = 6.0;
    const labelHeight = 15.0;
    const borderAllowance = 4.0;
    return verticalPadding + slotHeight + gap + labelHeight + borderAllowance;
  }

  double _searchIconScrollListHeight({
    required bool textOnly,
    required List<String> options,
    double? tileImageHeight,
    String? Function(String option)? imageAssetForOption,
    Widget? Function(String option)? graphicForOption,
    bool compactImageTile = false,
  }) {
    if (textOnly) return 52;
    var maxHeight = 0.0;
    for (final option in options) {
      final hasGraphic = graphicForOption != null ||
          (imageAssetForOption?.call(option) != null);
      final height = _searchIconTileHeight(
        textOnly: false,
        imageHeight: hasGraphic ? tileImageHeight : null,
        compactImageTile: compactImageTile,
      );
      if (height > maxHeight) maxHeight = height;
    }
    return maxHeight + 4;
  }

  Widget _searchIconOptionTile(
    BuildContext context, {
    required bool selected,
    IconData? icon,
    String? imageAsset,
    Widget? customGraphic,
    required String label,
    required VoidCallback onTap,
    double? width = 72,
    double? imageWidth,
    double? imageHeight,
    BoxFit imageFit = BoxFit.contain,
    double imageBorderRadius = 0,
    bool textOnly = false,
    bool compactImageTile = false,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final idleColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final Widget? graphic;
    if (textOnly) {
      graphic = null;
    } else if (customGraphic != null) {
      final slotWidth = imageWidth ?? 26;
      final slotHeight = imageHeight ?? 26;
      graphic = SizedBox(
        width: slotWidth,
        height: slotHeight,
        child: Center(child: customGraphic),
      );
    } else {
      final slotWidth = imageWidth ?? 26;
      final slotHeight = imageHeight ?? 26;
      final Widget slotChild;
      if (imageAsset != null) {
        slotChild = buildFilterIconImage(
          context: context,
          imageAsset: imageAsset,
          width: slotWidth,
          height: slotHeight,
          fit: imageFit,
          borderRadius: imageBorderRadius,
        );
      } else {
        slotChild = Icon(
          icon ?? Icons.grid_view_rounded,
          size: slotHeight * 0.85,
          color: selected ? _searchAccent : idleColor,
        );
      }
      graphic = SizedBox(
        width: slotWidth,
        height: slotHeight,
        child: Center(child: slotChild),
      );
    }
    final hPad = textOnly
        ? 12.0
        : (AppResponsive.isCompactPhone(context) ? 4.0 : 6.0);
    final vPad = textOnly
        ? 14.0
        : (compactImageTile
            ? 8.0
            : ((imageHeight ?? 0) > 80 ? 8.0 : 10.0));
    final tile = Material(
      color: isLight ? Colors.white : filterIconTileBackdropColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? _searchAccent : const Color(0xFFE0E0E5),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (graphic != null) ...[
                Center(child: graphic),
                const SizedBox(height: 6),
              ],
              AppResponsive.fittedLabel(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppResponsive.filterIconLabelFontSize(
                    context,
                    textOnly: textOnly,
                  ),
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: selected ? _searchAccent : idleColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (width == null) {
      return SizedBox(width: double.infinity, child: tile);
    }
    return SizedBox(
      width: AppResponsive.filterIconTileWidth(context, width),
      child: tile,
    );
  }

  Widget _searchIconCardSection(
    BuildContext context,
    StateSetter setStateDialog, {
    required String title,
    required List<String> options,
    required String? selected,
    required void Function(String? value) onSelected,
    IconData Function(String option)? iconForOption,
    String? Function(String option)? imageAssetForOption,
    Widget? Function(String option)? graphicForOption,
    String Function(BuildContext, String)? labelForOption,
    bool scrollHorizontally = false,
    bool textOnly = false,
    double tileWidth = 72,
    double? tileImageWidth,
    double? tileImageHeight,
    BoxFit tileImageFit = BoxFit.contain,
    double tileImageBorderRadius = 0,
    double? scrollListHeight,
    bool compactImageTile = false,
  }) {
    final visibleOptions =
        options.where((option) => option != 'Any').toList(growable: false);
    final normalizedSelected =
        (selected == null || selected.isEmpty || selected == 'Any')
            ? null
            : selected;

    final tiles = visibleOptions.map((option) {
      final isSelected = normalizedSelected == option;
      final label = labelForOption?.call(context, option) ??
          _translateValueGlobal(context, option) ??
          option;
      final customGraphic = graphicForOption?.call(option);
      final usesImageAsset = !textOnly &&
          customGraphic == null &&
          imageAssetForOption != null;
      return _searchIconOptionTile(
        context,
        selected: isSelected,
        icon: textOnly
            ? null
            : (customGraphic != null
                ? null
                : (usesImageAsset &&
                        imageAssetForOption.call(option) == null
                    ? iconForOption?.call(option)
                    : (usesImageAsset ? null : iconForOption?.call(option)))),
        imageAsset: textOnly || customGraphic != null
            ? null
            : imageAssetForOption?.call(option),
        customGraphic: customGraphic,
        label: label,
        width: scrollHorizontally ? tileWidth : null,
        imageWidth: (usesImageAsset || customGraphic != null)
            ? tileImageWidth
            : null,
        imageHeight: (usesImageAsset || customGraphic != null)
            ? tileImageHeight
            : null,
        imageFit: tileImageFit,
        imageBorderRadius: tileImageBorderRadius,
        textOnly: textOnly,
        compactImageTile: compactImageTile,
        onTap: () {
          setState(() => onSelected(isSelected ? null : option));
          setStateDialog(() {});
        },
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _searchCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _searchSectionHeader(
              context,
              title: title,
              valueSummary: _searchOptionSummary(
                context,
                selected,
                labelForOption: labelForOption,
              ),
              onSummaryTap: () {
                setState(() => onSelected(null));
                setStateDialog(() {});
              },
            ),
            const SizedBox(height: 12),
            if (scrollHorizontally)
              SizedBox(
                height: scrollListHeight ??
                    _searchIconScrollListHeight(
                      textOnly: textOnly,
                      options: visibleOptions,
                      tileImageHeight: tileImageHeight,
                      imageAssetForOption: imageAssetForOption,
                      graphicForOption: graphicForOption,
                      compactImageTile: compactImageTile,
                    ),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tiles.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 6),
                  itemBuilder: (context, index) => tiles[index],
                ),
              )
            else
              Row(
                children: tiles
                    .map(
                      (tile) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: tile,
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _searchMultiIconCardSection(
    BuildContext context,
    StateSetter setStateDialog, {
    required String title,
    required List<String> options,
    required List<String> selectedValues,
    required void Function(String value) onToggle,
    required VoidCallback onClear,
    IconData Function(String option)? iconForOption,
    String? Function(String option)? imageAssetForOption,
    String Function(BuildContext, String)? labelForOption,
    bool scrollHorizontally = false,
    double tileWidth = 72,
    double? tileImageWidth,
    double? tileImageHeight,
    BoxFit tileImageFit = BoxFit.contain,
    double tileImageBorderRadius = 0,
    double? scrollListHeight,
  }) {
    final visibleOptions =
        options.where((option) => option != 'Any').toList(growable: false);

    final tiles = visibleOptions.map((option) {
      final isSelected = selectedValues.contains(option);
      final label = labelForOption?.call(context, option) ??
          _translateValueGlobal(context, option) ??
          option;
      return _searchIconOptionTile(
        context,
        selected: isSelected,
        icon: imageAssetForOption?.call(option) == null
            ? iconForOption?.call(option)
            : null,
        imageAsset: imageAssetForOption?.call(option),
        label: label,
        width: scrollHorizontally ? tileWidth : null,
        imageWidth: imageAssetForOption == null ? null : tileImageWidth,
        imageHeight: imageAssetForOption == null ? null : tileImageHeight,
        imageFit: tileImageFit,
        imageBorderRadius: tileImageBorderRadius,
        onTap: () {
          setState(() => onToggle(option));
          setStateDialog(() {});
        },
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _searchCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _searchSectionHeader(
              context,
              title: title,
              valueSummary: homeFilterSummaryLabel(
                '',
                selectedValues,
                (value) =>
                    labelForOption?.call(context, value) ??
                    _translateValueGlobal(context, value) ??
                    value,
              ),
              onSummaryTap: () {
                setState(onClear);
                setStateDialog(() {});
              },
            ),
            const SizedBox(height: 12),
            if (scrollHorizontally)
              SizedBox(
                height: scrollListHeight ??
                    _searchIconScrollListHeight(
                      textOnly: false,
                      options: visibleOptions,
                      tileImageHeight: tileImageHeight,
                      imageAssetForOption: imageAssetForOption,
                    ),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tiles.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 6),
                  itemBuilder: (context, index) => tiles[index],
                ),
              )
            else
              Row(
                children: tiles
                    .map(
                      (tile) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: tile,
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
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

  List<String> _searchKeywordMatchedBrands(String raw) {
    final q = raw.toLowerCase().trim();
    if (q.isEmpty) return const [];
    return homeBrands.where((b) => b.toLowerCase().contains(q)).toList();
  }

  List<Map<String, String>> _searchKeywordMatchedModels(String raw) {
    final q = raw.toLowerCase().trim();
    if (q.isEmpty) return const [];
    final seen = <String>{};
    final results = <Map<String, String>>[];
    for (final brand in homeBrands) {
      final brandModels = models[brand] ?? const <String>[];
      if (brand.toLowerCase().contains(q)) {
        for (final model in brandModels) {
          final key = '$brand|$model';
          if (seen.add(key)) {
            results.add({'brand': brand, 'model': model});
          }
        }
      }
      for (final model in brandModels) {
        if (model.toLowerCase().contains(q)) {
          final key = '$brand|$model';
          if (seen.add(key)) {
            results.add({'brand': brand, 'model': model});
          }
        }
      }
    }
    results.sort((a, b) {
      final modelCmp = a['model']!.toLowerCase().compareTo(b['model']!.toLowerCase());
      if (modelCmp != 0) return modelCmp;
      return a['brand']!.toLowerCase().compareTo(b['brand']!.toLowerCase());
    });
    return results;
  }

  InputDecoration _searchKeywordFieldDecoration(
    BuildContext context,
    StateSetter setStateDialog,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: isLight ? const Color(0xFFE8E8ED) : Colors.white24,
      ),
    );
    return InputDecoration(
      hintText: _trLegacyText(
        context,
        'Search make or model',
        ar: 'ابحث عن الماركة أو الموديل',
        ku: 'براند یان مۆدێل بگەڕێ',
      ),
      prefixIcon: const Icon(Icons.search, color: _searchAccent),
      suffixIcon: _searchFiltersKeywordController.text.trim().isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.clear, size: 20),
              color: _searchAccent,
              onPressed: () {
                _searchFiltersKeywordController.clear();
                setStateDialog(() {});
              },
            ),
      filled: true,
      fillColor: isLight ? const Color(0xFFF7F7F9) : Colors.white10,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _searchAccent, width: 2),
      ),
    );
  }

  Widget _searchKeywordResultsPanel(
    BuildContext context,
    StateSetter setStateDialog,
    String query,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final mutedColor = isLight ? const Color(0xFF6B6B6B) : Colors.white70;
    final brands = _searchKeywordMatchedBrands(query);
    final modelHits = _searchKeywordMatchedModels(query);
    const maxResults = 10;
    final brandSlots = brands.take(maxResults).toList();
    final modelSlots = modelHits.take(maxResults - brandSlots.length).toList();

    if (brandSlots.isEmpty && modelSlots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          _trLegacyText(
            context,
            'No makes or models match your search.',
            ar: 'لا توجد ماركات أو موديلات مطابقة.',
            ku: 'هیچ براند یان مۆدێلێک نەدۆزرایەوە.',
          ),
          style: TextStyle(color: mutedColor, fontSize: 14),
        ),
      );
    }

    return Material(
      color: isLight ? Colors.white : Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final brand in brandSlots)
            ListTile(
              dense: true,
              leading: _searchBrandLogoCircle(brand),
              title: Text(
                CarNameTranslations.getLocalizedBrand(context, brand).isNotEmpty
                    ? CarNameTranslations.getLocalizedBrand(context, brand)
                    : brand,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                _trLegacyText(
                  context,
                  'Make',
                  ar: 'الماركة',
                  ku: 'براند',
                ),
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
              onTap: () {
                setState(() {
                  _homeSetSelectedBrand(brand);
                  clearFiltersOnVehicleChange();
                  _searchFiltersKeywordController.clear();
                  _searchFiltersKeywordFocusNode.unfocus();
                });
                setStateDialog(() {});
              },
            ),
          for (final item in modelSlots)
            ListTile(
              dense: true,
              leading: _searchBrandLogoCircle(item['brand']!),
              title: Text(
                item['model']!,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                CarNameTranslations.getLocalizedBrand(
                          context,
                          item['brand']!,
                        ).isNotEmpty
                    ? CarNameTranslations.getLocalizedBrand(
                        context,
                        item['brand']!,
                      )
                    : item['brand']!,
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
              onTap: () {
                setState(() {
                  _homeSetSelectedBrand(item['brand']);
                  selectedModel = item['model'];
                  selectedTrim = null;
                  clearFiltersOnVehicleChange();
                  _searchFiltersKeywordController.clear();
                  _searchFiltersKeywordFocusNode.unfocus();
                });
                setStateDialog(() {});
              },
            ),
        ],
      ),
    );
  }

  Widget _searchKeywordField(
    BuildContext context,
    StateSetter setStateDialog, {
    bool autofocus = false,
  }) {
    final query = _searchFiltersKeywordController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchFiltersKeywordController,
          focusNode: _searchFiltersKeywordFocusNode,
          autofocus: autofocus,
          onChanged: (_) => setStateDialog(() {}),
          textInputAction: TextInputAction.search,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.words,
          enableInteractiveSelection: true,
          decoration: _searchKeywordFieldDecoration(context, setStateDialog),
        ),
        if (query.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: _searchKeywordResultsPanel(
                context,
                setStateDialog,
                query,
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _searchFiltersPageScrollBody(
    BuildContext context,
    StateSetter setStateDialog, {
    required bool brandsExpanded,
    required VoidCallback onToggleBrandsExpanded,
  }) {
    final style = _searchMoreFiltersStyle(context);

    return [
      _searchMakeSection(
        context,
        setStateDialog,
        brandsExpanded: brandsExpanded,
        onToggleBrandsExpanded: onToggleBrandsExpanded,
      ),
      _searchAllFilterSections(context, setStateDialog, style),
    ];
  }

  Future<void> _openHomeSearchFiltersPage(
    BuildContext context, {
    bool focusSearchField = true,
  }) async {
    _searchFiltersKeywordController.clear();
    _searchFiltersKeywordFocusNode.unfocus();
    _syncMoreFiltersControllers();
    final revertSnapshot = <Map<String, dynamic>>[
      _searchFiltersPageSnapshot(),
    ];
    final applied = await Navigator.of(context).push<bool>(
      AppPageRoute<bool>(
        fullscreenDialog: true,
        builder: (pageContext) {
          var didRequestSearchFocus = false;
          var searchBrandsExpanded = false;
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              void toggleSearchBrandsExpanded() {
                setStateDialog(() {
                  searchBrandsExpanded = !searchBrandsExpanded;
                });
              }
              if (focusSearchField && !didRequestSearchFocus) {
                didRequestSearchFocus = true;
                _focusSearchFiltersKeywordField();
              }
              final isLightShell =
                  Theme.of(context).brightness == Brightness.light;
              final titleColor =
                  isLightShell ? const Color(0xFF1A1A1A) : Colors.white;
              return PopScope(
                canPop: true,
                onPopInvokedWithResult: (bool didPop, dynamic result) {
                  if (didPop && result != true) {
                    _cancelSearchFiltersPage(revertSnapshot.first);
                  }
                },
                child: Scaffold(
                  resizeToAvoidBottomInset: true,
                  backgroundColor: isLightShell ? Colors.white : null,
                  body: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close),
                                color: titleColor,
                                onPressed: () => Navigator.pop(context),
                              ),
                              Expanded(
                                child: Text(
                                  _trLegacyText(
                                    context,
                                    'Search Cars',
                                    ar: 'بحث السيارات',
                                    ku: 'گەڕانی ئۆتۆمبێل',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: titleColor,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: _trLegacyText(
                                  context,
                                  'Save search',
                                  ar: 'حفظ البحث',
                                  ku: 'پاشەکەوتکردنی گەڕان',
                                ),
                                icon: const Icon(Icons.bookmark_add_outlined),
                                color: _searchAccent,
                                onPressed: () => unawaited(
                                  _saveSearchFromFiltersPage(context),
                                ),
                              ),
                              IconButton(
                                tooltip: _trLegacyText(
                                  context,
                                  'Notify me',
                                  ar: 'أعلمني',
                                  ku: 'ئاگادارم بکە',
                                ),
                                icon: const Icon(
                                  Icons.notifications_active_outlined,
                                ),
                                color: _searchAccent,
                                onPressed: () => unawaited(
                                  _enableSearchMatchAlerts(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: _searchKeywordField(
                            context,
                            setStateDialog,
                            autofocus: focusSearchField,
                          ),
                        ),
                        Expanded(
                          child: Container(
                            decoration: isLightShell
                                ? null
                                : AppThemes.shellBackgroundDecoration(
                                    Theme.of(context).brightness,
                                  ),
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              children: _searchFiltersPageScrollBody(
                                context,
                                setStateDialog,
                                brandsExpanded: searchBrandsExpanded,
                                onToggleBrandsExpanded:
                                    toggleSearchBrandsExpanded,
                              ),
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: SizedBox(
                            height: 58,
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      await _resetSearchFiltersPage(
                                        () => setStateDialog(() {}),
                                      );
                                      revertSnapshot[0] =
                                          _searchFiltersPageSnapshot();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _searchAccent,
                                      side: const BorderSide(
                                        color: _searchAccent,
                                        width: 1.4,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(
                                      AppLocalizations.of(context)!.resetButton,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 5,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _searchAccent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: () {
                                      unawaited(_persistFilters());
                                      onFilterChanged();
                                      Navigator.pop(context, true);
                                    },
                                    child: Text(
                                      _searchShowCarsLabel(context),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (applied != true) {
      onFilterChanged();
    }
  }
}
