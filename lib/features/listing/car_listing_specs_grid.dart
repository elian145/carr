import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'package:image_picker/image_picker.dart';

import '../../pages/listing_image_gallery_page.dart'
    show ListingPreviewMediaGridPage;
import '../../features/listing/listing_spec_item.dart';
import '../../l10n/app_localizations.dart';
import '../../models/online_spec_variant.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import '../../shared/i18n/listing_field_labels.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/i18n/region_spec_labels.dart';
import '../../shared/media/media_url.dart';
import '../../shared/vin/open_vin_search.dart';
/// Full URLs for listing images tagged `kind: damage` (shared by detail + specs grid).
List<String> listingDamageImageFullUrls(Map<String, dynamic> car) {
  final List<String> urls = [];
  final List<dynamic> imgs =
      (car['images'] is List) ? (car['images'] as List) : const [];
  for (final dynamic it in imgs) {
    if (it is! Map) continue;
    if ((it['kind'] ?? '').toString().toLowerCase() != 'damage') continue;
    final s =
        (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '').toString();
    if (s.isNotEmpty) {
      final full = buildLegacyFullImageUrl(s);
      if (!urls.contains(full)) urls.add(full);
    }
  }
  return urls;
}

/// Damage photos for preview / review: API `images` with `kind: damage`, else
/// sell-flow `damage_images` (XFile or path strings) before submit.
List<dynamic> listingDamagePreviewEntries(Map<String, dynamic> car) {
  final List<dynamic> out = [];
  for (final url in listingDamageImageFullUrls(car)) {
    if (url.trim().isNotEmpty) out.add(url);
  }
  if (out.isNotEmpty) return out;
  final raw = car['damage_images'];
  if (raw is! List) return out;
  for (final e in raw) {
    if (e is XFile) {
      if (e.path.trim().isNotEmpty) out.add(e);
    } else {
      final s = e?.toString().trim() ?? '';
      if (s.isNotEmpty) out.add(e);
    }
  }
  return out;
}

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

  Widget detailRowSpec({
    required IconData icon,
    required String label,
    required String? value,
    Widget? valueWidget,
    VoidCallback? onTap,
  }) {
    if (valueWidget == null && (value == null || value.isEmpty)) {
      return SizedBox.shrink();
    }
    final isLight = Theme.of(context).brightness == Brightness.light;
    final content = Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: onTap != null
            ? (isLight ? const Color(0xFFFFF2E8) : Colors.white.withValues(alpha: 0.09))
            : (isLight ? const Color(0xFFF3F3F3) : Colors.white.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: onTap != null
              ? const Color(0xFFFF6B00).withValues(alpha: isLight ? 0.34 : 0.42)
              : (isLight ? const Color(0xFFE0E0E0) : Colors.white12),
          width: onTap != null ? 1.2 : 1,
        ),
        boxShadow: onTap != null
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: onTap != null
                  ? const Color(0xFFFF6B00)
                  : const Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.black),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isLight ? const Color(0xFF3A3A3A) : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (valueWidget != null)
            valueWidget
          else if (onTap != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    value!,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Color(0xFFFF6B00)),
              ],
            )
          else
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Color(0xFFFF6B00),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                value!,
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }

  Widget specCard(ListingSpecItem item) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double labelFontSize =
              (constraints.maxWidth * 0.13).clamp(9.0, 11.0);
          final double valueFontSize =
              (constraints.maxWidth * 0.16).clamp(10.0, 14.0);

          final labelStyle = TextStyle(
            fontSize: labelFontSize,
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            height: 1.05,
          );
          final valueStyle = TextStyle(
            fontSize: valueFontSize,
            height: 1.0,
            color: Colors.black,
            fontWeight: FontWeight.w800,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 6,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: constraints.maxWidth * 0.13,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              constraints.maxWidth - (constraints.maxWidth * 0.13) - 4,
                        ),
                        child: AutoSizeText(
                          item.label,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          softWrap: false,
                          textScaleFactor: 1.0,
                          style: labelStyle,
                          minFontSize: 7,
                          stepGranularity: 0.5,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  vertical: math.max(3.0, constraints.maxHeight * 0.02),
                  horizontal: 6,
                ),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.black.withValues(alpha: 0.22),
                ),
              ),
              Expanded(
                flex: 5,
                child: Center(
                  child: AutoSizeText(
                    item.value!,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    textScaleFactor: 1.0,
                    style: valueStyle,
                    minFontSize: 9,
                    stepGranularity: 0.5,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
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
    detailRowSpec(
      icon: Icons.layers,
      label: AppLocalizations.of(context)!.trimLabel,
      value: orDash(
        translateListingValue(context, pickNE(car, ['trim'])) ??
            pickNE(car, ['trim']),
      ),
    ),
    detailRowSpec(
      icon: Icons.check_circle,
      label: AppLocalizations.of(context)!.detail_condition,
      value: orDash(
        translateListingValue(context, pickNE(car, ['condition'])),
      ),
    ),
    detailRowSpec(
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
        child: detailRowSpec(
          icon: Icons.pin_outlined,
          label: 'VIN',
          value: car['vin'].toString().trim(),
          onTap: () {
            final vin = car['vin'].toString().trim();
            openVinSearch(vin);
          },
        ),
      ),
    detailRowSpec(
      icon: Icons.drive_eta,
      label: AppLocalizations.of(context)!.detail_drive,
      value: orDash(
        translateListingValue(
          context,
          pickNE(car, ['drive_type', 'driveType', 'drivetrain', 'drive']),
        ),
      ),
    ),
    detailRowSpec(
      icon: Icons.directions_car_filled,
      label: AppLocalizations.of(context)!.detail_body,
      value: orDash(
        translateListingValue(
          context,
          pickNE(car, ['body_type', 'bodyType', 'body']),
        ),
      ),
    ),
    detailRowSpec(
      icon: Icons.color_lens,
      label: AppLocalizations.of(context)!.detail_color,
      value: orDash(translateListingValue(context, pickNE(car, ['color']))),
    ),
    detailRowSpec(
      icon: Icons.airline_seat_recline_normal,
      label: AppLocalizations.of(context)!.detail_seating,
      value: orDash(
        localizeDigits(
          context,
          pickNE(car, ['seating', 'seats', 'seatCount']) ?? '',
        ),
      ),
    ),
    detailRowSpec(
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
      detailRowSpec(
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
        itemBuilder: (context, index) => specCard(primary[index]),
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

