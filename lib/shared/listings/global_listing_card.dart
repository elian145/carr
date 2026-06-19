import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/car_name_translations.dart';
import '../../globals.dart';
import '../../l10n/app_localizations.dart';
import '../../services/config.dart';
import '../../services/recently_viewed_service.dart';
import '../../theme_provider.dart';
import '../listings/listing_card_media.dart';
import '../listings/listing_identity.dart';
import '../media/media_url.dart';
import '../text/pretty_title_case.dart';

String _normalizeBrandId(String brand) {
  return brand
      .trim()
      .toLowerCase()
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9\-]'), '');
}

String _localizedCarTitleForCard(BuildContext context, Map<String, dynamic> car) {
  final title = CarNameTranslations.getLocalizedCarTitleNoYear(context, car);
  final year = (car['year'] ?? '').toString().trim();
  final raw = [
    if (title.isNotEmpty) title else (car['title']?.toString() ?? '').trim(),
    if (year.isNotEmpty) year,
  ].join(' ').trim();
  return prettyTitleCase(raw);
}

String _localizedTrimForCard(BuildContext context, Map<String, dynamic> car) {
  final trim = (car['trim'] ?? '').toString().trim();
  if (trim.isEmpty) return '';
  if (trim.toLowerCase() == 'base') return '';
  return _translateValueGlobal(context, trim) ?? trim;
}

String? _translateValueGlobal(BuildContext context, String? raw) {
  if (raw == null) return null;
  final l = raw.trim().toLowerCase();
  final loc = AppLocalizations.of(context)!;
  switch (l) {
    case 'any':
      return loc.anyOption;
    case 'new':
      return loc.value_condition_new;
    case 'used':
      return loc.value_condition_used;
    case 'base':
    case 'standard':
      return loc.value_trim_base;
    case 'sport':
      return loc.value_trim_sport;
    case 'luxury':
      return loc.value_trim_luxury;
    case 'certified':
      return loc.value_condition_certified;
    case 'automatic':
      return loc.value_transmission_automatic;
    case 'manual':
      return loc.value_transmission_manual;
    case 'cvt':
      return loc.value_transmission_cvt;
    case 'semi-automatic':
    case 'semi automatic':
    case 'semi auto':
      return loc.value_transmission_semi_automatic;
    case 'front wheel drive':
    case 'fwd':
      return loc.value_drive_fwd;
    case 'rear wheel drive':
    case 'rwd':
      return loc.value_drive_rwd;
    case 'all wheel drive':
    case 'awd':
      return loc.value_drive_awd;
    case '4wd':
    case '4x4':
      return loc.value_drive_4wd;
    default:
      return raw;
  }
}

String _localizeDigitsGlobal(BuildContext context, String input) {
  final locale = Localizations.localeOf(context);
  if (locale.languageCode == 'ar' ||
      locale.languageCode == 'ku' ||
      locale.languageCode == 'ckb') {
    return input;
  }
  return input;
}

Widget _listingNetworkImage(String url) {
  return Image.network(
    url,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.low,
    errorBuilder: (context, error, stackTrace) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Icon(
            Icons.directions_car,
            size: 60,
            color: Colors.grey[400],
          ),
        ),
      );
    },
    loadingBuilder: (context, child, loadingProgress) {
      if (loadingProgress == null) return child;
      return Container(
        color: Colors.white10,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
            ),
          ),
        ),
      );
    },
  );
}

Widget _globalListingCardVideoCountBadge(Map<String, dynamic> car) {
  final videos = car['videos'];
  final count = videos is List ? videos.length : 0;
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
          '$count',
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

String _formatCurrencyGlobal(BuildContext context, dynamic raw) {
  final symbol = globalSymbol;
  num? value;
  if (raw is num) {
    value = raw;
  } else {
    value = num.tryParse(
      raw?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '',
    );
  }
  if (value == null) {
    return symbol;
  }
  return symbol + NumberFormat.decimalPattern().format(value);
}

Widget _buildGlobalCarCardInnerText(
  BuildContext context,
  Map<String, dynamic> car, {
  required String brandId,
  required String trimLine,
  required String yearDisplay,
  required String mileageDisplay,
  required String cityLine,
  required Color dividerLineColor,
  required Color metaTextColor,
  bool pinBottomMeta = false,
}) {
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
              if (brandId.isNotEmpty)
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
                    ),
                    child: CachedNetworkImage(
                      imageUrl: '${effectiveApiBase()}/static/images/brands/$brandId.png',
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
              if (brandId.isNotEmpty) SizedBox(width: gap),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    height: reservedTitleHeight,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AutoSizeText(
                        [
                          _localizedCarTitleForCard(context, car),
                          yearDisplay,
                        ].where((s) => s.isNotEmpty).join(' '),
                        textScaleFactor: 1.0,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFFF6B00),
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
                  : _formatCurrencyGlobal(context, car['price']),
              textScaler: const TextScaler.linear(1.0),
              style: const TextStyle(
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
                  _formatCurrencyGlobal(context, car['price']),
                  textScaler: const TextScaler.linear(1.0),
                  style: const TextStyle(
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
                    color: metaTextColor.withOpacity(0.35),
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

Widget _buildGlobalCardImageCarousel(
  BuildContext context,
  Map<String, dynamic> car, {
  int carouselResetSeed = 0,
  bool enableDetailTap = true,
}) {
  final slots = ListingCardMedia.collectFromCar(
    car,
    resolveNetworkUrl: buildMediaUrl,
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
        final int visible = slots.length < kMaxVisibleDots ? slots.length : kMaxVisibleDots;
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
            networkBuilder: (url, {BoxFit fit = BoxFit.cover}) =>
                _listingNetworkImage(url),
            fit: BoxFit.cover,
          );
        },
      );

      final carId = listingPrimaryId(car);
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
                  final int visible = slots.length < kMaxVisibleDots ? slots.length : kMaxVisibleDots;
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

/// Brand + model title for cards/comparison (no year).
String listingCardTitleNoYear(BuildContext context, Map<String, dynamic> car) {
  final title = CarNameTranslations.getLocalizedCarTitleNoYear(context, car);
  final raw = title.isEmpty ? (car['title']?.toString() ?? '') : title;
  return prettyTitleCase(raw.trim());
}

/// Trim line for listing cards. Empty if none / base.
String listingCardTrimLine(BuildContext context, Map<String, dynamic> car) {
  return _localizedTrimForCard(context, car);
}

/// Human-readable "time since listing was created" for card and detail UI.
String listingUploadedAgo(BuildContext context, Map<String, dynamic> car) {
  final loc = AppLocalizations.of(context);
  if (loc == null) return '';
  dynamic raw = car['created_at'];
  if (raw == null || raw.toString().trim().isEmpty) {
    raw = car['posted_at'] ?? car['listed_at'];
  }
  if (raw == null) return '';
  final dt = DateTime.tryParse(raw.toString().trim());
  if (dt == null) return '';
  final now = DateTime.now();
  var diff = now.difference(dt);
  if (diff.isNegative) diff = Duration.zero;
  if (diff.inMinutes < 1) return loc.justNow;
  if (diff.inHours < 24) {
    if (diff.inHours < 1) {
      return loc.timeMinutesAgo(diff.inMinutes < 1 ? 1 : diff.inMinutes);
    }
    return loc.timeHoursAgo(diff.inHours);
  }
  final days = diff.inDays;
  return loc.timeDaysAgo(days < 1 ? 1 : days);
}

/// Normalizes API listing / favorite payloads into the shape expected by [buildGlobalCarCard].
Map<String, dynamic> mapListingToGlobalCarCardData(
  BuildContext context,
  Map<String, dynamic> listing,
) {
  final String brand = (listing['brand'] ?? '').toString().trim();
  final String model = (listing['model'] ?? '').toString().trim();
  final String yearStr = (listing['year']?.toString() ?? '').trim();
  final String apiTitle = (listing['title'] ?? '').toString().trim();
  String displayTitle;
  if (apiTitle.isNotEmpty) {
    displayTitle = apiTitle;
  } else {
    final String base = [
      if (brand.isNotEmpty) prettyTitleCase(brand),
      if (model.isNotEmpty) prettyTitleCase(model),
    ].join(' ');
    displayTitle = yearStr.isNotEmpty ? ('$base ($yearStr)') : base;
  }
  displayTitle = prettyTitleCase(displayTitle);

  final num? mileageNum = () {
    final v = listing['mileage'];
    if (v == null) return null;
    if (v is num) return v;
    final s = v.toString().replaceAll(RegExp(r'[^0-9.-]'), '');
    return num.tryParse(s);
  }();
  final String mileageFormatted = mileageNum == null
      ? (listing['mileage']?.toString() ?? '')
      : NumberFormat.decimalPattern().format(mileageNum);

  final String carId =
      (listing['public_id'] ?? listing['id'] ?? listing['car_id'] ?? '')
          .toString();

  return {
    'id': carId,
    'brand': brand,
    'model': model,
    'trim': listing['trim'],
    'title': displayTitle,
    'price': listing['price'],
    'year': listing['year'],
    'mileage': mileageFormatted,
    'city': listing['city'] ?? listing['location'] ?? listing['city_name'],
    'image_url': listing['image_url'],
    'images': listing['images'],
    'videos': listing['videos'],
    'is_quick_sell': listing['is_quick_sell'] ?? false,
    'status': listing['status'],
    'created_at': listing['created_at'],
  };
}

Widget buildGlobalCarCard(
  BuildContext context,
  Map<String, dynamic> car, {
  bool listLayout = false,
  int carouselResetSeed = 0,
  VoidCallback? onCardTap,
}) {
  final brand = (car['brand'] ?? '').toString();
  final brandId = _normalizeBrandId(brand);
  final trimLine = _localizedTrimForCard(context, car);
  final bool quickSell =
      car['is_quick_sell'] == true || car['is_quick_sell'] == 'true';
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
      : (_translateValueGlobal(context, cityRaw) ?? cityRaw).trim();
  final locCard = AppLocalizations.of(context)!;
  final String yearDisplay = yearRaw.isEmpty
      ? ''
      : _localizeDigitsGlobal(context, yearRaw);
  final num? mileageNum = mileageRaw.isEmpty
      ? null
      : num.tryParse(mileageRaw.replaceAll(RegExp(r'[^0-9.]'), ''));
  final String mileageDisplay =
      mileageRaw.isEmpty
          ? ''
          : '${_localizeDigitsGlobal(context, mileageNum == null ? mileageRaw : NumberFormat.decimalPattern().format(mileageNum))} ${locCard.unit_km}';

  final isLight = Theme.of(context).brightness == Brightness.light;
  final cardFill = isLight
      ? AppThemes.listingCardFillGridOnLightShell()
      : Colors.white.withOpacity(0.10);
  final metaTextColor = Colors.white70;
  final dividerLineColor = Colors.white24;
  final bool showVideoCountBadge =
      car['videos'] is List && (car['videos'] as List).isNotEmpty;
  final EdgeInsets listingCardTextPadding = listLayout
      ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
      : const EdgeInsets.fromLTRB(12, 8, 12, 10);

  void onDefaultCardTap() {
    final String carId = listingPrimaryId(car);
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

  final VoidCallback cardTap = onCardTap ?? onDefaultCardTap;
  final bool enableCarouselDetailTap = onCardTap == null;

  return Container(
    decoration: BoxDecoration(
      color: cardFill,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: cardTap,
          child: listLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    if (quickSell)
                      Container(
                        width: double.infinity,
                        height: 35,
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.orange, Colors.deepOrange],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: const Row(
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
                                topLeft: Radius.circular(quickSell ? 0 : 20),
                                bottomLeft: const Radius.circular(20),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildGlobalCardImageCarousel(
                                    context,
                                    car,
                                    carouselResetSeed: carouselResetSeed,
                                    enableDetailTap: enableCarouselDetailTap,
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
                            flex: 6,
                            child: Padding(
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
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    if (quickSell)
                      Container(
                        width: double.infinity,
                        height: 35,
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.orange, Colors.deepOrange],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: const Row(
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
                    SizedBox(
                      height: quickSell ? 120 : 170,
                      child: ClipRRect(
                        borderRadius: BorderRadius.vertical(
                          top: quickSell ? Radius.zero : const Radius.circular(20),
                          bottom: Radius.zero,
                        ),
                        child: _buildGlobalCardImageCarousel(
                          context,
                          car,
                          carouselResetSeed: carouselResetSeed,
                          enableDetailTap: enableCarouselDetailTap,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
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
                  ],
                ),
        ),
        if (!listLayout && showVideoCountBadge)
          Positioned(
            top: 12,
            right: 12,
            child: _globalListingCardVideoCountBadge(car),
          ),
      ],
    ),
  );
}
