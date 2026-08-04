part of 'global_listing_card.dart';

/// Price badge metrics scaled to the listing card's text-row width.
///
/// Narrow 2-column tiles get a smaller orange pill; wider cards / list rows
/// keep the fuller size. [footerHeight] matches padding + type so the row
/// does not overflow.
class _ListingPriceBadgeStyle {
  const _ListingPriceBadgeStyle({
    required this.fontSize,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.radius,
    required this.footerHeight,
  });

  final double fontSize;
  final double horizontalPadding;
  final double verticalPadding;
  final double radius;
  final double footerHeight;
}

_ListingPriceBadgeStyle _listingPriceBadgeStyle({
  required double rowWidth,
  required bool hasPrice,
  required bool listLayout,
}) {
  // Grid reference: ~148px text width → smallest badge, ~204px → full size.
  // List rows are wider, so they use a higher reference band.
  final double t = listLayout
      ? ((rowWidth - 200) / 140).clamp(0.0, 1.0)
      : ((rowWidth - 148) / 56).clamp(0.0, 1.0);

  // Slightly larger than the compact baseline so prices read clearly without
  // overpowering the rest of the card.
  final double fontSize = listLayout
      ? (hasPrice ? 15.0 + 2.5 * t : 12.5 + 2.0 * t)
      : (hasPrice ? 14.0 + 3.0 * t : 11.5 + 2.5 * t);
  final double horizontalPadding = listLayout
      ? (hasPrice ? 9.5 + 3.5 * t : 6.5 + 2.0 * t)
      : (hasPrice ? 6.5 + 4.5 * t : 5.0 + 3.5 * t);
  final double verticalPadding = listLayout
      ? 6.0 + 2.0 * t
      : 4.0 + 3.0 * t;
  final double radius = listLayout ? 7.5 + 2.0 * t : 7.0 + 2.0 * t;
  // +1.5 slack covers font metric rounding inside the fixed footer slot.
  final double footerHeight = listLayout
      ? verticalPadding * 2 + fontSize + 1.5
      : (verticalPadding * 2 + fontSize + 1.5).clamp(24.0, 34.0);

  return _ListingPriceBadgeStyle(
    fontSize: fontSize,
    horizontalPadding: horizontalPadding,
    verticalPadding: verticalPadding,
    radius: radius,
    footerHeight: footerHeight,
  );
}

/// Title / price / mileage block shared by grid and horizontal list listing cards.
Widget _buildGlobalCarCardInnerText(
  BuildContext context,
  Map car, {
  required String brandId,
  required String trimLine,
  String engineLine = '',
  required String yearDisplay,
  required String mileageDisplay,
  required String cityLine,
  required Color titleTextColor,
  required Color dividerLineColor,
  required Color metaTextColor,
  bool listLayout = false,
}) {
  if (listLayout) {
    return _buildListCarCardInnerText(
      context,
      car,
      brandId: brandId,
      trimLine: trimLine,
      engineLine: engineLine,
      yearDisplay: yearDisplay,
      mileageDisplay: mileageDisplay,
      cityLine: cityLine,
      titleTextColor: titleTextColor,
      dividerLineColor: dividerLineColor,
      metaTextColor: metaTextColor,
    );
  }

  return _buildGridCarCardInnerText(
    context,
    car,
    brandId: brandId,
    trimLine: trimLine,
    engineLine: engineLine,
    yearDisplay: yearDisplay,
    mileageDisplay: mileageDisplay,
    cityLine: cityLine,
    titleTextColor: titleTextColor,
    dividerLineColor: dividerLineColor,
    metaTextColor: metaTextColor,
  );
}

/// Grid card using the same visual language as the horizontal card.
Widget _buildGridCarCardInnerText(
  BuildContext context,
  Map car, {
  required String brandId,
  required String trimLine,
  required String engineLine,
  required String yearDisplay,
  required String mileageDisplay,
  required String cityLine,
  required Color titleTextColor,
  required Color dividerLineColor,
  required Color metaTextColor,
}) {
  // Grid tiles: brand logo + title, trim, year/price, mileage/city.
  final bool compact = AppResponsive.isCompactPhone(context);
  // Fixed title metrics so the brand logo sits at the same spot on every card.
  const double titleFontSize = 15;
  const double titleLineHeight = 1.12;
  const int titleMaxLines = 2;
  const double logoSize = 24;
  const double logoPad = 4.0;
  const double logoTitleGap = 6.0;
  final double titleLineBoxHeight = titleFontSize * titleLineHeight;
  final double reservedTitleHeight = titleLineBoxHeight * titleMaxLines;
  final double sectionGap = compact ? 4.0 : 6.0;
  final double blockGap = compact ? 6.0 : 8.0;
  final bool hasPrice = tryParseCurrencyValue(car['price']) != null;
  final String priceText = hasPrice
      ? formatCurrency(context, car['price'])
      : AppLocalizations.of(context)!.contactForPrice;
  final bool isLight = Theme.of(context).brightness == Brightness.light;
  final inheritedTextDirection = Directionality.of(context);
  final languageCode = Localizations.localeOf(context).languageCode;
  final bool isRtl =
      inheritedTextDirection == TextDirection.rtl ||
      languageCode == 'ar' ||
      languageCode == 'ku';
  final textDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;
  final double leadingShift = isRtl ? 6 : -6;
  final double trailingShift = isRtl ? -4 : 4;
  const Color priceAccent = Color(0xFFFF5A00);

  Widget infoChip(String value, {Color? color, bool scaleDown = false}) {
    final text = Text(
      value,
      textDirection: textDirection,
      textAlign: TextAlign.start,
      textScaler: const TextScaler.linear(1.0),
      maxLines: 1,
      softWrap: false,
      overflow: scaleDown ? TextOverflow.visible : TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? titleTextColor,
        fontSize: compact ? 11 : 13,
        fontWeight: FontWeight.w500,
        height: 1,
      ),
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFF4F4F4)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: scaleDown
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
              child: text,
            )
          : text,
    );
  }

  /// Year / mileage chips: soft accent tint + icon so specs feel less flat.
  /// Pass [constrainWidth] for the mileage chip so it respects remaining row
  /// width. Mileage content is always LTR (icon then digits). The chip only
  /// stretches to the full slot when the full-size label would overflow —
  /// otherwise it hugs content so the pill has no empty internal gap.
  Widget yearMileageChip(
    String value, {
    required IconData icon,
    bool constrainWidth = false,
  }) {
    final double baseFontSize = compact ? 12.0 : 12.5;
    final double iconSize = compact ? 11.0 : 12.0;
    final double iconGap = compact ? 3.0 : 4.0;
    final double hPad = compact ? 5.0 : 7.0;
    const TextDirection chipDir = TextDirection.ltr;
    final textStyle = TextStyle(
      color: isLight ? const Color(0xFF3A3A3A) : Colors.white,
      fontSize: baseFontSize,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: 0.1,
    );

    Widget buildChip({
      required double fontSize,
      required bool fillWidth,
      double? width,
    }) {
      final label = Text(
        value,
        textDirection: chipDir,
        textAlign: TextAlign.left,
        textScaler: const TextScaler.linear(1.0),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: textStyle.copyWith(fontSize: fontSize),
      );
      return SizedBox(
        width: width,
        child: Container(
          width: fillWidth ? double.infinity : null,
          alignment: fillWidth ? Alignment.centerLeft : null,
          padding: EdgeInsets.symmetric(
            horizontal: hPad,
            vertical: compact ? 4 : 5.5,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLight
                  ? [
                      priceAccent.withValues(alpha: 0.10),
                      priceAccent.withValues(alpha: 0.04),
                    ]
                  : [
                      priceAccent.withValues(alpha: 0.22),
                      priceAccent.withValues(alpha: 0.10),
                    ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: priceAccent.withValues(alpha: isLight ? 0.28 : 0.40),
              width: 1,
            ),
          ),
          child: Row(
            textDirection: chipDir,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize, color: priceAccent),
              SizedBox(width: iconGap),
              if (fillWidth)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: label,
                  ),
                )
              else
                label,
            ],
          ),
        ),
      );
    }

    if (!constrainWidth) {
      return buildChip(fontSize: baseFontSize, fillWidth: false);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool canConstrain =
            constraints.maxWidth.isFinite &&
            constraints.maxWidth < double.infinity;
        if (!canConstrain) {
          return buildChip(fontSize: baseFontSize, fillWidth: false);
        }

        final painter = TextPainter(
          text: TextSpan(text: value, style: textStyle),
          textDirection: chipDir,
          textScaler: TextScaler.noScaling,
          maxLines: 1,
        )..layout(minWidth: 0, maxWidth: double.infinity);
        final textW = painter.width;
        painter.dispose();

        final preferredW = iconSize + iconGap + textW + hPad * 2 + 2;
        // Only stretch the pill when the label cannot fit at full size.
        // Stretching while it fits leaves empty space inside the chip.
        if (preferredW > constraints.maxWidth) {
          return buildChip(
            fontSize: baseFontSize,
            fillWidth: true,
            width: constraints.maxWidth,
          );
        }

        // Fits at full size — hug content and sit beside the year.
        return Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: buildChip(fontSize: baseFontSize, fillWidth: false),
        );
      },
    );
  }

  const double logoInner = logoSize - (logoPad * 2);
  final bool showLogo =
      car['brand'] != null && car['brand'].toString().trim().isNotEmpty;
  final String titleText = localizedCarTitleForCard(context, car);
  final titleStyle = TextStyle(
    fontWeight: FontWeight.bold,
    color: titleTextColor,
    fontSize: titleFontSize,
    height: titleLineHeight,
    leadingDistribution: TextLeadingDistribution.even,
  );
  final titleStrut = StrutStyle(
    fontSize: titleFontSize,
    height: titleLineHeight,
    fontWeight: FontWeight.bold,
    forceStrutHeight: true,
    leadingDistribution: TextLeadingDistribution.even,
  );

  final Widget titleBlock = Transform.translate(
    offset: Offset(leadingShift, 0),
    child: SizedBox(
      height: reservedTitleHeight,
      child: Row(
        textDirection: textDirection,
        // Center logo with the title block so one- and two-line names share
        // the same vertical midpoint (logo sits slightly below the top edge).
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showLogo)
            SizedBox(
              width: logoSize,
              height: logoSize,
              child: Container(
                width: logoSize,
                height: logoSize,
                padding: const EdgeInsets.all(logoPad),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: isLight
                        ? const Color(0xFFD0D0D0)
                        : Colors.white.withValues(alpha: 0.30),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: BrandLogoImage(
                  brand: brandId,
                  placeholderSize: logoInner,
                  errorIconSize: 20,
                ),
              ),
            ),
          if (showLogo) const SizedBox(width: logoTitleGap),
          Expanded(
            child: Text(
              titleText,
              textDirection: textDirection,
              textScaler: TextScaler.noScaling,
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
              style: titleStyle,
              strutStyle: titleStrut,
              maxLines: titleMaxLines,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
        ],
      ),
    ),
  );

  final bool hasDetail = engineLine.isNotEmpty || trimLine.isNotEmpty;
  final Widget trimBlock = Padding(
    padding: EdgeInsets.only(top: blockGap),
    child: Transform.translate(
      offset: Offset(leadingShift, 0),
      child: Row(
        textDirection: textDirection,
        children: [
          if (engineLine.isNotEmpty)
            Flexible(
              flex: 2,
              child: infoChip(
                engineLine,
                color: metaTextColor,
                scaleDown: true,
              ),
            ),
          if (engineLine.isNotEmpty && trimLine.isNotEmpty)
            SizedBox(width: compact ? 4 : 6),
          if (trimLine.isNotEmpty) ...[
            Flexible(
              flex: 4,
              child: infoChip(trimLine, color: metaTextColor, scaleDown: true),
            ),
          ],
        ],
      ),
    ),
  );

  final bool hasSpecs = yearDisplay.isNotEmpty || mileageDisplay.isNotEmpty;
  final int mileageDigits =
      mileageDisplay.replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '').length;
  // 5+ digits (or long formatted strings) fill the remaining row width.
  final bool longMileage =
      mileageDisplay.isNotEmpty &&
      (mileageDigits > 4 || mileageDisplay.length > 10);
  final Widget yearPriceBlock = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(height: sectionGap),
      // Same leadingShift as title/trim so year lines up with those chips.
      Transform.translate(
        offset: Offset(leadingShift, 0),
        child: Row(
          textDirection: textDirection,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (yearDisplay.isNotEmpty)
              yearMileageChip(
                yearDisplay,
                icon: Icons.calendar_today_rounded,
              ),
            if (yearDisplay.isNotEmpty && mileageDisplay.isNotEmpty)
              SizedBox(width: compact ? 4 : 6),
            if (mileageDisplay.isNotEmpty)
              // Short values sit beside the year. Long values take the rest of
              // the row so the number can stay larger.
              longMileage
                  ? Expanded(
                      child: yearMileageChip(
                        mileageDisplay,
                        icon: Icons.speed_rounded,
                        constrainWidth: true,
                      ),
                    )
                  : yearMileageChip(
                      mileageDisplay,
                      icon: Icons.speed_rounded,
                    ),
          ],
        ),
      ),
    ],
  );

  final Widget mileageCityRow = LayoutBuilder(
    builder: (context, constraints) {
      final priceStyle = _listingPriceBadgeStyle(
        rowWidth: constraints.maxWidth,
        hasPrice: hasPrice,
        listLayout: false,
      );
      // Keep enough room for the city; long price labels shrink instead.
      final double maxPriceWidth =
          constraints.maxWidth * (hasPrice ? 0.62 : 0.52);
      final Widget priceBadge = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxPriceWidth),
        child: Transform.translate(
          offset: Offset(trailingShift, 0),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: priceStyle.horizontalPadding,
              vertical: priceStyle.verticalPadding,
            ),
            decoration: BoxDecoration(
              color: priceAccent,
              borderRadius: BorderRadius.circular(priceStyle.radius),
            ),
            // No FittedBox: it expands to the max width and leaves empty
            // orange beside short prices. Text + maxWidth hugs content.
            child: Text(
              priceText,
              textScaler: const TextScaler.linear(1.0),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: priceStyle.fontSize,
                height: 1,
              ),
            ),
          ),
        ),
      );

      return SizedBox(
        height: priceStyle.footerHeight,
        child: Row(
          textDirection: textDirection,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (cityLine.isNotEmpty)
              Expanded(
                child: Transform.translate(
                  offset: Offset(leadingShift, 0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: isRtl
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Row(
                      textDirection: textDirection,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: priceAccent,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          cityLine,
                          textDirection: textDirection,
                          textScaler: const TextScaler.linear(1.0),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: TextStyle(
                            color: titleTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (cityLine.isNotEmpty) SizedBox(width: compact ? 4 : 6),
            if (cityLine.isEmpty) const Spacer(),
            priceBadge,
          ],
        ),
      );
    },
  );

  // Fixed spacing (no FittedBox): leftover height sits between the specs and
  // the footer so logo/title/chip sizes stay identical across phone sizes.
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      titleBlock,
      if (hasDetail) trimBlock,
      if (hasSpecs) yearPriceBlock,
      const Spacer(),
      SizedBox(height: sectionGap),
      mileageCityRow,
    ],
  );
}

/// Slim horizontal list card with inline specs and an orange price badge.
Widget _buildListCarCardInnerText(
  BuildContext context,
  Map car, {
  required String brandId,
  required String trimLine,
  required String engineLine,
  required String yearDisplay,
  required String mileageDisplay,
  required String cityLine,
  required Color titleTextColor,
  required Color dividerLineColor,
  required Color metaTextColor,
}) {
  final bool isLight = Theme.of(context).brightness == Brightness.light;
  final inheritedTextDirection = Directionality.of(context);
  final languageCode = Localizations.localeOf(context).languageCode;
  final bool isRtl =
      inheritedTextDirection == TextDirection.rtl ||
      languageCode == 'ar' ||
      languageCode == 'ku';
  final textDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;
  final double leadingShift = isRtl ? 6 : -6;
  final double trailingShift = isRtl ? -4 : 4;
  final String titleText = localizedCarTitleForCard(context, car);
  final bool hasTrim = trimLine.isNotEmpty;
  final bool hasEngine = engineLine.isNotEmpty;
  final bool hasDetailRow = hasEngine || hasTrim;
  final bool hasPrice = tryParseCurrencyValue(car['price']) != null;
  final String priceText = hasPrice
      ? formatCurrency(context, car['price'])
      : AppLocalizations.of(context)!.contactForPrice;
  final String yearText = yearDisplay.isNotEmpty ? yearDisplay : '—';
  final String mileageText = mileageDisplay.isNotEmpty ? mileageDisplay : '—';
  final String cityText = cityLine.isNotEmpty ? cityLine : '—';
  const Color priceAccent = Color(0xFFFF5A00);
  final bool showLogo =
      car['brand'] != null && car['brand'].toString().trim().isNotEmpty;

  final Widget titleRow = Row(
    textDirection: textDirection,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (showLogo) ...[
        Container(
          width: 26,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: isLight
                  ? const Color(0xFFD0D0D0)
                  : Colors.white.withValues(alpha: 0.30),
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: BrandLogoImage(
            brand: brandId,
            placeholderSize: 14,
            errorIconSize: 18,
            errorIconColor: priceAccent,
          ),
        ),
        const SizedBox(width: 6),
      ],
      Expanded(
        child: Text(
          titleText,
          textDirection: textDirection,
          textScaler: TextScaler.noScaling,
          textAlign: isRtl ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: titleTextColor,
            fontSize: 15,
            height: 1.1,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
      ),
      const SizedBox(width: 4),
      _ListingCardFavoriteButton(car: car, idleColor: priceAccent),
    ],
  );

  Widget buildPriceBadge({
    double? maxWidth,
    required _ListingPriceBadgeStyle style,
  }) {
    Widget badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: style.horizontalPadding,
        vertical: style.verticalPadding,
      ),
      decoration: BoxDecoration(
        color: priceAccent,
        borderRadius: BorderRadius.circular(style.radius),
      ),
      child: Text(
        priceText,
        textScaler: const TextScaler.linear(1.0),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: style.fontSize,
          height: 1,
        ),
      ),
    );
    if (maxWidth != null) {
      badge = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: badge,
      );
    }
    return badge;
  }

  Widget infoChip(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFF4F4F4)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
      ),
      child: child,
    );
  }

  Widget yearMileageChip(
    String value, {
    required IconData icon,
    bool constrainWidth = false,
  }) {
    const double baseFontSize = 13;
    const double iconSize = 12.0;
    const double iconGap = 4.0;
    const double hPad = 7.0;
    const TextDirection chipDir = TextDirection.ltr;
    final textStyle = TextStyle(
      color: isLight ? const Color(0xFF3A3A3A) : Colors.white,
      fontSize: baseFontSize,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: 0.1,
    );

    Widget buildChip({
      required double fontSize,
      required bool fillWidth,
      double? width,
    }) {
      final label = Text(
        value,
        textDirection: chipDir,
        textAlign: TextAlign.left,
        textScaler: const TextScaler.linear(1.0),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: textStyle.copyWith(fontSize: fontSize),
      );
      return SizedBox(
        width: width,
        child: Container(
          width: fillWidth ? double.infinity : null,
          alignment: fillWidth ? Alignment.centerLeft : null,
          padding: const EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLight
                  ? [
                      priceAccent.withValues(alpha: 0.10),
                      priceAccent.withValues(alpha: 0.04),
                    ]
                  : [
                      priceAccent.withValues(alpha: 0.22),
                      priceAccent.withValues(alpha: 0.10),
                    ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: priceAccent.withValues(alpha: isLight ? 0.28 : 0.40),
              width: 1,
            ),
          ),
          child: Row(
            textDirection: chipDir,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize, color: priceAccent),
              const SizedBox(width: iconGap),
              if (fillWidth)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: label,
                  ),
                )
              else
                label,
            ],
          ),
        ),
      );
    }

    if (!constrainWidth) {
      return buildChip(fontSize: baseFontSize, fillWidth: false);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool canConstrain =
            constraints.maxWidth.isFinite &&
            constraints.maxWidth < double.infinity;
        if (!canConstrain) {
          return buildChip(fontSize: baseFontSize, fillWidth: false);
        }

        final painter = TextPainter(
          text: TextSpan(text: value, style: textStyle),
          textDirection: chipDir,
          textScaler: TextScaler.noScaling,
          maxLines: 1,
        )..layout(minWidth: 0, maxWidth: double.infinity);
        final textW = painter.width;
        painter.dispose();

        final preferredW = iconSize + iconGap + textW + hPad * 2 + 2;
        if (preferredW > constraints.maxWidth) {
          return buildChip(
            fontSize: baseFontSize,
            fillWidth: true,
            width: constraints.maxWidth,
          );
        }

        return Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: buildChip(fontSize: baseFontSize, fillWidth: false),
        );
      },
    );
  }

  final int mileageDigits =
      mileageText.replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '').length;
  final bool longMileage =
      mileageDigits > 4 || mileageText.length > 10;
  final Widget specsRow = Row(
    textDirection: textDirection,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      yearMileageChip(yearText, icon: Icons.calendar_today_rounded),
      const SizedBox(width: 6),
      longMileage
          ? Expanded(
              child: yearMileageChip(
                mileageText,
                icon: Icons.speed_rounded,
                constrainWidth: true,
              ),
            )
          : yearMileageChip(
              mileageText,
              icon: Icons.speed_rounded,
            ),
    ],
  );

  Widget adaptiveDetailText(String value, Color color) {
    return AutoSizeText(
      value,
      textDirection: textDirection,
      textScaleFactor: 1.0,
      maxLines: 1,
      minFontSize: 10,
      stepGranularity: 0.25,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1,
      ),
    );
  }

  final Widget engineTrimRow = Row(
    textDirection: textDirection,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (hasEngine)
        Flexible(
          child: infoChip(adaptiveDetailText(engineLine, metaTextColor)),
        ),
      if (hasEngine && hasTrim) const SizedBox(width: 6),
      if (hasTrim)
        Flexible(child: infoChip(adaptiveDetailText(trimLine, metaTextColor))),
    ],
  );

  final Widget priceRow = LayoutBuilder(
    builder: (context, constraints) {
      final priceStyle = _listingPriceBadgeStyle(
        rowWidth: constraints.maxWidth,
        hasPrice: hasPrice,
        listLayout: true,
      );
      final double maxPriceWidth =
          constraints.maxWidth * (hasPrice ? 0.62 : 0.52);
      return Row(
        textDirection: textDirection,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Transform.translate(
              offset: Offset(leadingShift, 0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
                child: Row(
                  textDirection: textDirection,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: priceAccent,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      cityText,
                      textDirection: textDirection,
                      textScaler: const TextScaler.linear(1.0),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        color: titleTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Transform.translate(
            offset: Offset(trailingShift, 0),
            child: buildPriceBadge(
              maxWidth: maxPriceWidth,
              style: priceStyle,
            ),
          ),
        ],
      );
    },
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.max,
    children: [
      Expanded(
        flex: 4,
        child: LayoutBuilder(
          builder: (context, titleConstraints) {
            final reservedWidth = (showLogo ? 32.0 : 0.0) + 36.0;
            final availableTitleWidth =
                (titleConstraints.maxWidth - reservedWidth).clamp(
                  0.0,
                  double.infinity,
                );
            final titleProbe = TextPainter(
              text: TextSpan(
                text: titleText,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  height: 1.1,
                ),
              ),
              maxLines: 1,
              textDirection: textDirection,
              textScaler: TextScaler.noScaling,
            )..layout(maxWidth: availableTitleWidth);
            final singleLine = !titleProbe.didExceedMaxLines;

            return Align(
              alignment: singleLine
                  ? (isRtl ? Alignment.topRight : Alignment.topLeft)
                  : (isRtl ? Alignment.centerRight : Alignment.centerLeft),
              child: titleRow,
            );
          },
        ),
      ),
      if (hasDetailRow) ...[
        Expanded(
          flex: 3,
          child: Align(
            alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
            child: Transform.translate(
              offset: const Offset(0, -2),
              child: engineTrimRow,
            ),
          ),
        ),
      ],
      Expanded(
        flex: 3,
        child: Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: Transform.translate(
            offset: const Offset(0, -2),
            child: specsRow,
          ),
        ),
      ),
      Expanded(flex: 3, child: priceRow),
    ],
  );
}

class _ListingCardFavoriteButton extends StatefulWidget {
  const _ListingCardFavoriteButton({
    required this.car,
    required this.idleColor,
  });

  final Map car;
  final Color idleColor;

  @override
  State<_ListingCardFavoriteButton> createState() =>
      _ListingCardFavoriteButtonState();
}

class _ListingCardFavoriteButtonState
    extends State<_ListingCardFavoriteButton> {
  late bool _isFavorite;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = _readFavorite(widget.car);
  }

  @override
  void didUpdateWidget(covariant _ListingCardFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.car != widget.car) {
      _isFavorite = _readFavorite(widget.car);
    }
  }

  static bool _readFavorite(Map car) {
    final v = car['is_favorited'] ?? car['favorited'];
    return v == true || v == 1 || v == 'true' || v == '1';
  }

  String get _carId =>
      (widget.car['public_id'] ??
              widget.car['id'] ??
              widget.car['car_id'] ??
              '')
          .toString()
          .trim();

  Future<void> _toggle() async {
    if (_busy) return;
    final tok = ApiService.accessToken;
    if (tok == null || tok.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.loginRequired)),
      );
      return;
    }
    final id = _carId;
    if (id.isEmpty) return;

    final previous = _isFavorite;
    setState(() {
      _busy = true;
      _isFavorite = !previous;
    });
    unawaited(AppHaptics.light());
    try {
      final res = await ApiService.toggleFavorite(id);
      final favorited =
          (res['is_favorited'] == true) || (res['favorited'] == true);
      if (!mounted) return;
      setState(() => _isFavorite = favorited);
      if (favorited) {
        unawaited(AnalyticsService.trackFavorite(id));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFavorite = previous);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        tooltip: AppLocalizations.of(context)!.favoriteAction,
        onPressed: _busy ? null : _toggle,
        icon: Icon(
          _isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 20,
          color: _isFavorite ? AppColors.brandOrange : widget.idleColor,
        ),
      ),
    );
  }
}
