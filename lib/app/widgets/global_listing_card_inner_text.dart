part of 'global_listing_card.dart';

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
  /// Pass [constrainWidth] for the mileage chip so long values scale down inside
  /// the remaining row width; the chip still hugs short values.
  Widget yearMileageChip(
    String value, {
    required IconData icon,
    bool constrainWidth = false,
  }) {
    final textStyle = TextStyle(
      color: isLight ? const Color(0xFF3A3A3A) : Colors.white,
      fontSize: compact ? 12 : 12.5,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: 0.1,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool canConstrain =
            constrainWidth &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth < double.infinity;
        final label = Text(
          value,
          textDirection: textDirection,
          textAlign: TextAlign.start,
          textScaler: const TextScaler.linear(1.0),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: textStyle,
        );
        final chip = Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 7,
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
            textDirection: textDirection,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 11 : 12, color: priceAccent),
              SizedBox(width: compact ? 3 : 4),
              if (canConstrain)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: isRtl
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: label,
                  ),
                )
              else
                label,
            ],
          ),
        );
        if (!canConstrain) return chip;
        return Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: chip,
          ),
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
  final Widget yearPriceBlock = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(height: sectionGap),
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
              Flexible(
                child: yearMileageChip(
                  mileageDisplay,
                  icon: Icons.speed_rounded,
                  constrainWidth: true,
                ),
              ),
          ],
        ),
      ),
    ],
  );

  final Widget mileageCityRow = SizedBox(
    // Leave a little room under padding + label so fractional rounding never
    // paints a bottom-overflow stripe on compact phones.
    height: compact ? 26.0 : 30.0,
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Keep enough room for the city; long price labels shrink instead.
        final double maxPriceWidth =
            constraints.maxWidth * (hasPrice ? 0.62 : 0.52);
        final Widget priceBadge = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxPriceWidth),
          child: Transform.translate(
            offset: Offset(trailingShift, 0),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? (hasPrice ? 7 : 6) : (hasPrice ? 10 : 8),
                vertical: compact ? 5 : 7,
              ),
              decoration: BoxDecoration(
                color: priceAccent,
                borderRadius: BorderRadius.circular(8),
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
                  fontSize: compact
                      ? (hasPrice ? 13 : 11)
                      : (hasPrice ? 15 : 13),
                  height: 1,
                ),
              ),
            ),
          ),
        );

        return Row(
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
        );
      },
    ),
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

  Widget buildPriceBadge({double? maxWidth}) {
    Widget badge = Container(
      padding: EdgeInsets.symmetric(horizontal: hasPrice ? 12 : 8, vertical: 7),
      decoration: BoxDecoration(
        color: priceAccent,
        borderRadius: BorderRadius.circular(9),
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
          fontSize: hasPrice ? 16 : 13,
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
    final textStyle = TextStyle(
      color: isLight ? const Color(0xFF3A3A3A) : Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: 0.1,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool canConstrain =
            constrainWidth &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth < double.infinity;
        final label = Text(
          value,
          textScaler: const TextScaler.linear(1.0),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: textStyle,
        );
        final chip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
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
            textDirection: textDirection,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: priceAccent),
              const SizedBox(width: 4),
              if (canConstrain)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: isRtl
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: label,
                  ),
                )
              else
                label,
            ],
          ),
        );
        if (!canConstrain) return chip;
        return Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: chip,
          ),
        );
      },
    );
  }

  final Widget specsRow = Row(
    textDirection: textDirection,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      yearMileageChip(yearText, icon: Icons.calendar_today_rounded),
      const SizedBox(width: 6),
      Flexible(
        child: yearMileageChip(
          mileageText,
          icon: Icons.speed_rounded,
          constrainWidth: true,
        ),
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
            child: buildPriceBadge(maxWidth: maxPriceWidth),
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
