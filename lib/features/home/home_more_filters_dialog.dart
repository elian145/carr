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
      anyOrange: const Color(0xFFFF6B00),
      fieldFill: isLightMoreFilters
          ? Colors.grey.shade200
          : Colors.black.withValues(alpha: 0.2),
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
      ..._moreFiltersMidWidgets(context, setStateDialog, style),
      ..._moreFiltersSpecsWidgets(context, setStateDialog, style),
    ];
  }

  List<Widget> _searchFiltersPageWidgets(
    BuildContext context,
    StateSetter setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    return [
      ..._moreFiltersVehicleWidgets(context, setStateDialog, style),
      ..._moreFiltersAdvancedWidgets(context, setStateDialog, style),
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

  Future<void> _resetSearchFiltersPage(
    VoidCallback refreshDialog,
  ) async {
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
    bool fullSearchPage = false,
    required void Function(Map<String, dynamic> snapshot) onCancel,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        textDirection: ui.TextDirection.ltr,
        children: [
          TextButton(
            onPressed: () async {
              if (fullSearchPage) {
                await _resetSearchFiltersPage(() => setStateDialog(() {}));
              } else {
                await _resetFiltersFromMoreFiltersDialog(
                  () => setStateDialog(() {}),
                );
              }
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
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B00),
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
                style: GoogleFonts.orbitron(
                  color: const Color(0xFFFF6B00),
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
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

  Future<void> _openHomeSearchFiltersPage(BuildContext context) async {
    _syncMoreFiltersControllers();
    final searchFiltersSnapshot = _searchFiltersPageSnapshot();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (pageContext) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              final style = _moreFiltersStyle(context);
              final isLightShell =
                  Theme.of(context).brightness == Brightness.light;
              return PopScope(
                canPop: true,
                onPopInvokedWithResult: (bool didPop, dynamic result) {
                  if (didPop) {
                    _cancelSearchFiltersPage(searchFiltersSnapshot);
                  }
                },
                child: Scaffold(
                  backgroundColor: isLightShell ? Colors.white : null,
                  appBar: AppBar(
                    title: Text(
                      AppLocalizations.of(context)!.homeSearchHeading,
                    ),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        _cancelSearchFiltersPage(searchFiltersSnapshot);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  body: Container(
                    decoration: isLightShell
                        ? null
                        : AppThemes.shellBackgroundDecoration(
                            Theme.of(context).brightness,
                          ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: KeyedSubtree(
                        key: ValueKey<int>(_moreFiltersDialogFieldGeneration),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _searchFiltersPageWidgets(
                            context,
                            setStateDialog,
                            style,
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottomNavigationBar: SafeArea(
                    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _moreFiltersActionBar(
                      context,
                      setStateDialog,
                      style,
                      searchFiltersSnapshot,
                      fullSearchPage: true,
                      onClose: () => Navigator.pop(context),
                      onCancel: _cancelSearchFiltersPage,
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
