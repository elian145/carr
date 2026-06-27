part of 'global_listing_card.dart';

// Global car card building function to ensure consistency across all pages
Widget buildGlobalCarCard(
  BuildContext context,
  Map car, {
  bool listLayout = false,
  int carouselResetSeed = 0,
  VoidCallback? onCardTap,
}) {
  final brand = car['brand'] ?? '';
  final brandId =
      brandLogoFilenames[brand] ??
      brand
          .toString()
          .toLowerCase()
          .replaceAll(' ', '-')
          .replaceAll('Ã©', 'e')
          .replaceAll('Ã¶', 'o');
  final trimLine = localizedTrimForCard(context, car);
  final bool quickSell =
      car['is_quick_sell'] == true || car['is_quick_sell'] == 'true';
  final bool sold = isListingSold(Map<String, dynamic>.from(car));
  final String yearRaw = (car['year'] ?? '').toString().trim();
  final String mileageRaw = (car['mileage'] ?? '').toString().trim();
  String? cityRaw;
  for (final key in const ['city', 'location', 'city_name']) {
    final v = car[key];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) {
      cityRaw = s;
      break;
    }
  }
  final String cityLine = cityRaw == null || cityRaw.isEmpty
      ? ''
      : (translateListingValue(context, cityRaw) ?? cityRaw).trim();
  final locCard = AppLocalizations.of(context)!;
  final String yearDisplay = yearRaw.isEmpty
      ? ''
      : localizeDigits(context, yearRaw);
  final num? mileageNum = mileageRaw.isEmpty
      ? null
      : num.tryParse(mileageRaw.replaceAll(RegExp(r'[^0-9.]'), ''));
  final String mileageDisplay = mileageRaw.isEmpty
      ? ''
      : '${localizeDigits(context, mileageNum == null ? mileageRaw : decimalFormatterForLocale(context).format(mileageNum))} ${locCard.unit_km}';

  final isLight = Theme.of(context).brightness == Brightness.light;
  // On dark shell: true frosted overlay. On light shell: solid blend so color matches dark mode.
  final cardFill = isLight
      ? AppThemes.listingCardFillGridOnLightShell()
      : Colors.white.withValues(alpha: 0.10);
  final metaTextColor = Colors.white70;
  final dividerLineColor = Colors.white24;
  final bool showVideoCountBadge =
      car['videos'] != null && (car['videos'] as List).isNotEmpty;
  final EdgeInsets listingCardTextPadding = listLayout
      // Horizontal cards: keep top tighter so title sits higher; keep a bit of bottom room.
      ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
      : const EdgeInsets.fromLTRB(12, 8, 12, 6);

  Widget wrapCardTextTap(Widget child) {
    if (onCardTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCardTap,
        child: child,
      ),
    );
  }

  void onPublishedCardTap() {
    final carId = (car['id'] ?? '').toString().trim();
    if (carId.isEmpty) return;
    unawaited(
      RecentlyViewedService.recordView(
        carId,
        snapshot: Map<String, dynamic>.from(car),
      ),
    );
    Navigator.pushNamed(
      context,
      '/car_detail',
      arguments: {'carId': carId},
    );
  }

  final Widget cardInner = listLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    if (car['is_quick_sell'] == true ||
                        car['is_quick_sell'] == 'true')
                      Container(
                        width: double.infinity,
                        height: 35,
                        padding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.orange, Colors.deepOrange],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.flash_on, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'QUICK SELL',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 4,
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(
                                  (car['is_quick_sell'] == true ||
                                          car['is_quick_sell'] == 'true')
                                      ? 0
                                      : 20,
                                ),
                                bottomLeft: const Radius.circular(20),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildGlobalCardImageCarousel(
                                    context,
                                    car,
                                    carouselResetSeed: carouselResetSeed,
                                    enableDetailTap: onCardTap == null,
                                  ),
                                  if (showVideoCountBadge)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: _globalListingCardVideoCountBadge(
                                        car,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 6,
                            child: wrapCardTextTap(
                              Padding(
                                padding: listingCardTextPadding,
                                child: SizedBox(
                                  width: double.infinity,
                                  height: double.infinity,
                                  child: _buildGlobalCarCardInnerText(
                                    context,
                                    car,
                                    brandId: brandId,
                                    trimLine: trimLine,
                                    yearDisplay: yearDisplay,
                                    mileageDisplay: mileageDisplay,
                                    cityLine: cityLine,
                                    dividerLineColor: dividerLineColor,
                                    metaTextColor: metaTextColor,
                                    pinBottomMeta: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final bannerH = quickSell ? 35.0 : 0.0;
                    const textReserve = 136.0;
                    final maxImage = (constraints.maxHeight - bannerH - textReserve)
                        .clamp(quickSell ? 100.0 : 120.0, 190.0);
                    final imageH = AppResponsive.listingGridImageHeight(
                      context,
                      quickSell: quickSell,
                      maxHeight: maxImage,
                    );

                    return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Quick Sell Banner (conditional height)
                    if (car['is_quick_sell'] == true ||
                        car['is_quick_sell'] == 'true')
                      Container(
                        width: double.infinity,
                        height: 35, // Fixed height for banner
                        padding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.orange, Colors.deepOrange],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.flash_on, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'QUICK SELL',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Image section
                    SizedBox(
                      height: imageH,
                      child: ClipRRect(
                        borderRadius: BorderRadius.vertical(
                          top:
                              (car['is_quick_sell'] == true ||
                                      car['is_quick_sell'] == 'true')
                                  ? Radius.zero
                                  : Radius.circular(20),
                          bottom: Radius.zero,
                        ),
                        child: _buildGlobalCardImageCarousel(
                          context,
                          car,
                          carouselResetSeed: carouselResetSeed,
                          enableDetailTap: onCardTap == null,
                        ),
                      ),
                    ),
                    // Content section sits directly under the image (no spacer gap).
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: Padding(
                              padding: listingCardTextPadding,
                              child: wrapCardTextTap(
                                _buildGlobalCarCardInnerText(
                                  context,
                                  car,
                                  brandId: brandId,
                                  trimLine: trimLine,
                                  yearDisplay: yearDisplay,
                                  mileageDisplay: mileageDisplay,
                                  cityLine: cityLine,
                                  dividerLineColor: dividerLineColor,
                                  metaTextColor: metaTextColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
                  },
                );

  final titleForA11y = localizedCarTitleForCard(context, car);
  return Semantics(
    button: true,
    label: titleForA11y.isEmpty ? locCard.navHome : titleForA11y,
    child: Container(
    decoration: BoxDecoration(
      color: cardFill,
      borderRadius: BorderRadius.circular(20),
      border: null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (onCardTap == null)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onPublishedCardTap,
            child: cardInner,
          )
        else
          cardInner,
        if (!listLayout && showVideoCountBadge)
          Positioned(
            top: 12,
            right: 12,
            child: _globalListingCardVideoCountBadge(car),
          ),
        if (sold)
          Positioned(
            top: listLayout ? 8 : 12,
            left: listLayout ? 8 : 12,
            child: buildListingSoldBadge(context),
          ),
      ],
    ),
    ),
  );
}
