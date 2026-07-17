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
  final design = listLayout
      ? ListingLayoutPrefs.horizontalCardDesign
      : ListingLayoutPrefs.gridCardDesign;
  return ValueListenableBuilder<int>(
    valueListenable: design,
    builder: (context, value, _) => _buildGlobalCarCardForDesign(
      context,
      car,
      listLayout: listLayout,
      design: value,
      carouselResetSeed: carouselResetSeed,
      onCardTap: onCardTap,
      allowOwnerManagementOnOpen: allowOwnerManagementOnOpen,
    ),
  );
}

Widget _buildGlobalCarCardForDesign(
  BuildContext context,
  Map car, {
  required bool listLayout,
  required int design,
  required int carouselResetSeed,
  required VoidCallback? onCardTap,
  required bool allowOwnerManagementOnOpen,
}) {
  final preset = _cardPreset(listLayout, design);
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
  final languageCode = Localizations.localeOf(context).languageCode;
  final literSeparator = languageCode == 'ar' || languageCode == 'ku'
      ? ' '
      : '';
  String? firstCardValue(Map source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value == null || value is Map || value is Iterable) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  final engineKeys = const [
    'engine_size',
    'engine_size_liters',
    'engine_size_l',
    'engineSize',
    'engineSizeLiters',
    'engine',
  ];
  String? engineRaw = firstCardValue(car, engineKeys);
  if (engineRaw == null) {
    final specsRaw = car['specs'] ?? car['spec'] ?? car['details'];
    if (specsRaw is Map) {
      engineRaw = firstCardValue(specsRaw, engineKeys);
    }
  }
  String engineLine = '';
  if (engineRaw != null) {
    final numericEngine = RegExp(
      r'^(\d+(?:\.\d+)?)\s*(?:l|liters?)?$',
      caseSensitive: false,
    ).firstMatch(engineRaw);
    if (numericEngine != null) {
      final liters = double.tryParse(numericEngine.group(1)!);
      if (liters != null && liters > 0) {
        engineLine =
            '${localizeDigits(context, liters.toStringAsFixed(1))}$literSeparator${locCard.unit_liter_suffix}';
      }
    }
    if (engineLine.isEmpty) {
      engineLine = localizeDigits(
        context,
        translateListingValue(context, engineRaw) ?? engineRaw,
      );
    }
  }
  if (engineLine.isEmpty) {
    final fallbackRaw = firstCardValue(car, const [
      'fuel_type',
      'engine_type',
      'drive_type',
      'drivetrain',
      'transmission',
      'body_type',
    ]);
    if (fallbackRaw != null) {
      engineLine = translateListingValue(context, fallbackRaw) ?? fallbackRaw;
    }
  }
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
  // White shell lets the grey specification chips read clearly in light mode.
  final cardFill = isLight
      ? Colors.white
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
      ? EdgeInsets.fromLTRB(design == 1 ? 10 : 9, 7, 8, design == 1 ? 0 : 7)
      : EdgeInsets.fromLTRB(design == 1 ? 12 : 10, 8, design == 1 ? 12 : 10, 6);

  Widget wrapCardTextTap(Widget child) {
    if (onCardTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onCardTap, child: child),
    );
  }

  Widget buildCardText({required bool horizontal}) {
    if (design == 1) {
      return _buildGlobalCarCardInnerText(
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
        listLayout: horizontal,
      );
    }
    return _buildPresetCardText(
      context,
      car,
      preset: preset,
      brandId: brandId,
      trimLine: trimLine,
      engineLine: engineLine,
      yearDisplay: yearDisplay,
      mileageDisplay: mileageDisplay,
      cityLine: cityLine,
      titleColor: titleTextColor,
      metaColor: metaTextColor,
      listLayout: horizontal,
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
                textDirection: preset.imageTrailing
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: preset.imageFlex,
                    child: ClipRRect(
                      borderRadius: BorderRadius.zero,
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
                          Positioned(
                            top: 8,
                            left: 8,
                            child: _globalListingCardPhotoCountBadge(
                              ListingCardMedia.collectFromCar(
                                car,
                                resolveNetworkUrl: buildLegacyFullImageUrl,
                              ).length,
                            ),
                          ),
                          if (showVideoCountBadge)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: _globalListingCardVideoCountBadge(car),
                            ),
                          if (sold)
                            Center(
                              child: buildListingSoldBadge(
                                context,
                                large: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 12 - preset.imageFlex,
                    child: LayoutBuilder(
                      builder: (context, textConstraints) {
                        final pad = listingCardTextPadding;
                        final contentW =
                            (textConstraints.maxWidth - pad.horizontal).clamp(
                              0.0,
                              double.infinity,
                            );
                        final contentH =
                            (textConstraints.maxHeight - pad.vertical).clamp(
                              0.0,
                              double.infinity,
                            );
                        return wrapCardTextTap(
                          Padding(
                            padding: pad,
                            child: SizedBox(
                              width: contentW,
                              height: contentH,
                              // Fill the text column: title stays at the top,
                              // mileage/city at the bottom (no vertical centering
                              // that leaves empty bands on taller phones).
                              child: buildCardText(horizontal: true),
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
            // Keep enough white space for a two-line title without scaling
            // the specification chips and footer down.
            final textReserve = AppResponsive.isCompactPhone(context)
                ? 140.0
                : 152.0;
            final maxImage = (constraints.maxHeight - bannerH - textReserve)
                .clamp(quickSell ? 100.0 : 120.0, 190.0);
            final baseImageH = AppResponsive.listingGridImageHeight(
              context,
              quickSell: quickSell,
              maxHeight: maxImage,
              cardWidth: constraints.maxWidth,
            );
            final imageH = (baseImageH * preset.imageScale).clamp(
              78.0,
              maxImage,
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
                        if (sold)
                          Center(
                            child: buildListingSoldBadge(context, large: true),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, textBox) {
                      final pad = listingCardTextPadding;
                      final contentW = (textBox.maxWidth - pad.horizontal)
                          .clamp(0.0, double.infinity);
                      final contentH = (textBox.maxHeight - pad.vertical).clamp(
                        0.0,
                        double.infinity,
                      );
                      return Padding(
                        padding: pad,
                        child: SizedBox(
                          width: contentW,
                          height: contentH,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: contentW,
                              child: wrapCardTextTap(
                                buildCardText(horizontal: false),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );

  final titleForA11y = localizedCarTitleForCard(context, car);
  final shellRadius = design == 1 ? (listLayout ? 14.0 : 20.0) : preset.radius;
  Widget cardShell = Container(
    decoration: BoxDecoration(
      color: cardFill,
      borderRadius: BorderRadius.circular(shellRadius),
      border: design == 1 || preset.borderWidth == 0
          ? null
          : Border.all(
              color: preset.accent.withValues(alpha: 0.55),
              width: preset.borderWidth,
            ),
      boxShadow: featured
          ? null
          : preset.elevation <= 0
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: listLayout ? 0.17 : 0.2),
                blurRadius: design == 1
                    ? (listLayout ? 16 : 8)
                    : preset.elevation,
                spreadRadius: listLayout ? 0.5 : 0,
                offset: Offset(0, preset.elevation > 12 ? 7 : 4),
              ),
            ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(shellRadius),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (onCardTap == null)
            InkWell(
              borderRadius: BorderRadius.circular(shellRadius),
              onTap: onPublishedCardTap,
              child: design > 1 && preset.accentEdge
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        border: BorderDirectional(
                          start: BorderSide(color: preset.accent, width: 4),
                        ),
                      ),
                      child: cardInner,
                    )
                  : cardInner,
            )
          else
            design > 1 && preset.accentEdge
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(color: preset.accent, width: 4),
                      ),
                    ),
                    child: cardInner,
                  )
                : cardInner,
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
              child: buildListingFeaturedBadge(context, compact: listLayout),
            ),
        ],
      ),
    ),
  );

  if (featured) {
    cardShell = wrapListingFeaturedGlow(child: cardShell, radius: shellRadius);
  }

  return Semantics(
    button: true,
    label: titleForA11y.isEmpty ? locCard.navHome : titleForA11y,
    child: cardShell,
  );
}
