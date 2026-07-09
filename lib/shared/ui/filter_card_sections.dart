import 'package:flutter/material.dart';

import '../../features/home/more_filters_dialog_style.dart';
import '../../l10n/app_localizations.dart';
import 'filter_icon_image.dart';
import 'filter_option_icons.dart';
import 'responsive.dart';

const Color kFilterAccentColor = Color(0xFFFF6B00);

BoxDecoration filterCardDecoration(BuildContext context, {bool isError = false}) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return BoxDecoration(
    color: isLight ? const Color(0xFFF7F7F9) : Colors.white.withValues(alpha: 0.06),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: isError
          ? Colors.redAccent
          : (isLight ? const Color(0xFFE8E8ED) : Colors.white12),
      width: isError ? 2 : 1,
    ),
  );
}

class FilterCard extends StatelessWidget {
  const FilterCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.isError = false,
    this.margin = const EdgeInsets.only(bottom: 14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool isError;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: filterCardDecoration(context, isError: isError),
        child: child,
      ),
    );
  }
}

class FilterSectionHeader extends StatelessWidget {
  const FilterSectionHeader({
    super.key,
    required this.title,
    required this.valueSummary,
    this.onSummaryTap,
    this.requiredField = false,
  });

  final String title;
  final String valueSummary;
  final VoidCallback? onSummaryTap;
  final bool requiredField;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final titleColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final summaryColor = isLight ? const Color(0xFF8E8E93) : Colors.white70;
    final displayTitle = requiredField ? '$title *' : title;

    final summaryStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: summaryColor,
    );

    return Row(
      children: [
        Expanded(
          child: Text(
            displayTitle.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: titleColor,
            ),
          ),
        ),
        if (onSummaryTap != null)
          InkWell(
            onTap: onSummaryTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    valueSummary,
                    style: summaryStyle,
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: summaryColor,
                  ),
                ],
              ),
            ),
          )
        else
          Text(
            valueSummary,
            style: summaryStyle,
          ),
      ],
    );
  }
}

String filterOptionSummary(
  BuildContext context,
  String? selected, {
  String Function(BuildContext, String)? labelForOption,
  String? placeholder,
}) {
  final loc = AppLocalizations.of(context)!;
  if (selected == null || selected.isEmpty || selected == 'Any') {
    return placeholder ?? loc.tapToSelect;
  }
  return labelForOption?.call(context, selected) ?? selected;
}

InputDecoration filterFieldDecoration(
  MoreFiltersDialogStyle style,
  String label, {
  Widget? suffixIcon,
  String? errorText,
}) {
  return InputDecoration(
    labelText: label,
    isDense: true,
    errorText: errorText,
    labelStyle: TextStyle(
      color: style.onSurface,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
    floatingLabelStyle: TextStyle(
      color: style.onSurface,
      fontSize: 15,
      fontWeight: FontWeight.bold,
    ),
    filled: true,
    fillColor: style.fieldFill,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE0E0E5)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE0E0E5)),
    ),
  );
}

MoreFiltersDialogStyle filterDialogStyle(BuildContext context) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return MoreFiltersDialogStyle(
    onSurface: isLight ? const Color(0xFF1A1A1A) : Colors.white,
    muted: isLight ? const Color(0xFF8E8E93) : Colors.white70,
    anyOrange: kFilterAccentColor,
    fieldFill: isLight ? Colors.white : Colors.black.withValues(alpha: 0.2),
    fieldGap: 12,
  );
}

double _filterIconTileHeight({
  required bool textOnly,
  double? imageHeight,
  bool compactImageTile = false,
}) {
  if (textOnly) return 52;
  final slotHeight = imageHeight ?? 26;
  final verticalPadding = compactImageTile
      ? 16.0
      : (slotHeight > 80 ? 16.0 : 20.0);
  const gap = 6.0;
  const labelHeight = 28.0;
  const borderAllowance = 4.0;
  return verticalPadding + slotHeight + gap + labelHeight + borderAllowance;
}

double filterIconScrollListHeight({
  required bool textOnly,
  required List<String> options,
  double? tileImageHeight,
  String? Function(String option)? imageAssetForOption,
  Widget? Function(String option)? graphicForOption,
  bool compactImageTile = false,
}) {
  if (textOnly) return 52;
  var maxHeight = 0.0;
  for (final option in options) {
    final hasGraphic =
        graphicForOption != null || (imageAssetForOption?.call(option) != null);
    final height = _filterIconTileHeight(
      textOnly: false,
      imageHeight: hasGraphic ? tileImageHeight : null,
      compactImageTile: compactImageTile,
    );
    if (height > maxHeight) maxHeight = height;
  }
  return maxHeight + 4;
}

class FilterIconOptionTile extends StatelessWidget {
  const FilterIconOptionTile({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
    this.icon,
    this.imageAsset,
    this.customGraphic,
    this.width = 72,
    this.imageWidth,
    this.imageHeight,
    this.imageFit = BoxFit.contain,
    this.imageBorderRadius = 0,
    this.textOnly = false,
    this.compactImageTile = false,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? imageAsset;
  final Widget? customGraphic;
  final double? width;
  final double? imageWidth;
  final double? imageHeight;
  final BoxFit imageFit;
  final double imageBorderRadius;
  final bool textOnly;
  final bool compactImageTile;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final idleColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final Widget? graphic;
    if (textOnly) {
      graphic = null;
    } else if (customGraphic != null) {
      final slotWidth = imageWidth ?? 26;
      final slotHeight = imageHeight ?? 26;
      graphic = SizedBox(
        width: slotWidth,
        height: slotHeight,
        child: Center(child: customGraphic),
      );
    } else {
      final slotWidth = imageWidth ?? 26;
      final slotHeight = imageHeight ?? 26;
      final Widget slotChild;
      if (imageAsset != null) {
        slotChild = buildFilterIconImage(
          context: context,
          imageAsset: imageAsset!,
          width: slotWidth,
          height: slotHeight,
          fit: imageFit,
          borderRadius: imageBorderRadius,
        );
      } else {
        slotChild = Icon(
          icon ?? kFilterAnyOptionIcon,
          size: slotHeight * 0.85,
          color: selected ? kFilterAccentColor : idleColor,
        );
      }
      graphic = SizedBox(
        width: slotWidth,
        height: slotHeight,
        child: Center(child: slotChild),
      );
    }

    final tile = Material(
      clipBehavior: Clip.none,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: EdgeInsets.symmetric(
            vertical: textOnly
                ? 14
                : (compactImageTile
                    ? 8
                    : ((imageHeight ?? 0) > 80 ? 8 : 10)),
            horizontal: textOnly
                ? 12
                : (AppResponsive.isCompactPhone(context) ? 6 : 8),
          ),
          decoration: BoxDecoration(
            color: isLight
                ? Colors.white
                : filterIconTileBackdropColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kFilterAccentColor : const Color(0xFFE0E0E5),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (graphic != null) ...[
                Center(child: graphic),
                const SizedBox(height: 6),
              ],
              AppResponsive.fittedLabel(
                label,
                style: TextStyle(
                  fontSize: AppResponsive.filterIconLabelFontSize(
                    context,
                    textOnly: textOnly,
                  ),
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: selected ? kFilterAccentColor : idleColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (width == null) {
      return SizedBox(width: double.infinity, child: tile);
    }
    return SizedBox(width: width, child: tile);
  }
}

class FilterIconCardSection extends StatelessWidget {
  const FilterIconCardSection({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.labelForOption,
    this.iconForOption,
    this.imageAssetForOption,
    this.graphicForOption,
    this.scrollHorizontally = false,
    this.textOnly = false,
    this.includeAnyOption = false,
    this.tileWidth = 72,
    this.tileImageWidth,
    this.tileImageHeight,
    this.tileImageFit = BoxFit.contain,
    this.tileImageBorderRadius = 0,
    this.scrollListHeight,
    this.compactImageTile = false,
    this.isError = false,
    this.requiredField = false,
    this.placeholder,
    this.onClear,
  });

  final String title;
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final String Function(BuildContext, String)? labelForOption;
  final IconData Function(String option)? iconForOption;
  final String? Function(String option)? imageAssetForOption;
  final Widget? Function(String option)? graphicForOption;
  final bool scrollHorizontally;
  final bool textOnly;
  final bool includeAnyOption;
  final double tileWidth;
  final double? tileImageWidth;
  final double? tileImageHeight;
  final BoxFit tileImageFit;
  final double tileImageBorderRadius;
  final double? scrollListHeight;
  final bool compactImageTile;
  final bool isError;
  final bool requiredField;
  final String? placeholder;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final effectiveOptions = includeAnyOption
        ? (options.contains('Any') ? options : ['Any', ...options])
        : options.where((o) => o != 'Any').toList();

    final normalizedSelected =
        (selected == null || selected!.isEmpty || selected == 'Any')
            ? null
            : selected;

    final tiles = effectiveOptions.map((option) {
      final isAny = option == 'Any';
      final isSelected =
          isAny ? normalizedSelected == null : normalizedSelected == option;
      final label = isAny
          ? loc.any
          : (labelForOption?.call(context, option) ?? option);
      final customGraphic = isAny ? null : graphicForOption?.call(option);
      final usesImageAsset = !textOnly &&
          customGraphic == null &&
          imageAssetForOption != null;
      return FilterIconOptionTile(
        selected: isSelected,
        icon: isAny
            ? kFilterAnyOptionIcon
            : (textOnly
                ? null
                : (customGraphic != null
                    ? null
                    : (usesImageAsset &&
                            imageAssetForOption!.call(option) == null
                        ? iconForOption?.call(option)
                        : (usesImageAsset ? null : iconForOption?.call(option))))),
        imageAsset: isAny
            ? null
            : (textOnly || customGraphic != null
                ? null
                : imageAssetForOption?.call(option)),
        customGraphic: customGraphic,
        label: label,
        width: scrollHorizontally
            ? AppResponsive.filterIconTileWidth(context, tileWidth)
            : null,
        imageWidth: (usesImageAsset || customGraphic != null)
            ? tileImageWidth
            : null,
        imageHeight: (usesImageAsset || customGraphic != null)
            ? tileImageHeight
            : null,
        imageFit: tileImageFit,
        imageBorderRadius: tileImageBorderRadius,
        textOnly: textOnly,
        compactImageTile: compactImageTile,
        onTap: () => onSelected(isAny ? null : option),
      );
    }).toList();

    return FilterCard(
      isError: isError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterSectionHeader(
            title: title,
            requiredField: requiredField,
            valueSummary: filterOptionSummary(
              context,
              selected,
              labelForOption: labelForOption,
              placeholder: placeholder,
            ),
            onSummaryTap: onClear,
          ),
          const SizedBox(height: 12),
          if (scrollHorizontally)
            SizedBox(
              height: scrollListHeight ??
                  filterIconScrollListHeight(
                    textOnly: textOnly,
                    options: effectiveOptions,
                    tileImageHeight: tileImageHeight,
                    imageAssetForOption: imageAssetForOption,
                    graphicForOption: graphicForOption,
                    compactImageTile: compactImageTile,
                  ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tiles.length,
                separatorBuilder: (context, index) => const SizedBox(width: 6),
                itemBuilder: (context, index) => tiles[index],
              ),
            )
          else
            Row(
              children: tiles
                  .map(
                    (tile) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: tile,
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class FilterDropdownCardSection extends StatelessWidget {
  const FilterDropdownCardSection({
    super.key,
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
    this.isError = false,
    this.requiredField = false,
    this.valueSummary,
    this.onClear,
    this.style,
    this.hint,
  });

  final String title;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;
  final bool isError;
  final bool requiredField;
  final String? valueSummary;
  final VoidCallback? onClear;
  final MoreFiltersDialogStyle? style;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final fieldStyle = style ?? filterDialogStyle(context);
    final summary = valueSummary ??
        filterOptionSummary(context, value, placeholder: hint);

    return FilterCard(
      isError: isError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterSectionHeader(
            title: title,
            requiredField: requiredField,
            valueSummary: summary,
            onSummaryTap: onClear,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: value,
            decoration: filterFieldDecoration(fieldStyle, title),
            items: items,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
