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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            displayTitle.toUpperCase(),
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: titleColor,
              height: 1.25,
            ),
          ),
        ),
        if (valueSummary.trim().isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: onSummaryTap != null
                  ? InkWell(
                      onTap: onSummaryTap,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              valueSummary,
                              style: summaryStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: summaryColor,
                          ),
                        ],
                      ),
                    )
                  : Text(
                      valueSummary,
                      style: summaryStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
            ),
          ),
        ],
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
  bool compactLabel = true,
  bool hideLabel = false,
}) {
  if (suffixIcon == null && !hideLabel) {
    return filterDropdownFieldDecoration(
      style,
      label,
      errorText: errorText,
      compactLabel: compactLabel,
    );
  }

  final labelFontSize = compactLabel ? 15.0 : 20.0;
  final labelStyle = TextStyle(
    color: style.onSurface,
    fontSize: labelFontSize,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );
  return InputDecoration(
    isDense: true,
    labelText: hideLabel ? null : label,
    errorText: errorText,
    labelStyle: labelStyle,
    floatingLabelStyle: hideLabel
        ? null
        : labelStyle.copyWith(fontSize: labelFontSize),
    floatingLabelBehavior:
        hideLabel ? FloatingLabelBehavior.never : FloatingLabelBehavior.always,
    alignLabelWithHint: !hideLabel,
    filled: true,
    fillColor: style.fieldFill,
    suffixIcon: suffixIcon,
    contentPadding: EdgeInsets.fromLTRB(
      12,
      hideLabel ? 10 : (compactLabel ? 15 : 20),
      12,
      hideLabel ? 10 : (compactLabel ? 9 : 14),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: errorText != null ? Colors.redAccent : const Color(0xFFE0E0E5),
      ),
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

/// Orange placeholder style for closed filter dropdowns (RTL-safe metrics).
TextStyle filterDropdownHintStyle(
  MoreFiltersDialogStyle style, {
  double fontSize = 18,
}) {
  return TextStyle(
    color: style.anyOrange,
    fontWeight: FontWeight.w600,
    fontSize: fontSize,
    height: 1.35,
    leadingDistribution: TextLeadingDistribution.even,
  );
}

/// Closed-field decoration matching search-page filter dropdowns.
InputDecoration filterDropdownFieldDecoration(
  MoreFiltersDialogStyle style,
  String label, {
  String? errorText,
  /// Smaller in-field label for narrow manual min/max text inputs.
  bool compactLabel = false,
  /// When a [FilterSectionHeader] already shows [label], omit the field label.
  bool hideLabel = false,
}) {
  final labelFontSize = compactLabel ? 15.0 : 20.0;
  final floatingFontSize = compactLabel ? 15.0 : 20.0;
  final labelStyle = TextStyle(
    color: style.onSurface,
    fontSize: labelFontSize,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );
  return InputDecoration(
    isDense: true,
    labelText: hideLabel ? null : label,
    errorText: errorText,
    labelStyle: labelStyle,
    floatingLabelStyle: hideLabel
        ? null
        : labelStyle.copyWith(fontSize: floatingFontSize),
    floatingLabelBehavior:
        hideLabel ? FloatingLabelBehavior.never : FloatingLabelBehavior.always,
    alignLabelWithHint: !hideLabel,
    filled: true,
    fillColor: style.fieldFill,
    contentPadding: EdgeInsets.fromLTRB(
      12,
      hideLabel ? 10 : (compactLabel ? 15 : 20),
      12,
      hideLabel ? 10 : (compactLabel ? 9 : 14),
    ),
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
    this.hideLabel = false,
  });

  final MoreFiltersDialogStyle style;
  final String label;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;
  final String? errorText;
  final Widget? hint;
  final bool narrowMenu;
  /// When true, the section header already shows [label] — omit the field label.
  final bool hideLabel;

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
                              alignment: AlignmentDirectional.centerStart,
                              child: DefaultTextStyle(
                                style: TextStyle(
                                  color: style.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
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
    final fieldFontSize = narrowMenu ? 16.0 : 18.0;

    return InputDecorator(
      decoration: filterDropdownFieldDecoration(
        style,
        label,
        errorText: errorText,
        compactLabel: narrowMenu,
        hideLabel: hideLabel,
      ),
      isEmpty: false,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? () => _openMenu(context) : null,
          borderRadius: BorderRadius.circular(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: DefaultTextStyle(
                  style: TextStyle(
                    color: style.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: fieldFontSize,
                    height: narrowMenu ? 1.15 : 1.35,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: selectedChild ?? const SizedBox.shrink(),
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: narrowMenu ? 20 : 24,
                color: style.onSurface.withValues(alpha: 0.7),
              ),
            ],
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
    fieldGap: 0,
  );
}

double _filterIconTileVerticalPad({
  required bool textOnly,
  double? imageHeight,
  bool compactImageTile = false,
}) {
  if (textOnly) return 14.0;
  final slot = imageHeight ?? 26;
  if (compactImageTile) {
    if (slot <= 24) return 4.0;
    if (slot <= 40) return 6.0;
    return 8.0;
  }
  if (slot > 80) return 8.0;
  return 10.0;
}

double _filterIconTileGap({
  required bool textOnly,
  double? imageHeight,
  bool compactImageTile = false,
}) {
  if (textOnly) return 0;
  final slot = imageHeight ?? 26;
  if (compactImageTile && slot <= 40) return 4.0;
  return 6.0;
}

double _filterIconTileHeight({
  required bool textOnly,
  double? imageHeight,
  bool compactImageTile = false,
}) {
  if (textOnly) return 52;
  final slotHeight = imageHeight ?? 26;
  final verticalPadding = _filterIconTileVerticalPad(
        textOnly: textOnly,
        imageHeight: imageHeight,
        compactImageTile: compactImageTile,
      ) *
      2;
  final gap = _filterIconTileGap(
    textOnly: textOnly,
    imageHeight: imageHeight,
    compactImageTile: compactImageTile,
  );
  const labelHeight = 14.0;
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
    final asset = imageAssetForOption?.call(option);
    final hasGraphic = graphicForOption != null || asset != null;
    final isFuel =
        asset != null && asset.startsWith('assets/fuel_types/');
    final effectiveHeight = !hasGraphic
        ? null
        : (isFuel
            ? (tileImageHeight == null
                ? 40.0
                : tileImageHeight.clamp(32.0, 48.0).toDouble())
            : tileImageHeight);
    final height = _filterIconTileHeight(
      textOnly: false,
      imageHeight: effectiveHeight,
      compactImageTile: compactImageTile || isFuel,
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
    final isFuelAsset =
        imageAsset != null && imageAsset!.startsWith('assets/fuel_types/');
    // Fuel artwork is 256²; keep tiles modestly compact (between original
    // oversized cards and the too-tiny experiment).
    final effectiveImageWidth = isFuelAsset
        ? (imageWidth == null ? 40.0 : imageWidth!.clamp(32.0, 48.0).toDouble())
        : imageWidth;
    final effectiveImageHeight = isFuelAsset
        ? (imageHeight == null
            ? 40.0
            : imageHeight!.clamp(32.0, 48.0).toDouble())
        : imageHeight;
    final effectiveCompact = compactImageTile || isFuelAsset;
    final effectiveWidth = isFuelAsset
        ? (width == null ? 80.0 : width!.clamp(72.0, 88.0).toDouble())
        : width;
    final Widget? graphic;
    if (textOnly) {
      graphic = null;
    } else if (customGraphic != null) {
      final slotWidth = effectiveImageWidth ?? 26;
      final slotHeight = effectiveImageHeight ?? 26;
      graphic = SizedBox(
        width: slotWidth,
        height: slotHeight,
        child: Center(child: customGraphic),
      );
    } else {
      final slotWidth = effectiveImageWidth ?? 26;
      final slotHeight = effectiveImageHeight ?? 26;
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
    final vPad = _filterIconTileVerticalPad(
      textOnly: textOnly,
      imageHeight: effectiveImageHeight,
      compactImageTile: effectiveCompact,
    );
    final gap = _filterIconTileGap(
      textOnly: textOnly,
      imageHeight: effectiveImageHeight,
      compactImageTile: effectiveCompact,
    );
    final radius =
        effectiveCompact && (effectiveImageHeight ?? 26) <= 40 ? 8.0 : 12.0;
    final tile = Material(
      color: isLight ? Colors.white : filterIconTileBackdropColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: selected ? kFilterAccentColor : const Color(0xFFE0E0E5),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (graphic != null) ...[
                Center(child: graphic),
                SizedBox(height: gap),
              ],
              AppResponsive.fittedLabel(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppResponsive.filterIconLabelFontSize(
                    context,
                    textOnly: textOnly,
                    regular: effectiveCompact &&
                            (effectiveImageHeight ?? 26) < 36
                        ? 11
                        : 12,
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

    if (effectiveWidth == null) {
      return SizedBox(width: double.infinity, child: tile);
    }
    return SizedBox(width: effectiveWidth, child: tile);
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

    final hasFuelArtwork = effectiveOptions.any((o) {
      final asset = imageAssetForOption?.call(o);
      return asset != null && asset.startsWith('assets/fuel_types/');
    });
    final resolvedTileWidth =
        hasFuelArtwork ? tileWidth.clamp(72.0, 88.0).toDouble() : tileWidth;
    final resolvedImageWidth = hasFuelArtwork
        ? (tileImageWidth ?? 40).clamp(32.0, 48.0).toDouble()
        : tileImageWidth;
    final resolvedImageHeight = hasFuelArtwork
        ? (tileImageHeight ?? 40).clamp(32.0, 48.0).toDouble()
        : tileImageHeight;
    final resolvedCompact = compactImageTile || hasFuelArtwork;

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
            ? AppResponsive.filterIconTileWidth(
                context,
                resolvedTileWidth,
                compactBoost: resolvedCompact ? 0 : 16,
              )
            : null,
        imageWidth: (usesImageAsset || customGraphic != null)
            ? resolvedImageWidth
            : null,
        imageHeight: (usesImageAsset || customGraphic != null)
            ? resolvedImageHeight
            : null,
        imageFit: tileImageFit,
        imageBorderRadius: tileImageBorderRadius,
        textOnly: textOnly,
        compactImageTile: resolvedCompact,
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    tiles[i],
                  ],
                ],
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
            hideLabel: true,
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
