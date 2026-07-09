part of 'global_listing_card.dart';

/// Title / price / mileage block shared by grid and horizontal list listing cards.
Widget _buildGlobalCarCardInnerText(
  BuildContext context,
  Map car, {
  required String brandId,
  required String trimLine,
  required String yearDisplay,
  required String mileageDisplay,
  required String cityLine,
  required Color titleTextColor,
  required Color dividerLineColor,
  required Color metaTextColor,
  bool pinBottomMeta = false,
  bool listLayout = false,
}) {
  final bool compact = listLayout || AppResponsive.isCompactPhone(context);
  // Keep the title box height stable (prevents card overflows), but render the
  // brand+model text larger so it has stronger hierarchy than trim.
  final double titleBoxFontSize = compact ? 13 : 15;
  final double titleFontSize = compact ? 14 : 17;
  final double yearFontSize = compact ? 13 : 16;
  final double priceFontSize = compact ? 16 : 20;
  final double metaFontSize = compact ? 11 : 13;
  final double trimFontSize = compact ? 12 : 15;
  const double titleLineHeight = 1.1;
  final int titleMaxLines = listLayout ? 1 : 2;
  final double reservedTitleHeight =
      titleBoxFontSize * titleLineHeight * titleMaxLines;
  final double sectionGap = compact ? 4.0 : 6.0;
  final double blockGap = compact ? 6.0 : 8.0;
  final bool hasTrim = trimLine.isNotEmpty;
  final bool hasPrice = tryParseCurrencyValue(car['price']) != null;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: pinBottomMeta ? MainAxisSize.max : MainAxisSize.min,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final double maxW = constraints.maxWidth;
          final double logoSize =
              maxW < 130 ? 20 : (maxW < 150 ? 22 : (maxW < 175 ? 24 : 28));
          final double logoInner = logoSize - 4;
          final double gap = maxW < 150 ? 4 : (maxW < 175 ? 6 : 8);
          final double effectiveTitleFontSize = maxW < 130
              ? 13
              : (maxW < 150
                  ? 14
                  : (maxW < 175 ? 15 : titleFontSize));

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (car['brand'] != null && car['brand'].toString().isNotEmpty)
                SizedBox(
                  width: logoSize,
                  height: logoSize,
                  child: Container(
                    width: logoSize,
                    height: logoSize,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: null,
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
              SizedBox(width: gap),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    height: reservedTitleHeight,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AutoSizeText(
                        localizedCarTitleForCard(context, car),
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
                        overflow: TextOverflow.clip,
                        softWrap: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      SizedBox(height: blockGap),
      Visibility(
        visible: hasTrim,
        maintainAnimation: true,
        maintainSize: true,
        maintainState: true,
        child: Text(
          trimLine,
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(color: metaTextColor, fontSize: trimFontSize, height: 1.1),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      SizedBox(height: sectionGap),
      Visibility(
        visible: hasTrim,
        maintainAnimation: true,
        maintainSize: true,
        maintainState: true,
        child: Divider(height: 1, thickness: 1, color: dividerLineColor),
      ),
      SizedBox(height: sectionGap),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 1,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: yearDisplay.isNotEmpty
                  ? Text(
                      yearDisplay,
                      textScaler: const TextScaler.linear(1.0),
                      style: TextStyle(
                        color: metaTextColor,
                        fontSize: yearFontSize,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      softWrap: false,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: hasPrice
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        formatCurrency(context, car['price']),
                        textScaler: const TextScaler.linear(1.0),
                        style: TextStyle(
                          color: Color(0xFFFF6B00),
                          fontWeight: FontWeight.w600,
                          fontSize: priceFontSize,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        textAlign: TextAlign.end,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
      if (pinBottomMeta) const Spacer(),
      if (mileageDisplay.isNotEmpty || cityLine.isNotEmpty) ...[
        SizedBox(height: sectionGap),
        Divider(height: 1, thickness: 1, color: dividerLineColor),
        SizedBox(height: sectionGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 1,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: mileageDisplay.isNotEmpty
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          mileageDisplay,
                          textScaler: const TextScaler.linear(1.0),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: TextStyle(color: metaTextColor, fontSize: metaFontSize),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (mileageDisplay.isNotEmpty && cityLine.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
                child: Center(
                  child: Container(
                    width: 1,
                    height: 12,
                    color: metaTextColor.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
            if (cityLine.isNotEmpty)
              Expanded(
                flex: 1,
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_city,
                            size: compact ? 10 : 12,
                            color: metaTextColor,
                          ),
                          SizedBox(width: compact ? 2 : 4),
                          Text(
                            cityLine,
                            textScaler: const TextScaler.linear(1.0),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: metaTextColor,
                              fontSize: metaFontSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ],
  );
}
