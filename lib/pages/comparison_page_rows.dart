part of 'comparison_page.dart';

extension _CarComparisonPageRows on CarComparisonPage {
  List<Widget> _buildComparisonRows(
    BuildContext context,
    List<Map<String, dynamic>> cars,
  ) {
    final sections = [
      {
        'title': AppLocalizations.of(context)!.brandLabel,
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
        Padding(
          padding: EdgeInsets.only(top: s == 0 ? 0 : 20, bottom: 12),
          child: Text(
            section['title'].toString(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFF6B00),
            ),
          ),
        ),
      );

      final List rows = section['rows'] as List;
      for (final row in rows) {
        final property = Map<String, dynamic>.from(row as Map);
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: _comparisonRowDecoration(context),
              child: cars.length == 2
                  ? _buildTwoCarComparisonRow(context, cars, property)
                  : _buildMultiCarComparisonRow(context, cars, property),
            ),
          ),
        );
      }
    }
    return out;
  }

  Widget _buildTwoCarComparisonRow(
    BuildContext context,
    List<Map<String, dynamic>> cars,
    Map<String, dynamic> property,
  ) {
    final icon = property['icon'] is IconData
        ? property['icon'] as IconData
        : Icons.label_outline;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: _buildCellValue(context, cars[0], property),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildComparisonLabel(
              context,
              icon: icon,
              label: property['label']!.toString(),
              compact: true,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: _buildCellValue(context, cars[1], property),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiCarComparisonRow(
    BuildContext context,
    List<Map<String, dynamic>> cars,
    Map<String, dynamic> property,
  ) {
    final icon = property['icon'] is IconData
        ? property['icon'] as IconData
        : Icons.label_outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildComparisonLabel(
          context,
          icon: icon,
          label: property['label']!.toString(),
          compact: true,
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < cars.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _buildCellValue(context, cars[i], property),
                ),
              ),
            ],
          ],
        ),
      ],
    );
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
      final boolVal = text.toLowerCase() == yesText(context).toLowerCase();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: boolVal
              ? Colors.green.withValues(alpha: 0.18)
              : Colors.red.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: boolVal
                ? Colors.green.withValues(alpha: 0.45)
                : Colors.red.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          boolVal ? yesText(context) : noText(context),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: boolVal ? Colors.green.shade700 : Colors.red.shade700,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      );
    }

    if (text == '-') {
      return Text(
        '—',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return _buildComparisonValueChip(context, text);
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
    return localizeDigits(context, raw + (suffix?.toString() ?? ''));
  }
}
