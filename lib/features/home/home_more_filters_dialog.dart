part of 'home_flow.dart';

mixin _HomePageMoreFiltersDialog on _HomePageMoreFiltersSpecs {
  Future<void> _showMoreFiltersDialog(BuildContext context) async {
    // Sync manual-entry controllers to current selections
    // (do this once when opening the dialog, not during typing).
    _minPriceController.text = selectedMinPrice ?? '';
    _maxPriceController.text = selectedMaxPrice ?? '';
    _minYearController.text = selectedMinYear ?? '';
    _maxYearController.text = selectedMaxYear ?? '';
    _minMileageController.text = selectedMinMileage ?? '';
    _maxMileageController.text = selectedMaxMileage ?? '';
    _engineSizeController.text = selectedEngineSize ?? '';
    final moreFiltersSnapshot = _moreFiltersDialogSnapshot();
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final isLightMoreFilters =
                Theme.of(context).brightness == Brightness.light;
            final moreFiltersBg = isLightMoreFilters
                ? Colors.white
                : (Colors.grey[900]?.withValues(alpha: 0.98) ??
                      Colors.grey.shade900);
            final style = MoreFiltersDialogStyle(
              onSurface: isLightMoreFilters
                  ? const Color(0xFF1A1A1A)
                  : Colors.white,
              muted: isLightMoreFilters
                  ? const Color(0xFF757575)
                  : Colors.white70,
              anyOrange: const Color(0xFFFF6B00),
              fieldFill: isLightMoreFilters
                  ? Colors.grey.shade200
                  : Colors.black.withValues(alpha: 0.2),
            );
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
                    children: [
                      ..._moreFiltersPriceWidgets(context, setStateDialog, style),
                      ..._moreFiltersYearWidgets(context, setStateDialog, style),
                      ..._moreFiltersMidWidgets(context, setStateDialog, style),
                      ..._moreFiltersSpecsWidgets(context, setStateDialog, style),
                    ],
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: Row(
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
                          _restoreMoreFiltersDialogSnapshot(moreFiltersSnapshot);
                          unawaited(_persistFilters());
                          Navigator.pop(context);
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
                            Navigator.pop(context);
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
                ),
              ],
            );
          },
        );
      },
    );
  }
}
