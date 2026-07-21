import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import '../../data/car_name_translations.dart';
import '../../l10n/app_localizations.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../services/recently_viewed_service.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/listings/listing_card_media.dart';
import '../../shared/media/media_url.dart';
import '../../shared/text/pretty_title_case.dart';
import '../../shared/ui/responsive.dart';
import '../../theme_provider.dart';
import 'listing_network_image.dart';

const Color _kFeaturedAccent = Color(0xFFFF6B00);
const Color _kFeaturedCardBgDark = Color(0xFF121212);
const Color _kFeaturedMutedDark = Color(0xFF9A9A9A);
const double _kFeaturedRadius = 16;

class _FeaturedCardColors {
  const _FeaturedCardColors({
    required this.cardBg,
    required this.title,
    required this.muted,
    required this.divider,
    required this.placeholderBg,
    required this.placeholderIcon,
    required this.favoriteIdle,
    required this.outerBorder,
    required this.midBorder,
    required this.innerBorder,
  });

  final Color cardBg;
  final Color title;
  final Color muted;
  final Color divider;
  final Color placeholderBg;
  final Color placeholderIcon;
  final Color favoriteIdle;
  final Color outerBorder;
  final Color midBorder;
  final Color innerBorder;

  factory _FeaturedCardColors.of(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    if (isLight) {
      final scheme = Theme.of(context).colorScheme;
      return _FeaturedCardColors(
        cardBg: AppThemes.listingCardFillGridOnLightShell(),
        title: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        divider: scheme.outlineVariant,
        placeholderBg: const Color(0xFFE8E8ED),
        placeholderIcon: const Color(0xFF9E9E9E),
        favoriteIdle: scheme.onSurface,
        outerBorder: _kFeaturedAccent.withValues(alpha: 0.14),
        midBorder: _kFeaturedAccent.withValues(alpha: 0.28),
        innerBorder: _kFeaturedAccent.withValues(alpha: 0.75),
      );
    }
    return _FeaturedCardColors(
      cardBg: _kFeaturedCardBgDark,
      title: Colors.white,
      muted: _kFeaturedMutedDark,
      divider: const Color(0xFF3A3A3A),
      placeholderBg: const Color(0xFF1A1A1A),
      placeholderIcon: const Color(0xFF757575),
      favoriteIdle: Colors.white,
      outerBorder: _kFeaturedAccent.withValues(alpha: 0.18),
      midBorder: _kFeaturedAccent.withValues(alpha: 0.35),
      innerBorder: _kFeaturedAccent.withValues(alpha: 0.9),
    );
  }
}

/// Wide featured listing card used in the home "Featured Listings" carousel.
class FeaturedListingCard extends StatefulWidget {
  const FeaturedListingCard({super.key, required this.car, this.onTap});

  final Map<String, dynamic> car;
  final VoidCallback? onTap;

  @override
  State<FeaturedListingCard> createState() => _FeaturedListingCardState();
}

class _FeaturedListingCardState extends State<FeaturedListingCard> {
  late bool _isFavorite;
  bool _favoriteBusy = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = _readFavorite(widget.car);
  }

  @override
  void didUpdateWidget(covariant FeaturedListingCard oldWidget) {
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

  void _openDetail() {
    final id = _carId;
    if (id.isEmpty) return;
    unawaited(
      RecentlyViewedService.recordView(
        id,
        snapshot: Map<String, dynamic>.from(widget.car),
      ),
    );
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    Navigator.pushNamed(context, '/car_detail', arguments: {'carId': id});
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
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

    setState(() => _favoriteBusy = true);
    final previous = _isFavorite;
    setState(() => _isFavorite = !previous);
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
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  int _imageCount() {
    final slots = ListingCardMedia.collectFromCar(
      widget.car,
      resolveNetworkUrl: buildLegacyFullImageUrl,
    );
    return slots.length;
  }

  ListingCardImageSlot? _firstImage() {
    final slots = ListingCardMedia.collectFromCar(
      widget.car,
      resolveNetworkUrl: buildLegacyFullImageUrl,
    );
    if (slots.isEmpty) return null;
    return slots.first;
  }

  String _title(BuildContext context) {
    final localized = CarNameTranslations.getLocalizedCarTitleNoYear(
      context,
      widget.car,
    );
    final raw = localized.isNotEmpty
        ? localized
        : (widget.car['title']?.toString() ?? '').trim();
    final base = prettyTitleCase(raw);
    final yearRaw = (widget.car['year'] ?? '').toString().trim();
    if (yearRaw.isEmpty) return base;
    final year = localizeDigits(context, yearRaw);
    if (base.isEmpty) return year;
    return '$base $year';
  }

  String _mileage(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final raw = (widget.car['mileage'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final num? n = num.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
    final digits = localizeDigits(
      context,
      n == null ? raw : decimalFormatterForLocale(context).format(n),
    );
    return '$digits ${loc.unit_km}';
  }

  String _label(BuildContext context, dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    return translateListingValue(context, s) ?? s;
  }

  String _city(BuildContext context) {
    for (final key in const ['city', 'location', 'city_name']) {
      final v = widget.car[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) {
        return translateListingValue(context, s) ?? s;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = _FeaturedCardColors.of(context);
    final image = _firstImage();
    final imageCount = _imageCount();
    final title = _title(context);
    final hasPrice = tryParseCurrencyValue(widget.car['price']) != null;
    final price = formatCurrency(context, widget.car['price']);
    final mileage = _mileage(context);
    final transmission = _label(context, widget.car['transmission']);
    final fuel = _label(context, widget.car['fuel_type']);
    final city = _city(context);
    final featuredLabel = AppLocalizations.of(context)!.featured;

    return Material(
      color: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: _openDetail,
        borderRadius: BorderRadius.circular(_kFeaturedRadius),
        child: DecoratedBox(
          // Soft outer rim only (stroke layers) — no filled boxShadow flood.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kFeaturedRadius + 3),
            border: Border.all(color: colors.outerBorder, width: 3),
          ),
          child: Padding(
            padding: const EdgeInsets.all(1.5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_kFeaturedRadius + 1.5),
                border: Border.all(color: colors.midBorder, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: Ink(
                  decoration: BoxDecoration(
                    color: colors.cardBg,
                    borderRadius: BorderRadius.circular(_kFeaturedRadius),
                    border: Border.all(color: colors.innerBorder, width: 1.25),
                    boxShadow: Theme.of(context).brightness == Brightness.light
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_kFeaturedRadius - 0.5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (image != null)
                          ListingCardMedia.buildCarouselImage(
                            image,
                            networkBuilder: listingNetworkImage,
                            fit: BoxFit.cover,
                          )
                        else
                          ColoredBox(
                            color: colors.placeholderBg,
                            child: Icon(
                              Icons.directions_car,
                              size: 56,
                              color: colors.placeholderIcon,
                            ),
                          ),
                        // Soft bottom scrim so transparent text stays readable.
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 140,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00000000), Color(0x99000000)],
                              ),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          top: 12,
                          start: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _kFeaturedAccent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.white,
                                  size: 17,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  featuredLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    letterSpacing: 0.6,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          top: 4,
                          end: 4,
                          child: IconButton(
                            onPressed: _toggleFavorite,
                            tooltip: AppLocalizations.of(
                              context,
                            )!.favoriteAction,
                            icon: Icon(
                              _isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: _isFavorite
                                  ? _kFeaturedAccent
                                  : Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                        if (imageCount > 0)
                          PositionedDirectional(
                            top: 12,
                            end: 48,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.photo_camera_outlined,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    localizeDigits(
                                      context,
                                      imageCount.toString(),
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LayoutBuilder(
                            builder: (context, textConstraints) {
                              final compact =
                                  AppResponsive.isNarrowPhone(context) ||
                                  textConstraints.maxWidth < 340;
                              final textPad = compact
                                  ? const EdgeInsets.fromLTRB(12, 10, 12, 12)
                                  : const EdgeInsets.fromLTRB(16, 12, 16, 14);
                              final titleSize = compact ? 17.0 : 20.0;
                              final priceSize = compact ? 18.0 : 21.0;
                              const overlayTitle = Colors.white;
                              const overlayMuted = Color(0xFFE8E8E8);
                              const overlayDivider = Color(0x66FFFFFF);
                              const titleShadow = [
                                Shadow(
                                  color: Color(0x99000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 1),
                                ),
                              ];

                              return Padding(
                                padding: textPad,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (compact) ...[
                                      AutoSizeText(
                                        title,
                                        maxLines: 2,
                                        minFontSize: 13,
                                        stepGranularity: 0.5,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: overlayTitle,
                                          fontWeight: FontWeight.w700,
                                          fontSize: titleSize,
                                          height: 1.15,
                                          shadows: titleShadow,
                                        ),
                                      ),
                                      if (hasPrice) ...[
                                        const SizedBox(height: 4),
                                        Align(
                                          alignment:
                                              AlignmentDirectional.centerStart,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: AlignmentDirectional
                                                .centerStart,
                                            child: Text(
                                              price,
                                              style: TextStyle(
                                                color: _kFeaturedAccent,
                                                fontWeight: FontWeight.w800,
                                                fontSize: priceSize,
                                                height: 1.1,
                                                shadows: titleShadow,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ] else
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: AutoSizeText(
                                              title,
                                              maxLines: 2,
                                              minFontSize: 14,
                                              stepGranularity: 0.5,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: overlayTitle,
                                                fontWeight: FontWeight.w700,
                                                fontSize: titleSize,
                                                height: 1.2,
                                                shadows: titleShadow,
                                              ),
                                            ),
                                          ),
                                          if (hasPrice) ...[
                                            const SizedBox(width: 12),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment:
                                                  AlignmentDirectional.topEnd,
                                              child: Text(
                                                price,
                                                style: TextStyle(
                                                  color: _kFeaturedAccent,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: priceSize,
                                                  height: 1.2,
                                                  shadows: titleShadow,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    SizedBox(height: compact ? 8 : 10),
                                    _FeaturedSpecsRow(
                                      mileage: mileage,
                                      transmission: transmission,
                                      fuel: fuel,
                                      city: city,
                                      muted: overlayMuted,
                                      divider: overlayDivider,
                                      compact: compact,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedSpecsRow extends StatelessWidget {
  const _FeaturedSpecsRow({
    required this.mileage,
    required this.transmission,
    required this.fuel,
    required this.city,
    required this.muted,
    required this.divider,
    this.compact = false,
  });

  final String mileage;
  final String transmission;
  final String fuel;
  final String city;
  final Color muted;
  final Color divider;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String text})>[
      if (mileage.isNotEmpty) (icon: Icons.speed, text: mileage),
      if (transmission.isNotEmpty)
        (icon: Icons.settings_outlined, text: transmission),
      if (fuel.isNotEmpty) (icon: Icons.local_gas_station, text: fuel),
      if (city.isNotEmpty) (icon: Icons.location_on_outlined, text: city),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    final iconSize = compact ? 13.0 : 15.0;
    final fontSize = compact ? 11.0 : 13.0;
    final separatorPad = compact ? 5.0 : 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: separatorPad),
                      child: SizedBox(
                        width: 1,
                        height: compact ? 12 : 14,
                        child: ColoredBox(color: divider),
                      ),
                    ),
                  ],
                  Icon(items[i].icon, size: iconSize, color: muted),
                  SizedBox(width: compact ? 3 : 4),
                  Text(
                    items[i].text,
                    style: TextStyle(
                      color: muted,
                      fontSize: fontSize,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
