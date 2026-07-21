part of 'home_flow.dart';

mixin _HomePageSearchFiltersFields on _HomePageSearchFiltersIconSections {
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
}
