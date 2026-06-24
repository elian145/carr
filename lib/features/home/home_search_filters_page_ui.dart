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
          _searchIconCardSection(
            context,
            setStateDialog,
            title: loc.fuelTypeLabel,
            options: fuelTypes,
            selected: selectedFuelType,
            onSelected: (v) => selectedFuelType = v ?? 'Any',
            iconForOption: _searchFuelTypeIcon,
            labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
            scrollHorizontally: true,
          ),
          _searchIconCardSection(
            context,
            setStateDialog,
            title: loc.bodyTypeLabel,
            options: bodyTypes,
            selected: selectedBodyType,
            onSelected: (v) => selectedBodyType = v,
            iconForOption: _searchBodyTypeIcon,
            labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
            scrollHorizontally: true,
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
            title: loc.driveType,
            options: driveTypes,
            selected: selectedDriveType,
            onSelected: (v) => selectedDriveType = v,
            iconForOption: _searchDriveTypeIcon,
            labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
          ),
          _searchIconCardSection(
            context,
            setStateDialog,
            title: loc.transmissionLabel,
            options: transmissions,
            selected: selectedTransmission,
            onSelected: (v) => selectedTransmission = v ?? 'Any',
            iconForOption: _searchTransmissionIcon,
            labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
          ),
          _searchIconCardSection(
            context,
            setStateDialog,
            title: loc.titleStatus,
            options: const ['Any', 'clean', 'damaged'],
            selected: selectedTitleStatus,
            onSelected: (v) {
              selectedTitleStatus = v;
              if (v != 'damaged') {
                selectedDamagedParts = null;
              }
            },
            iconForOption: _searchTitleStatusIcon,
            labelForOption: _searchTitleStatusLabel,
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
            options: conditions,
            selected: selectedCondition,
            onSelected: (v) => selectedCondition = v ?? 'Any',
            iconForOption: _searchConditionIcon,
            labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
          ),
          _searchIconCardSection(
            context,
            setStateDialog,
            title: loc.regionSpecsLabel,
            options: ['Any', ...kCarRegionSpecCodes],
            selected: selectedRegionSpecs,
            onSelected: (v) => selectedRegionSpecs = v,
            iconForOption: _searchRegionSpecIcon,
            labelForOption: (ctx, o) =>
                carRegionSpecDisplayLabelLocalized(ctx, o),
            scrollHorizontally: true,
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
              'Any',
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
            tileWidth: 104,
            tileImageWidth: 96,
            tileImageHeight: 20,
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
    final loc = AppLocalizations.of(context)!;
    if (selectedBrand == null || selectedBrand!.isEmpty) return loc.any;
    final localized =
        CarNameTranslations.getLocalizedBrand(context, selectedBrand);
    return localized.isNotEmpty ? localized : selectedBrand!;
  }

  String _searchModelLabel(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    if (selectedModel == null || selectedModel!.isEmpty) return loc.any;
    final localized = CarNameTranslations.getLocalizedModel(
      context,
      selectedBrand,
      selectedModel,
    );
    return localized.isNotEmpty ? localized : selectedModel!;
  }

  String _searchTrimLabel(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    if (selectedTrim == null || selectedTrim!.isEmpty) return loc.any;
    return selectedTrim!;
  }

  String _searchShowCarsLabel(BuildContext context) {
    final count = localizeDigits(context, cars.length.toString());
    return _trLegacyText(
      context,
      'Show $count Cars',
      ar: 'عرض $count سيارة',
      ku: 'نیشاندانی $count ئۆتۆمبێل',
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
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: titleColor,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: onSummaryTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  valueSummary,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: summaryColor,
                  ),
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

  String _searchBrandLogoSlug(String brand) {
    return brandLogoFilenames[brand] ??
        brand.toLowerCase().replaceAll(' ', '-');
  }

  Widget _searchBrandLogoCircle(String brand, {double size = 52}) {
    final slug = _searchBrandLogoSlug(brand);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      child: CachedNetworkImage(
        imageUrl: '${getApiBase()}/static/images/brands/$slug.png',
        placeholder: (context, url) => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (context, url, error) => Icon(
          Icons.directions_car,
          size: 22,
          color: _searchAccent,
        ),
        fit: BoxFit.contain,
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

  Future<void> _openSearchBrandPicker(
    BuildContext context,
    void Function(void Function()) setStateDialog,
  ) async {
    final brand = await _showHomeBrandPickerDialog(context);
    if (brand == null) return;
    setState(() {
      selectedBrand = brand;
      selectedModel = null;
      selectedTrim = null;
      clearFiltersOnVehicleChange();
    });
    setStateDialog(() {});
  }

  Widget _searchMakeSection(
    BuildContext context,
    StateSetter setStateDialog,
  ) {
    final loc = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final labelColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final featured = _searchFeaturedBrands();
    final hasBrand =
        selectedBrand != null && selectedBrand!.trim().isNotEmpty;
    final hasModel =
        selectedModel != null && selectedModel!.trim().isNotEmpty;
    final trimList = hasBrand && hasModel
        ? (trimsByBrandModel[selectedBrand!]?[selectedModel!] ??
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
              onSummaryTap: () =>
                  _openSearchBrandPicker(context, setStateDialog),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: featured.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  if (index == featured.length) {
                    return InkWell(
                      onTap: () => _openSearchBrandPicker(
                        context,
                        setStateDialog,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 72,
                        child: Column(
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
                                Icons.more_horiz,
                                color: _searchAccent,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _trLegacyText(
                                context,
                                'More',
                                ar: 'المزيد',
                                ku: 'زیاتر',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: labelColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final brand = featured[index];
                  final selected = selectedBrand == brand;
                  final display = CarNameTranslations.getLocalizedBrand(
                            context,
                            brand,
                          ).isNotEmpty
                      ? CarNameTranslations.getLocalizedBrand(context, brand)
                      : brand;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        selectedBrand = brand;
                        selectedModel = null;
                        selectedTrim = null;
                        clearFiltersOnVehicleChange();
                      });
                      setStateDialog(() {});
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 72,
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? _searchAccent
                                    : const Color(0xFFE0E0E5),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: _searchBrandLogoCircle(brand),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            display,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? _searchAccent : labelColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (hasBrand) ...[
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
      case '4WD':
        return Icons.terrain_outlined;
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

  IconData _searchTitleStatusIcon(String status) {
    switch (status) {
      case 'clean':
        return Icons.verified_outlined;
      case 'damaged':
        return Icons.car_crash_outlined;
      default:
        return Icons.grid_view_rounded;
    }
  }

  String _searchTitleStatusLabel(BuildContext context, String status) {
    final loc = AppLocalizations.of(context)!;
    switch (status) {
      case 'Any':
        return loc.any;
      case 'clean':
        return loc.value_title_clean;
      case 'damaged':
        return loc.value_title_damaged;
      default:
        return status;
    }
  }

  IconData _searchConditionIcon(String condition) {
    switch (condition) {
      case 'New':
        return Icons.fiber_new_outlined;
      case 'Used':
        return Icons.history_toggle_off_outlined;
      default:
        return Icons.grid_view_rounded;
    }
  }

  Widget _searchDamagedPartsField(
    BuildContext context,
    StateSetter setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    final loc = AppLocalizations.of(context)!;

    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: selectedDamagedParts ?? '',
      decoration: InputDecoration(
        labelText: loc.damagedParts,
        filled: true,
        fillColor: style.fieldFill,
        labelStyle: TextStyle(
          color: style.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      items: [
        DropdownMenuItem(
          value: '',
          child: Text(
            loc.any,
            style: TextStyle(color: style.anyOrange),
          ),
        ),
        ...List.generate(
          15,
          (i) => (i + 1).toString(),
        ).map(
          (p) => DropdownMenuItem(
            value: p,
            child: Text(
              '${localizeDigits(context, p)} ${loc.damagedParts}',
            ),
          ),
        ),
      ],
      onChanged: (value) {
        setState(() {
          selectedDamagedParts = value == null || value.isEmpty ? null : value;
        });
        setStateDialog(() {});
      },
    );
  }

  IconData _searchBodyTypeIcon(String bodyType) {
    if (bodyType == 'Any') return Icons.grid_view_rounded;
    return homeFilterBodyTypeIcon(bodyType.toLowerCase());
  }

  String _searchOptionSummary(
    BuildContext context,
    String? selected, {
    String Function(BuildContext, String)? labelForOption,
  }) {
    final loc = AppLocalizations.of(context)!;
    if (selected == null || selected.isEmpty || selected == 'Any') {
      return loc.any;
    }
    return labelForOption?.call(context, selected) ??
        _translateValueGlobal(context, selected) ??
        selected;
  }

  Widget _searchIconOptionTile(
    BuildContext context, {
    required bool selected,
    IconData? icon,
    String? imageAsset,
    required String label,
    required VoidCallback onTap,
    double? width = 72,
    double? imageWidth,
    double? imageHeight,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final idleColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final slotWidth = imageWidth ?? 26;
    final slotHeight = imageHeight ?? 26;
    final Widget slotChild;
    if (imageAsset != null) {
      slotChild = Image.asset(
        imageAsset,
        width: slotWidth,
        height: slotHeight,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    } else {
      slotChild = Icon(
        icon ?? Icons.grid_view_rounded,
        size: slotHeight * 0.85,
        color: selected ? _searchAccent : idleColor,
      );
    }
    final graphic = SizedBox(
      width: slotWidth,
      height: slotHeight,
      child: Center(child: slotChild),
    );
    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: isLight ? Colors.white : Colors.black.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _searchAccent : const Color(0xFFE0E0E5),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              graphic,
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? _searchAccent : idleColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (width == null) return tile;
    return SizedBox(width: width, child: tile);
  }

  Widget _searchIconCardSection(
    BuildContext context,
    StateSetter setStateDialog, {
    required String title,
    required List<String> options,
    required String? selected,
    required void Function(String? value) onSelected,
    required IconData Function(String option) iconForOption,
    String? Function(String option)? imageAssetForOption,
    String Function(BuildContext, String)? labelForOption,
    bool scrollHorizontally = false,
    double tileWidth = 72,
    double? tileImageWidth,
    double? tileImageHeight,
  }) {
    final loc = AppLocalizations.of(context)!;
    final normalizedSelected =
        (selected == null || selected.isEmpty || selected == 'Any')
            ? null
            : selected;

    final tiles = options.map((option) {
      final isAny = option == 'Any';
      final isSelected =
          isAny ? normalizedSelected == null : normalizedSelected == option;
      final label = isAny
          ? loc.any
          : (labelForOption?.call(context, option) ??
              _translateValueGlobal(context, option) ??
              option);
      return _searchIconOptionTile(
        context,
        selected: isSelected,
        icon: imageAssetForOption?.call(option) == null
            ? iconForOption(option)
            : null,
        imageAsset: imageAssetForOption?.call(option),
        label: label,
        width: scrollHorizontally ? tileWidth : null,
        imageWidth: imageAssetForOption == null ? null : tileImageWidth,
        imageHeight: imageAssetForOption == null ? null : tileImageHeight,
        onTap: () {
          setState(() => onSelected(isAny ? null : option));
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
                height: 88,
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
    final loc = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final brand = selectedBrand;
    if (brand == null || brand.isEmpty) return const SizedBox.shrink();
    final modelList = models[brand] ?? const <String>[];
    if (modelList.isEmpty) return const SizedBox.shrink();

    final currentModel =
        selectedModel != null && modelList.contains(selectedModel)
            ? selectedModel
            : null;

    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: currentModel,
      decoration: InputDecoration(
        hintText: loc.any,
        filled: true,
        fillColor: isLight ? Colors.white : Colors.black.withValues(alpha: 0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLight ? const Color(0xFFE0E0E5) : Colors.white24,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLight ? const Color(0xFFE0E0E5) : Colors.white24,
          ),
        ),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(
            loc.any,
            style: TextStyle(
              color: _searchAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...modelList.map(
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
        ),
      ],
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
    final loc = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final currentTrim = selectedTrim != null && trimList.contains(selectedTrim)
        ? selectedTrim
        : null;

    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: currentTrim,
      decoration: InputDecoration(
        hintText: loc.any,
        filled: true,
        fillColor: isLight ? Colors.white : Colors.black.withValues(alpha: 0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLight ? const Color(0xFFE0E0E5) : Colors.white24,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLight ? const Color(0xFFE0E0E5) : Colors.white24,
          ),
        ),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(
            loc.any,
            style: TextStyle(
              color: _searchAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...trimList.map(
          (trim) => DropdownMenuItem<String>(
            value: trim,
            child: Text(trim, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) {
        setState(() {
          selectedTrim = value;
          clearFiltersOnVehicleChange();
        });
        setStateDialog(() {});
      },
    );
  }

  List<Widget> _searchFiltersPageBody(
    BuildContext context,
    StateSetter setStateDialog,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final style = _searchMoreFiltersStyle(context);

    return [
      TextField(
        readOnly: true,
        onTap: () => _openMoreFiltersBrandModelSearch(context, setStateDialog),
        decoration: InputDecoration(
          hintText: _trLegacyText(
            context,
            'Search make, model, or keyword',
            ar: 'ابحث عن الماركة أو الموديل أو كلمة',
            ku: 'براند، مۆدێل یان وشە بگەڕێ',
          ),
          prefixIcon: const Icon(Icons.search, color: _searchAccent),
          filled: true,
          fillColor: isLight ? const Color(0xFFF7F7F9) : Colors.white10,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: isLight ? const Color(0xFFE8E8ED) : Colors.white24,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: isLight ? const Color(0xFFE8E8ED) : Colors.white24,
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      _searchMakeSection(context, setStateDialog),
      _searchAllFilterSections(context, setStateDialog, style),
    ];
  }

  Future<void> _openHomeSearchFiltersPage(BuildContext context) async {
    _syncMoreFiltersControllers();
    final searchFiltersSnapshot = _searchFiltersPageSnapshot();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (pageContext) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              final isLightShell =
                  Theme.of(context).brightness == Brightness.light;
              final titleColor =
                  isLightShell ? const Color(0xFF1A1A1A) : Colors.white;
              return PopScope(
                canPop: true,
                onPopInvokedWithResult: (bool didPop, dynamic result) {
                  if (didPop && result != true) {
                    _cancelSearchFiltersPage(searchFiltersSnapshot);
                  }
                },
                child: Scaffold(
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
                              TextButton(
                                onPressed: () async {
                                  await _resetSearchFiltersPage(
                                    () => setStateDialog(() {}),
                                  );
                                },
                                child: Text(
                                  AppLocalizations.of(context)!.resetButton,
                                  style: const TextStyle(
                                    color: _searchAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
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
                              children: _searchFiltersPageBody(
                                context,
                                setStateDialog,
                              ),
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: SizedBox(
                            width: double.infinity,
                            height: 52,
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
  }
}
