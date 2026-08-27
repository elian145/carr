part of 'sell_flow.dart';

extension _ListingPreviewWidgetHelpers on _ListingPreviewWidgetState {
  void _openCarouselDetail(
    BuildContext context,
    List<_PreviewMediaEntry> media,
    List<dynamic> images,
  ) {
    if (media.isEmpty) return;
    final i = _currentMediaIndex.clamp(0, media.length - 1);
    final videos = media.where((m) => m.isVideo).map((m) => m.item).toList();
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ListingPreviewMediaGridPage(
          imageFilesOrUrls: images.map((item) {
            final local = ListingImageMedia.localFile(item);
            return local ?? ListingImageMedia.source(item);
          }).toList(),
          videoFilesOrUrls: videos,
          initialIndex: i,
        ),
      ),
    );
  }

  Widget _buildVideoCarouselSlide(dynamic item) {
    final String path = ListingImageMedia.source(item);
    final bool isLocalFile =
        path.isNotEmpty &&
        !path.startsWith('http://') &&
        !path.startsWith('https://');
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isLocalFile)
          FutureBuilder<String?>(
            future: generateVideoThumbnail(path),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                );
              }
              return Container(
                color: Colors.grey[850],
                child: Center(
                  child: Icon(Icons.videocam, color: Colors.white70, size: 48),
                ),
              );
            },
          )
        else
          Container(
            color: Colors.grey[850],
            child: Center(
              child: Icon(Icons.videocam, color: Colors.white70, size: 56),
            ),
          ),
        Center(
          child: Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 40),
          ),
        ),
      ],
    );
  }

  static String? _getFirstNonEmpty(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      final String stringValue = value.toString().trim();
      if (stringValue.isNotEmpty) return stringValue;
    }
    return null;
  }

  String _formatPrice(BuildContext context, String raw) {
    try {
      final num? value = num.tryParse(raw.replaceAll(RegExp(r'[^0-9\.-]'), ''));
      if (value == null) return raw;
      final formatter = _decimalFormatterGlobal(context);
      return formatter.format(value);
    } catch (e, st) {
      logNonFatal(e, st);
      return raw;
    }
  }

  Widget _buildSpecCard(_SpecItem item) {
    const brandOrange = AppColors.brandOrange;
    const labelGrey = Color(0xFF8E8E93);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardBg = isLight ? Colors.white : const Color(0xFF1E1E1E);
    final iconCircleFill = isLight
        ? const Color(0xFFFFF0E6)
        : const Color(0xFFFFE8D6);
    final valueColor = isLight ? Colors.black : Colors.white;
    final asset = item.imageAsset;
    final Widget iconGlyph = (asset != null && asset.isNotEmpty)
        ? ColorFiltered(
            colorFilter: const ColorFilter.mode(brandOrange, BlendMode.srcIn),
            child: Image.asset(
              asset,
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(item.icon, size: 26, color: brandOrange),
            ),
          )
        : Icon(item.icon, size: 26, color: brandOrange);

    return Semantics(
      label: '${item.label}: ${item.value ?? ''}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: cardBg,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.10 : 0.50),
              blurRadius: isLight ? 16 : 18,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.28),
              blurRadius: isLight ? 4 : 6,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isLight
                ? const Color(0xFFE8E8ED)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: iconCircleFill,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: iconGlyph,
                    ),
                    const SizedBox(height: 8),
                    AutoSizeText(
                      item.label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      textScaleFactor: 1.0,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        color: labelGrey,
                        fontWeight: FontWeight.w500,
                      ),
                      minFontSize: 7,
                      stepGranularity: 0.5,
                      overflow: TextOverflow.clip,
                    ),
                    const SizedBox(height: 4),
                    AutoSizeText(
                      item.value!,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      textScaleFactor: 1.0,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.1,
                        color: valueColor,
                        fontWeight: FontWeight.w800,
                      ),
                      minFontSize: 10,
                      stepGranularity: 0.5,
                      overflow: TextOverflow.clip,
                    ),
                  ],
                ),
              ),
              const ColoredBox(
                color: brandOrange,
                child: SizedBox(height: 2.5, width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String? value,
  }) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final isLight = Theme.of(context).brightness == Brightness.light;
    const brandOrange = AppColors.brandOrange;
    const labelGrey = Color(0xFF8E8E93);
    final cardBg = isLight ? Colors.white : const Color(0xFF1E1E1E);
    final iconCircleFill = isLight
        ? const Color(0xFFFFF0E6)
        : const Color(0xFFFFE8D6);
    final valueColor = isLight ? Colors.black : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.10 : 0.50),
            blurRadius: isLight ? 18 : 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.05 : 0.28),
            blurRadius: isLight ? 6 : 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: isLight
              ? const Color(0xFFE8E8ED)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconCircleFill,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: brandOrange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: labelGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value,
                        style: TextStyle(
                          color: valueColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const ColoredBox(
            color: brandOrange,
            child: SizedBox(height: 2.5, width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecsFromData(Map<String, dynamic> data) {
    final loc = AppLocalizations.of(context)!;
    final String? engineSize = _getFirstNonEmpty(data, [
      'engine_size',
      'engineSize',
      'engine',
    ]);
    final List<_SpecItem> primary = [
      _SpecItem(
        icon: Icons.speed,
        label: loc.mileageLabel,
        value: data['mileage'] != null
            ? '${_localizeDigitsGlobal(context, _formatPrice(context, data['mileage'].toString()))} ${data['mileage_unit']?.toString() == 'miles' ? loc.unit_miles : loc.unit_km}'
            : null,
        imageAsset: ListingSpecIcons.mileage,
      ),
      _SpecItem(
        icon: Icons.view_column_rounded,
        label: loc.detail_cylinders,
        value: () {
          final raw = _getFirstNonEmpty(data, [
            'cylinder_count',
            'cylinders',
            'cylinderCount',
          ]);
          if (raw == null) return null;
          return _localizeDigitsGlobal(context, raw);
        }(),
        imageAsset: ListingSpecIcons.cylinders,
      ),
      _SpecItem(
        icon: Icons.precision_manufacturing_outlined,
        label: loc.detail_engine,
        value: engineSize != null
            ? '${_localizeDigitsGlobal(context, engineSize.toString())}${loc.unit_liter_suffix}'
            : null,
        imageAsset: ListingSpecIcons.engine,
      ),
      _SpecItem(
        icon: Icons.layers,
        label: loc.trimLabel,
        value:
            _translateValueGlobal(context, _getFirstNonEmpty(data, ['trim'])) ??
            _getFirstNonEmpty(data, ['trim']),
      ),
      _SpecItem(
        icon: Icons.settings,
        label: loc.transmissionLabel,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['transmission']),
        ),
        imageAsset: ListingSpecIcons.transmission,
      ),
      _SpecItem(
        icon: Icons.local_gas_station,
        label: loc.detail_fuel,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['fuel_type']),
        ),
        imageAsset: ListingSpecIcons.fuel,
      ),
    ];
    final List<Widget> details = [
      _detailRow(
        icon: Icons.layers,
        label: loc.trimLabel,
        value:
            _translateValueGlobal(context, _getFirstNonEmpty(data, ['trim'])) ??
            _getFirstNonEmpty(data, ['trim']),
      ),
      _detailRow(
        icon: Icons.check_circle,
        label: loc.detail_condition,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['condition']),
        ),
      ),
      _detailRow(
        icon: Icons.assignment_turned_in,
        label: loc.titleStatus,
        value: data['title_status'] != null
            ? (data['title_status'].toString().toLowerCase() == 'damaged'
                  ? (data['damaged_parts'] != null
                        ? loc.titleStatusDamagedWithParts(
                            _localizeDigitsGlobal(
                              context,
                              data['damaged_parts'].toString(),
                            ),
                          )
                        : loc.value_title_damaged)
                  : loc.value_title_clean)
            : null,
      ),
      _detailRow(
        icon: Icons.drive_eta,
        label: loc.detail_drive,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, [
            'drive_type',
            'driveType',
            'drivetrain',
            'drive',
          ]),
        ),
      ),
      _detailRow(
        icon: Icons.directions_car_filled,
        label: loc.detail_body,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['body_type', 'bodyType', 'body']),
        ),
      ),
      _detailRow(
        icon: Icons.color_lens,
        label: loc.detail_color,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['color']),
        ),
      ),
      _detailRow(
        icon: Icons.airline_seat_recline_normal,
        label: loc.detail_seating,
        value: _localizeDigitsGlobal(
          context,
          _getFirstNonEmpty(data, ['seating', 'seats', 'seatCount']) ?? '',
        ),
      ),
      _detailRow(
        icon: Icons.phone,
        label: loc.phoneLabel,
        value: () {
          final phones = sellContactPhonesFromCarData(data);
          if (phones.isNotEmpty) return phones.join(' · ');
          return _getFirstNonEmpty(data, ['contact_phone']);
        }(),
      ),
      _detailRow(
        icon: Icons.pin_outlined,
        label: 'VIN',
        value: _getFirstNonEmpty(data, ['vin']),
      ),
    ];
    final primItems = primary
        .where((i) => i.value != null && i.value!.isNotEmpty)
        .toList();
    final primGrid = GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: primItems.length,
      itemBuilder: (context, index) => _buildSpecCard(primItems[index]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [primGrid, SizedBox(height: 12), ...details],
    );
  }
}
