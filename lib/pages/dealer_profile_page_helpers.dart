part of 'dealer_profile_page.dart';

extension _DealerProfilePageHelpers on _DealerProfilePageState {
  String _tr(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  String _dayLabel(String key) {
    switch (key) {
      case 'sun':
        return _tr('Sunday', ar: 'الأحد', ku: 'یەکشەممە');
      case 'mon':
        return _tr('Monday', ar: 'الاثنين', ku: 'دووشەممە');
      case 'tue':
        return _tr('Tuesday', ar: 'الثلاثاء', ku: 'سێشەممە');
      case 'wed':
        return _tr('Wednesday', ar: 'الأربعاء', ku: 'چوارشەممە');
      case 'thu':
        return _tr('Thursday', ar: 'الخميس', ku: 'پێنجشەممە');
      case 'fri':
        return _tr('Friday', ar: 'الجمعة', ku: 'هەینی');
      case 'sat':
        return _tr('Saturday', ar: 'السبت', ku: 'شەممە');
      default:
        return key;
    }
  }

  String _formatLocalTime(TimeOfDay t) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(t, alwaysUse24HourFormat: false);
  }

  String _localizedOpeningHoursValue(String raw, {required bool allEmpty}) {
    final v = raw.trim();
    if (allEmpty) {
      return _tr('Not provided', ar: 'غير متوفر', ku: 'بەردەست نییە');
    }
    if (v.isEmpty) return _tr('Closed', ar: 'مغلق', ku: 'داخراوە');

    final normalized = v
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s:]'), '')
        .trim();
    if (normalized == 'closed' ||
        normalized == 'close' ||
        normalized.contains('closed') ||
        normalized.contains('close')) {
      return _tr('Closed', ar: 'مغلق', ku: 'داخراوە');
    }
    if ((normalized.contains('24') && normalized.contains('hour')) ||
        normalized == '24') {
      return _tr('24 hours', ar: '24 ساعة', ku: '24 کاتژمێر');
    }

    final parts = v.split(RegExp(r'\s*-\s*'));
    if (parts.length >= 2) {
      final a = parseHourTimeToken(parts[0]);
      final b = parseHourTimeToken(parts[1]);
      if (a != null && b != null) {
        return '${_formatLocalTime(a)} - ${_formatLocalTime(b)}';
      }
    }
    return v;
  }

  String _firstListingImage() {
    for (final listing in _listings) {
      final direct = (listing['image_url'] ?? '').toString().trim();
      if (direct.isNotEmpty) return buildMediaUrl(direct);
      final images = listing['images'];
      if (images is List && images.isNotEmpty) {
        final first = images.first;
        if (first is Map) {
          final v = (first['image_url'] ?? '').toString().trim();
          if (v.isNotEmpty) return buildMediaUrl(v);
        }
      }
    }
    return '';
  }

  static const Color _brandOrange = Color(0xFFFF6B00);
  static const Color _iconCircleFillLight = Color(0xFFFFF0E6);
  static const Color _iconCircleFillDark = Color(0xFFFFE8D6);

  BoxDecoration _softCardDecoration(bool isLight) {
    return BoxDecoration(
      color: isLight
          ? Colors.white
          : Color.alphaBlend(
              Colors.white.withValues(alpha: 0.07),
              AppThemes.darkHomeShellBackground,
            ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isLight
            ? const Color(0xFFE0E0E0)
            : Colors.white.withValues(alpha: 0.12),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isLight ? 0.05 : 0.35),
          blurRadius: isLight ? 12 : 18,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildDealerHero({
    required String bannerUrl,
    required String logoUrl,
    required String displayName,
    required bool isLightShell,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final sheetColor = isLightShell
        ? AppThemes.lightAppBackground
        : AppThemes.darkHomeShellBackground;
    final bannerHeight = bannerUrl.isNotEmpty
        ? (MediaQuery.sizeOf(context).width * 2 / 3)
              .clamp(210.0, 360.0)
              .toDouble()
        : 168.0;

    return SizedBox(
      height: bannerHeight + 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: bannerHeight,
            child: bannerUrl.isNotEmpty
                ? Image.network(
                    bannerUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.storefront_rounded,
                        size: 56,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Center(
                      child: Icon(
                        Icons.storefront_rounded,
                        size: 56,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: bannerHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.12),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0.0, 0.28, 0.7, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: bannerHeight,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: sheetColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 4,
            child: Material(
              elevation: 8,
              shadowColor: Colors.black38,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: sheetColor,
                  border: Border.all(
                    color: _brandOrange.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0x26FF6B00),
                  backgroundImage: logoUrl.isNotEmpty
                      ? NetworkImage(logoUrl)
                      : null,
                  child: logoUrl.isEmpty
                      ? Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : 'D',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: _brandOrange,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip({
    required IconData icon,
    required String label,
    required bool isLight,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFFFF0E6)
            : _brandOrange.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _brandOrange),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isLight
                    ? AppThemes.darkHomeShellBackground
                    : const Color(0xFFF7F7F7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionControl(bool isLight) {
    final listingsLabel = _tr('Listings', ar: 'الإعلانات', ku: 'ڕێکلامەکان');
    final aboutLabel = _tr('Info', ar: 'معلومات', ku: 'زانیاری');

    if (AppResponsive.isCompactPhone(context)) {
      return DropdownButtonFormField<_DealerSection>(
        initialValue: _section,
        isExpanded: true,
        decoration: InputDecoration(
          filled: true,
          fillColor: isLight
              ? const Color(0xFFF4F4F4)
              : Colors.white.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: isLight
                  ? const Color(0xFFE0E0E0)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: isLight
                  ? const Color(0xFFE0E0E0)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _brandOrange, width: 1.5),
          ),
        ),
        items: [
          DropdownMenuItem(
            value: _DealerSection.listings,
            child: Text(listingsLabel),
          ),
          DropdownMenuItem(
            value: _DealerSection.about,
            child: Text(aboutLabel),
          ),
        ],
        onChanged: (value) {
          if (value == null) return;
          _selectSection(value);
        },
      );
    }

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<_DealerSection>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: _brandOrange.withValues(alpha: 0.14),
          selectedForegroundColor: _brandOrange,
          backgroundColor: isLight
              ? const Color(0xFFF4F4F4)
              : Colors.white.withValues(alpha: 0.06),
          foregroundColor: isLight
              ? const Color(0xFF5C5C5C)
              : const Color(0xFFD8D8D8),
          side: BorderSide(
            color: isLight
                ? const Color(0xFFE0E0E0)
                : Colors.white.withValues(alpha: 0.12),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
        segments: [
          ButtonSegment(
            value: _DealerSection.listings,
            label: Text(listingsLabel),
            icon: const Icon(Icons.grid_view_rounded, size: 16),
          ),
          ButtonSegment(
            value: _DealerSection.about,
            label: Text(aboutLabel),
            icon: const Icon(Icons.info_outline_rounded, size: 16),
          ),
        ],
        selected: {_section},
        onSelectionChanged: (s) {
          if (s.isEmpty) return;
          _selectSection(s.first);
        },
      ),
    );
  }

  Widget _buildAboutSection({
    required List<String> phones,
    required String email,
    required String location,
    required double? mapLat,
    required double? mapLng,
    required Map<String, String> openingHours,
    required bool isLightShell,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (phones.isNotEmpty || email.isNotEmpty || location.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _softCardDecoration(isLightShell),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('Contact', ar: 'التواصل', ku: 'پەیوەندی'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (phones.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (var i = 0; i < phones.length; i++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                      child: Tooltip(
                        message: _tr(
                          'Tap to call • Hold to copy',
                          ar: 'اضغط للاتصال • اضغط مطولاً للنسخ',
                          ku: 'کرتە بکە بۆ پەیوەندی • چەند چرکە هەڵبگرە بۆ کۆپی',
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _brandOrange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () => _callDealer(phones[i]),
                            onLongPress: () => _copyToClipboard(
                              phones[i],
                              _tr(
                                'Phone number copied to clipboard',
                                ar: 'تم نسخ رقم الهاتف',
                                ku: 'ژمارەی تەلەفۆن کۆپی کرا',
                              ),
                            ),
                            icon: const Icon(Icons.phone_outlined, size: 18),
                            label: Text(
                              phones[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Tooltip(
                    message: _tr(
                      'Tap to send email • Hold to copy',
                      ar: 'اضغط لإرسال بريد • اضغط مطولاً للنسخ',
                      ku: 'کرتە بکە بۆ ناردنی ئیمەیل • چەند چرکە هەڵبگرە بۆ کۆپی',
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brandOrange,
                          side: BorderSide(
                            color: _brandOrange.withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () => _emailDealer(email),
                        onLongPress: () => _copyToClipboard(
                          email,
                          _tr(
                            'Email copied to clipboard',
                            ar: 'تم نسخ البريد الإلكتروني',
                            ku: 'ئیمەیل کۆپی کرا',
                          ),
                        ),
                        icon: const Icon(Icons.email_outlined, size: 18),
                        label: Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
                _infoRow(
                  Icons.location_on_outlined,
                  _tr('Location', ar: 'الموقع', ku: 'شوێن'),
                  location,
                  isLight: isLightShell,
                ),
              ],
            ),
          ),
        if (mapLat != null &&
            mapLng != null &&
            isValidDealerLatLng(mapLat, mapLng)) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: _softCardDecoration(isLightShell),
            child: DealerLocationMapPreview(
              latitude: mapLat,
              longitude: mapLng,
              onOpenInGoogleMaps: () => _openDealerOnGoogleMaps(mapLat, mapLng),
            ),
          ),
        ],
        _openingHoursTable(openingHours, isLight: isLightShell),
      ],
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    bool isLight = true,
  }) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isLight ? _iconCircleFillLight : _iconCircleFillDark,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: _brandOrange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isLight ? const Color(0xFF8E8E93) : Colors.white60,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isLight
                        ? AppThemes.darkHomeShellBackground
                        : const Color(0xFFF7F7F7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _normalizeTel(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '+' && buf.isEmpty) {
        buf.write(c);
      } else if (RegExp(r'[0-9]').hasMatch(c)) {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  Future<void> _callDealer(String rawPhone) async {
    final phone = _normalizeTel(rawPhone);
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');

    bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!launched) {
      launched = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      ).catchError((_) => false);
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Could not start a call',
              ar: 'تعذر بدء الاتصال',
              ku: 'نەتوانرا پەیوەندی دەستپێبکرێت',
            ),
          ),
        ),
      );
    }
  }

  List<String> _phonesFromAnySource(Map<String, dynamic>? dealer) {
    final out = <String>[];
    final raw = dealer?['dealership_phones'];
    if (raw is List) {
      for (final x in raw) {
        final s = (x ?? '').toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
    }
    final legacy =
        (dealer?['dealership_phone'] ?? dealer?['phone_number'] ?? '')
            .toString()
            .trim();
    if (out.isEmpty && legacy.isNotEmpty) out.add(legacy);
    // De-dupe (preserve order)
    final seen = <String>{};
    return out.where((p) => seen.add(p)).toList();
  }

  Future<void> _emailDealer(String rawEmail) async {
    final addr = rawEmail.trim();
    if (addr.isEmpty) return;
    final uri = Uri(scheme: 'mailto', path: addr);

    bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!launched) {
      launched = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      ).catchError((_) => false);
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Could not open email app',
              ar: 'تعذر فتح تطبيق البريد الإلكتروني',
              ku: 'نەکرا ئەپی ئیمەیل بکرێتەوە',
            ),
          ),
        ),
      );
    }
  }

  void _copyToClipboard(String text, String snackbarMessage) {
    final t = text.trim();
    if (t.isEmpty) return;
    Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(snackbarMessage)));
  }

  Future<void> _openDealerOnGoogleMaps(double lat, double lng) async {
    final ok = await openGoogleMapsAt(lat, lng);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Could not open Google Maps',
              ar: 'تعذر فتح خرائط Google',
              ku: 'نەکرا نەخشەی گووگڵ بکرێتەوە',
            ),
          ),
        ),
      );
    }
  }

  Map<String, String> _openingHoursFromAnySource(
    Map<String, dynamic>? dealer,
    List<Map<String, dynamic>> listings,
    Map<String, dynamic>? currentUser,
    bool isDealerOwner,
  ) {
    dynamic raw;
    if (dealer != null) {
      raw =
          dealer['dealership_opening_hours'] ??
          dealer['opening_hours'] ??
          dealer['dealership_hours'];
    }
    // Fallback: sometimes the seller blob inside listings has more fields.
    if (raw is! Map && listings.isNotEmpty) {
      final seller = listings.first['seller'];
      if (seller is Map) {
        raw =
            seller['dealership_opening_hours'] ??
            seller['opening_hours'] ??
            seller['dealership_hours'];
      }
    }
    // Fallback for owner: use locally refreshed /auth/me payload.
    if (raw is! Map && isDealerOwner && currentUser != null) {
      raw =
          currentUser['dealership_opening_hours'] ??
          currentUser['opening_hours'] ??
          currentUser['dealership_hours'];
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) raw = decoded;
      } catch (e, st) {
        logNonFatal(e, st);
      }
    }
    if (raw is! Map) return const {};

    final m = <String, String>{};
    for (final entry in raw.entries) {
      final key = (entry.key ?? '').toString().trim().toLowerCase();
      final val = (entry.value ?? '').toString().trim();
      if (key.isEmpty) continue;
      if (val.isEmpty) continue;
      m[key] = val;
    }
    return m;
  }

  Widget _openingHoursTable(Map<String, String> hours, {bool isLight = true}) {
    const rows = <({String label, String key})>[
      (label: 'Sunday', key: 'sun'),
      (label: 'Monday', key: 'mon'),
      (label: 'Tuesday', key: 'tue'),
      (label: 'Wednesday', key: 'wed'),
      (label: 'Thursday', key: 'thu'),
      (label: 'Friday', key: 'fri'),
      (label: 'Saturday', key: 'sat'),
    ];

    final allEmpty = rows.every((r) => (hours[r.key] ?? '').trim().isEmpty);
    final borderColor = isLight
        ? const Color(0xFFE0E0E0)
        : Colors.white.withValues(alpha: 0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: _softCardDecoration(isLight),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: isLight
                        ? const Color(0xFFFFF7F0)
                        : _brandOrange.withValues(alpha: 0.14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isLight
                              ? _iconCircleFillLight
                              : _iconCircleFillDark,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: _brandOrange,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _tr(
                          'Opening hours',
                          ar: 'ساعات العمل',
                          ku: 'کاتەکانی کارکردن',
                        ),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                    1: FlexColumnWidth(2),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: TableBorder(
                    horizontalInside: BorderSide(color: borderColor, width: 1),
                  ),
                  children: [
                    for (final r in rows)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            child: Text(
                              _dayLabel(r.key),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: isLight
                                    ? const Color(0xFF5C5C5C)
                                    : Colors.white70,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            child: Text(
                              _localizedOpeningHoursValue(
                                (hours[r.key] ?? '').trim(),
                                allEmpty: allEmpty,
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: isLight
                                    ? AppThemes.darkHomeShellBackground
                                    : const Color(0xFFF7F7F7),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
