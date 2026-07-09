part of 'global_listing_card.dart';

// Global car card building function to ensure consistency across all pages
Widget buildGlobalCarCard(
  BuildContext context,
  Map car, {
  bool listLayout = false,
  int carouselResetSeed = 0,
  VoidCallback? onCardTap,
  bool allowOwnerManagementOnOpen = false,
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
  final bool featured = listingIsFeatured(car);
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
  // On dark shell: true frosted overlay. On light shell: pale grey card.
  final cardFill = isLight
      ? AppThemes.listingCardFillGridOnLightShell()
      : Colors.white.withValues(alpha: 0.10);
  final titleTextColor = isLight
      ? Theme.of(context).colorScheme.onSurface
      : Colors.white;
  final metaTextColor = isLight
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : Colors.white70;
  final dividerLineColor = isLight
      ? Theme.of(context).colorScheme.outlineVariant
      : Colors.white24;
  final bool showVideoCountBadge =
      car['videos'] != null && (car['videos'] as List).isNotEmpty;
  final EdgeInsets listingCardTextPadding = listLayout
      // Horizontal cards: tighter padding so title + specs fit without bottom overflow.
      ? const EdgeInsets.fromLTRB(8, 6, 8, 4)
      : const EdgeInsets.fromLTRB(12, 8, 12, 6);

  Widget wrapCardTextTap(Widget child) {
    if (onCardTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onCardTap, child: child),
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
      arguments: {
        'carId': carId,
        if (allowOwnerManagementOnOpen) 'allowOwnerManagement': true,
      },
    );
  }

  final Widget cardInner = listLayout
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            if (car['is_quick_sell'] == true || car['is_quick_sell'] == 'true')
              Container(
                width: double.infinity,
                height: 35,
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange, Colors.deepOrange],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    flex: AppResponsive.isCompactPhone(context) ? 3 : 4,
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
                            allowOwnerManagementOnOpen:
                                allowOwnerManagementOnOpen,
                          ),
                          if (showVideoCountBadge)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: _globalListingCardVideoCountBadge(car),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: AppResponsive.isCompactPhone(context) ? 7 : 6,
                    child: LayoutBuilder(
                      builder: (context, textConstraints) {
                        return wrapCardTextTap(
                          Padding(
                            padding: listingCardTextPadding,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: textConstraints.maxWidth,
                                  child: _buildGlobalCarCardInnerText(
                                    context,
                                    car,
                                    brandId: brandId,
                                    trimLine: trimLine,
                                    yearDisplay: yearDisplay,
                                    mileageDisplay: mileageDisplay,
                                    cityLine: cityLine,
                                    titleTextColor: titleTextColor,
                                    dividerLineColor: dividerLineColor,
                                    metaTextColor: metaTextColor,
                                    listLayout: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
            final textReserve = AppResponsive.isCompactPhone(context)
                ? 118.0
                : 136.0;
            final maxImage = (constraints.maxHeight - bannerH - textReserve)
                .clamp(quickSell ? 100.0 : 120.0, 190.0);
            final imageH = AppResponsive.listingGridImageHeight(
              context,
              quickSell: quickSell,
              maxHeight: maxImage,
              cardWidth: constraints.maxWidth,
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
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                      allowOwnerManagementOnOpen: allowOwnerManagementOnOpen,
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
                              titleTextColor: titleTextColor,
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
  Widget cardShell = Container(
    decoration: BoxDecoration(
      color: cardFill,
      borderRadius: BorderRadius.circular(20),
      border: null,
      boxShadow: featured
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
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
          if (featured)
            Positioned(
              top: listLayout ? 8 : 10,
              left: listLayout ? 8 : 10,
              child: buildListingFeaturedBadge(
                context,
                compact: listLayout,
              ),
            ),
          if (sold)
            Positioned(
              top: listLayout
                  ? (featured ? 36 : 8)
                  : (featured ? 42 : 12),
              left: listLayout ? 8 : 12,
              child: buildListingSoldBadge(context),
            ),
        ],
      ),
    ),
  );

  if (featured) {
    cardShell = wrapListingFeaturedGlow(child: cardShell, radius: 20);
  }

  return Semantics(
    button: true,
    label: titleForA11y.isEmpty ? locCard.navHome : titleForA11y,
    child: cardShell,
  );
}
