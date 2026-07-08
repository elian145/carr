import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/car_name_translations.dart';
import '../../l10n/app_localizations.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../services/recently_viewed_service.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/listings/listing_card_media.dart';
import '../../shared/media/media_url.dart';
import '../../shared/text/pretty_title_case.dart';
import 'listing_network_image.dart';

const Color _kFeaturedAccent = Color(0xFFFF6B00);
const Color _kFeaturedCardBg = Color(0xFF121212);
const Color _kFeaturedMuted = Color(0xFF9A9A9A);
const double _kFeaturedRadius = 16;

/// Wide featured listing card used in the home "Featured Listings" carousel.
class FeaturedListingCard extends StatefulWidget {
  const FeaturedListingCard({
    super.key,
    required this.car,
    this.onTap,
  });

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
      (widget.car['public_id'] ?? widget.car['id'] ?? widget.car['car_id'] ?? '')
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
    Navigator.pushNamed(
      context,
      '/car_detail',
      arguments: {'carId': id},
    );
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

  String? _firstImageUrl() {
    final slots = ListingCardMedia.collectFromCar(
      widget.car,
      resolveNetworkUrl: buildLegacyFullImageUrl,
    );
    if (slots.isEmpty) return null;
    return slots.first.url;
  }

  String _title(BuildContext context) {
    final localized = CarNameTranslations.getLocalizedCarTitleNoYear(
      context,
      widget.car,
    );
    final raw = localized.isNotEmpty
        ? localized
        : (widget.car['title']?.toString() ?? '').trim();
    return prettyTitleCase(raw);
  }

  String _subtitle(BuildContext context) {
    final bodyRaw = (widget.car['body_type'] ?? '').toString().trim();
    final yearRaw = (widget.car['year'] ?? '').toString().trim();
    final body = bodyRaw.isEmpty
        ? ''
        : (translateListingValue(context, bodyRaw) ?? bodyRaw);
    final year = yearRaw.isEmpty ? '' : localizeDigits(context, yearRaw);
    if (body.isNotEmpty && year.isNotEmpty) return '$body • $year';
    if (body.isNotEmpty) return body;
    return year;
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
    final imageUrl = _firstImageUrl();
    final imageCount = _imageCount();
    final title = _title(context);
    final subtitle = _subtitle(context);
    final price = formatCurrency(context, widget.car['price']);
    final mileage = _mileage(context);
    final transmission = _label(context, widget.car['transmission']);
    final fuel = _label(context, widget.car['fuel_type']);
    final city = _city(context);
    final featuredLabel = trLegacyText(
      context,
      'FEATURED',
      ar: 'مميز',
      ku: 'تایبەت',
    );

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
            border: Border.all(
              color: _kFeaturedAccent.withValues(alpha: 0.18),
              width: 3,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(1.5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_kFeaturedRadius + 1.5),
                border: Border.all(
                  color: _kFeaturedAccent.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: Ink(
                  decoration: BoxDecoration(
                    color: _kFeaturedCardBg,
                    borderRadius: BorderRadius.circular(_kFeaturedRadius),
                    border: Border.all(
                      color: _kFeaturedAccent.withValues(alpha: 0.9),
                      width: 1.25,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(_kFeaturedRadius - 0.5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 58,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (imageUrl != null && imageUrl.isNotEmpty)
                                listingNetworkImage(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                )
                              else
                                ColoredBox(
                                  color: const Color(0xFF1A1A1A),
                                  child: Icon(
                                    Icons.directions_car,
                                    size: 56,
                                    color: Colors.grey[600],
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
                                  tooltip: AppLocalizations.of(context)!
                                      .favoriteAction,
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
                                  bottom: 12,
                                  end: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
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
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 42,
                          child: ColoredBox(
                            color: _kFeaturedCardBg,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 20,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        price,
                                        style: const TextStyle(
                                          color: _kFeaturedAccent,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 21,
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _kFeaturedMuted,
                                        fontSize: 15,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  _FeaturedSpecsRow(
                                    mileage: mileage,
                                    transmission: transmission,
                                    fuel: fuel,
                                    city: city,
                                  ),
                                ],
                              ),
                            ),
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
  });

  final String mileage;
  final String transmission;
  final String fuel;
  final String city;

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

    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 1,
                    height: 14,
                    child: ColoredBox(color: Color(0xFF3A3A3A)),
                  ),
                ),
              ],
              Icon(items[i].icon, size: 15, color: _kFeaturedMuted),
              const SizedBox(width: 4),
              Text(
                items[i].text,
                style: const TextStyle(
                  color: _kFeaturedMuted,
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
