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
import '../shared/home/home_listings_fetch.dart';
import '../shared/home/home_filter_persistence.dart';
import '../shared/home/home_active_filter_chips.dart';
import '../shared/home/home_feed_toolbar.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../shared/shell/home_feed_scroll_persistence.dart';
import '../shared/shell/main_bottom_nav.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/listings/listing_card_media.dart';
import '../shared/media/media_url.dart';
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
    builder: (context, setState) {
      int computeDotStart(int index) {
        final int visible = slots.length < kMaxVisibleDots ? slots.length : kMaxVisibleDots;
        if (visible <= 0 || slots.length <= visible) return 0;
        final int maxStart = (slots.length - visible).clamp(0, slots.length);
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
              itemCount: slots.length,
              itemBuilder: (context, i) {
                return ListingCardMedia.buildCarouselImage(
                  slots[i],
                  networkBuilder: (url, {BoxFit fit = BoxFit.cover}) =>
                      _listingNetworkImage(url),
                  fit: BoxFit.cover,
                );
              },
            ),
          ),
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

  // Route replacement recreates Home; keep an in-memory snapshot for exact restore.
  static List<Map<String, dynamic>> _cacheCars = <Map<String, dynamic>>[];
  static bool _cacheHasNext = true;
  static int _cachePage = 1;
  static double _cacheOffset = 0;

  final List<Map<String, dynamic>> _cars = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  String? _error;
  int _activeFilterCount = 0;
  List<HomeActiveFilterChipSpec> _filterChips = const [];
  String? _selectedSortBy;

  static const int _perPage = 20;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ListingLayoutPrefs.load();

    _controller.addListener(() {
      if (_controller.hasClients) {
        HomeFeedScrollPersistence.savePixels(_controller.offset);
        _cacheOffset = _controller.offset;
      }
      if (!_hasNext || _loadingMore || _loading) return;
      final pos = _controller.position;
      if (pos.pixels >= (pos.maxScrollExtent - 500)) {
        _loadMore();
      }
    });

    if (_cacheCars.isNotEmpty) {
      _cars
        ..clear()
        ..addAll(_cacheCars.map((e) => Map<String, dynamic>.from(e)));
      _hasNext = _cacheHasNext;
      _page = _cachePage;
      _loading = false;
      _loadingMore = false;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScrollOffset());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetch(refresh: true);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshFilterState();
    });
  }

  Future<void> _refreshFilterState() async {
    final map = await HomeFilterPersistence.loadMap();
    if (!mounted) return;
    final specs = homeActiveFilterChipSpecs(context, map);
    final sortRaw = map['sort_by']?.toString().trim();
    setState(() {
      _filterChips = specs;
      _activeFilterCount = specs.length;
      _selectedSortBy =
          (sortRaw != null && sortRaw.isNotEmpty) ? sortRaw : null;
    });
  }

  Future<void> _applySort(String? localizedSort) async {
    await HomeFilterPersistence.updateSort(localizedSort);
    if (!mounted) return;
    await _refreshFilterState();
    await _fetch(refresh: true);
  }

  Future<void> _applyLayoutColumns(int columns) async {
    await ListingLayoutPrefs.setColumns(columns);
    if (mounted) setState(() {});
  }

  Future<void> _clearHomeFilter(String filterType) async {
    await HomeFilterPersistence.clearFilter(filterType);
    if (!mounted) return;
    await _refreshFilterState();
    await _fetch(refresh: true);
  }

  @override
  void dispose() {
    _persistCacheSnapshot();
    _controller.dispose();
    super.dispose();
  }

  void _persistCacheSnapshot() {
    _cacheCars = _cars.map((e) => Map<String, dynamic>.from(e)).toList();
    _cacheHasNext = _hasNext;
    _cachePage = _page;
    if (_controller.hasClients) {
      _cacheOffset = _controller.offset;
    }
  }

  void _restoreScrollOffset() {
    if (!_controller.hasClients || _cacheOffset <= 0) return;
    final max = _controller.position.maxScrollExtent;
    final target = _cacheOffset.clamp(0, max).toDouble();
    _controller.jumpTo(target);
    // If layout expands after first frame, retry once to reach exact previous offset.
    if (target < _cacheOffset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final max2 = _controller.position.maxScrollExtent;
        _controller.jumpTo(_cacheOffset.clamp(0, max2).toDouble());
      });
    }
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
      final result = await fetchHomeListingsPage(
        page: _page,
        perPage: _perPage,
        context: context,
      );

      if (!mounted) return;
      setState(() {
        _cars.addAll(result.cars);
        _hasNext = result.hasNext;
        _loading = false;
        _loadingMore = false;
      });
      _persistCacheSnapshot();
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
      _persistCacheSnapshot();
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

  void _onShellTab(int idx) {
    if (idx == 0) {
      if (_controller.hasClients) {
        _controller.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
      HomeFeedScrollPersistence.markTop();
      return;
    }
    HomeFeedScrollPersistence.capture(_controller);
    final route = switch (idx) {
      1 => '/favorites',
      2 => '/dealers',
      3 => '/profile',
      _ => '/',
    };
    Navigator.of(context).pushReplacementNamed(route);
  }

  Future<void> _openFilters() async {
    final changed = await Navigator.of(context).pushNamed('/home_filters');
    if (!mounted) return;
    await _refreshFilterState();
    if (changed == true) {
      await _fetch(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final loc = AppLocalizations.of(context);
    final title = loc?.appTitle ?? 'CarNet';

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 18)),
        titleSpacing: NavigationToolbar.kMiddleSpacing,
        actions: [
          IconButton(
            tooltip: loc?.moreFilters ?? 'Filters',
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount'),
              child: const Icon(Icons.tune),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              end: NavigationToolbar.kMiddleSpacing,
            ),
            child: OutlinedButton.icon(
              onPressed: () {
                HomeFeedScrollPersistence.capture(_controller);
                Navigator.of(context).pushReplacementNamed('/sell');
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                loc?.sellButton ?? 'Sell',
                style: const TextStyle(color: Colors.white),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white70),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 0,
        onTap: _onShellTab,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
            ),
            RefreshIndicator(
              onRefresh: () async {
                await _fetch(refresh: true);
                await _refreshFilterState();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildHomeActiveFilterChipWrap(
                    context,
                    specs: _filterChips,
                    onClearFilterType: _clearHomeFilter,
                  ),
                  buildHomeFeedToolbarWithLayoutListener(
                    context: context,
                    selectedSortBy: _selectedSortBy,
                    onSortSelected: _applySort,
                    onLayoutSelected: _applyLayoutColumns,
                  ),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: ListingLayoutPrefs.columns,
                      builder: (context, listingColumns, _) {
                        return _buildHomeScrollContent(
                          context,
                          loc: loc,
                          listingColumns: listingColumns,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeScrollContent(
    BuildContext context, {
    required AppLocalizations? loc,
    required int listingColumns,
  }) {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_cars.isEmpty && _error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
      );
    }
    if (_cars.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Text(
              loc?.noCarsFound ?? 'No cars found',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    return GridView.builder(
      controller: _controller,
      key: const PageStorageKey<String>('home_grid'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: listingColumns == 1 ? 1 : 2,
        childAspectRatio: ListingLayoutPrefs.gridChildAspectRatio(
          listingColumns == 1 ? 1 : 2,
        ),
        crossAxisSpacing: listingColumns == 1 ? 4 : 8,
        mainAxisSpacing: listingColumns == 1 ? 4 : 8,
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
        final card = buildGlobalCarCard(
          context,
          car,
          listLayout: listingColumns == 1,
        );
        if (listingColumns == 3) {
          return GestureDetector(
            onTap: () {
              Navigator.pushNamed(
                context,
                '/tiktok_scroll',
                arguments: {
                  'cars': _cars,
                  'initialIndex': index,
                },
              );
            },
            child: AbsorbPointer(child: card),
          );
        }
        return card;
      },
    );
  }
}

