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
      MaterialPageRoute(
        builder: (_) => ListingPreviewMediaGridPage(
          imageFilesOrUrls: images,
          videoFilesOrUrls: videos,
          initialIndex: i,
        ),
      ),
    );
  }

  Widget _buildVideoCarouselSlide(dynamic item) {
    final String path = item is XFile ? item.path : item.toString().trim();
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
    } catch (e, st) { logNonFatal(e, st); 
      return raw;
    }
  }

  Widget _buildSpecCard(_SpecItem item) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      constraints: BoxConstraints(minHeight: 84),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(item.icon, size: 16, color: Colors.black87),
              SizedBox(width: 6),
              Flexible(
                child: AutoSizeText(
                  item.label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  textScaleFactor: 1.0,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    height: 1.1,
                  ),
                  minFontSize: 7,
                  stepGranularity: 0.5,
                  overflow: TextOverflow.clip,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.black.withValues(alpha: 0.22),
            ),
          ),
          AutoSizeText(
            item.value!,
            maxLines: 2,
            textAlign: TextAlign.center,
            textScaleFactor: 1.0,
            style: TextStyle(
              fontSize: 15,
              height: 1.15,
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ),
            minFontSize: 10,
            stepGranularity: 0.5,
            overflow: TextOverflow.clip,
          ),
        ],
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String? value,
  }) {
    if (value == null || value.isEmpty) return SizedBox.shrink();
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFF3F3F3)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLight ? const Color(0xFFE0E0E0) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.black),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isLight ? const Color(0xFF3A3A3A) : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
              ),
            ),
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
            ? '${_localizeDigitsGlobal(context, _formatPrice(context, data['mileage'].toString()))} ${loc.unit_km}'
            : null,
      ),
      _SpecItem(
        icon: Icons.settings_input_component,
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
      ),
      _SpecItem(
        icon: Icons.straighten,
        label: loc.detail_engine,
        value: engineSize != null
            ? '${_localizeDigitsGlobal(context, engineSize.toString())}${loc.unit_liter_suffix}'
            : null,
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
      ),
      _SpecItem(
        icon: Icons.local_gas_station,
        label: loc.detail_fuel,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['fuel_type']),
        ),
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
        value: _getFirstNonEmpty(data, ['contact_phone']),
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
