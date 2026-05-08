import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../legacy/main_legacy.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../shared/maps/dealer_map_coords.dart';
import '../shared/maps/open_google_maps.dart';
import '../shared/media/media_url.dart';
import '../shared/errors/user_error_text.dart';
import '../theme_provider.dart';
import '../widgets/dealer_location_map_preview.dart';
import 'edit_dealer_page.dart';

class DealerProfilePage extends StatefulWidget {
  final String dealerPublicId;
  const DealerProfilePage({super.key, required this.dealerPublicId});

  @override
  State<DealerProfilePage> createState() => _DealerProfilePageState();
}

class _DealerProfilePageState extends State<DealerProfilePage> {
  _DealerSection _section = _DealerSection.listings;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _dealer;
  List<Map<String, dynamic>> _listings = const [];
  Map<String, dynamic> _stats = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getDealerProfile(widget.dealerPublicId);
      final dealerRaw = data['dealer'];
      final listingsRaw = data['listings'];
      final statsRaw = data['stats'];
      setState(() {
        _dealer = dealerRaw is Map
            ? Map<String, dynamic>.from(dealerRaw.cast<String, dynamic>())
            : null;
        _listings = listingsRaw is List
            ? listingsRaw
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
                .toList()
            : <Map<String, dynamic>>[];
        _stats = statsRaw is Map
            ? Map<String, dynamic>.from(statsRaw.cast<String, dynamic>())
            : <String, dynamic>{};
      });
    } catch (e) {
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback:
              AppLocalizations.of(context)?.failedToLoadListings ??
              'Failed to load listings',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final dealer = _dealer;
    final dealershipName = (dealer?['dealership_name'] ?? '').toString().trim();
    final firstName = (dealer?['first_name'] ?? '').toString().trim();
    final lastName = (dealer?['last_name'] ?? '').toString().trim();
    final fallbackName = ('$firstName $lastName').trim();
    final displayName = dealershipName.isNotEmpty
        ? dealershipName
        : (fallbackName.isNotEmpty ? fallbackName : _tr('Dealer', ar: 'وكيل', ku: 'وەکیل'));
    final logoUrl = buildMediaUrl((dealer?['profile_picture'] ?? '').toString().trim());
    final coverUrl = buildMediaUrl(
      (dealer?['dealership_cover_picture'] ?? '').toString().trim(),
    );
    final bannerUrl = coverUrl.isNotEmpty ? coverUrl : _firstListingImage();
    final location = (dealer?['dealership_location'] ?? dealer?['location'] ?? '')
        .toString()
        .trim();
    final double? mapLat = parseDealerCoord(dealer?['dealership_latitude']);
    final double? mapLng = parseDealerCoord(dealer?['dealership_longitude']);
    final phones = _phonesFromAnySource(dealer);
    final email = (dealer?['email'] ?? '').toString().trim();
    final description = (dealer?['dealership_description'] ?? '').toString().trim();
    final currentUserPublicId = (auth.currentUser?['public_id'] ??
            auth.currentUser?['id'] ??
            auth.currentUser?['user_id'] ??
            '')
        .toString()
        .trim();
    final isDealerOwner =
        auth.isAuthenticated && currentUserPublicId == widget.dealerPublicId;
    final openingHours = _openingHoursFromAnySource(
      dealer,
      _listings,
      auth.currentUser,
      isDealerOwner,
    );
    final isLightShell = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
      appBar: AppBar(title: Text(_tr('Dealer', ar: 'الوكيل', ku: 'وەکیل'))),
      backgroundColor: isLightShell ? AppThemes.lightAppBackground : null,
      body: Stack(
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: Text(AppLocalizations.of(context)?.retryAction ?? 'Retry')),
                        ],
                      )
                    : ListView(
                        children: [
                      SizedBox(
                        height: bannerUrl.isNotEmpty ? 188 : 148,
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: bannerUrl.isNotEmpty
                                  ? Image.network(
                                      bannerUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const ColoredBox(color: Colors.black12),
                                    )
                                  : const ColoredBox(color: Colors.black12),
                            ),
                            if (bannerUrl.isNotEmpty)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.5),
                                    ],
                                  ),
                                ),
                              ),
                            Positioned(
                              left: 16,
                              bottom: 12,
                              child: Material(
                                elevation: 6,
                                shadowColor: Colors.black45,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: CircleAvatar(
                                  radius: 36,
                                  backgroundColor: Theme.of(context).colorScheme.surface,
                                  child: CircleAvatar(
                                    radius: 32,
                                    backgroundImage: logoUrl.isNotEmpty
                                        ? NetworkImage(logoUrl)
                                        : null,
                                    child: logoUrl.isEmpty
                                        ? Text(
                                            displayName.isNotEmpty
                                                ? displayName[0].toUpperCase()
                                                : 'D',
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                description,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (isDealerOwner) ...[
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final changed = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const EditDealerPage(),
                                    ),
                                  );
                                  if (changed == true) {
                                    await _load();
                                  }
                                },
                                icon: const Icon(Icons.edit_outlined),
                                label: Text(_tr('Edit dealer page', ar: 'تعديل صفحة الوكيل', ku: 'دەستکاری پەڕەی وەکیل')),
                              ),
                            ],
                            const SizedBox(height: 12),
                            SegmentedButton<_DealerSection>(
                              segments: [
                                ButtonSegment(
                                  value: _DealerSection.listings,
                                  label: Text(_tr('Listings', ar: 'الإعلانات', ku: 'ڕێکلامەکان')),
                                ),
                                ButtonSegment(
                                  value: _DealerSection.about,
                                  label: Text(_tr('About', ar: 'حول', ku: 'دەربارە')),
                                ),
                              ],
                              selected: {_section},
                              onSelectionChanged: (s) {
                                if (s.isEmpty) return;
                                setState(() => _section = s.first);
                              },
                            ),
                            const SizedBox(height: 12),
                            if (_section == _DealerSection.about) ...[
                            if (phones.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var i = 0; i < phones.length; i++)
                                      Padding(
                                        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                                        child: Tooltip(
                                          message: _tr('Tap to call • Hold to copy', ar: 'اضغط للاتصال • اضغط مطولاً للنسخ', ku: 'کرتە بکە بۆ پەیوەندی • چەند چرکە هەڵبگرە بۆ کۆپی'),
                                          child: SizedBox(
                                            width: double.infinity,
                                            child: FilledButton.icon(
                                              onPressed: () =>
                                                  _callDealer(phones[i]),
                                              onLongPress: () =>
                                                  _copyToClipboard(
                                                phones[i],
                                                _tr('Phone number copied to clipboard', ar: 'تم نسخ رقم الهاتف', ku: 'ژمارەی تەلەفۆن کۆپی کرا'),
                                              ),
                                              icon: const Icon(
                                                Icons.phone_outlined,
                                              ),
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
                                ),
                              ),
                            _infoRow(
                              Icons.location_on_outlined,
                              _tr('Location', ar: 'الموقع', ku: 'شوێن'),
                              location,
                            ),
                            if (mapLat != null &&
                                mapLng != null &&
                                isValidDealerLatLng(mapLat, mapLng)) ...[
                              const SizedBox(height: 10),
                              DealerLocationMapPreview(
                                latitude: mapLat,
                                longitude: mapLng,
                                onOpenInGoogleMaps: () => _openDealerOnGoogleMaps(
                                  mapLat,
                                  mapLng,
                                ),
                              ),
                            ],
                            if (email.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Tooltip(
                                  message: _tr('Tap to send email • Hold to copy', ar: 'اضغط لإرسال بريد • اضغط مطولاً للنسخ', ku: 'کرتە بکە بۆ ناردنی ئیمەیل • چەند چرکە هەڵبگرە بۆ کۆپی'),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _emailDealer(email),
                                      onLongPress: () => _copyToClipboard(
                                        email,
                                        _tr('Email copied to clipboard', ar: 'تم نسخ البريد الإلكتروني', ku: 'ئیمەیل کۆپی کرا'),
                                      ),
                                      icon: const Icon(Icons.email_outlined),
                                      label: Text(
                                        email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            _openingHoursTable(openingHours),
                            ],
                          ],
                        ),
                      ),
                      if (_section == _DealerSection.listings) ...[
                        const Divider(height: 1),
                        if (_listings.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(_tr('No active vehicles right now.', ar: 'لا توجد مركبات نشطة حالياً.', ku: 'لە ئێستادا هیچ ئۆتۆمبێلێکی چالاک نییە.')),
                          )
                        else
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            // Match home_page.dart listing grid padding and gaps.
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              // Match global card layout used on home/favorites.
                              childAspectRatio: 0.62,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _listings.length,
                            itemBuilder: (context, index) {
                              final item = _listings[index];
                              final mapped =
                                  mapListingToGlobalCarCardData(context, item);
                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  final card =
                                      buildGlobalCarCard(context, mapped);
                                  return FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.topCenter,
                                    child: SizedBox(
                                      width: constraints.maxWidth,
                                      child: card,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

enum _DealerSection { about, listings }

