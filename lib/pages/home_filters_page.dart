import 'dart:async';

import 'package:flutter/material.dart';

import '../data/car_catalog.dart';
import '../l10n/app_localizations.dart';
import '../shared/home/home_active_filter_chips.dart';
import '../shared/home/home_filter_fields.dart';
import '../shared/home/home_filter_options.dart';
import '../shared/home/home_filter_persistence.dart';
import '../shared/home/home_more_filters_sheet.dart';

/// Production home filter screen (`/home_filters`).
class HomeFiltersPage extends StatefulWidget {
  const HomeFiltersPage({super.key});

  @override
  State<HomeFiltersPage> createState() => _HomeFiltersPageState();
}

class _HomeFiltersPageState extends State<HomeFiltersPage> {
  HomeFilterFields _fields = const HomeFilterFields();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fields = await HomeFilterFields.load();
    if (!mounted) return;
    setState(() {
      _fields = fields;
      _loading = false;
    });
  }

  void _setFields(HomeFilterFields fields) {
    setState(() => _fields = fields);
  }

  Future<void> _clearChip(String filterType) async {
    final map = HomeFilterPersistence.clearFilterInMap(
      _fields.toPersistMap(),
      filterType,
    );
    _setFields(HomeFilterFields.fromPersistMap(map));
  }

  Future<void> _clearAll() async {
    _setFields(const HomeFilterFields());
  }

  Future<void> _apply() async {
    await _fields.save();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _openMoreFilters() async {
    final updated = await showHomeMoreFiltersSheet(context, initial: _fields);
    if (updated != null) {
      _setFields(updated);
    }
  }

  Future<String?> _pickBrand() async {
    final loc = AppLocalizations.of(context)!;
    var query = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final brands = CarCatalog.brands
                .where(
                  (b) =>
                      query.isEmpty ||
                      b.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
            return AlertDialog(
              title: Text(loc.brandLabel),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: loc.homeSearchHeading,
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (v) => setDialogState(() => query = v),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: brands.length,
                        itemBuilder: (context, index) {
                          final brand = brands[index];
                          return ListTile(
                            title: Text(brand),
                            onTap: () => Navigator.pop(ctx, brand),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (_fields.brand != null)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, ''),
                    child: Text(loc.clearFilters),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(loc.cancelAction),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _selectorTile({
    required String label,
    required String? value,
    required VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    final display = value == null || value.isEmpty
        ? AppLocalizations.of(context)!.anyOption
        : value;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(label, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          display,
          style: TextStyle(
            fontWeight: value != null ? FontWeight.w600 : FontWeight.normal,
            color: value != null ? const Color(0xFFFF6B00) : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onClear != null && value != null)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: onClear,
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    bool enabled = true,
  }) {
    final display = HomeFilterOptions.toDropdown(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$display'),
        initialValue: options.contains(display) ? display : HomeFilterOptions.any,
        decoration: InputDecoration(labelText: label),
        isExpanded: true,
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: enabled
            ? (v) => onChanged(HomeFilterOptions.fromDropdown(v))
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final chipSpecs = homeActiveFilterChipSpecs(context, _fields.toPersistMap());
    final models = _fields.brand == null
        ? const <String>[]
        : (CarCatalog.models[_fields.brand!] ?? const <String>[]);
    final trims = CarCatalog.trimsFor(_fields.brand, _fields.model);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _apply,
        ),
        title: Text(loc.moreFilters, style: const TextStyle(fontSize: 18)),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _clearAll,
                child: Text(
                  loc.clearFilters,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B00),
                  foregroundColor: Colors.white,
                ),
                onPressed: _apply,
                child: Text(
                  loc.applyFilters,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                buildHomeActiveFilterChipWrap(
                  context,
                  specs: chipSpecs,
                  onClearFilterType: (type) => unawaited(_clearChip(type)),
                ),
                if (chipSpecs.isNotEmpty) const SizedBox(height: 8),
                _selectorTile(
                  label: loc.brandLabel,
                  value: _fields.brand,
                  onTap: () async {
                    final picked = await _pickBrand();
                    if (!mounted || picked == null) return;
                    if (picked.isEmpty) {
                      _setFields(
                        _fields.copyWith(brand: null, model: null, trim: null),
                      );
                      return;
                    }
                    if (picked == _fields.brand) return;
                    _setFields(
                      _fields.copyWith(
                        brand: picked,
                        model: null,
                        trim: null,
                      ),
                    );
                  },
                  onClear: _fields.brand != null
                      ? () => _setFields(
                            _fields.copyWith(
                              brand: null,
                              model: null,
                              trim: null,
                            ),
                          )
                      : null,
                ),
                _dropdown(
                  label: loc.modelLabel,
                  value: _fields.model,
                  options: [
                    HomeFilterOptions.any,
                    ...models,
                  ],
                  enabled: _fields.brand != null,
                  onChanged: (v) => _setFields(
                    _fields.copyWith(model: v, trim: null),
                  ),
                ),
                _dropdown(
                  label: loc.trimLabel,
                  value: _fields.trim,
                  options: [
                    HomeFilterOptions.any,
                    ...trims,
                  ],
                  enabled: _fields.brand != null && _fields.model != null,
                  onChanged: (v) => _setFields(_fields.copyWith(trim: v)),
                ),
                _dropdown(
                  label: loc.cityLabel,
                  value: _fields.city,
                  options: HomeFilterOptions.cities,
                  onChanged: (v) => _setFields(_fields.copyWith(city: v)),
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _openMoreFilters,
                  icon: const Icon(Icons.tune),
                  label: Text(loc.moreFilters),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: Color(0xFFFF6B00)),
                    foregroundColor: const Color(0xFFFF6B00),
                  ),
                ),
              ],
            ),
    );
  }
}
