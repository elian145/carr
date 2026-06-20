import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../car/region_specs.dart';
import 'home_filter_fields.dart';
import 'home_filter_labels.dart';
import 'home_filter_options.dart';
import 'home_sort_api.dart';

/// Full-screen-style bottom sheet for secondary home filters.
Future<HomeFilterFields?> showHomeMoreFiltersSheet(
  BuildContext context, {
  required HomeFilterFields initial,
}) {
  return showModalBottomSheet<HomeFilterFields>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _HomeMoreFiltersSheet(initial: initial),
  );
}

class _HomeMoreFiltersSheet extends StatefulWidget {
  const _HomeMoreFiltersSheet({required this.initial});

  final HomeFilterFields initial;

  @override
  State<_HomeMoreFiltersSheet> createState() => _HomeMoreFiltersSheetState();
}

class _HomeMoreFiltersSheetState extends State<_HomeMoreFiltersSheet> {
  late HomeFilterFields _fields;
  late final TextEditingController _priceMin;
  late final TextEditingController _priceMax;
  late final TextEditingController _yearMin;
  late final TextEditingController _yearMax;
  late final TextEditingController _mileageMin;
  late final TextEditingController _mileageMax;
  late final TextEditingController _engineSize;
  late final TextEditingController _plateCity;
  late final TextEditingController _damagedParts;

  @override
  void initState() {
    super.initState();
    _fields = widget.initial;
    _priceMin = TextEditingController(text: _fields.priceMin ?? '');
    _priceMax = TextEditingController(text: _fields.priceMax ?? '');
    _yearMin = TextEditingController(text: _fields.yearMin ?? '');
    _yearMax = TextEditingController(text: _fields.yearMax ?? '');
    _mileageMin = TextEditingController(text: _fields.minMileage ?? '');
    _mileageMax = TextEditingController(text: _fields.maxMileage ?? '');
    _engineSize = TextEditingController(text: _fields.engineSize ?? '');
    _plateCity = TextEditingController(text: _fields.plateCity ?? '');
    _damagedParts = TextEditingController(text: _fields.damagedParts ?? '');
  }

  @override
  void dispose() {
    _priceMin.dispose();
    _priceMax.dispose();
    _yearMin.dispose();
    _yearMax.dispose();
    _mileageMin.dispose();
    _mileageMax.dispose();
    _engineSize.dispose();
    _plateCity.dispose();
    _damagedParts.dispose();
    super.dispose();
  }

  String? _textOrNull(TextEditingController c) {
    final s = c.text.trim();
    return s.isEmpty ? null : s;
  }

  HomeFilterFields _collect() {
    final title = _fields.titleStatus;
    return _fields.copyWith(
      priceMin: _textOrNull(_priceMin),
      priceMax: _textOrNull(_priceMax),
      yearMin: _textOrNull(_yearMin),
      yearMax: _textOrNull(_yearMax),
      minMileage: _textOrNull(_mileageMin),
      maxMileage: _textOrNull(_mileageMax),
      engineSize: _textOrNull(_engineSize),
      plateCity: _textOrNull(_plateCity),
      damagedParts: title == 'damaged' ? _textOrNull(_damagedParts) : null,
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final display = HomeFilterOptions.toDropdown(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$display'),
        initialValue: options.contains(display) ? display : HomeFilterOptions.any,
        decoration: InputDecoration(labelText: label),
        isExpanded: true,
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) => onChanged(HomeFilterOptions.fromDropdown(v)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final sortOptions = homeLocalizedSortOptions(context);
    final regionOptions = [
      HomeFilterOptions.any,
      ...kCarRegionSpecCodes.map(homeFilterRegionSpecLabel),
    ];
    final regionValue = _fields.regionSpecs == null
        ? HomeFilterOptions.any
        : homeFilterRegionSpecLabel(_fields.regionSpecs!);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Material(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        loc.moreFilters,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFFF6B00),
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    Text(loc.priceRange,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _priceMin,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: loc.minPrice),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _priceMax,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: loc.maxPrice),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(loc.yearLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _yearMin,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: loc.minYear),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _yearMax,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: loc.maxYear),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(loc.mileageLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _mileageMin,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: loc.minMileage),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _mileageMax,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: loc.maxMileage),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _dropdown(
                      label: loc.conditionLabel,
                      value: _fields.condition,
                      options: HomeFilterOptions.conditions,
                      onChanged: (v) =>
                          setState(() => _fields = _fields.copyWith(condition: v)),
                    ),
                    _dropdown(
                      label: loc.transmissionLabel,
                      value: _fields.transmission,
                      options: HomeFilterOptions.transmissions,
                      onChanged: (v) => setState(
                        () => _fields = _fields.copyWith(transmission: v),
                      ),
                    ),
                    _dropdown(
                      label: loc.fuelTypeLabel,
                      value: _fields.fuelType,
                      options: HomeFilterOptions.fuelTypes,
                      onChanged: (v) =>
                          setState(() => _fields = _fields.copyWith(fuelType: v)),
                    ),
                    _dropdown(
                      label: loc.bodyTypeLabel,
                      value: _fields.bodyType,
                      options: HomeFilterOptions.bodyTypes,
                      onChanged: (v) =>
                          setState(() => _fields = _fields.copyWith(bodyType: v)),
                    ),
                    _dropdown(
                      label: loc.colorLabel,
                      value: _fields.color,
                      options: HomeFilterOptions.colors,
                      onChanged: (v) =>
                          setState(() => _fields = _fields.copyWith(color: v)),
                    ),
                    _dropdown(
                      label: loc.driveType,
                      value: _fields.driveType,
                      options: HomeFilterOptions.driveTypes,
                      onChanged: (v) =>
                          setState(() => _fields = _fields.copyWith(driveType: v)),
                    ),
                    _dropdown(
                      label: loc.regionSpecsLabel,
                      value: regionValue,
                      options: regionOptions,
                      onChanged: (v) {
                        setState(() {
                          if (v == null || v == HomeFilterOptions.any) {
                            _fields = _fields.copyWith(regionSpecs: null);
                            return;
                          }
                          final code = kCarRegionSpecCodes.firstWhere(
                            (c) => homeFilterRegionSpecLabel(c) == v,
                            orElse: () => '',
                          );
                          _fields = _fields.copyWith(
                            regionSpecs:
                                code.isEmpty ? null : code.toLowerCase(),
                          );
                        });
                      },
                    ),
                    _dropdown(
                      label: loc.cylinderCount,
                      value: _fields.cylinders,
                      options: HomeFilterOptions.cylinderCounts(),
                      onChanged: (v) =>
                          setState(() => _fields = _fields.copyWith(cylinders: v)),
                    ),
                    _dropdown(
                      label: loc.seating,
                      value: _fields.seating,
                      options: HomeFilterOptions.seatings(),
                      onChanged: (v) =>
                          setState(() => _fields = _fields.copyWith(seating: v)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _engineSize,
                        decoration: InputDecoration(labelText: loc.engineSizeL),
                      ),
                    ),
                    _dropdown(
                      label: 'Plate type',
                      value: _fields.plateType,
                      options: HomeFilterOptions.plateTypes,
                      onChanged: (v) =>
                          setState(() => _fields = _fields.copyWith(plateType: v)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _plateCity,
                        decoration: const InputDecoration(labelText: 'Plate city'),
                      ),
                    ),
                    _dropdown(
                      label: loc.status,
                      value: _fields.titleStatus,
                      options: HomeFilterOptions.titleStatuses,
                      onChanged: (v) => setState(() {
                        _fields = _fields.copyWith(
                          titleStatus: v,
                          damagedParts: v == 'damaged' ? _fields.damagedParts : null,
                        );
                        if (v != 'damaged') _damagedParts.clear();
                      }),
                    ),
                    if (_fields.titleStatus == 'damaged')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: _damagedParts,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Damaged parts count'),
                        ),
                      ),
                    _dropdown(
                      label: loc.sortBy,
                      value: _fields.sortBy ?? loc.defaultSort,
                      options: sortOptions,
                      onChanged: (v) => setState(() {
                        _fields = _fields.copyWith(
                          sortBy: v == null || v == loc.defaultSort ? null : v,
                        );
                      }),
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(loc.cancelAction),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B00),
                          ),
                          onPressed: () => Navigator.pop(context, _collect()),
                          child: Text(loc.applyFilters),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
