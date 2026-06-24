part of 'car_listing_specs_grid.dart';

/// Specification grid matching [CarDetailsPage] (shared with sell-flow review).
Widget buildCarListingSpecsGrid(
  BuildContext context,
  Map<String, dynamic> car,
) {
  final List<dynamic> damagePreviewEntries = listingDamagePreviewEntries(car);
  String? pickNE(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      final String stringValue = value.toString().trim();
      if (stringValue.isNotEmpty) return stringValue;
    }
    return null;
  }

  String formatNumericLabel(String raw) {
    try {
      final num? value = num.tryParse(raw.replaceAll(RegExp(r'[^0-9\.-]'), ''));
      if (value == null) return raw;
      return decimalFormatterForLocale(context).format(value);
    } catch (e, st) { logNonFatal(e, st); 
      return raw;
    }
  }

  String orDash(String? s) {
    final v = (s ?? '').toString().trim();
    return v.isEmpty ? '—' : v;
  }

  final String mileageVal = car['mileage'] != null
      ? '${localizeDigits(context, formatNumericLabel(car['mileage'].toString()))} ${AppLocalizations.of(context)!.unit_km}'
      : '—';

  final String? transRaw = pickNE(car, ['transmission']);
  final String transmissionVal = orDash(
    translateListingValue(context, transRaw) ?? transRaw,
  );

  final String? engineSizePrimary = pickNE(car, [
    'engine_size',
    'engine_size_liters',
    'engine_size_l',
    'engineSize',
    'engineSizeLiters',
    'engine',
  ]) ??
      () {
        final dynamic specsRaw = car['specs'] ?? car['spec'] ?? car['details'];
        if (specsRaw is Map) {
          final specs = Map<String, dynamic>.from(specsRaw);
          return pickNE(specs, [
            'engine_size',
            'engine_size_liters',
            'engine_size_l',
            'engineSize',
            'engineSizeLiters',
            'engine',
          ]);
        }
        return null;
      }();
  final String engineCardVal = () {
    final raw = engineSizePrimary?.toString().trim() ?? '';
    if (raw.isEmpty) return '—';
    final eng = OnlineSpecVariant.parseLeadingEngineLiters(raw) ??
        double.tryParse(raw);
    if (eng != null && eng > 0) {
      return '${localizeDigits(context, eng.toStringAsFixed(1))}${AppLocalizations.of(context)!.unit_liter_suffix}';
    }
    return localizeDigits(context, raw);
  }();

  final String? cylRawPrimary = pickNE(car, [
    'cylinder_count',
    'cylinders',
    'cylinderCount',
  ]);
  final String cylinderVal = cylRawPrimary != null
      ? localizeDigits(context, cylRawPrimary)
      : '—';

  final String titleStatusVal = orDash(
    car['title_status'] != null
        ? (car['title_status'].toString().toLowerCase() == 'damaged'
              ? (car['damaged_parts'] != null
                    ? AppLocalizations.of(context)!.titleStatusDamagedWithParts(
                        localizeDigits(
                          context,
                          car['damaged_parts'].toString(),
                        ),
                      )
                    : AppLocalizations.of(context)!.value_title_damaged)
              : AppLocalizations.of(context)!.value_title_clean)
        : null,
  );

  final String? fuelRaw = pickNE(car, ['fuel_type', 'fuelType', 'fuel']);
  final String fuelVal = orDash(
    translateListingValue(context, fuelRaw) ?? fuelRaw,
  );

  final List<ListingSpecItem> primary = [
    ListingSpecItem(
      icon: Icons.speed,
      label: AppLocalizations.of(context)!.mileageLabel,
      value: mileageVal,
    ),
    ListingSpecItem(
      icon: Icons.settings_input_component,
      label: AppLocalizations.of(context)!.detail_cylinders,
      value: cylinderVal,
    ),
    ListingSpecItem(
      icon: Icons.straighten,
      label: AppLocalizations.of(context)!.detail_engine,
      value: engineCardVal,
    ),
    ListingSpecItem(
      icon: Icons.public,
      label: AppLocalizations.of(context)!.regionSpecsLabel,
      value: orDash(() {
        final raw = pickNE(car, ['region_specs', 'regionSpecs']) ?? '';
        final c = raw.toString().trim().toLowerCase();
        if (!isValidCarRegionSpecCode(c)) return '';
        return carRegionSpecDisplayLabel(c);
      }()),
    ),
    ListingSpecItem(
      icon: Icons.settings,
      label: AppLocalizations.of(context)!.transmissionLabel,
      value: transmissionVal,
    ),
    ListingSpecItem(
      icon: Icons.local_gas_station,
      label: AppLocalizations.of(context)!.detail_fuel,
      value: fuelVal,
    ),
  ];

  final List<Widget> details = [
    carListingSpecsDetailRow(context, 
      icon: Icons.layers,
      label: AppLocalizations.of(context)!.trimLabel,
      value: orDash(
        translateListingValue(context, pickNE(car, ['trim'])) ??
            pickNE(car, ['trim']),
      ),
    ),
    carListingSpecsDetailRow(context, 
      icon: Icons.check_circle,
      label: AppLocalizations.of(context)!.detail_condition,
      value: orDash(
        translateListingValue(context, pickNE(car, ['condition'])),
      ),
    ),
    carListingSpecsDetailRow(context, 
      icon: Icons.assignment_turned_in,
      label: AppLocalizations.of(context)!.titleStatus,
      value: titleStatusVal,
      onTap: damagePreviewEntries.isEmpty
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ListingPreviewMediaGridPage(
                    imageFilesOrUrls: List<dynamic>.from(damagePreviewEntries),
                    videoFilesOrUrls: const <dynamic>[],
                    initialIndex: 0,
                    appBarTitle: AppLocalizations.of(context)!.damageImagesTitle,
                  ),
                ),
              );
            },
    ),
    if ((car['vin'] ?? '').toString().trim().isNotEmpty)
      GestureDetector(
        onLongPress: () {
          final vin = car['vin'].toString().trim();
          services.Clipboard.setData(services.ClipboardData(text: vin));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                trLegacyText(context, 'VIN copied', ar: 'تم نسخ رقم الهيكل', ku: 'ژمارەی شاسی کۆپی کرا'),
              ),
            ),
          );
        },
        child: carListingSpecsDetailRow(context, 
          icon: Icons.pin_outlined,
          label: 'VIN',
          value: car['vin'].toString().trim(),
          onTap: () {
            final vin = car['vin'].toString().trim();
            openVinSearch(vin);
          },
        ),
      ),
    carListingSpecsDetailRow(context, 
      icon: Icons.drive_eta,
      label: AppLocalizations.of(context)!.detail_drive,
      value: orDash(
        translateListingValue(
          context,
          pickNE(car, ['drive_type', 'driveType', 'drivetrain', 'drive']),
        ),
      ),
    ),
    carListingSpecsDetailRow(context, 
      icon: Icons.directions_car_filled,
      label: AppLocalizations.of(context)!.detail_body,
      value: orDash(
        translateListingValue(
          context,
          pickNE(car, ['body_type', 'bodyType', 'body']),
        ),
      ),
    ),
    carListingSpecsDetailRow(context, 
      icon: Icons.color_lens,
      label: AppLocalizations.of(context)!.detail_color,
      value: orDash(translateListingValue(context, pickNE(car, ['color']))),
    ),
    carListingSpecsDetailRow(context, 
      icon: Icons.airline_seat_recline_normal,
      label: AppLocalizations.of(context)!.detail_seating,
      value: orDash(
        localizeDigits(
          context,
          pickNE(car, ['seating', 'seats', 'seatCount']) ?? '',
        ),
      ),
    ),
    carListingSpecsDetailRow(context, 
      icon: Icons.confirmation_number_outlined,
      label: trLegacyText(
        context,
        'Plate',
        ar: 'اللوحة',
        ku: 'پڵەیت',
      ),
      value: orDash(() {
        final rawCity = pickNE(car, ['plate_city', 'plateCity'])?.trim();
        final rawType = pickNE(car, ['plate_type', 'plateType'])?.trim();

        final String? city = (rawCity == null || rawCity.isEmpty)
            ? null
            : (translateListingValue(context, rawCity) ?? rawCity);
        final String? type = (rawType == null || rawType.isEmpty)
            ? null
            : translatePlateTypeLabel(context, rawType);

        if (city == null && type == null) return null;
        if (city != null && type != null) return '$city/$type';
        return city ?? type;
      }()),
    ),
  ];
  final description = pickNE(car, ['description'])?.trim() ?? '';
  if (description.isNotEmpty) {
    details.add(
      carListingSpecsDetailRow(context, 
        icon: Icons.description_outlined,
        label: AppLocalizations.of(context)?.descriptionTitle ?? 'Description',
        value: trLegacyText(
          context,
          'View description',
          ar: 'عرض الوصف',
          ku: 'پیشاندانی وەسف',
        ),
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                AppLocalizations.of(context)?.descriptionTitle ?? 'Description',
              ),
              content: SingleChildScrollView(child: Text(description)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    trLegacyText(
                      context,
                      'Close',
                      ar: 'إغلاق',
                      ku: 'داخستن',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  final isLightSpecs = Theme.of(context).brightness == Brightness.light;
  // Width-based row height: tighter than childAspectRatio 1.5 so the outer
  // shell does not grow vertically on narrow phones (GridView + padding).
  final primGrid = LayoutBuilder(
    builder: (context, constraints) {
      const double crossGap = 12;
      const int crossCount = 3;
      final double maxW = constraints.maxWidth;
      final double tileW = (maxW - crossGap * (crossCount - 1)) / crossCount;
      // Was ~1.5 (height = tileW/1.5); 1.72 shortens each row ~13%.
      final double rowH = tileW / 1.72;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          crossAxisSpacing: crossGap,
          mainAxisSpacing: 12,
          mainAxisExtent: rowH,
        ),
        itemCount: primary.length,
        itemBuilder: (context, index) => carListingSpecsCard(primary[index]),
      );
    },
  );

  final topSpecs = Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: isLightSpecs
          ? const Color(0xFFEEEEEE)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isLightSpecs ? const Color(0xFFE0E0E0) : Colors.white24,
      ),
    ),
    child: primGrid,
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [topSpecs, SizedBox(height: 12), ...details],
  );
}

