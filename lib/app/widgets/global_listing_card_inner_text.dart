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
  final double titleBoxFontSize = compact ? 13 : 15;
  final double titleFontSize = compact ? 14 : 17;
  const double titleLineHeight = 1.12;
  const int titleMaxLines = 2;
  final double reservedTitleHeight =
      titleBoxFontSize * titleLineHeight * titleMaxLines;
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
  final bool isArabic = languageCode == 'ar';
  final double trailingShift = isArabic ? -3 : (isRtl ? -6 : 6);
  final double footerShiftY = compact ? 1 : 2;
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

  final Widget titleBlock = LayoutBuilder(
    builder: (context, constraints) {
      final double maxW = constraints.maxWidth;
      final double logoSize = maxW < 130
          ? 20
          : (maxW < 150 ? 22 : (maxW < 175 ? 24 : 28));
      const double logoPad = 4.0;
      final double logoInner = logoSize - (logoPad * 2);
      final double gap = maxW < 150 ? 4 : (maxW < 175 ? 6 : 8);
      final double effectiveTitleFontSize = maxW < 130
          ? 13
          : (maxW < 150 ? 14 : (maxW < 175 ? 15 : titleFontSize));
      final bool showLogo =
          car['brand'] != null && car['brand'].toString().trim().isNotEmpty;
      final String titleText = localizedCarTitleForCard(context, car);
      final double titleMaxWidth = (maxW - (showLogo ? logoSize + gap : 0))
          .clamp(0.0, double.infinity);
      final titleProbe = TextPainter(
        text: TextSpan(
          text: titleText,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: effectiveTitleFontSize,
            height: titleLineHeight,
          ),
        ),
        maxLines: 1,
        textDirection: textDirection,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: titleMaxWidth);
      final bool titleIsSingleLine = !titleProbe.didExceedMaxLines;
      final double titleRowHeight = reservedTitleHeight > logoSize
          ? reservedTitleHeight
          : logoSize;

      return Transform.translate(
        offset: Offset(leadingShift, 0),
        child: Row(
          textDirection: textDirection,
          crossAxisAlignment: titleIsSingleLine
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
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
                  child: CachedNetworkImage(
                    imageUrl:
                        '${getApiBase()}/static/images/brands/$brandId.png',
                    placeholder: (context, url) => SizedBox(
                      width: logoInner,
                      height: logoInner,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.directions_car,
                      size: 20,
                      color: Color(0xFFFF6B00),
                    ),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            if (showLogo) SizedBox(width: gap),
            Expanded(
              child: SizedBox(
                height: titleRowHeight,
                child: Align(
                  alignment: titleIsSingleLine
                      ? (isRtl ? Alignment.centerRight : Alignment.centerLeft)
                      : (isRtl ? Alignment.topRight : Alignment.topLeft),
                  child: AutoSizeText(
                    titleText,
                    textDirection: textDirection,
                    textScaleFactor: 1.0,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: titleTextColor,
                      fontSize: effectiveTitleFontSize,
                      height: titleLineHeight,
                    ),
                    maxLines: titleMaxLines,
                    minFontSize: 8,
                    stepGranularity: 0.25,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
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
              infoChip(yearDisplay, color: metaTextColor),
            if (yearDisplay.isNotEmpty && mileageDisplay.isNotEmpty)
              SizedBox(width: compact ? 4 : 6),
            if (mileageDisplay.isNotEmpty)
              Flexible(child: infoChip(mileageDisplay, color: metaTextColor)),
          ],
        ),
      ),
    ],
  );

  final Widget mileageCityRow = SizedBox(
    height: compact ? 23.0 : 29.0,
    child: Row(
      textDirection: textDirection,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (cityLine.isNotEmpty)
          Expanded(
            child: Transform.translate(
              offset: Offset(leadingShift, footerShiftY),
              child: Row(
                textDirection: textDirection,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: priceAccent,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: isRtl
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (cityLine.isNotEmpty) const SizedBox.shrink(),
        if (cityLine.isEmpty) const Spacer(),
        Transform.translate(
          offset: Offset(trailingShift, footerShiftY),
          child: Transform.scale(
            scale: hasPrice ? 1 : 0.82,
            alignment: isRtl ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 7 : 10,
                vertical: compact ? 5 : 7,
              ),
              decoration: BoxDecoration(
                color: priceAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  priceText,
                  textScaler: const TextScaler.linear(1.0),
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 13 : 15,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      titleBlock,
      if (hasDetail) trimBlock,
      if (hasSpecs) yearPriceBlock,
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
          child: CachedNetworkImage(
            imageUrl: '${getApiBase()}/static/images/brands/$brandId.png',
            placeholder: (context, url) => const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            errorWidget: (context, url, error) =>
                const Icon(Icons.directions_car, size: 18, color: priceAccent),
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 6),
      ],
      Expanded(
        child: AutoSizeText(
          titleText,
          textDirection: textDirection,
          textScaleFactor: 1.0,
          textAlign: TextAlign.start,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: titleTextColor,
            fontSize: 15,
            height: 1.1,
          ),
          maxLines: 2,
          minFontSize: 11,
          stepGranularity: 0.25,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
      ),
      const SizedBox(width: 4),
      _ListingCardFavoriteButton(car: car, idleColor: priceAccent),
    ],
  );

  final Widget priceBadge = Transform.scale(
    scale: hasPrice ? 1 : 0.82,
    alignment: isRtl ? Alignment.centerLeft : Alignment.centerRight,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: priceAccent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          priceText,
          textScaler: const TextScaler.linear(1.0),
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            height: 1,
          ),
        ),
      ),
    ),
  );

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

  final Widget specsRow = Row(
    textDirection: textDirection,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      infoChip(
        Text(
          yearText,
          textScaler: const TextScaler.linear(1.0),
          maxLines: 1,
          style: TextStyle(
            color: metaTextColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: infoChip(
          Text(
            mileageText,
            textScaler: const TextScaler.linear(1.0),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: metaTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
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

  final Widget priceRow = Row(
    textDirection: textDirection,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Transform.translate(
          offset: Offset(leadingShift, 0),
          child: Row(
            textDirection: textDirection,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: priceAccent,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: isRtl
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Text(
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
                ),
              ),
            ],
          ),
        ),
      ),
      Transform.translate(offset: Offset(trailingShift, 0), child: priceBadge),
    ],
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
          color: _isFavorite ? const Color(0xFFFF6B00) : widget.idleColor,
        ),
      ),
    );
  }
}
