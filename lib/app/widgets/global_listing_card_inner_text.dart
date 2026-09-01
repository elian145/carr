part of 'global_listing_card.dart';

/// Price badge metrics scaled to the listing card's text-row width.
///
/// Narrow 2-column tiles get a smaller orange pill; wider grid cards grow
/// toward the full size. [footerHeight] matches padding + type so the row
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
  bool listLayout = false,
}) {
  if (listLayout) {
    // Horizontal list cards: slightly smaller than grid, but still readable.
    final double t = ((rowWidth - 110) / 70).clamp(0.0, 1.0);
    final double fontSize = hasPrice ? 12.0 + 2.5 * t : 10.5 + 2.0 * t;
    final double horizontalPadding = hasPrice ? 5.5 + 3.5 * t : 4.5 + 3.0 * t;
    final double verticalPadding = 3.0 + 2.0 * t;
    final double radius = 6.5 + 1.5 * t;
    final double footerHeight =
        (verticalPadding * 2 + fontSize + 1.5).clamp(22.0, 28.0);

    return _ListingPriceBadgeStyle(
      fontSize: fontSize,
      horizontalPadding: horizontalPadding,
      verticalPadding: verticalPadding,
      radius: radius,
      footerHeight: footerHeight,
    );
  }

  // ~148px text width → smallest badge, ~204px → full size.
  final double t = ((rowWidth - 148) / 56).clamp(0.0, 1.0);

  final double fontSize = hasPrice ? 14.0 + 3.0 * t : 11.5 + 2.5 * t;
  final double horizontalPadding =
      hasPrice ? 6.5 + 4.5 * t : 5.0 + 3.5 * t;
  final double verticalPadding = 4.0 + 3.0 * t;
  final double radius = 7.0 + 2.0 * t;
  // +1.5 slack covers font metric rounding inside the fixed footer slot.
  final double footerHeight =
      (verticalPadding * 2 + fontSize + 1.5).clamp(24.0, 34.0);

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
  // 1.28 line height keeps Arabic/Kurdish descenders from clipping in the
  // fixed two-line slot (1.12 was too tight with forceStrutHeight).
  const double titleFontSize = 15;
  const double titleLineHeight = 1.28;
  const int titleMaxLines = 2;
  const double logoSize = 24;
  const double logoPad = 4.0;
  const double logoTitleGap = 6.0;
  final double titleLineBoxHeight = titleFontSize * titleLineHeight;
  // +2px slack covers font metric rounding on the second line.
  final double reservedTitleHeight = titleLineBoxHeight * titleMaxLines + 2;
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

  /// Spec chip that always hugs its label. Do not put a FittedBox inside a
  /// Flexible — that expands the pill to the flex share while shrinking text,
  /// leaving empty space to the right (common on Android).
  Widget infoChip(String value, {Color? color}) {
    final double chipFont = compact ? 11.0 : 13.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        // Matches year/mileage chip height: font + (compact ? 10 : 12).
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFF4F4F4)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        value,
        textDirection: textDirection,
        textAlign: TextAlign.start,
        textScaler: const TextScaler.linear(1.0),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: color ?? titleTextColor,
          fontSize: chipFont,
          fontWeight: FontWeight.w500,
          height: 1,
        ),
      ),
    );
  }

  /// Year / mileage chips: soft accent tint + icon so specs feel less flat.
  /// Always hugs its label — never stretches into a wide empty pill.
  /// Height matches [infoChip] so engine/trim and year/mileage rows align.
  Widget yearMileageChip(
    String value, {
    required IconData icon,
    required double fontSize,
  }) {
    final double iconSize = (fontSize * 0.92).clamp(10.0, 14.0);
    final double iconGap = compact ? 3.0 : 3.5;
    final double hPad = (fontSize * 0.42).clamp(4.0, 7.0);
    final double chipFont = compact ? 11.0 : 13.0;
    final double chipHeight = chipFont + (compact ? 10.0 : 12.0);
    const TextDirection chipDir = TextDirection.ltr;

    return Container(
      height: chipHeight,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      alignment: Alignment.center,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: priceAccent),
          SizedBox(width: iconGap),
          Text(
            value,
            textDirection: chipDir,
            textAlign: TextAlign.left,
            textScaler: const TextScaler.linear(1.0),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: isLight ? const Color(0xFF3A3A3A) : Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  double _yearMileageChipWidth(String value, double fontSize) {
    final double iconSize = (fontSize * 0.92).clamp(10.0, 14.0);
    final double iconGap = compact ? 3.0 : 3.5;
    final double hPad = (fontSize * 0.42).clamp(4.0, 7.0);
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1,
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    final textW = painter.width;
    painter.dispose();
    return iconSize + iconGap + textW + hPad * 2 + 2;
  }

  /// Year + mileage at one shared type size. Font is chosen as if mileage were
  /// a 6-digit odometer so short values stay the same type size as long ones.
  /// Chips always hug their labels (never a wide empty mileage pill).
  Widget matchedYearMileageRow() {
    final double gap = compact ? 4.0 : 6.0;
    final Alignment align =
        isRtl ? Alignment.centerRight : Alignment.centerLeft;
    // Prefer a readable size; grow when the row has room, floor when tight.
    // Cap at the info-chip type size so year/mileage pills match engine/trim.
    final double minFont = compact ? 10.0 : 11.0;
    final double maxFont = compact ? 11.0 : 13.0;
    // Reference long mileage (6 digits + unit) so short odometers do not get a
    // larger type size than cards with 5+ digit mileages.
    final String mileageUnit = AppLocalizations.of(context)!.unit_km;
    final String referenceMileageDisplay =
        '${localizeDigits(context, decimalFormatterForLocale(context).format(999999))} $mileageUnit';

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool bounded =
            constraints.maxWidth.isFinite &&
            constraints.maxWidth < double.infinity;
        final double maxW = bounded ? constraints.maxWidth : double.infinity;

        double mileageWidthForSizing(double fontSize) {
          if (mileageDisplay.isEmpty) return 0;
          final actual = _yearMileageChipWidth(mileageDisplay, fontSize);
          final reference =
              _yearMileageChipWidth(referenceMileageDisplay, fontSize);
          return actual > reference ? actual : reference;
        }

        double rowWidthAt(double fontSize) {
          double total = 0;
          if (yearDisplay.isNotEmpty) {
            total += _yearMileageChipWidth(yearDisplay, fontSize);
          }
          if (yearDisplay.isNotEmpty && mileageDisplay.isNotEmpty) {
            total += gap;
          }
          total += mileageWidthForSizing(fontSize);
          return total;
        }

        // Actual rendered row may be narrower than the sizing probe when
        // mileage is short — only scale the painted chips if they overflow.
        double paintedRowWidthAt(double fontSize) {
          double total = 0;
          if (yearDisplay.isNotEmpty) {
            total += _yearMileageChipWidth(yearDisplay, fontSize);
          }
          if (yearDisplay.isNotEmpty && mileageDisplay.isNotEmpty) {
            total += gap;
          }
          if (mileageDisplay.isNotEmpty) {
            total += _yearMileageChipWidth(mileageDisplay, fontSize);
          }
          return total;
        }

        double fontSize = maxFont;
        if (bounded) {
          // Largest shared size that would fit year + a long mileage.
          fontSize = minFont;
          for (double fs = maxFont; fs >= minFont - 0.001; fs -= 0.25) {
            if (rowWidthAt(fs) <= maxW) {
              fontSize = fs;
              break;
            }
          }
          // Even the floor is too wide — keep floor and scale the pair together.
          if (rowWidthAt(minFont) > maxW) {
            fontSize = minFont;
          }
        }

        final chips = Row(
          textDirection: textDirection,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (yearDisplay.isNotEmpty)
              yearMileageChip(
                yearDisplay,
                icon: Icons.calendar_today_rounded,
                fontSize: fontSize,
              ),
            if (yearDisplay.isNotEmpty && mileageDisplay.isNotEmpty)
              SizedBox(width: gap),
            if (mileageDisplay.isNotEmpty)
              yearMileageChip(
                mileageDisplay,
                icon: Icons.speed_rounded,
                fontSize: fontSize,
              ),
          ],
        );

        if (!bounded) {
          return Align(alignment: align, child: chips);
        }

        final bool needsScale = paintedRowWidthAt(fontSize) > maxW;
        return Align(
          alignment: align,
          child: needsScale
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: align,
                    child: chips,
                  ),
                )
              : chips,
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
  final Alignment trimAlign =
      isRtl ? Alignment.centerRight : Alignment.centerLeft;
  // Intrinsic chips first; scale the whole row only when it overflows so a long
  // trim can use leftover width instead of shrinking inside a wide empty pill.
  final Widget trimBlock = Padding(
    padding: EdgeInsets.only(top: blockGap),
    child: Transform.translate(
      offset: Offset(leadingShift, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chips = Row(
            textDirection: textDirection,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (engineLine.isNotEmpty)
                infoChip(engineLine, color: metaTextColor),
              if (engineLine.isNotEmpty && trimLine.isNotEmpty)
                SizedBox(width: compact ? 4 : 6),
              if (trimLine.isNotEmpty)
                infoChip(trimLine, color: metaTextColor),
            ],
          );
          return Align(
            alignment: trimAlign,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: trimAlign,
                child: chips,
              ),
            ),
          );
        },
      ),
    ),
  );

  final bool hasSpecs = yearDisplay.isNotEmpty || mileageDisplay.isNotEmpty;
  final Widget yearPriceBlock = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(height: sectionGap),
      // Same leadingShift as title/trim so year lines up with those chips.
      Transform.translate(
        offset: Offset(leadingShift, 0),
        child: matchedYearMileageRow(),
      ),
    ],
  );

  final Widget mileageCityRow = LayoutBuilder(
    builder: (context, constraints) {
      final priceStyle = _listingPriceBadgeStyle(
        rowWidth: constraints.maxWidth,
        hasPrice: hasPrice,
      );
      // Long prices need most of the footer; city can scale down.
      final double maxPriceWidth =
          constraints.maxWidth * (hasPrice ? 0.72 : 0.52);
      final priceTextStyle = TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: priceStyle.fontSize,
        height: 1,
      );
      final pricePainter = TextPainter(
        text: TextSpan(text: priceText, style: priceTextStyle),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      )..layout(minWidth: 0, maxWidth: double.infinity);
      final priceTextW = pricePainter.width;
      pricePainter.dispose();
      final priceNeeded =
          priceTextW + priceStyle.horizontalPadding * 2;
      final bool priceNeedsShrink = priceNeeded > maxPriceWidth;

      final Widget priceBadge = Transform.translate(
        offset: Offset(trailingShift, 0),
        child: Container(
          width: priceNeedsShrink ? maxPriceWidth : null,
          padding: EdgeInsets.symmetric(
            horizontal: priceStyle.horizontalPadding,
            vertical: priceStyle.verticalPadding,
          ),
          decoration: BoxDecoration(
            color: priceAccent,
            borderRadius: BorderRadius.circular(priceStyle.radius),
          ),
          // LTR + scaleDown: full amount stays visible; short prices still hug.
          child: priceNeedsShrink
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    priceText,
                    textDirection: TextDirection.ltr,
                    textScaler: const TextScaler.linear(1.0),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: priceTextStyle,
                  ),
                )
              : Text(
                  priceText,
                  textDirection: TextDirection.ltr,
                  textScaler: const TextScaler.linear(1.0),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: priceTextStyle,
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
  final bool compact = AppResponsive.isCompactPhone(context);
  final double chipFontSize = compact ? 11.0 : 13.0;
  final double sharedChipHeight = chipFontSize + (compact ? 10.0 : 12.0);
  final inheritedTextDirection = Directionality.of(context);
  final languageCode = Localizations.localeOf(context).languageCode;
  final bool isRtl =
      inheritedTextDirection == TextDirection.rtl ||
      languageCode == 'ar' ||
      languageCode == 'ku';
  final textDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;
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
            height: 1.28,
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
    final textStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: style.fontSize,
      height: 1,
    );

    final label = Text(
      priceText,
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(1.0),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: textStyle,
    );

    return Container(
      constraints: maxWidth != null && maxWidth.isFinite
          ? BoxConstraints(maxWidth: maxWidth)
          : null,
      padding: EdgeInsets.symmetric(
        horizontal: style.horizontalPadding,
        vertical: style.verticalPadding,
      ),
      decoration: BoxDecoration(
        color: priceAccent,
        borderRadius: BorderRadius.circular(style.radius),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: label,
      ),
    );
  }

  Widget infoChip(Widget child) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        // Matches year/mileage chip height: font + (compact ? 10 : 12).
        vertical: compact ? 5 : 6,
      ),
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
    required double fontSize,
  }) {
    final double iconSize = (fontSize * 0.92).clamp(10.0, 14.0);
    final double iconGap = compact ? 3.0 : 3.5;
    final double hPad = (fontSize * 0.42).clamp(4.0, 7.0);
    const TextDirection chipDir = TextDirection.ltr;

    return Container(
      height: sharedChipHeight,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      alignment: Alignment.center,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: priceAccent),
          SizedBox(width: iconGap),
          Text(
            value,
            textDirection: chipDir,
            textAlign: TextAlign.left,
            textScaler: const TextScaler.linear(1.0),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: isLight ? const Color(0xFF3A3A3A) : Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  double _yearMileageChipWidth(String value, double fontSize) {
    final double iconSize = (fontSize * 0.92).clamp(10.0, 14.0);
    final double iconGap = compact ? 3.0 : 3.5;
    final double hPad = (fontSize * 0.42).clamp(4.0, 7.0);
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1,
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    final textW = painter.width;
    painter.dispose();
    return iconSize + iconGap + textW + hPad * 2 + 2;
  }

  final Alignment specsAlign =
      isRtl ? Alignment.centerRight : Alignment.centerLeft;
  final Widget specsRow = LayoutBuilder(
    builder: (context, constraints) {
      final double gap = compact ? 4.0 : 6.0;
      final double minFont = compact ? 10.0 : 11.0;
      final double maxFont = chipFontSize;
      final bool bounded =
          constraints.maxWidth.isFinite &&
          constraints.maxWidth < double.infinity;
      final double maxW = bounded ? constraints.maxWidth : double.infinity;
      // Size type as if mileage were 6 digits so short values match long ones.
      final String mileageUnit = AppLocalizations.of(context)!.unit_km;
      final String referenceMileageDisplay =
          '${localizeDigits(context, decimalFormatterForLocale(context).format(999999))} $mileageUnit';

      double mileageWidthForSizing(double fontSize) {
        final actual = _yearMileageChipWidth(mileageText, fontSize);
        final reference =
            _yearMileageChipWidth(referenceMileageDisplay, fontSize);
        return actual > reference ? actual : reference;
      }

      double rowWidthAt(double fontSize) {
        return _yearMileageChipWidth(yearText, fontSize) +
            gap +
            mileageWidthForSizing(fontSize);
      }

      double fontSize = maxFont;
      if (bounded) {
        fontSize = minFont;
        for (double fs = maxFont; fs >= minFont - 0.001; fs -= 0.25) {
          if (rowWidthAt(fs) <= maxW) {
            fontSize = fs;
            break;
          }
        }
        if (rowWidthAt(minFont) > maxW) {
          fontSize = minFont;
        }
      }

      final chips = Row(
        textDirection: textDirection,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          yearMileageChip(
            yearText,
            icon: Icons.calendar_today_rounded,
            fontSize: fontSize,
          ),
          SizedBox(width: gap),
          yearMileageChip(
            mileageText,
            icon: Icons.speed_rounded,
            fontSize: fontSize,
          ),
        ],
      );

      if (!bounded) {
        return Align(alignment: specsAlign, child: chips);
      }

      return Align(
        alignment: specsAlign,
        child: SizedBox(
          width: maxW,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: specsAlign,
            child: chips,
          ),
        ),
      );
    },
  );

  Widget detailChipText(String value, Color color) {
    return Text(
      value,
      textDirection: textDirection,
      textScaler: const TextScaler.linear(1.0),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: color,
        fontSize: chipFontSize,
        fontWeight: FontWeight.w500,
        height: 1,
      ),
    );
  }

  final Alignment detailAlign =
      isRtl ? Alignment.centerRight : Alignment.centerLeft;
  // Same as grid: hug labels at full size; only scale the row if it overflows.
  final Widget engineTrimRow = LayoutBuilder(
    builder: (context, constraints) {
      final chips = Row(
        textDirection: textDirection,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasEngine)
            infoChip(detailChipText(engineLine, metaTextColor)),
          if (hasEngine && hasTrim) const SizedBox(width: 6),
          if (hasTrim) infoChip(detailChipText(trimLine, metaTextColor)),
        ],
      );
      return Align(
        alignment: detailAlign,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: detailAlign,
            child: chips,
          ),
        ),
      );
    },
  );

  final Widget priceRow = LayoutBuilder(
    builder: (context, constraints) {
      final priceStyle = _listingPriceBadgeStyle(
        rowWidth: constraints.maxWidth,
        hasPrice: hasPrice,
        listLayout: true,
      );
      final double maxPriceWidth =
          constraints.maxWidth * (hasPrice ? 0.64 : 0.48);
      return SizedBox(
        height: priceStyle.footerHeight,
        child: Row(
          textDirection: textDirection,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment:
                    isRtl ? Alignment.centerRight : Alignment.centerLeft,
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
                      overflow: TextOverflow.ellipsis,
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
            const SizedBox(width: 6),
            buildPriceBadge(
              maxWidth: maxPriceWidth,
              style: priceStyle,
            ),
          ],
        ),
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
                  height: 1.28,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment:
                    isRtl ? Alignment.centerRight : Alignment.centerLeft,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Transform.translate(
                    offset: const Offset(0, -2),
                    child: engineTrimRow,
                  ),
                ),
              );
            },
          ),
        ),
      ],
      Expanded(
        flex: 3,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Align(
              alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Transform.translate(
                  offset: const Offset(0, -2),
                  child: specsRow,
                ),
              ),
            );
          },
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
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.loginRequired),
          action: SnackBarAction(
            label: loc.loginAction,
            onPressed: () => Navigator.pushNamed(context, '/login'),
          ),
        ),
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFavorite = previous);
      final is401 = e is ApiException && e.statusCode == 401;
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            is401 ? loc.loginRequired : userErrorText(context, e, fallback: loc.error),
          ),
        ),
      );
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
