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

/// Text scale the fixed design tile accommodates without growing.
const double _specsTextScaleHeadroom = 1.5;

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
  double textScale = 1.0,
}) {
  const crossCount = 3;
  final width = availableWidth <= 0 ? _specsPackedWidth(crossCount) : availableWidth;
  final scale = width / _specsPackedWidth(crossCount);
  return _SpecsGridMetrics(
    crossCount: crossCount,
    scale: scale,
    gap: _specsDim(_specsDesignGap, scale),
    // The design tile (label/value zones) already holds text up to ~1.5x;
    // beyond that the row grows so 2.0x text is not scaled back down.
    rowH: _specsDim(_specsDesignTileHeight, scale) *
        (textScale > _specsTextScaleHeadroom
            ? textScale / _specsTextScaleHeadroom
            : 1.0),
  );
}

/// Inner (text + icon) height of one tile: the tile minus the orange bar and
/// the vertical padding. Shared by [carListingSpecsCard] and
/// [_specsSharedFontSizes] so both always agree on the label / value zones.
double _specsInnerHeight(double tileHeight, double scale) => math.max(
      0.0,
      tileHeight -
          _specsDim(_specsDesignOrangeBar, scale) -
          _specsDim(_specsDesignPadTop, scale) -
          _specsDim(_specsDesignPadBottom, scale),
    );

/// The one label size and one value size used by all six tiles (pre-text-scale
/// font sizes, i.e. what goes into `TextStyle.fontSize`).
final class _SpecsFontSizes {
  const _SpecsFontSizes({required this.label, required this.value});

  final double label;
  final double value;
}

/// The six specification boxes stop following the system text size at this
/// scale. They are fixed-size tiles in a 3x2 grid whose type was already
/// limited by the tile width (~19 px on a Pro Max), so above 1.3x the tiles
/// only got taller (150 dp vs 113 dp at 2.0x) without the text getting
/// bigger. Everything else on the page (title, description, seller block,
/// contact bar...) keeps following the system text size.
const double _specsMaxTextScale = 1.3;

/// Caps the text scale seen by the six specification boxes at
/// [_specsMaxTextScale]. Below the cap the inherited scaler is left untouched.
/// (Not `TextScaler.noScaling`: the boxes still honour the user's size up to
/// 1.3x.)
Widget _specsCappedTextScale(BuildContext context, {required Widget child}) {
  final mq = MediaQuery.of(context);
  if (appTextScaleOf(context) <= _specsMaxTextScale) return child;
  return MediaQuery(
    data: mq.copyWith(textScaler: const TextScaler.linear(_specsMaxTextScale)),
    child: child,
  );
}

/// Lowest rendered size (as a fraction of the design size) the shared type may
/// shrink to just to fit one long value. Anything longer than that is shrunk
/// inside its own tile only (the per-tile FittedBox), so a single long
/// translation cannot drag the other five values down.
const double _specsMinSharedFraction = 0.85;

/// Largest label size relative to the value size. The design ratio is
/// 11 / 14 = 0.79; this keeps labels visibly smaller than values when the
/// label zone is the tighter one.
const double _specsMaxLabelToValue = 0.8;

/// Picks one value size and one label size for the whole grid.
///
/// Each tile used to size itself with its own FittedBox(scaleDown): short
/// values ("4", "2.0L") stayed at full size while "123,456 km" / "Automatic"
/// shrank to the tile width, so at larger text scales or with iOS Bold Text
/// (wider glyphs) the six values rendered at very different sizes. Here the
/// longest value is measured with the real text scaler and weight (Bold Text
/// forces `FontWeight.bold` on every `Text`), and everyone gets the size that
/// fits it. Normal text sizes are unaffected: if everything fits, the design
/// size is kept.
_SpecsFontSizes _specsSharedFontSizes(
  BuildContext context,
  List<ListingSpecItem> items, {
  required double tileWidth,
  required double tileHeight,
  required double scale,
}) {
  final designLabel = _specsDim(_specsDesignLabelFontSize, scale);
  final designValue = _specsDim(_specsDesignValueFontSize, scale);
  final padH = _specsDim(_specsDesignPadH, scale);
  final innerH = _specsInnerHeight(tileHeight, scale);
  final zoneW = math.max(0.0, tileWidth - padH * 2);
  final labelZoneH = innerH * _specsLabelFlex / _specsContentFlexTotal;
  final valueZoneH = innerH * _specsValueFlex / _specsContentFlexTotal;

  final textScaler = MediaQuery.textScalerOf(context);
  final textScale = appTextScaleOf(context);
  final bold = MediaQuery.boldTextOf(context);
  final direction = Directionality.of(context);
  final locale = Localizations.maybeLocaleOf(context);
  final base = DefaultTextStyle.of(context).style;

  double fit({
    required Iterable<String> texts,
    required double design,
    required FontWeight weight,
    required double zoneHeight,
  }) {
    final style = base.merge(
      TextStyle(
        fontSize: design,
        height: 1.05,
        // Text() forces FontWeight.bold when Bold Text is on; measure with
        // the weight that will really be painted.
        fontWeight: bold ? FontWeight.bold : weight,
      ),
    );
    var widest = 0.0;
    var lineHeight = 0.0;
    for (final t in texts) {
      if (t.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: t, style: style),
        textDirection: direction,
        textScaler: textScaler,
        locale: locale,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      lineHeight = math.max(lineHeight, painter.height);
      painter.dispose();
    }
    var k = 1.0;
    if (widest > zoneW && widest > 0) k = zoneW / widest;
    if (lineHeight > zoneHeight && lineHeight > 0) {
      k = math.min(k, zoneHeight / lineHeight);
    }
    // Never below ~85% of the design size once text scale is applied.
    final floorK = math.min(1.0, _specsMinSharedFraction / textScale);
    return design * math.min(1.0, math.max(k, floorK));
  }

  final value = fit(
    texts: items.map((i) => i.value ?? ''),
    design: designValue,
    weight: FontWeight.w800,
    zoneHeight: valueZoneH,
  );
  final label = fit(
    texts: items.map((i) => i.label),
    design: designLabel,
    weight: FontWeight.w500,
    zoneHeight: labelZoneH,
  );
  return _SpecsFontSizes(
    label: math.min(label, value * _specsMaxLabelToValue),
    value: value,
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
    const brandOrange = AppColors.brandOrangeIcon;
    const iconCircleFillLight = Color(0xFFFFF0E6);
    const iconCircleFillDark = Color(0xFFFFE8D6);
    final labelGrey = AppColors.mutedTextFor(Theme.of(context).brightness);
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
                  maxLines: appTextScaleOf(context) > 1.3 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
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
                // Cap the value so a scaled (up to 2x) value can never push
                // the label to zero width / overflow the row.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.55,
                  ),
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onTap != null ? AppColors.accentText(context) : valueColor,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
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

Widget carListingSpecsCard(
  ListingSpecItem item, {
  required double scale,
  // Shared across the six tiles by buildCarListingSpecsGrid; null keeps the
  // design size scaled by [scale] (standalone use).
  double? labelFontSize,
  double? valueFontSize,
}) {
  const brandOrange = AppColors.brandOrangeIcon;
  final radius = _specsDim(_specsDesignRadius, scale);

  return Semantics(
    label: '${item.label}: ${item.value ?? ''}',
    child: Builder(
      builder: (context) {
        final isLight = Theme.of(context).brightness == Brightness.light;
        final labelGrey = AppColors.mutedTextFor(Theme.of(context).brightness);
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
                // One shared size for all six tiles (see _specsSharedFontSizes).
                final labelFontSizePx = labelFontSize ??
                    _specsDim(_specsDesignLabelFontSize, scale);
                final valueFontSizePx = valueFontSize ??
                    _specsDim(_specsDesignValueFontSize, scale);
                final orangeBar = _specsDim(_specsDesignOrangeBar, scale);

                final innerH = _specsInnerHeight(constraints.maxHeight, scale);
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
                                  style: TextStyle(
                                    fontSize: labelFontSizePx,
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
                                  style: TextStyle(
                                    fontSize: valueFontSizePx,
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
