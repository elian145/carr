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

  TimeOfDay? _parseHourTime(String raw) {
    final m = RegExp(
      r'^\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (m == null) return null;
    int? h = int.tryParse(m.group(1) ?? '');
    final min = int.tryParse(m.group(2) ?? '0') ?? 0;
    final ap = (m.group(3) ?? '').toLowerCase();
    if (h == null || min < 0 || min > 59) return null;
    if (ap.isNotEmpty) {
      if (h < 1 || h > 12) return null;
      if (ap == 'am') {
        h = h == 12 ? 0 : h;
      } else if (ap == 'pm') {
        h = h == 12 ? 12 : h + 12;
      }
    } else {
      if (h < 0 || h > 23) return null;
    }
    return TimeOfDay(hour: h, minute: min);
  }

  String _formatLocalTime(TimeOfDay t) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      t,
      alwaysUse24HourFormat: false,
    );
  }

  String _localizedOpeningHoursValue(String raw, {required bool allEmpty}) {
    final v = raw.trim();
    if (allEmpty) return _tr('Not provided', ar: 'غير متوفر', ku: 'بەردەست نییە');
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
      final a = _parseHourTime(parts[0]);
      final b = _parseHourTime(parts[1]);
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

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
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
        SnackBar(content: Text(_tr('Could not start a call', ar: 'تعذر بدء الاتصال', ku: 'نەتوانرا پەیوەندی دەستپێبکرێت'))),
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
    final legacy = (dealer?['dealership_phone'] ?? dealer?['phone_number'] ?? '')
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
        SnackBar(content: Text(_tr('Could not open email app', ar: 'تعذر فتح تطبيق البريد الإلكتروني', ku: 'نەکرا ئەپی ئیمەیل بکرێتەوە'))),
      );
    }
  }

  void _copyToClipboard(String text, String snackbarMessage) {
    final t = text.trim();
    if (t.isEmpty) return;
    Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snackbarMessage)),
    );
  }

  Future<void> _openDealerOnGoogleMaps(
    double lat,
    double lng,
  ) async {
    final ok = await openGoogleMapsAt(lat, lng);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Could not open Google Maps', ar: 'تعذر فتح خرائط Google', ku: 'نەکرا نەخشەی گووگڵ بکرێتەوە'))),
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
      raw = dealer['dealership_opening_hours'] ??
          dealer['opening_hours'] ??
          dealer['dealership_hours'];
    }
    // Fallback: sometimes the seller blob inside listings has more fields.
    if (raw is! Map && listings.isNotEmpty) {
      final seller = listings.first['seller'];
      if (seller is Map) {
        raw = seller['dealership_opening_hours'] ??
            seller['opening_hours'] ??
            seller['dealership_hours'];
      }
    }
    // Fallback for owner: use locally refreshed /auth/me payload.
    if (raw is! Map && isDealerOwner && currentUser != null) {
      raw = currentUser['dealership_opening_hours'] ??
          currentUser['opening_hours'] ??
          currentUser['dealership_hours'];
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) raw = decoded;
      } catch (e, st) { logNonFatal(e, st); }
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

  Widget _openingHoursTable(Map<String, String> hours) {
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
    final borderColor = Theme.of(context)
        .colorScheme
        .outline
        .withValues(alpha: Theme.of(context).brightness == Brightness.light ? 0.35 : 0.55);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          _tr('Opening hours', ar: 'ساعات العمل', ku: 'کاتەکانی کارکردن'),
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(2),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder(
                horizontalInside: BorderSide(color: borderColor, width: 1),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.55),
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        _tr('Day', ar: 'اليوم', ku: 'ڕۆژ'),
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        _tr('Hours', ar: 'الساعات', ku: 'کاتەکان'),
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                for (final r in rows)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(_dayLabel(r.key)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          _localizedOpeningHoursValue(
                            (hours[r.key] ?? '').trim(),
                            allEmpty: allEmpty,
                          ),
                        ),
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
