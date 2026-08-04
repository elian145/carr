part of 'home_flow.dart';

mixin _HomePageSearchFiltersPageUi on _HomePageSearchFiltersKeyword {
  List<Widget> _searchEssentialFilterSections(
    BuildContext context,
    StateSetter setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    final loc = AppLocalizations.of(context)!;

    return [
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
        title: loc.conditionLabel,
        options: const ['New', 'Used'],
        selected: selectedCondition,
        onSelected: (v) => selectedCondition = v ?? 'Any',
        labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
        textOnly: true,
      ),
      _searchNumericRangeCard(
        context: context,
        children: _moreFiltersSpecsEngineWidgets(
          context,
          setStateDialog,
          style,
          narrowMenu: true,
          includeSeating: false,
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
    ];
  }

  List<Widget> _searchAdvancedFilterSections(
    BuildContext context,
    StateSetter setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    final loc = AppLocalizations.of(context)!;

    return [
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
        title: AppLocalizations.of(context)!.labelPlateType,
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
        title: AppLocalizations.of(context)!.labelPlateCity,
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
        children: _moreFiltersSpecsEngineWidgets(
          context,
          setStateDialog,
          style,
          narrowMenu: true,
          includeCylinder: false,
          includeEngine: false,
        ),
      ),
    ];
  }

  Widget _searchAllFilterSections(
    BuildContext context,
    StateSetter setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    return KeyedSubtree(
      key: ValueKey<int>(_moreFiltersDialogFieldGeneration),
      child: Column(
        children: [
          ..._searchEssentialFilterSections(context, setStateDialog, style),
          ..._searchAdvancedFilterSections(context, setStateDialog, style),
        ],
      ),
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
      _searchAllFilterSections(
        context,
        setStateDialog,
        style,
      ),
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
    // Ensure brand→model map is populated (lazy asset load; not in bootstrap).
    unawaited(CarCatalogLoader.ensureLoaded());
    final applied = await Navigator.of(context).push<bool>(
      AppPageRoute<bool>(
        fullscreenDialog: true,
        builder: (pageContext) {
          var didRequestSearchFocus = false;
          var searchBrandsExpanded = false;
          var catalogLoadStarted = false;
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              void toggleSearchBrandsExpanded() {
                setStateDialog(() {
                  searchBrandsExpanded = !searchBrandsExpanded;
                });
              }

              if (!catalogLoadStarted) {
                catalogLoadStarted = true;
                unawaited(
                  CarCatalogLoader.ensureLoaded().then((_) {
                    if (!context.mounted) return;
                    setStateDialog(() {});
                  }),
                );
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
                                tooltip: AppLocalizations.of(context)!.close,
                                icon: const Icon(Icons.close),
                                color: titleColor,
                                onPressed: () => Navigator.pop(context),
                              ),
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(context)!.searchCars,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: titleColor,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: AppLocalizations.of(context)!.saveSearch,
                                icon: const Icon(Icons.bookmark_add_outlined),
                                color: _searchAccent,
                                onPressed: () => unawaited(
                                  _saveSearchFromFiltersPage(context),
                                ),
                              ),
                              IconButton(
                                tooltip: AppLocalizations.of(context)!.notifyMe,
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
                                  flex: 3,
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.resetButton,
                                        maxLines: 1,
                                        softWrap: false,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
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
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _searchShowCarsLabel(context),
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.visible,
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
