part of 'main_legacy.dart';

class SavedSearchesPage extends StatefulWidget {
  final dynamic parentState;

  const SavedSearchesPage({super.key, this.parentState});

  @override
  State<SavedSearchesPage> createState() => _SavedSearchesPageState();
}

class _SavedSearchesPageState extends State<SavedSearchesPage> {
  static const String _savedSearchesKey = 'saved_searches_v1';
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final merged = await SavedSearchService.loadMerged();
    if (!mounted) return;
    setState(() {
      _items = merged;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await SavedSearchService.persistLocal(_items);
  }

  void _rename(int index) async {
    final controller = TextEditingController(
      text: _items[index]['name']?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _items[index]['name'] = controller.text.trim().isEmpty
            ? _items[index]['name']
            : controller.text.trim();
      });
      await _save();
      unawaited(SavedSearchService.pushItemToServer(_items[index]));
    }
  }

  void _delete(int index) async {
    final id = (_items[index]['id'] ?? '').toString();
    setState(() {
      _items.removeAt(index);
    });
    await _save();
    unawaited(SavedSearchService.deleteOnServer(id));
  }

  void _toggleNotify(int index, bool value) async {
    setState(() {
      _items[index]['notify'] = value;
    });
    await _save();
    unawaited(SavedSearchService.pushItemToServer(_items[index]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.savedSearchesTitle),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.noSavedSearchesYet,
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.savedSearchesHint,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _items[index];
                final filters = item['filters'] as Map<String, dynamic>? ?? {};
                final isAutoSaved = item['auto_saved'] == true;

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    onTap: () => _showFilterDetails(
                      item['name']?.toString() ??
                          AppLocalizations.of(context)!.unnamedSearch,
                      filters,
                    ),
                    leading: Icon(Icons.bookmark, color: Color(0xFFFF6B00)),
                    title: Text(
                      item['name']?.toString() ??
                          AppLocalizations.of(context)!.unnamedSearch,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 4),
                        _buildFilterChips(context, filters),
                        SizedBox(height: 4),
                        Text(
                          _formatDate(
                            context,
                            item['created_at']?.toString() ?? '',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            (item['notify'] == true)
                                ? Icons.notifications_active
                                : Icons.notifications_none,
                            color: const Color(0xFFFF6B00),
                          ),
                          onPressed: () => _toggleNotify(
                            index,
                            item['notify'] != true,
                          ),
                          tooltip: _trLegacyText(
                            context,
                            'Alerts',
                            ar: 'التنبيهات',
                            ku: 'ئاگادارکردنەوە',
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.search, color: Colors.green),
                          onPressed: () => _applySearch(filters),
                          tooltip: AppLocalizations.of(context)!.applySearch,
                        ),
                        IconButton(
                          icon: Icon(Icons.edit),
                          onPressed: () => _rename(index),
                          tooltip: AppLocalizations.of(context)!.renameTooltip,
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _delete(index),
                          tooltip: AppLocalizations.of(context)!.deleteTooltip,
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }

  Widget _buildFilterChips(BuildContext context, Map<String, dynamic> filters) {
    final chips = <Widget>[];
    final l = AppLocalizations.of(context)!;
    String tr(String? v) =>
        _translateValueGlobal(context, v?.toString()) ?? v ?? '';

    if (filters['brand'] != null) {
      chips.add(
        _buildFilterChip(context, l.brandLabel, filters['brand'].toString()),
      );
    }
    if (filters['model'] != null) {
      chips.add(
        _buildFilterChip(context, l.modelLabel, filters['model'].toString()),
      );
    }
    if (filters['trim'] != null) {
      chips.add(
        _buildFilterChip(context, l.trimLabel, filters['trim'].toString()),
      );
    }
    if (filters['city'] != null) {
      chips.add(
        _buildFilterChip(context, l.cityLabel, tr(filters['city'].toString())),
      );
    }
    if (filters['plate_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          _trLegacyText(context, 'Plate type', ar: 'نوع اللوحة', ku: 'جۆری پڵەیت'),
          _translatePlateTypeLegacy(context, filters['plate_type'].toString()),
        ),
      );
    }
    if (filters['plate_city'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          _trLegacyText(context, 'Plate city', ar: 'مدينة اللوحة', ku: 'شاری پڵەیت'),
          tr(filters['plate_city'].toString()),
        ),
      );
    }
    if (filters['min_price'] != null || filters['max_price'] != null) {
      final priceRange =
          '${filters['min_price'] ?? '0'} - ${filters['max_price'] ?? '∞'}';
      chips.add(_buildFilterChip(context, l.priceLabel, priceRange));
    }
    if (filters['min_year'] != null || filters['max_year'] != null) {
      final yearRange =
          '${filters['min_year'] ?? '0'} - ${filters['max_year'] ?? '∞'}';
      chips.add(_buildFilterChip(context, l.yearLabel, yearRange));
    }
    if (filters['min_mileage'] != null || filters['max_mileage'] != null) {
      final mileageRange =
          '${filters['min_mileage'] ?? '0'} - ${filters['max_mileage'] ?? '∞'} ${l.unit_km}';
      chips.add(_buildFilterChip(context, l.mileageLabel, mileageRange));
    }
    if (filters['transmission'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.transmissionLabel,
          tr(filters['transmission'].toString()),
        ),
      );
    }
    if (filters['condition'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.conditionLabel,
          tr(filters['condition'].toString()),
        ),
      );
    }
    if (filters['body_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.bodyTypeLabel,
          tr(filters['body_type'].toString()),
        ),
      );
    }
    if (filters['fuel_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.fuelTypeLabel,
          tr(filters['fuel_type'].toString()),
        ),
      );
    }
    if (filters['color'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.colorLabel,
          tr(filters['color'].toString()),
        ),
      );
    }
    if (filters['drive_type'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.driveType,
          tr(filters['drive_type'].toString()),
        ),
      );
    }
    if (filters['region_specs'] != null) {
      final code = filters['region_specs'].toString().trim().toLowerCase();
      chips.add(
        _buildFilterChip(
          context,
          l.regionSpecsLabel,
          carRegionSpecDisplayLabel(code),
        ),
      );
    }
    if (filters['cylinder_count'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.cylinderCount,
          filters['cylinder_count'].toString(),
        ),
      );
    }
    if (filters['seating'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.seating,
          '${filters['seating'].toString()}',
        ),
      );
    }
    if (filters['engine_size'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.engineSizeL,
          _engineSizeChipLabel(context, filters['engine_size'].toString()),
        ),
      );
    }
    if (filters['title_status'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.status,
          tr(filters['title_status'].toString()),
        ),
      );
    }
    if (filters['damaged_parts'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          'Damaged Parts',
          filters['damaged_parts'].toString(),
        ),
      );
    }
    if (filters['sort_by'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          l.sortBy,
          _capitalizeFirst(filters['sort_by'].toString()),
        ),
      );
    }
    if (filters['owners'] != null) {
      chips.add(
        _buildFilterChip(context, 'Owners', filters['owners'].toString()),
      );
    }
    if (filters['vin'] != null) {
      chips.add(_buildFilterChip(context, 'VIN', filters['vin'].toString()));
    }
    if (filters['accident_history'] != null) {
      chips.add(
        _buildFilterChip(
          context,
          'Accident History',
          _capitalizeFirst(filters['accident_history'].toString()),
        ),
      );
    }

    if (chips.isEmpty) {
      return Text(
        l.noFiltersApplied,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      );
    }
    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }

  Widget _buildFilterChip(BuildContext context, String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, color: Color(0xFFFF6B00)),
      ),
    );
  }

  String _formatDate(BuildContext context, String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);
      final l = AppLocalizations.of(context)!;
      final timeStr =
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

      if (difference.inDays == 0) {
        return '${l.today} $timeStr';
      } else if (difference.inDays == 1) {
        return '${l.yesterday} $timeStr';
      } else if (difference.inDays < 7) {
        return l.daysAgo(difference.inDays);
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateString;
    }
  }

  void _applySearch(Map<String, dynamic> filters) async {
    final normalized = SavedSearchService.normalizeFilters(filters);
    await persistSavedSearchFiltersForHome(normalized);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final successText = _trLegacyText(
      context,
      'Search applied successfully!',
      ar: 'تم تطبيق البحث بنجاح!',
      ku: 'گەڕان بە سەرکەوتوویی جێبەجێ کرا!',
    );

    final parent = widget.parentState;
    if (parent != null && parent.mounted) {
      Navigator.pop(context);
      parent.setState(() {
        parent.applyFiltersFromSavedSearch(normalized);
      });
      parent.fetchCars(bypassCache: true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(successText),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    Navigator.pop(context);
    if (!context.mounted) return;
    await _markPendingSavedSearchFetch();
    navigateMainShellTab(context, '/');
    messenger.showSnackBar(
      SnackBar(
        content: Text(successText),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showFilterDetails(String searchName, Map<String, dynamic> filters) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          searchName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.filter_list, color: Color(0xFFFF6B00), size: 20),
                  SizedBox(width: 8),
                  Text(
                    _trLegacyText(
                      context,
                      'Applied Filters:',
                      ar: 'الفلاتر المطبقة:',
                      ku: 'فلتەرە جێبەجێکراوەکان:',
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              _buildDetailedFilterList(filters),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[400]),
            child: Text(
              _trLegacyText(
                context,
                'Close',
                ar: 'إغلاق',
                ku: 'داخستن',
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _applySearch(filters);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF6B00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              _trLegacyText(
                context,
                'Apply Search',
                ar: 'تطبيق البحث',
                ku: 'جێبەجێکردنی گەڕان',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedFilterList(Map<String, dynamic> filters) {
    final List<Widget> filterItems = [];

    // Vehicle Information
    if (filters['brand'] != null) {
      filterItems.add(
        _buildFilterDetailItem('Brand', filters['brand'].toString()),
      );
    }
    if (filters['model'] != null) {
      filterItems.add(
        _buildFilterDetailItem('Model', filters['model'].toString()),
      );
    }
    if (filters['trim'] != null) {
      filterItems.add(
        _buildFilterDetailItem('Trim', filters['trim'].toString()),
      );
    }

    // Price Range
    if (filters['min_price'] != null || filters['max_price'] != null) {
      final minPrice = filters['min_price']?.toString() ?? 'Any';
      final maxPrice = filters['max_price']?.toString() ?? 'Any';
      filterItems.add(
        _buildFilterDetailItem('Price Range', '$minPrice - $maxPrice'),
      );
    }

    // Year Range
    if (filters['min_year'] != null || filters['max_year'] != null) {
      final minYear = filters['min_year']?.toString() ?? 'Any';
      final maxYear = filters['max_year']?.toString() ?? 'Any';
      filterItems.add(
        _buildFilterDetailItem('Year Range', '$minYear - $maxYear'),
      );
    }

    // Mileage Range
    if (filters['min_mileage'] != null || filters['max_mileage'] != null) {
      final minMileage = filters['min_mileage']?.toString() ?? 'Any';
      final maxMileage = filters['max_mileage']?.toString() ?? 'Any';
      filterItems.add(
        _buildFilterDetailItem('Mileage Range', '$minMileage - $maxMileage km'),
      );
    }

    // Vehicle Specifications
    if (filters['condition'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Condition',
          _capitalizeFirst(filters['condition'].toString()),
        ),
      );
    }
    if (filters['transmission'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Transmission',
          _capitalizeFirst(filters['transmission'].toString()),
        ),
      );
    }
    if (filters['fuel_type'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Fuel Type',
          _capitalizeFirst(filters['fuel_type'].toString()),
        ),
      );
    }
    if (filters['body_type'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Body Type',
          _capitalizeFirst(filters['body_type'].toString()),
        ),
      );
    }
    if (filters['color'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Color',
          _capitalizeFirst(filters['color'].toString()),
        ),
      );
    }
    if (filters['drive_type'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Drive Type',
          filters['drive_type'].toString().toUpperCase(),
        ),
      );
    }
    if (filters['region_specs'] != null) {
      final code = filters['region_specs'].toString().trim().toLowerCase();
      filterItems.add(
        _buildFilterDetailItem(
          AppLocalizations.of(context)!.regionSpecsLabel,
          carRegionSpecDisplayLabel(code),
        ),
      );
    }
    if (filters['cylinder_count'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Cylinder Count',
          filters['cylinder_count'].toString(),
        ),
      );
    }
    if (filters['seating'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Seating',
          '${filters['seating'].toString()} seats',
        ),
      );
    }
    if (filters['engine_size'] != null) {
      final es = filters['engine_size'].toString().trim();
      final plain = double.tryParse(es) != null;
      filterItems.add(
        _buildFilterDetailItem('Engine Size', plain ? '${es}L' : es),
      );
    }

    // Location and Other
    if (filters['city'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'City',
          _capitalizeFirst(filters['city'].toString()),
        ),
      );
    }
    if (filters['title_status'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Title Status',
          _capitalizeFirst(filters['title_status'].toString()),
        ),
      );
    }
    if (filters['damaged_parts'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Damaged Parts',
          filters['damaged_parts'].toString(),
        ),
      );
    }
    if (filters['sort_by'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Sort By',
          _capitalizeFirst(filters['sort_by'].toString()),
        ),
      );
    }
    if (filters['owners'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Number of Owners',
          filters['owners'].toString(),
        ),
      );
    }
    if (filters['vin'] != null) {
      filterItems.add(_buildFilterDetailItem('VIN', filters['vin'].toString()));
    }
    if (filters['accident_history'] != null) {
      filterItems.add(
        _buildFilterDetailItem(
          'Accident History',
          _capitalizeFirst(filters['accident_history'].toString()),
        ),
      );
    }

    if (filterItems.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Color(0xFF404040), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey[400], size: 20),
            SizedBox(width: 8),
            Text(
              'No filters applied to this search.',
              style: TextStyle(
                color: Colors.grey[400],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 6, children: filterItems);
  }

  Widget _buildFilterDetailItem(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(0xFF404040), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFFFF6B00),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}

// Library-wide helper to map body types to emojis for all pages
String _getBodyTypeAsset(String bodyType) {
  // First try dynamic map built from assets
  if (bodyType.toLowerCase() == 'any') {
    // No dedicated "default" asset; use a safe built-in icon.
    return 'assets/body_types_png/sedan.png';
  }

  // Try direct label match from dynamic map
  // We store labels in title case keys (e.g., 'Mini Truck'), so we normalize here
  String normalizeTitle(String s) {
    final words = s
        .replaceAll(RegExp(r'[_\\-]+'), ' ')
        .trim()
        .split(RegExp(r'\\s+'));
    return words
        .map((w) {
          if (w.isEmpty) return w;
          final lettersOnly = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
          // Preserve short acronyms like "ATV" / "UTV".
          if (lettersOnly.isNotEmpty && lettersOnly.length <= 3) {
            return w.toUpperCase();
          }
          return w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '');
        })
        .join(' ');
  }

  final String titleKey = normalizeTitle(bodyType);
  if (globalBodyTypeAssetMap.containsKey(titleKey)) {
    return globalBodyTypeAssetMap[titleKey]!;
  }

  // Fallback to known static mappings for common names
  final normalized = bodyType
      .toLowerCase()
      .replaceAll(RegExp(r'[_\\-]+'), ' ')
      .trim();

  switch (normalized) {
    case 'micro':
      return 'assets/body_types_png/micro.png';
    case 'cuv':
      return 'assets/body_types_png/cuv.png';
    case 'sedan':
      return 'assets/body_types_png/sedan.png';
    case 'suv':
      return 'assets/body_types_png/suv.png';
    case 'hatchback':
      return 'assets/body_types_png/hatchback.png';
    case 'coupe':
      return 'assets/body_types_png/coupe.png';
    case 'wagon':
    case 'station wagon':
    case 'estate':
      // No dedicated wagon asset; use hatchback as closest match.
      return 'assets/body_types_png/hatchback.png';
    case 'pickup':
      return 'assets/body_types_png/pickup.png';
    case 'roadster':
      return 'assets/body_types_png/roadster.png';
    case 'truck':
      return 'assets/body_types_png/truck.png';
    case 'minitruck':
    case 'mini truck':
      return 'assets/body_types_png/minitruck.png';
    case 'bigtruck':
    case 'big truck':
      return 'assets/body_types_png/bigtruck.png';
    case 'van':
      return 'assets/body_types_png/van.png';
    case 'minivan':
    case 'mini van':
    case 'mpv':
      // No dedicated minivan asset; use van icon.
      return 'assets/body_types_png/van.png';
    case 'supercar':
      return 'assets/body_types_png/supercar.png';
    case 'cabriolet':
    case 'convertible':
    case 'cabrio':
      return 'assets/body_types_png/cabriolet.png';
    case 'motorcycle':
      return 'assets/body_types_png/motorcycle.png';
    case 'utv':
      return 'assets/body_types_png/UTV.png';
    case 'atv':
      return 'assets/body_types_png/ATV.png';
    default:
      return 'assets/body_types_png/sedan.png';
  }
}


