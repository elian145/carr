part of 'car_listing_specs_grid.dart';

/// Layout at ~107dp tile width; every dimension scales with the tile so the
/// rounded-rectangle aspect ratio stays the same at any size.
const double _specsDesignTileWidth = 107.0;
const double _specsDesignTileHeight = _specsDesignTileWidth / 1.05;
const double _specsDesignIconSize = 30.0;
const double _specsDesignCircleSize = 44.0;
const double _specsDesignLabelFontSize = 11.0;
const double _specsDesignValueFontSize = 14.0;
const double _specsDesignOrangeBar = 2.5;
const double _specsDesignPadH = 8.0;
const double _specsDesignPadTop = 10.0;
const double _specsDesignPadBottom = 6.0;
const double _specsDesignGap = 12.0;
const double _specsDesignOuterPad = 12.0;
const double _specsDesignRadius = 14.0;
const double _specsDetailCircleSize = 32.0;
const double _specsDetailIconSize = 17.0;
const double _specsDetailFontSize = 15.0;
const double _specsDetailPadL = 12.0;
const double _specsDetailPadT = 8.0;
const double _specsDetailPadR = 20.0;
const double _specsDetailPadB = 8.0;
const double _specsDetailIconGap = 12.0;
const double _specsDetailValueGap = 8.0;
const double _specsDetailChevronSize = 22.0;
const double _specsDetailChevronGap = 4.0;
const double _specsDetailRowGap = 12.0;
const int _specsIconFlex = 5;
const int _specsLabelFlex = 2;
const int _specsValueFlex = 3;
const int _specsContentFlexTotal =
    _specsIconFlex + _specsLabelFlex + _specsValueFlex;

double _specsDim(double designPixels, double scale) => designPixels * scale;

double _specsPackedWidth(int crossCount) =>
    crossCount * _specsDesignTileWidth +
    (crossCount - 1) * _specsDesignGap;

final class _SpecsGridMetrics {
  const _SpecsGridMetrics({
    required this.crossCount,
    required this.scale,
    required this.gap,
    required this.rowH,
  });

  final int crossCount;
  final double scale;
  final double gap;
  final double rowH;

  double gridHeight(int itemCount) {
    final rows = (itemCount / crossCount).ceil();
    return rowH * rows + gap * math.max(0, rows - 1);
  }
}

/// Always 3×2. Tile size follows available width so the rounded-rectangle
/// design stays the same when system font or display size changes.
_SpecsGridMetrics _specsGridMetrics({
  required double availableWidth,
}) {
  const crossCount = 3;
  final width = availableWidth <= 0 ? _specsPackedWidth(crossCount) : availableWidth;
  final scale = width / _specsPackedWidth(crossCount);
  return _SpecsGridMetrics(
    crossCount: crossCount,
    scale: scale,
    gap: _specsDim(_specsDesignGap, scale),
    rowH: _specsDim(_specsDesignTileHeight, scale),
  );
}

Widget carListingSpecsDetailRow(
  BuildContext context, {
    required IconData icon,
    required String label,
    required String? value,
    Widget? valueWidget,
    VoidCallback? onTap,
  }) {
    if (valueWidget == null && (value == null || value.isEmpty)) {
      return const SizedBox.shrink();
    }
    final isLight = Theme.of(context).brightness == Brightness.light;
    const brandOrange = AppColors.brandOrange;
    const iconCircleFillLight = Color(0xFFFFF0E6);
    const iconCircleFillDark = Color(0xFFFFE8D6);
    const labelGrey = Color(0xFF8E8E93);
    final cardBg = onTap != null
        ? (isLight
            ? const Color(0xFFFFF7F0)
            : const Color(0xFF2A211C))
        : (isLight ? Colors.white : const Color(0xFF1E1E1E));
    final iconCircleFill = isLight ? iconCircleFillLight : iconCircleFillDark;
    final valueColor = isLight ? Colors.black : Colors.white;

    const scale = 1.0;
    final radius = _specsDim(_specsDesignRadius, scale);
    final circle = _specsDim(_specsDetailCircleSize, scale);
    final iconSize = _specsDim(_specsDetailIconSize, scale);
    final fontSize = _specsDim(_specsDetailFontSize, scale);
    final orangeBar = _specsDim(_specsDesignOrangeBar, scale);

    final row = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            _specsDim(_specsDetailPadL, scale),
            _specsDim(_specsDetailPadT, scale),
            _specsDim(_specsDetailPadR, scale),
            _specsDim(_specsDetailPadB, scale),
          ),
          child: Row(
            children: [
              Container(
                width: circle,
                height: circle,
                decoration: BoxDecoration(
                  color: iconCircleFill,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: iconSize, color: brandOrange),
              ),
              SizedBox(width: _specsDim(_specsDetailIconGap, scale)),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: labelGrey,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ),
              if (valueWidget != null) ...[
                SizedBox(width: _specsDim(_specsDetailValueGap, scale)),
                valueWidget,
              ] else if (value != null) ...[
                SizedBox(width: _specsDim(_specsDetailValueGap, scale)),
                Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: onTap != null ? brandOrange : valueColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                if (onTap != null) ...[
                  SizedBox(width: _specsDim(_specsDetailChevronGap, scale)),
                  Icon(
                    Icons.chevron_right,
                    color: brandOrange,
                    size: _specsDim(_specsDetailChevronSize, scale),
                  ),
                ],
              ] else if (onTap != null) ...[
                Icon(
                  Icons.chevron_right,
                  color: brandOrange,
                  size: _specsDim(_specsDetailChevronSize, scale),
                ),
              ],
            ],
          ),
        ),
        ColoredBox(
          color: brandOrange,
          child: SizedBox(height: orangeBar, width: double.infinity),
        ),
      ],
    );

    final card = Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: _specsDim(_specsDetailRowGap, scale)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.10 : 0.50),
            blurRadius: (isLight ? 18 : 20) * scale,
            offset: Offset(0, 8 * scale),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.05 : 0.28),
            blurRadius: (isLight ? 6 : 8) * scale,
            offset: Offset(0, 2 * scale),
          ),
        ],
        border: onTap != null
            ? Border.all(color: brandOrange.withValues(alpha: 0.55))
            : Border.all(
                color: isLight
                    ? const Color(0xFFE8E8ED)
                    : Colors.white.withValues(alpha: 0.08),
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: row,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: card,
      ),
    );
  }

Widget carListingSpecsCard(ListingSpecItem item, {required double scale}) {
  const brandOrange = AppColors.brandOrange;
  const labelGrey = Color(0xFF8E8E93);
  final radius = _specsDim(_specsDesignRadius, scale);

  return Semantics(
    label: '${item.label}: ${item.value ?? ''}',
    child: Builder(
      builder: (context) {
        final isLight = Theme.of(context).brightness == Brightness.light;
        final cardBg = isLight ? Colors.white : const Color(0xFF1E1E1E);
        final iconCircleFill =
            isLight ? const Color(0xFFFFF0E6) : const Color(0xFFFFE8D6);
        final valueColor = isLight ? Colors.black : Colors.white;

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: cardBg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.10 : 0.50),
                blurRadius: (isLight ? 16 : 18) * scale,
                offset: Offset(0, 6 * scale),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.28),
                blurRadius: (isLight ? 4 : 6) * scale,
                offset: Offset(0, 2 * scale),
              ),
            ],
            border: Border.all(
              color: isLight
                  ? const Color(0xFFE8E8ED)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padH = _specsDim(_specsDesignPadH, scale);
                final padTop = _specsDim(_specsDesignPadTop, scale);
                final padBottom = _specsDim(_specsDesignPadBottom, scale);
                final labelFontSize = _specsDim(_specsDesignLabelFontSize, scale);
                final valueFontSize = _specsDim(_specsDesignValueFontSize, scale);
                final orangeBar = _specsDim(_specsDesignOrangeBar, scale);

                final innerH = math.max(
                  0.0,
                  constraints.maxHeight - orangeBar - padTop - padBottom,
                );
                final iconZoneH =
                    innerH * _specsIconFlex / _specsContentFlexTotal;
                final labelZoneH =
                    innerH * _specsLabelFlex / _specsContentFlexTotal;
                final valueZoneH =
                    innerH * _specsValueFlex / _specsContentFlexTotal;
                final desiredCircle = _specsDim(_specsDesignCircleSize, scale);
                final circleSize = iconZoneH > 0
                    ? math.min(desiredCircle, iconZoneH)
                    : 0.0;
                final iconSize = circleSize *
                    (_specsDesignIconSize / _specsDesignCircleSize);

                final Widget iconGlyph;
                final asset = item.imageAsset;
                if (asset != null && asset.isNotEmpty) {
                  iconGlyph = ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      brandOrange,
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      asset,
                      width: iconSize,
                      height: iconSize,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        item.icon,
                        size: iconSize,
                        color: brandOrange,
                      ),
                    ),
                  );
                } else {
                  iconGlyph = Icon(
                    item.icon,
                    size: iconSize,
                    color: brandOrange,
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        padH,
                        padTop,
                        padH,
                        padBottom,
                      ),
                      child: SizedBox(
                        height: innerH,
                        child: Column(
                          children: [
                            SizedBox(
                              height: iconZoneH,
                              child: Center(
                                child: Container(
                                  width: circleSize,
                                  height: circleSize,
                                  decoration: BoxDecoration(
                                    color: iconCircleFill,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: iconGlyph,
                                ),
                              ),
                            ),
                            SizedBox(
                              height: labelZoneH,
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  textScaler: TextScaler.noScaling,
                                  style: TextStyle(
                                    fontSize: labelFontSize,
                                    height: 1.05,
                                    color: labelGrey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: valueZoneH,
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  item.value!,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  textScaler: TextScaler.noScaling,
                                  style: TextStyle(
                                    fontSize: valueFontSize,
                                    height: 1.05,
                                    color: valueColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ColoredBox(
                      color: brandOrange,
                      child: SizedBox(
                        height: orangeBar,
                        width: double.infinity,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          );
      },
    ),
  );
}
