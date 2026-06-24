part of 'comparison_page.dart';

extension _CarComparisonPageRows on CarComparisonPage {
  List<Widget> _buildComparisonRows(
    BuildContext context,
    List<Map<String, dynamic>> cars,
    double columnWidth,
    double labelWidth,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final lightInk = AppThemes.darkHomeShellBackground;
    final lightInkMuted = lightInk.withValues(alpha: 0.72);
    final sections = [
      {
        'title': AppLocalizations.of(context)!.brandLabel,
        'icon': Icons.info_outline,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.brandLabel,
            'key': 'brand',
            'icon': Icons.directions_car,
          },
          {
            'label': AppLocalizations.of(context)!.modelLabel,
            'key': 'model',
            'icon': Icons.badge_outlined,
          },
          {
            'label': AppLocalizations.of(context)!.trimLabel,
            'key': 'trim',
            'icon': Icons.layers,
          },
          {
            'label': AppLocalizations.of(context)!.yearLabel,
            'key': 'year',
            'icon': Icons.calendar_today,
          },
          {
            'label': AppLocalizations.of(context)!.cityLabel,
            'key': 'city',
            'icon': Icons.location_city,
          },
          {
            'label': AppLocalizations.of(context)!.priceLabel,
            'key': 'price',
            'icon': Icons.attach_money,
          },
        ],
      },
      {
        'title': AppLocalizations.of(context)!.specificationsLabel,
        'icon': Icons.speed,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.mileageLabel,
            'key': 'mileage',
            'suffix': ' ${AppLocalizations.of(context)!.unit_km}',
            'icon': Icons.speed,
          },
          {
            'label': AppLocalizations.of(context)!.engineSizeL,
            'key': 'engine_size',
            'suffix': AppLocalizations.of(context)!.unit_liter_suffix,
            'icon': Icons.settings,
          },
          {
            'label': AppLocalizations.of(context)!.detail_cylinders,
            'key': 'cylinder_count',
            'suffix': '',
            'icon': Icons.precision_manufacturing,
          },
          {
            'label': AppLocalizations.of(context)!.seating,
            'key': 'seating',
            'suffix': '',
            'icon': Icons.event_seat,
          },
        ],
      },
      {
        'title': AppLocalizations.of(context)!.moreFilters,
        'icon': Icons.tune,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.detail_condition,
            'key': 'condition',
            'icon': Icons.verified,
          },
          {
            'label': AppLocalizations.of(context)!.transmissionLabel,
            'key': 'transmission',
            'icon': Icons.settings_suggest,
          },
          {
            'label': AppLocalizations.of(context)!.detail_fuel,
            'key': 'fuel_type',
            'icon': Icons.local_gas_station,
          },
          {
            'label': AppLocalizations.of(context)!.detail_body,
            'key': 'body_type',
            'icon': Icons.directions_car_filled,
          },
          {
            'label': AppLocalizations.of(context)!.driveType,
            'key': 'drive_type',
            'icon': Icons.all_inclusive,
          },
          {
            'label': AppLocalizations.of(context)!.regionSpecsLabel,
            'key': 'region_specs',
            'icon': Icons.public,
          },
          {
            'label': AppLocalizations.of(context)!.detail_color,
            'key': 'color',
            'icon': Icons.color_lens,
          },
        ],
      },
      {
        'title': AppLocalizations.of(context)!.status,
        'icon': Icons.assignment_turned_in,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.titleStatus,
            'key': 'title_status',
            'icon': Icons.assignment,
          },
          {
            'label': AppLocalizations.of(context)!.damagedParts,
            'key': 'damaged_parts',
            'suffix': '',
            'icon': Icons.build,
          },
          {
            'label': AppLocalizations.of(context)!.quickSell,
            'key': 'is_quick_sell',
            'isBoolean': true,
            'icon': Icons.flash_on,
          },
        ],
      },
    ];

    final List<Widget> out = [];
    for (int s = 0; s < sections.length; s++) {
      final section = sections[s] as Map<String, dynamic>;
      out.add(
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: EdgeInsets.only(top: s == 0 ? 0 : 16),
          decoration: BoxDecoration(
            // Keep the orange accent in light mode, but soften it.
            color: Color(0xFFFF6B00).withValues(alpha: isDark ? 0.12 : 0.10),
            borderRadius: BorderRadius.circular(12),
            border: isDark ? null : Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              if (section['icon'] is IconData)
                Icon(
                  section['icon'] as IconData,
                  color: Color(0xFFFF6B00),
                  size: 18,
                )
              else
                Icon(Icons.toc, color: Color(0xFFFF6B00), size: 18),
              SizedBox(width: 8),
              Text(
                section['title'].toString(),
                style: TextStyle(
                  color: isDark ? Colors.white : lightInk,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );

      final List rows = section['rows'] as List;
      for (int i = 0; i < rows.length; i++) {
        final property = Map<String, dynamic>.from(rows[i] as Map);
        final bool isOdd = i % 2 == 1;
        out.add(
          Container(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: isOdd
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.02)
                      : Colors.black.withValues(alpha: 0.02))
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white12 : cs.outlineVariant,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: cars.length == 2
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (cars.length == 2) ...[
                  SizedBox(
                    width: columnWidth,
                    child: _buildCellValue(context, cars[0], property),
                  ),
                  SizedBox(
                    width: labelWidth,
                    child: Center(
                      child: Builder(
                        builder: (context) {
                          final bool isDamagedParts =
                              (property['key']?.toString() ?? '') ==
                              'damaged_parts';
                          final double gap = isDamagedParts ? 2 : 4;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                (rows[i]['icon'] is IconData)
                                    ? (rows[i]['icon'] as IconData)
                                    : Icons.label_outline,
                                color: isDark ? Colors.white54 : lightInkMuted,
                                size: 16,
                              ),
                              SizedBox(width: gap),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: (labelWidth - 16 - gap).clamp(
                                    48.0,
                                    labelWidth,
                                  ),
                                ),
                                child: AutoSizeText(
                                  property['label']!.toString(),
                                  textScaleFactor: 1.0,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : lightInkMuted,
                                    height: 1.15,
                                  ),
                                  textAlign: isDamagedParts
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  maxLines: 2,
                                  minFontSize: 8,
                                  stepGranularity: 0.5,
                                  overflow: TextOverflow.clip,
                                  softWrap: true,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: columnWidth,
                    child: _buildCellValue(context, cars[1], property),
                  ),
                ] else ...[
                  SizedBox(
                    width: labelWidth,
                    child: Center(
                      child: Builder(
                        builder: (context) {
                          final bool isDamagedParts =
                              (property['key']?.toString() ?? '') ==
                              'damaged_parts';
                          final double gap = isDamagedParts ? 2 : 4;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                (rows[i]['icon'] is IconData)
                                    ? (rows[i]['icon'] as IconData)
                                    : Icons.label_outline,
                                color: isDark ? Colors.white54 : lightInkMuted,
                                size: 16,
                              ),
                              SizedBox(width: gap),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: (labelWidth - 16 - gap).clamp(
                                    48.0,
                                    labelWidth,
                                  ),
                                ),
                                child: AutoSizeText(
                                  property['label']!.toString(),
                                  textScaleFactor: 1.0,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : lightInkMuted,
                                    height: 1.15,
                                  ),
                                  textAlign: isDamagedParts
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  maxLines: 2,
                                  minFontSize: 8,
                                  stepGranularity: 0.5,
                                  overflow: TextOverflow.clip,
                                  softWrap: true,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: cars
                          .map(
                            (car) => SizedBox(
                              width: columnWidth,
                              child: _buildCellValue(context, car, property),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }
    }
    return out;
  }

  Widget _buildCellValue(
    BuildContext context,
    Map<String, dynamic> car,
    Map<String, dynamic> property,
  ) {
    final text = _formatPropertyValue(context, car, property);
    final isBool =
        property['isBoolean'] == true || property['isBoolean'] == 'true';
    if (isBool) {
      final boolVal = text.toLowerCase() == 'yes';
      return Align(
        alignment: Alignment.center,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: boolVal
                ? Colors.green.withValues(alpha: 0.18)
                : Colors.red.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: boolVal
                  ? Colors.greenAccent.withValues(alpha: 0.3)
                  : Colors.redAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            boolVal ? yesText(context) : noText(context),
            style: TextStyle(
              color: boolVal ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        color: isDark ? Colors.white : AppThemes.darkHomeShellBackground,
        fontWeight: FontWeight.w600,
      ),
      textAlign: TextAlign.center,
    );
  }

  String _formatPropertyValue(
    BuildContext context,
    Map<String, dynamic> car,
    Map<String, dynamic> property,
  ) {
    final key = property['key']!;
    final value = car[key];

    if (value == null) return '-';
    if (key == 'price') {
      return formatCurrency(context, value);
    }
    if (key == 'region_specs') {
      final c = value.toString().trim().toLowerCase();
      if (!isValidCarRegionSpecCode(c)) return '-';
      return carRegionSpecDisplayLabel(c);
    }

    if (property['isBoolean'] == true || property['isBoolean'] == 'true') {
      return value == true || value == 'true'
          ? yesText(context)
          : noText(context);
    }

    final suffix = property['suffix'] ?? '';
    final String raw = value.toString();
    // Translate known categorical fields
    const translatableKeys = {
      'condition',
      'transmission',
      'fuel_type',
      'body_type',
      'drive_type',
      'color',
      'city',
      'title_status',
    };
    if (translatableKeys.contains(key)) {
      final translated = translateListingValue(context, raw) ?? raw;
      return translated + (suffix?.toString() ?? '');
    }
    // Localize digits for numeric-like strings
    return localizeDigits(context, raw + (suffix?.toString() ?? ''));
  }
}
