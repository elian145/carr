import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../features/comparison/state/car_comparison_store.dart';
import '../l10n/app_localizations.dart';

class ComparisonPage extends StatelessWidget {
  const ComparisonPage({super.key});

  String _val(Map<String, dynamic> car, String key) {
    final v = car[key];
    if (v == null) return '';
    final s = v.toString().trim();
    return (s.toLowerCase() == 'null') ? '' : s;
  }

  /// Keep in sync with `carRegionSpecDisplayLabel` in legacy home/sell flow.
  String _regionSpecsDisplay(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'us':
        return 'US';
      case 'gcc':
        return 'GCC';
      case 'iraq':
        return 'Iraq';
      case 'canada':
        return 'Canada';
      case 'eu':
        return 'EU';
      case 'cn':
        return 'CN';
      case 'korea':
        return 'Korea';
      case 'ru':
        return 'RU';
      case 'iran':
        return 'Iran';
      default:
        return raw;
    }
  }

  String _displayCell(Map<String, dynamic> car, String key) {
    if (key == 'region_specs') {
      return _regionSpecsDisplay(_val(car, key));
    }
    return _val(car, key);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final store = context.watch<CarComparisonStore>();
    final cars = store.comparisonCars;

    if (cars.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(loc?.comparisonTitle ?? 'Comparison')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.compare_arrows, size: 72, color: Colors.black26),
                const SizedBox(height: 12),
                Text(loc?.noCarsSelected ?? 'No cars selected'),
                const SizedBox(height: 8),
                Text(
                  loc?.comparisonEmptyHint ?? 'Add cars to comparison from listings.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/'),
                  child: Text(loc?.navHome ?? 'Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final specs = <Map<String, String>>[
      {'label': 'Year', 'key': 'year'},
      {'label': 'Price', 'key': 'price'},
      {'label': 'Mileage', 'key': 'mileage'},
      {'label': 'Engine', 'key': 'engine_type'},
      {'label': 'Fuel', 'key': 'fuel_type'},
      {'label': 'Transmission', 'key': 'transmission'},
      {'label': 'Drive', 'key': 'drive_type'},
      {'label': loc?.regionSpecsLabel ?? 'Region specs', 'key': 'region_specs'},
      {'label': 'Condition', 'key': 'condition'},
      {'label': 'Body', 'key': 'body_type'},
      {'label': 'Location', 'key': 'location'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.comparisonTitle ?? 'Comparison'),
        actions: [
          IconButton(
            tooltip: loc?.shareAction ?? 'Share',
            onPressed: () {
              final text = cars
                  .map((c) {
                    final t = _val(c, 'title');
                    final year = _val(c, 'year');
                    final price = _val(c, 'price');
                    return [t, year, price].where((s) => s.isNotEmpty).join(' • ');
                  })
                  .where((s) => s.isNotEmpty)
                  .join('\n');
              if (text.trim().isNotEmpty) {
                Share.share(text);
              }
            },
            icon: const Icon(Icons.share_outlined),
          ),
          TextButton(
            onPressed: store.clearComparison,
            child: Text(loc?.clearFilters ?? 'Clear', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: DataTable(
            columns: [
              DataColumn(label: Text(loc?.comparisonSpecLabel ?? 'Spec')),
              ...cars.map((c) {
                final title = _val(c, 'title');
                final id = _val(c, 'id');
                return DataColumn(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(
                          title.isEmpty ? id : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: loc?.removeAction ?? 'Remove',
                        onPressed: () => store.removeCarFromComparison(id),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                );
              }),
            ],
            rows: specs.map((spec) {
              final label = spec['label']!;
              final key = spec['key']!;
              return DataRow(
                cells: [
                  DataCell(Text(label)),
                  ...cars.map((c) => DataCell(Text(_displayCell(c, key)))),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

