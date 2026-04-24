import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../features/comparison/state/car_comparison_store.dart';
import '../l10n/app_localizations.dart';
import '../theme_provider.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lightModeInk = AppThemes.darkHomeShellBackground;
    final lightModeBackground = AppThemes.lightAppBackground;

    if (cars.isEmpty) {
      return Scaffold(
        backgroundColor: isDark ? null : lightModeBackground,
        appBar: AppBar(title: Text(loc?.comparisonTitle ?? 'Comparison')),
        body: Center(
          child: DefaultTextStyle.merge(
            style: TextStyle(color: isDark ? null : lightModeInk),
            child: IconTheme.merge(
              data: IconThemeData(color: isDark ? null : lightModeInk),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.compare_arrows,
                      size: 72,
                      color: isDark ? null : lightModeInk.withOpacity(0.25),
                    ),
                    const SizedBox(height: 12),
                    Text(loc?.noCarsSelected ?? 'No cars selected'),
                    const SizedBox(height: 8),
                    Text(
                      loc?.comparisonEmptyHint ??
                          'Add cars to comparison from listings.',
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

    const double specColW = 140;
    const double carColW = 180;

    return Scaffold(
      backgroundColor: isDark ? null : lightModeBackground,
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
      body: DefaultTextStyle.merge(
        style: TextStyle(color: isDark ? null : lightModeInk),
        child: IconTheme.merge(
          data: IconThemeData(color: isDark ? null : lightModeInk),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: DataTable(
                headingRowHeight: 76,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 120,
                columnSpacing: 18,
                headingTextStyle: TextStyle(
                  color: isDark ? null : lightModeInk,
                  fontWeight: FontWeight.w700,
                ),
                dataTextStyle: TextStyle(color: isDark ? null : lightModeInk),
                columns: [
                  DataColumn(
                    label: SizedBox(
                      width: specColW,
                      child: AutoSizeText(
                        loc?.comparisonSpecLabel ?? 'Spec',
                        maxLines: 2,
                        minFontSize: 10,
                        stepGranularity: 0.5,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
                  ...cars.map((c) {
                    final title = _val(c, 'title');
                    final id = _val(c, 'id');
                    return DataColumn(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: carColW,
                            child: AutoSizeText(
                              title.isEmpty ? id : title,
                              maxLines: 3,
                              minFontSize: 9,
                              stepGranularity: 0.5,
                              overflow: TextOverflow.clip,
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
                      DataCell(
                        SizedBox(
                          width: specColW,
                          child: AutoSizeText(
                            label,
                            maxLines: 2,
                            minFontSize: 10,
                            stepGranularity: 0.5,
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ),
                      ...cars.map(
                        (c) => DataCell(
                          SizedBox(
                            width: carColW,
                            child: AutoSizeText(
                              _displayCell(c, key),
                              maxLines: 3,
                              minFontSize: 10,
                              stepGranularity: 0.5,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

