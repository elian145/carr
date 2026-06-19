import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/car_name_translations.dart';
import '../../l10n/app_localizations.dart';
import 'home_filter_labels.dart';

class HomeActiveFilterChipSpec {
  const HomeActiveFilterChipSpec({
    required this.label,
    required this.value,
    required this.filterType,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String filterType;
  final IconData icon;
  final Color color;
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Builds chip descriptors from persisted home filter map (`home_filters_v1`).
List<HomeActiveFilterChipSpec> homeActiveFilterChipSpecs(
  BuildContext context,
  Map<String, dynamic> map,
) {
  final loc = AppLocalizations.of(context)!;
  final chips = <HomeActiveFilterChipSpec>[];
  const accent = Color(0xFFFF6B00);

  void add(
    String label,
    String value,
    String filterType,
    IconData icon,
    Color color,
  ) {
    chips.add(
      HomeActiveFilterChipSpec(
        label: label,
        value: value,
        filterType: filterType,
        icon: icon,
        color: color,
      ),
    );
  }

  final brand = _str(map['brand']);
  if (homeFilterIsActiveValue(brand)) {
    final display = CarNameTranslations.getLocalizedBrand(context, brand);
    add(
      loc.brandLabel,
      display.isNotEmpty ? display : brand!,
      'brand',
      Icons.directions_car,
      accent,
    );
  }

  final model = _str(map['model']);
  if (homeFilterIsActiveValue(model)) {
    final display = CarNameTranslations.getLocalizedModel(context, brand, model);
    add(
      loc.modelLabel,
      display.isNotEmpty ? display : model!,
      'model',
      Icons.directions_car,
      accent,
    );
  }

  final trim = _str(map['trim']);
  if (homeFilterIsActiveValue(trim)) {
    add(loc.trimLabel, trim!, 'trim', Icons.settings, accent);
  }

  final minPrice = _str(map['price_min']);
  final maxPrice = _str(map['price_max']);
  if (minPrice != null || maxPrice != null) {
    String priceText;
    if (minPrice != null && maxPrice != null) {
      priceText =
          '${homeFilterFormatCurrency(context, minPrice)} - ${homeFilterFormatCurrency(context, maxPrice)}';
    } else if (minPrice != null) {
      priceText = '${loc.minPrice}: ${homeFilterFormatCurrency(context, minPrice)}';
    } else {
      priceText = '${loc.maxPrice}: ${homeFilterFormatCurrency(context, maxPrice!)}';
    }
    add(loc.priceLabel, priceText, 'price', Icons.attach_money, Colors.green);
  }

  final minYear = _str(map['year_min']);
  final maxYear = _str(map['year_max']);
  if (minYear != null || maxYear != null) {
    String yearText;
    if (minYear != null && maxYear != null) {
      yearText =
          '${homeFilterLocalizeDigits(context, minYear)} - ${homeFilterLocalizeDigits(context, maxYear)}';
    } else if (minYear != null) {
      yearText =
          '${loc.minYear}: ${homeFilterLocalizeDigits(context, minYear)}';
    } else {
      yearText =
          '${loc.maxYear}: ${homeFilterLocalizeDigits(context, maxYear!)}';
    }
    add(loc.yearLabel, yearText, 'year', Icons.calendar_today, Colors.blue);
  }

  final minMileage = _str(map['min_mileage']);
  final maxMileage = _str(map['max_mileage']);
  if (minMileage != null || maxMileage != null) {
    String mileageText;
    if (minMileage != null && maxMileage != null) {
      mileageText =
          '${homeFilterLocalizeDigits(context, minMileage)} - ${homeFilterLocalizeDigits(context, maxMileage)} ${loc.unit_km}';
    } else if (minMileage != null) {
      mileageText =
          '${loc.minMileage}: ${homeFilterLocalizeDigits(context, minMileage)} ${loc.unit_km}';
    } else {
      mileageText =
          '${loc.maxMileage}: ${homeFilterLocalizeDigits(context, maxMileage!)} ${loc.unit_km}';
    }
    add(loc.mileageLabel, mileageText, 'mileage', Icons.speed, Colors.orange);
  }

  final condition = _str(map['condition']);
  if (homeFilterIsActiveValue(condition)) {
    add(
      loc.detail_condition,
      homeFilterTranslateValue(context, condition) ?? condition!,
      'condition',
      Icons.check_circle,
      Colors.green,
    );
  }

  final transmission = _str(map['transmission']);
  if (homeFilterIsActiveValue(transmission)) {
    add(
      loc.transmissionLabel,
      homeFilterTranslateValue(context, transmission) ?? transmission!,
      'transmission',
      Icons.settings,
      Colors.purple,
    );
  }

  final fuelType = _str(map['fuel_type']);
  if (homeFilterIsActiveValue(fuelType)) {
    add(
      loc.detail_fuel,
      homeFilterTranslateValue(context, fuelType) ?? fuelType!,
      'fuelType',
      Icons.local_gas_station,
      Colors.orange,
    );
  }

  final titleStatus = _str(map['title_status']);
  final damagedParts = _str(map['damaged_parts']);
  if (titleStatus != null && titleStatus.isNotEmpty) {
    if (titleStatus == 'damaged' && damagedParts != null && damagedParts.isNotEmpty) {
      add(
        loc.titleStatus,
        loc.titleStatusDamagedWithParts(
          homeFilterLocalizeDigits(context, damagedParts),
        ),
        'titleStatus',
        Icons.report,
        Colors.redAccent,
      );
    } else {
      final display = homeFilterTranslateValue(context, titleStatus) ??
          (titleStatus.substring(0, 1).toUpperCase() + titleStatus.substring(1));
      add(
        loc.titleStatus,
        display,
        'titleStatus',
        Icons.verified,
        Colors.green,
      );
    }
  }

  final bodyType = _str(map['body_type']);
  if (homeFilterIsActiveValue(bodyType)) {
    add(
      loc.bodyTypeLabel,
      homeFilterTranslateValue(context, bodyType) ?? bodyType!,
      'bodyType',
      Icons.directions_car,
      accent,
    );
  }

  final color = _str(map['color']);
  if (homeFilterIsActiveValue(color)) {
    add(
      loc.colorLabel,
      homeFilterTranslateValue(context, color) ?? color!,
      'color',
      Icons.palette,
      accent,
    );
  }

  final driveType = _str(map['drive_type']);
  if (homeFilterIsActiveValue(driveType)) {
    add(
      loc.driveType,
      homeFilterTranslateValue(context, driveType) ?? driveType!,
      'driveType',
      Icons.directions_car,
      Colors.cyan,
    );
  }

  final regionSpecs = _str(map['region_specs'])?.toLowerCase();
  if (homeFilterRegionActive(regionSpecs)) {
    add(
      loc.regionSpecsLabel,
      homeFilterRegionSpecLabel(regionSpecs!),
      'regionSpecs',
      Icons.public,
      Colors.blueGrey,
    );
  }

  final cylinders = _str(map['cylinders']);
  if (homeFilterIsActiveValue(cylinders)) {
    add(
      loc.detail_cylinders,
      homeFilterLocalizeDigits(context, cylinders!),
      'cylinderCount',
      Icons.engineering,
      Colors.red,
    );
  }

  final seating = _str(map['seating']);
  if (homeFilterIsActiveValue(seating)) {
    add(
      loc.seating,
      homeFilterLocalizeDigits(context, seating!),
      'seating',
      Icons.airline_seat_recline_normal,
      Colors.indigo,
    );
  }

  final engineSize = _str(map['engine_size']);
  if (homeFilterIsActiveValue(engineSize)) {
    add(
      loc.engineSizeL,
      homeFilterEngineSizeChipLabel(context, engineSize!),
      'engineSize',
      Icons.engineering,
      Colors.deepOrange,
    );
  }

  final city = _str(map['city']);
  if (homeFilterIsActiveValue(city)) {
    add(
      loc.cityLabel,
      homeFilterTranslateValue(context, city) ?? city!,
      'city',
      Icons.location_city,
      Colors.teal,
    );
  }

  final plateType = _str(map['plate_type']);
  if (homeFilterIsActiveValue(plateType)) {
    add(
      'Plate type',
      homeFilterPlateTypeLabel(context, plateType!),
      'plateType',
      Icons.confirmation_number_outlined,
      accent,
    );
  }

  final plateCity = _str(map['plate_city']);
  if (homeFilterIsActiveValue(plateCity)) {
    add(
      'Plate city',
      homeFilterTranslateValue(context, plateCity) ?? plateCity!,
      'plateCity',
      Icons.location_on_outlined,
      accent,
    );
  }

  final sortBy = _str(map['sort_by']);
  if (sortBy != null &&
      sortBy.toLowerCase() != 'any' &&
      sortBy.toLowerCase() != 'default') {
    add(
      loc.sortBy,
      homeFilterTranslateValue(context, sortBy) ?? sortBy,
      'sortBy',
      Icons.sort,
      Colors.grey,
    );
  }

  return chips;
}

Widget buildHomeActiveFilterChip(
  HomeActiveFilterChipSpec spec, {
  required VoidCallback onClear,
}) {
  return GestureDetector(
    onTap: onClear,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: spec.color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: spec.color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, color: spec.color, size: 12),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              '${spec.label}: ${spec.value}',
              style: GoogleFonts.orbitron(
                fontSize: 10,
                color: spec.color,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.close, color: spec.color, size: 12),
        ],
      ),
    ),
  );
}

Widget buildHomeActiveFilterChipWrap(
  BuildContext context, {
  required List<HomeActiveFilterChipSpec> specs,
  required ValueChanged<String> onClearFilterType,
}) {
  if (specs.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final spec in specs)
          buildHomeActiveFilterChip(
            spec,
            onClear: () => onClearFilterType(spec.filterType),
          ),
      ],
    ),
  );
}
