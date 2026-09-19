part of 'home_flow.dart';

/// Builds one filter-section widget on demand. Deferring construction to a
/// closure (instead of building the [Widget] eagerly) is what lets the
/// filters page's scroll body be consumed lazily via `ListView.builder` —
/// see `_searchFiltersPageScrollBody` below.
typedef _SearchFilterSectionBuilder =
    Widget Function(
      BuildContext context,
      StateSetter setStateDialog,
      MoreFiltersDialogStyle style,
    );

mixin _HomePageSearchFiltersPageUi on _HomePageSearchFiltersKeyword {
  List<_SearchFilterSectionBuilder> _searchEssentialFilterSectionBuilders() {
    return [
      (context, setStateDialog, style) => _searchNumericRangeCard(
        context: context,
        children: _moreFiltersPriceWidgets(
          context,
          setStateDialog,
          style,
        ),
      ),
      (context, setStateDialog, style) => _searchNumericRangeCard(
        context: context,
        children: _moreFiltersYearWidgets(
          context,
          setStateDialog,
          style,
        ),
      ),
      (context, setStateDialog, style) => _searchNumericRangeCard(
        context: context,
        children: _moreFiltersMileageRangeWidgets(
          context,
          setStateDialog,
          style,
        ),
      ),
      (context, setStateDialog, style) => _searchIconCardSection(
        context,
        setStateDialog,
        title: AppLocalizations.of(context)!.conditionLabel,
        options: const ['New', 'Used'],
        selected: selectedCondition,
        onSelected: (v) => selectedCondition = v ?? 'Any',
        labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
        textOnly: true,
      ),
      (context, setStateDialog, style) => _searchNumericRangeCard(
        context: context,
        children: _moreFiltersSpecsEngineWidgets(
          context,
          setStateDialog,
          style,
          narrowMenu: true,
          includeSeating: false,
        ),
      ),
      (context, setStateDialog, style) => _searchIconCardSection(
        context,
        setStateDialog,
        title: AppLocalizations.of(context)!.titleStatus,
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
        (context, setStateDialog, style) => _searchNumericRangeCard(
          context: context,
          children: [
            _searchDamagedPartsField(context, setStateDialog, style),
          ],
        ),
      (context, setStateDialog, style) => _searchMultiIconCardSection(
        context,
        setStateDialog,
        title: AppLocalizations.of(context)!.fuelTypeLabel,
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
      (context, setStateDialog, style) => _searchMultiIconCardSection(
        context,
        setStateDialog,
        title: AppLocalizations.of(context)!.bodyTypeLabel,
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
      (context, setStateDialog, style) => _searchIconCardSection(
        context,
        setStateDialog,
        title: AppLocalizations.of(context)!.transmissionLabel,
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

  List<_SearchFilterSectionBuilder> _searchAdvancedFilterSectionBuilders() {
    return [
      (context, setStateDialog, style) => _searchMultiIconCardSection(
        context,
        setStateDialog,
        title: AppLocalizations.of(context)!.driveType,
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
      (context, setStateDialog, style) => _searchNumericRangeCard(
        context: context,
        children: _moreFiltersColorWidgets(
          context,
          setStateDialog,
          style,
          narrowMenu: true,
        ),
      ),
      (context, setStateDialog, style) => _searchIconCardSection(
        context,
        setStateDialog,
        title: AppLocalizations.of(context)!.regionSpecsLabel,
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
      (context, setStateDialog, style) => _searchIconCardSection(
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
      (context, setStateDialog, style) => _searchIconCardSection(
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
      (context, setStateDialog, style) => _searchNumericRangeCard(
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

  /// Combined, ordered list of every filter-section builder (essential then
  /// advanced) — the exact same order previously produced by
  /// `_searchAllFilterSections`'s `Column`, just not built yet.
  List<_SearchFilterSectionBuilder> _searchAllFilterSectionBuilders() {
    return [
      ..._searchEssentialFilterSectionBuilders(),
      ..._searchAdvancedFilterSectionBuilders(),
    ];
  }

  /// One item per row of the filters page's `ListView.builder`: index 0 is
  /// the make/brand section, the rest are the essential+advanced filter
  /// sections in their original order. Each entry is only invoked (i.e.
  /// actually builds its widget subtree) when `ListView.builder` requests
  /// that index, so off-screen sections stay unbuilt until scrolled into
  /// view — this is what fixes the eager-build first-frame delay.
  List<Widget Function(BuildContext)> _searchFiltersPageScrollBody(
    BuildContext context,
    StateSetter setStateDialog, {
    required bool brandsExpanded,
    required VoidCallback onToggleBrandsExpanded,
  }) {
    final style = _searchMoreFiltersStyle(context);
    final sectionBuilders = _searchAllFilterSectionBuilders();

    return [
      (ctx) => _searchMakeSection(
        ctx,
        setStateDialog,
        brandsExpanded: brandsExpanded,
        onToggleBrandsExpanded: onToggleBrandsExpanded,
      ),
      for (var i = 0; i < sectionBuilders.length; i++)
        (ctx) => KeyedSubtree(
          // Same remount-on-reset trick as the previous single
          // `KeyedSubtree(key: ValueKey(_moreFiltersDialogFieldGeneration))`
          // wrapping the whole section Column: each individual section key
          // still changes together whenever the generation counter is
          // bumped (More Filters reset / cylinder / engine-size changes),
          // forcing dropdowns to remount and drop stale `initialValue`
          // state, just per-item instead of for the whole subtree at once.
          key: ValueKey(
            'filters_section_${i}_$_moreFiltersDialogFieldGeneration',
          ),
          child: sectionBuilders[i](ctx, setStateDialog, style),
        ),
    ];
  }

  Widget _buildListingSearchFiltersPage({
    required bool focusSearchField,
    required bool asRootRoute,
    List<Map<String, dynamic>>? revertSnapshot,
  }) {
    return StatefulBuilder(
      builder: (context, setStateDialog) {
        void toggleSearchBrandsExpanded() {
          setStateDialog(() {
            _searchFiltersBrandsExpanded = !_searchFiltersBrandsExpanded;
          });
        }

        if (!_searchFiltersCatalogLoadStarted) {
          _searchFiltersCatalogLoadStarted = true;
          unawaited(
            CarCatalogLoader.ensureLoaded().then((_) {
              if (!context.mounted) return;
              setStateDialog(() {});
            }),
          );
        }

        // RC smoke-test fix: the very first frame after `Navigator.push`
        // must be cheap so the route's push animation / first paint is
        // never delayed — but the filter-section list below (make/brand
        // logos, icon tiles, ...) is the one part of this page whose
        // *actual* on-device cost varies (image decode, first-use shader
        // work, etc.) instead of being a fixed, small amount of work.
        // Rendering a plain placeholder for exactly one frame, then
        // swapping in the real `ListView.builder` via a post-frame
        // callback, guarantees the page shell (title/close/keyword field/
        // footer — all already cheap) is what appears instantly, while
        // that variable-cost content is deferred to the frame right after,
        // once the route is already visually on screen. No filters,
        // localization, persistence, or keyword-search behavior changes —
        // only when the section list's widgets first get built.
        if (!_searchFiltersShellReady) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            setStateDialog(() => _searchFiltersShellReady = true);
          });
        }

        if (focusSearchField && !_searchFiltersDidRequestFocus) {
          _searchFiltersDidRequestFocus = true;
          _focusSearchFiltersKeywordField();
        }
        final isLightShell = Theme.of(context).brightness == Brightness.light;
        final titleColor =
            isLightShell ? const Color(0xFF1A1A1A) : Colors.white;
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (bool didPop, dynamic result) {
            if (asRootRoute || revertSnapshot == null) return;
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
                    child: Builder(
                      builder: (context) {
                        // Deferred by exactly one frame — see the
                        // `_searchFiltersShellReady` comment above — so the
                        // route's first frame never has to pay for this
                        // section list's build cost.
                        if (!_searchFiltersShellReady) {
                          return const SizedBox.shrink();
                        }
                        // Rebuilt list of *unbuilt* section closures — cheap
                        // (just closure references), unlike the sections
                        // themselves, which `ListView.builder` below only
                        // invokes for items it actually needs to lay out.
                        final sectionItems = _searchFiltersPageScrollBody(
                          context,
                          setStateDialog,
                          brandsExpanded: _searchFiltersBrandsExpanded,
                          onToggleBrandsExpanded: toggleSearchBrandsExpanded,
                        );
                        return Container(
                          decoration: isLightShell
                              ? null
                              : AppThemes.shellBackgroundDecoration(
                                  Theme.of(context).brightness,
                                ),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: sectionItems.length,
                            itemBuilder: (context, index) =>
                                sectionItems[index](context),
                          ),
                        );
                      },
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
                                if (revertSnapshot != null) {
                                  revertSnapshot[0] =
                                      _searchFiltersPageSnapshot();
                                }
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
                                  AppLocalizations.of(context)!.resetButton,
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
                                if (asRootRoute) {
                                  Navigator.pop(
                                    context,
                                    _homeFiltersSnapshot(),
                                  );
                                  return;
                                }
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
  }

  Future<void> _openHomeSearchFiltersPage(
    BuildContext context, {
    bool focusSearchField = true,
  }) async {
    _searchFiltersKeywordController.clear();
    _searchFiltersKeywordFocusNode.unfocus();
    _searchFiltersDidRequestFocus = false;
    _searchFiltersBrandsExpanded = false;
    _searchFiltersCatalogLoadStarted = false;
    _searchFiltersShellReady = false;
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
          return _buildListingSearchFiltersPage(
            focusSearchField: focusSearchField,
            asRootRoute: false,
            revertSnapshot: revertSnapshot,
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
