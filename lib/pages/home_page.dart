import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../globals.dart';
import '../data/car_name_translations.dart';
import '../l10n/app_localizations.dart';
import '../theme_provider.dart';
import '../services/api_service.dart';
import '../services/config.dart';
import '../shared/media/media_url.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/text/pretty_title_case.dart';

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

Widget _buildGlobalCardImageCarousel(BuildContext context, Map<String, dynamic> car) {
  final List<String> urls = () {
    final List<String> u = [];
    final String primary = (car['image_url'] ?? '').toString();
    final List<dynamic> imgs = (car['images'] is List) ? (car['images'] as List) : const [];
    if (primary.isNotEmpty) {
      u.add(buildMediaUrl(primary));
    }
    for (final dynamic it in imgs) {
      String s;
      if (it is Map) {
        s = (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '').toString();
      } else {
        s = it.toString();
      }
      if (s.isNotEmpty) {
        final full = buildMediaUrl(s);
        if (!u.contains(full)) u.add(full);
      }
    }
    if (u.isEmpty && imgs.isNotEmpty) {
      final dynamic first = imgs.first;
      final String s = first is Map
          ? (first['image_url'] ?? first['url'] ?? first['path'] ?? first['src'] ?? '').toString()
          : first.toString();
      if (s.isNotEmpty) u.add(buildMediaUrl(s));
    }
    return u;
  }();

  if (urls.isEmpty) {
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
    builder: (context, setState) {
      int computeDotStart(int index) {
        final int visible = urls.length < kMaxVisibleDots ? urls.length : kMaxVisibleDots;
        if (visible <= 0 || urls.length <= visible) return 0;
        final int maxStart = (urls.length - visible).clamp(0, urls.length);
        return (index - (visible - 1)).clamp(0, maxStart);
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(
                context,
                '/car_detail',
                arguments: {'carId': listingPrimaryId(car)},
              );
            },
            child: PageView.builder(
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
              itemCount: urls.length,
              itemBuilder: (context, i) {
                final url = urls[i];
                return _listingNetworkImage(url);
              },
            ),
          ),
          if (urls.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: () {
                  final int visible = urls.length < kMaxVisibleDots ? urls.length : kMaxVisibleDots;
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
                    (urls.length - visible).clamp(0, urls.length),
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

Widget buildGlobalCarCard(
  BuildContext context,
  Map<String, dynamic> car, {
  bool listLayout = false,
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
          onTap: () {
            final String carId = listingPrimaryId(car);
            if (carId.isEmpty) return;
            Navigator.pushNamed(
              context,
              '/car_detail',
              arguments: {'carId': carId},
            );
          },
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
                                  _buildGlobalCardImageCarousel(context, car),
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
                        child: _buildGlobalCardImageCarousel(context, car),
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin<HomePage> {
  final ScrollController _controller = ScrollController();

  final List<Map<String, dynamic>> _cars = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  String? _error;

  static const int _perPage = 20;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _controller.addListener(() {
      if (!_hasNext || _loadingMore || _loading) return;
      final pos = _controller.position;
      if (pos.pixels >= (pos.maxScrollExtent - 500)) {
        _loadMore();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetch(refresh: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasNext = true;
        _cars.clear();
      });
    } else {
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }

    try {
      final data = await ApiService.getCars(page: _page, perPage: _perPage);

      final dynamic rawCars = (data['cars'] ?? data);
      final List<dynamic> list = rawCars is List ? rawCars : const <dynamic>[];
      final newCars = list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .toList();

      bool hasNext = false;
      final dynamic pagination = data['pagination'];
      if (pagination is Map && pagination['has_next'] is bool) {
        hasNext = pagination['has_next'] as bool;
      } else {
        hasNext = newCars.length >= _perPage;
      }

      if (!mounted) return;
      setState(() {
        _cars.addAll(newCars);
        _hasNext = hasNext;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback:
              AppLocalizations.of(context)?.failedToLoadListings ??
              'Failed to load listings',
        );
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext) return;
    _page += 1;
    await _fetch(refresh: false);
  }

  Widget _carImage(Map<String, dynamic> car) {
    final primary = (car['image_url'] ?? '').toString();
    final url = buildMediaUrl(primary);
    if (url.isEmpty) {
      return Container(
        color: Colors.black12,
        child: const Center(child: Icon(Icons.directions_car)),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.black12,
          child: const Center(child: Icon(Icons.broken_image)),
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black12,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final loc = AppLocalizations.of(context);
    final title = (loc?.appTitle ?? 'CARZO').toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: loc?.sellTitle ?? 'Sell',
            onPressed: () => Navigator.pushNamed(context, '/sell'),
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: loc?.favoritesTitle ?? 'Favorites',
            onPressed: () => Navigator.pushNamed(context, '/favorites'),
            icon: const Icon(Icons.favorite_border),
          ),
          IconButton(
            tooltip: loc?.profileTitle ?? 'Profile',
            onPressed: () => Navigator.pushNamed(context, '/profile'),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetch(refresh: true),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_cars.isEmpty && _error != null)
                ? ListView(
                    children: [
                      const SizedBox(height: 40),
                      Center(
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: OutlinedButton(
                          onPressed: () => _fetch(refresh: true),
                          child: Text(loc?.retryAction ?? 'Retry'),
                        ),
                      ),
                    ],
                  )
                : (_cars.isEmpty)
                    ? ListView(
                        children: [
                          const SizedBox(height: 40),
                          Center(
                            child: Text(
                              loc?.noListingsYet ?? 'No listings yet',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: OutlinedButton(
                              onPressed: () => _fetch(refresh: true),
                              child: Text(loc?.retryAction ?? 'Retry'),
                            ),
                          ),
                        ],
                      )
                : GridView.builder(
                    controller: _controller,
                    key: const PageStorageKey<String>('home_grid'),
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _cars.length + (_hasNext ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _cars.length) {
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }

                      final car = _cars[index];
                      final carId = listingPrimaryId(car);
                      final carTitle = _localizedCarTitleForCard(context, car);
                      final price = (car['price'] ?? '').toString();
                      final location = (car['location'] ?? '').toString();
                      final year = (car['year'] ?? '').toString();

                      final isLight =
                          Theme.of(context).brightness == Brightness.light;
                      return InkWell(
                        onTap: () {
                          if (carId.isEmpty) return;
                          Navigator.pushNamed(
                            context,
                            '/car_detail',
                            arguments: {'carId': carId},
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isLight
                                ? AppThemes.listingCardFillGridOnLightShell()
                                : Colors.white.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AspectRatio(
                                aspectRatio: 16 / 10,
                                child: _carImage(car),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        height: 34,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  carTitle.isEmpty
                                                      ? (loc?.carLabel ?? 'Car')
                                                      : carTitle,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: isLight
                                                        ? const Color(0xFFFF6B00)
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurface,
                                                    fontSize: 15,
                                                    height: 1.1,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (price.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                price,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: isLight
                                                      ? const Color(0xFFFF6B00)
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .onSurface,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        [location]
                                            .where((s) => s.isNotEmpty)
                                            .join(' • '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: isLight ? Colors.white70 : null,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

