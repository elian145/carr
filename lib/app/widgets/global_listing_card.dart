import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/brand_logo_filenames.dart';
import '../../data/car_name_translations.dart';
import '../../l10n/app_localizations.dart';
import '../../services/recently_viewed_service.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/listings/listing_card_data.dart' as listing_card_data;
import '../../shared/listings/listing_card_media.dart';
import '../../shared/listings/listing_status.dart';
import '../../shared/listings/listing_sold_badge.dart';
import '../../shared/media/media_url.dart';
import '../../shared/text/pretty_title_case.dart';
import '../../theme_provider.dart';
import '../app_api_base.dart';
import 'listing_network_image.dart';

/// Localized car title for cards: brand + model (translated), no trim, no year.
String localizedCarTitleForCard(BuildContext context, Map car) {
  final title = CarNameTranslations.getLocalizedCarTitleNoYear(
    context,
    Map<String, dynamic>.from(car),
  );
  final raw = title.isEmpty ? (car['title']?.toString() ?? '') : title;
  return prettyTitleCase(raw);
}

/// Trim line for listing cards (under brand+model, above price). Empty if none / base.
String localizedTrimForCard(BuildContext context, Map car) {
  final trim = car['trim']?.toString().trim();
  if (trim == null || trim.isEmpty) return '';
  if (trim.toLowerCase() == 'base') return '';
  return translateListingValue(context, trim) ?? trim;
}

/// Normalizes API listing / favorite payloads into the shape expected by [buildGlobalCarCard].
Map<String, dynamic> mapListingToGlobalCarCardData(
  BuildContext context,
  Map<String, dynamic> listing,
) =>
    listing_card_data.mapListingToGlobalCarCardData(context, listing);

/// Video count pill used on global listing cards (grid + list layout).
Widget _globalListingCardVideoCountBadge(Map car) {
  return Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.videocam, color: Colors.white, size: 16),
        const SizedBox(width: 4),
        Text(
          '${(car['videos'] as List).length}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

/// Title / price / mileage block shared by grid and horizontal list listing cards.
Widget _buildGlobalCarCardInnerText(
  BuildContext context,
  Map car, {
  required String brandId,
  required String trimLine,
  required String yearDisplay,
  required String mileageDisplay,
  required String cityLine,
  required Color dividerLineColor,
  required Color metaTextColor,
  bool pinBottomMeta = false,
}) {
  // Keep the title box height stable (prevents card overflows), but render the
  // brand+model text larger so it has stronger hierarchy than trim.
  const double titleBoxFontSize = 15;
  const double titleFontSize = 17;
  const double titleLineHeight = 1.1;
  const int titleMaxLines = 2;
  final double reservedTitleHeight =
      titleBoxFontSize * titleLineHeight * titleMaxLines;
  final bool hasTrim = trimLine.isNotEmpty;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: pinBottomMeta ? MainAxisSize.max : MainAxisSize.min,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final double maxW = constraints.maxWidth;
          final double logoSize = maxW < 150 ? 22 : (maxW < 175 ? 24 : 28);
          final double logoInner = logoSize - 4;
          final double gap = maxW < 150 ? 6 : 8;
          final double effectiveTitleFontSize =
              maxW < 150 ? 15 : (maxW < 175 ? 16 : titleFontSize);

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
                          color: Color(0xFFFF6B00),
                          fontSize: effectiveTitleFontSize,
                          height: titleLineHeight,
                        ),
                        maxLines: titleMaxLines,
                        minFontSize: 12,
                        stepGranularity: 0.5,
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
      const SizedBox(height: 10),
      Visibility(
        visible: hasTrim,
        maintainAnimation: true,
        maintainSize: true,
        maintainState: true,
        child: Text(
          trimLine,
          textScaler: const TextScaler.linear(1.0),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFFF6B00),
            fontSize: 15,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
      const SizedBox(height: 6),
      Visibility(
        visible: hasTrim,
        maintainAnimation: true,
        maintainSize: true,
        maintainState: true,
        child: Divider(height: 1, thickness: 1, color: dividerLineColor),
      ),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              yearDisplay.isNotEmpty
                  ? yearDisplay
                  : formatCurrency(context, car['price']),
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                color: Color(0xFFFF6B00),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (yearDisplay.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  formatCurrency(context, car['price']),
                  textScaler: const TextScaler.linear(1.0),
                  style: TextStyle(
                    color: Color(0xFFFF6B00),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          ],
        ],
      ),
      if (pinBottomMeta) const Spacer(),
      if (mileageDisplay.isNotEmpty || cityLine.isNotEmpty) ...[
        const SizedBox(height: 6),
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
                          style: TextStyle(
                            color: metaTextColor,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (mileageDisplay.isNotEmpty && cityLine.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                            size: 12,
                            color: metaTextColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cityLine,
                            textScaler: const TextScaler.linear(1.0),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: metaTextColor,
                              fontSize: 13,
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
      : const EdgeInsets.fromLTRB(12, 8, 12, 10);

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
              : Column(
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
                      height: quickSell ? 120 : 170,
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
                    // Content section (year/mileage + city below price — in flow, no overlap)
                    Expanded(
                      child: wrapCardTextTap(
                        Padding(
                          padding: listingCardTextPadding,
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
                  ],
                );

  return Container(
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
  );
}

// Global image carousel for consistency
Widget _buildGlobalCardImageCarousel(
  BuildContext context,
  Map car, {
  int carouselResetSeed = 0,
  bool enableDetailTap = true,
}) {
  final slots = ListingCardMedia.collectFromCar(
    car,
    resolveNetworkUrl: buildLegacyFullImageUrl,
  );

  if (slots.isEmpty) {
    return Container(
      color: Colors.grey[900],
      width: double.infinity,
      child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
    );
  }

  int currentIndex = 0;
  const int kMaxVisibleDots = 6;
  int dotWindowStart = 0;
  bool dotWindowForward = true;

  return StatefulBuilder(
    key: ValueKey(
      'global_card_carousel_${car['id'] ?? car['draftId'] ?? ''}_$carouselResetSeed',
    ),
    builder: (context, setState) {
      int computeDotStart(int index) {
        final int visible =
            slots.length < kMaxVisibleDots ? slots.length : kMaxVisibleDots;
        if (visible <= 0 || slots.length <= visible) return 0;
        final int maxStart = (slots.length - visible).clamp(0, slots.length);
        return (index - (visible - 1)).clamp(0, maxStart);
      }

      final pageView = PageView.builder(
        onPageChanged: (i) {
          setState(() {
            currentIndex = i;
            final nextStart = computeDotStart(i);
            if (nextStart != dotWindowStart) {
              dotWindowForward = nextStart > dotWindowStart;
              dotWindowStart = nextStart;
            }
          });
        },
        itemCount: slots.length,
        itemBuilder: (context, i) {
          return ListingCardMedia.buildCarouselImage(
            slots[i],
            networkBuilder: listingNetworkImage,
            fit: BoxFit.cover,
          );
        },
      );

      final carId = (car['id'] ?? '').toString().trim();
      final Widget pager = enableDetailTap && carId.isNotEmpty
          ? GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/car_detail',
                  arguments: {'carId': carId},
                );
              },
              child: pageView,
            )
          : pageView;

      return Stack(
        fit: StackFit.expand,
        children: [
          pager,
          if (slots.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: () {
                  final int visible = slots.length < kMaxVisibleDots
                      ? slots.length
                      : kMaxVisibleDots;
                  if (visible <= 1) return const SizedBox.shrink();

                  Widget buildDotRow(int startIndex) {
                    return Row(
                      key: ValueKey<int>(startIndex),
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(visible, (j) {
                        final i = startIndex + j;
                        final active = i == currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 8 : 6,
                          height: active ? 8 : 6,
                          decoration: BoxDecoration(
                            color: active ? Colors.white : Colors.white70,
                            shape: BoxShape.circle,
                          ),
                        );
                      }),
                    );
                  }

                  final start = dotWindowStart.clamp(
                    0,
                    (slots.length - visible).clamp(0, slots.length),
                  );

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      final beginX = dotWindowForward ? 1.0 : -1.0;
                      final slide = Tween<Offset>(
                        begin: Offset(beginX, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      final fade = Tween<double>(begin: 0, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      );
                      return ClipRect(
                        child: SlideTransition(
                          position: slide,
                          child: FadeTransition(opacity: fade, child: child),
                        ),
                      );
                    },
                    child: buildDotRow(start),
                  );
                }(),
              ),
            ),
        ],
      );
    },
  );
}
