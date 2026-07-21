import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/home/more_filters_dialog_style.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import 'filter_icon_image.dart';
import 'filter_option_icons.dart';
import 'responsive.dart';

/// Brand accent for filter / sell tiles (alias of [AppColors.brandOrange]).
const Color kFilterAccentColor = AppColors.brandOrange;

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

/// Tall open-menu height used by search-page filter dropdowns.
double filterDropdownMenuMaxHeight(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  // Tall enough that short ladders (e.g. cylinder counts through 16) fit
  // without leaving 12/16 below the fold on typical phones.
  return (height * 0.72).clamp(360.0, 640.0);
}

double filterDropdownMenuWidth(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return (width * 0.48).clamp(160.0, 240.0);
}

/// Closed-field decoration matching search-page filter dropdowns.
InputDecoration filterDropdownFieldDecoration(
  MoreFiltersDialogStyle style,
  String label, {
  String? errorText,
}) {
  final labelStyle = TextStyle(
    color: style.onSurface,
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );
  return InputDecoration(
    labelText: label,
    errorText: errorText,
    labelStyle: labelStyle,
    floatingLabelStyle: labelStyle,
    filled: true,
    fillColor: style.fieldFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: errorText != null ? Colors.redAccent : const Color(0xFFE0E0E5),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: errorText != null ? Colors.redAccent : kFilterAccentColor,
        width: 1.5,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
  );
}

/// Dense dropdown field sized like the search-page filter dropdowns.
/// Opens a left-anchored menu (Material DropdownButton cannot reliably do this).
class FilterDropdownField extends StatelessWidget {
  const FilterDropdownField({
    super.key,
    required this.style,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.errorText,
    this.hint,
    this.narrowMenu = true,
  });

  final MoreFiltersDialogStyle style;
  final String label;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;
  final String? errorText;
  final Widget? hint;
  final bool narrowMenu;

  String? get _effectiveValue {
    final hasEmptyItem = items.any((item) => item.value == '');
    final raw = value ?? '';
    if (raw.isEmpty) return hasEmptyItem ? '' : null;
    return items.any((item) => item.value == raw) ? raw : null;
  }

  Widget? _selectedChild() {
    final current = _effectiveValue;
    if (current == null) return hint;
    for (final item in items) {
      if (item.value == current) return item.child;
    }
    return hint;
  }

  Future<void> _openMenu(BuildContext context) async {
    if (onChanged == null || items.isEmpty) return;

    final fieldBox = context.findRenderObject() as RenderBox?;
    if (fieldBox == null || !fieldBox.hasSize) return;

    final media = MediaQuery.sizeOf(context);
    final fieldTopLeft = fieldBox.localToGlobal(Offset.zero);
    final fieldSize = fieldBox.size;
    final padding = MediaQuery.paddingOf(context);

    final menuWidth = narrowMenu
        ? filterDropdownMenuWidth(context)
        : fieldSize.width;
    final left = fieldTopLeft.dx
        .clamp(0.0, math.max(0.0, media.width - menuWidth))
        .toDouble();

    final menuItems = [
      for (final item in items)
        if (item.value != null) item,
    ];
    if (menuItems.isEmpty) return;

    // showDialog treats a raw '' result awkwardly; map Any through a sentinel.
    const anySentinel = '__filter_dropdown_any__';
    const itemHeight = 48.0;
    const listPaddingV = 6.0;

    final selectedIndex = math.max(
      0,
      menuItems.indexWhere(
        (item) => item.value == (_effectiveValue ?? ''),
      ),
    );

    final preferredMaxHeight = filterDropdownMenuMaxHeight(context);
    final availableHeight =
        media.height - padding.top - padding.bottom - 24;
    final contentHeight =
        listPaddingV * 2 + menuItems.length * itemHeight;
    // Cap at the preferred fraction so long lists scroll instead of spanning
    // nearly the full screen.
    final cappedAvailable = math.max(120.0, availableHeight);
    final menuMaxHeight = math.min(preferredMaxHeight, cappedAvailable);
    final menuHeight = math.min(contentHeight, menuMaxHeight);

    // Overlap the field: keep the selected row aligned with the control
    // (Material-style), not hanging from the bottom edge.
    final fieldCenterY = fieldTopLeft.dy + fieldSize.height / 2;
    final selectedCenterInMenu =
        listPaddingV + selectedIndex * itemHeight + itemHeight / 2;
    final minTop = padding.top + 8;
    final maxTop = media.height - padding.bottom - menuHeight - 8;
    var menuTop = fieldCenterY - selectedCenterInMenu;
    menuTop = menuTop.clamp(minTop, maxTop);

    // If the list is taller than the menu, scroll so the selected row stays
    // near the field.
    final maxScroll = math.max(0.0, contentHeight - menuHeight);
    final idealScroll = (selectedCenterInMenu - menuHeight / 2)
        .clamp(0.0, maxScroll)
        .toDouble();

    final scrollController = ScrollController(
      initialScrollOffset: idealScroll,
    );
    try {
      final selected = await showDialog<String>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.01),
        // Global field coords include the status bar; SafeArea would shift the
        // Stack and mis-anchor the menu.
        useSafeArea: false,
        builder: (dialogContext) {
          final isLight =
              Theme.of(dialogContext).brightness == Brightness.light;
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(dialogContext),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: left,
                top: menuTop,
                width: menuWidth,
                height: menuHeight,
                child: Material(
                  color: style.menuFill,
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: ScrollbarTheme(
                    data: ScrollbarThemeData(
                      thumbVisibility: const WidgetStatePropertyAll(true),
                      trackVisibility: const WidgetStatePropertyAll(true),
                      thickness: const WidgetStatePropertyAll(5),
                      radius: const Radius.circular(8),
                      thumbColor: WidgetStatePropertyAll(
                        isLight
                            ? const Color(0xFFB0B0B5)
                            : Colors.white.withValues(alpha: 0.45),
                      ),
                      trackColor: WidgetStatePropertyAll(
                        isLight
                            ? const Color(0xFFE8E8ED)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Scrollbar(
                      controller: scrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: ListView.builder(
                        controller: scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: listPaddingV),
                        itemExtent: itemHeight,
                        itemCount: menuItems.length,
                        itemBuilder: (context, index) {
                          final item = menuItems[index];
                          final rawValue = item.value!;
                          final isSelected =
                              rawValue == (_effectiveValue ?? '');
                          return InkWell(
                            onTap: () => Navigator.pop(
                              dialogContext,
                              rawValue.isEmpty ? anySentinel : rawValue,
                            ),
                            child: Container(
                              height: itemHeight,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              color: isSelected
                                  ? kFilterAccentColor.withValues(alpha: 0.1)
                                  : null,
                              alignment: Alignment.centerLeft,
                              child: DefaultTextStyle(
                                style: TextStyle(
                                  color: style.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                child: item.child,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (selected != null) {
        onChanged?.call(selected == anySentinel ? '' : selected);
      }
    } finally {
      scrollController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedChild = _selectedChild();
    final enabled = onChanged != null;

    return InputDecorator(
      decoration: filterDropdownFieldDecoration(
        style,
        label,
        errorText: errorText,
      ),
      // Keep label floated so closed height matches search dropdowns.
      isEmpty: false,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? () => _openMenu(context) : null,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: style.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: selectedChild ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: style.onSurface.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

MoreFiltersDialogStyle filterDialogStyle(BuildContext context) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return MoreFiltersDialogStyle(
    onSurface: isLight ? const Color(0xFF1A1A1A) : Colors.white,
    muted: isLight ? const Color(0xFF8E8E93) : Colors.white70,
    anyOrange: kFilterAccentColor,
    fieldFill: isLight ? Colors.white : Colors.black.withValues(alpha: 0.2),
    menuFill: isLight ? Colors.white : const Color(0xFF2A2A2E),
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
  const labelHeight = 15.0;
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

    final hPad = textOnly
        ? 12.0
        : (AppResponsive.isCompactPhone(context) ? 4.0 : 6.0);
    final vPad = textOnly
        ? 14.0
        : (compactImageTile
            ? 8.0
            : ((imageHeight ?? 0) > 80 ? 8.0 : 10.0));
    final tile = Material(
      color: isLight ? Colors.white : filterIconTileBackdropColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? kFilterAccentColor : const Color(0xFFE0E0E5),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
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
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppResponsive.filterIconLabelFontSize(
                    context,
                    textOnly: textOnly,
                  ),
                  height: 1.1,
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
          FilterDropdownField(
            style: fieldStyle,
            label: title,
            value: value,
            items: items,
            onChanged: onChanged,
            hint: hint == null
                ? null
                : Text(
                    hint!,
                    style: TextStyle(
                      color: fieldStyle.anyOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
