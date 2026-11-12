part of 'global_listing_card.dart';

// Global car card building function to ensure consistency across all pages
Widget buildGlobalCarCard(
  BuildContext context,
  Map car, {
  bool listLayout = false,
  int carouselResetSeed = 0,
  VoidCallback? onCardTap,
  bool allowOwnerManagementOnOpen = false,
  bool enableImageCarousel = true,
}) => _buildGlobalCarCard(
  context,
  car,
  listLayout: listLayout,
  carouselResetSeed: carouselResetSeed,
  onCardTap: onCardTap,
  allowOwnerManagementOnOpen: allowOwnerManagementOnOpen,
  enableImageCarousel: enableImageCarousel,
);

Widget _buildGlobalCarCard(
  BuildContext context,
  Map car, {
  required bool listLayout,
  required int carouselResetSeed,
  required VoidCallback? onCardTap,
  required bool allowOwnerManagementOnOpen,
  required bool enableImageCarousel,
}) {
  final brand = car['brand'] ?? '';
  final brandId = brandLogoSlug(brand.toString());
  final trimLine = localizedTrimForCard(context, car);
  final bool sold = isListingSold(Map<String, dynamic>.from(car));
  final Widget? statusBadge = buildListingStatusBadge(
    context,
    Map<String, dynamic>.from(car),
    large: true,
  );
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
      ? const EdgeInsets.fromLTRB(10, 7, 8, 0)
      // Tight, fixed top inset so image→logo gap matches on iOS and Android.
      : const EdgeInsets.fromLTRB(12, 6, 12, 6);

  Widget wrapCardTextTap(Widget child) {
    if (onCardTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onCardTap, child: child),
    );
  }

  Widget buildCardText({required bool horizontal, BuildContext? withContext}) {
    return _buildGlobalCarCardInnerText(
      withContext ?? context,
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
            Expanded(
              child: LayoutBuilder(
                builder: (context, rowConstraints) {
                  final imageWidth = AppResponsive.listingHorizontalImageWidth(
                    context,
                    cardWidth: rowConstraints.maxWidth,
                    cardHeight: rowConstraints.maxHeight,
                  );
                  return Row(
                    textDirection: TextDirection.ltr,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: imageWidth,
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
                                enableSwipeCarousel: enableImageCarousel,
                              ),
                              if (showVideoCountBadge)
                                PositionedDirectional(
                                  top: 8,
                                  end: 8,
                                  child: _globalListingCardVideoCountBadge(car),
                                ),
                              if (sold)
                                Center(
                                  child: buildListingSoldBadge(
                                    context,
                                    large: true,
                                  ),
                                )
                              else if (statusBadge != null)
                                Center(child: statusBadge),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, textConstraints) {
                            final pad = listingCardTextPadding;
                            final contentW =
                                (textConstraints.maxWidth - pad.horizontal)
                                    .clamp(0.0, double.infinity);
                            final contentH =
                                (textConstraints.maxHeight - pad.vertical)
                                    .clamp(0.0, double.infinity);
                            return wrapCardTextTap(
                              Padding(
                                padding: pad,
                                child: SizedBox(
                                  width: contentW,
                                  height: contentH,
                                  // The card height is fixed, so its text only
                                  // follows the system size as far as that
                                  // height can hold (see
                                  // ListingLayoutPrefs.rectCardTextScale).
                                  child: _rectCardTextScope(
                                    context,
                                    cardHeight: textConstraints.maxHeight,
                                    builder: (scoped) => buildCardText(
                                      horizontal: true,
                                      withContext: scoped,
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
              ),
            ),
          ],
        )
      : LayoutBuilder(
          builder: (context, constraints) {
            // Room for two-line title + trim chips + specs + footer; keep a few
            // px slack so Arabic metrics don't clip on some devices.
            // The text block grows with the system text scale (the grid cell
            // does too, see ListingLayoutPrefs.gridChildAspectRatioForWidth).
            final textReserve = ListingLayoutPrefs.gridCardTextBlockHeightAt(
              appTextScaleOf(context),
              compact: AppResponsive.isCompactPhone(context),
            );
            // Prefer a shorter image over stealing from the text block — the
            // preferred 120px floor must not win when the card is short.
            final availableForImage = constraints.maxHeight - textReserve;
            final maxImage = availableForImage.clamp(78.0, 230.0);
            final baseImageH = AppResponsive.listingGridImageHeight(
              context,
              maxHeight: maxImage,
              cardWidth: constraints.maxWidth,
            );
            final imageH = baseImageH.clamp(78.0, maxImage);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                // Image section
                SizedBox(
                  height: imageH,
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
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
                          enableSwipeCarousel: enableImageCarousel,
                        ),
                        if (sold)
                          Center(
                            child: buildListingSoldBadge(context, large: true),
                          )
                        else if (statusBadge != null)
                          Center(child: statusBadge),
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
                          child: wrapCardTextTap(
                            buildCardText(horizontal: false),
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
  final shellRadius = listLayout ? 14.0 : 20.0;
  Widget cardShell = Container(
    decoration: BoxDecoration(
      color: cardFill,
      borderRadius: BorderRadius.circular(shellRadius),
      border: null,
      boxShadow: featured
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: listLayout ? 0.17 : 0.2),
                blurRadius: listLayout ? 16 : 8,
                spreadRadius: listLayout ? 0.5 : 0,
                offset: const Offset(0, 4),
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
              child: cardInner,
            )
          else
            cardInner,
          if (!listLayout && showVideoCountBadge)
            PositionedDirectional(
              top: 12,
              end: 12,
              child: _globalListingCardVideoCountBadge(car),
            ),
          if (featured)
            PositionedDirectional(
              top: listLayout ? 8 : 10,
              start: listLayout ? 8 : 10,
              child: buildListingFeaturedBadge(context, compact: listLayout),
            ),
        ],
      ),
    ),
  );

  if (featured) {
    cardShell = wrapListingFeaturedGlow(child: cardShell, radius: shellRadius);
  }

  // The rectangular card keeps a fixed height, so a long title can end in an
  // ellipsis at larger text sizes: a long press shows it in full. The tooltip
  // only listens for a long press (taps, scrolling and the favourite button
  // are untouched) and is hidden from accessibility, whose description of the
  // card already carries the whole title, engine, year, mileage, city and
  // price. The details page shows everything in full.
  final Widget semanticChild = listLayout && titleForA11y.isNotEmpty
      ? Tooltip(
          message: titleForA11y,
          triggerMode: TooltipTriggerMode.longPress,
          excludeFromSemantics: true,
          child: cardShell,
        )
      : cardShell;

  return RepaintBoundary(
    child: Semantics(
      button: true,
      label: titleForA11y.isEmpty ? locCard.navHome : titleForA11y,
      child: semanticChild,
    ),
  );
}

/// Lays out the rectangular card's text column at the text scale its FIXED
/// height can hold: the system size up to
/// [ListingLayoutPrefs.rectCardTextScale] (~1.5x Pro Max, ~1.3x 393 dp,
/// ~1.15-1.2x 360 dp and below). One scaler for the whole column keeps the
/// title, chips, year/mileage and city consistent. [builder] receives a
/// context under that scaler, so `appTextScaleOf` and every `Text` agree.
Widget _rectCardTextScope(
  BuildContext context, {
  required double cardHeight,
  required Widget Function(BuildContext scoped) builder,
}) {
  final ts = appTextScaleOf(context);
  final capped = ListingLayoutPrefs.rectCardTextScale(
    cardHeight: cardHeight,
    compact: AppResponsive.isCompactPhone(context),
    textScale: ts,
  );
  if (!(ts > 1.0) || capped >= ts) return Builder(builder: builder);
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(capped)),
    child: Builder(builder: builder),
  );
}
